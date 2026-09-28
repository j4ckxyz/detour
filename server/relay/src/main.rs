//! `detour-relay`: a tiny, game-agnostic ENet relay. Players (host included) connect out to
//! it, create or join a room by code, and it forwards packets between them. It never
//! simulates or parses game data, so it runs happily on a Raspberry Pi.
//!
//! Configuration (flags override environment variables):
//!
//! | flag              | env                          | default        |
//! |-------------------|------------------------------|----------------|
//! | `--bind ADDR`     | `DETOUR_RELAY_BIND`          | `0.0.0.0:24650`|
//! | `--max-rooms N`   | `DETOUR_RELAY_MAX_ROOMS`     | 32             |
//! | `--password PW`   | `DETOUR_RELAY_PASSWORD`      | none           |
//! | `--max-conns N`   | `DETOUR_RELAY_MAX_CONNS`     | 256            |

mod limits;
mod protocol;
mod rooms;

use std::net::{SocketAddr, UdpSocket};
use std::process::ExitCode;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rusty_enet::{EventNoRef, Host, HostSettings, Packet, PacketKind, PeerID};

use crate::protocol::{CHANNELS, Mode};
use crate::rooms::{Action, Config, Relay};

const DEFAULT_BIND: &str = "0.0.0.0:24650";
const TICK_INTERVAL: Duration = Duration::from_millis(500);
const STATS_INTERVAL: Duration = Duration::from_secs(300);

macro_rules! log {
    ($($arg:tt)*) => {{
        let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        eprintln!("[{secs}] {}", format!($($arg)*));
    }};
}

struct Options {
    bind: SocketAddr,
    max_conns: usize,
    relay: Config,
}

fn parse_options() -> Result<Options, String> {
    let mut bind = std::env::var("DETOUR_RELAY_BIND").unwrap_or_else(|_| DEFAULT_BIND.into());
    let mut max_rooms = std::env::var("DETOUR_RELAY_MAX_ROOMS").ok();
    let mut password = std::env::var("DETOUR_RELAY_PASSWORD")
        .ok()
        .filter(|p| !p.is_empty());
    let mut max_conns = std::env::var("DETOUR_RELAY_MAX_CONNS").ok();

    let mut args = std::env::args().skip(1);
    while let Some(flag) = args.next() {
        let mut value = || args.next().ok_or(format!("{flag} needs a value"));
        match flag.as_str() {
            "--bind" => bind = value()?,
            "--max-rooms" => max_rooms = Some(value()?),
            "--password" => password = Some(value()?),
            "--max-conns" => max_conns = Some(value()?),
            "-h" | "--help" => {
                println!(
                    "usage: detour-relay [--bind ADDR] [--max-rooms N] [--password PW] [--max-conns N]"
                );
                std::process::exit(0);
            }
            other => return Err(format!("unknown flag {other}")),
        }
    }

    let parse = |v: Option<String>, name: &str, default: usize| -> Result<usize, String> {
        v.map_or(Ok(default), |s| {
            s.parse().map_err(|_| format!("bad {name}: {s}"))
        })
    };
    Ok(Options {
        bind: bind
            .parse()
            .map_err(|_| format!("bad bind address: {bind}"))?,
        max_conns: parse(max_conns, "max-conns", 256)?,
        relay: Config {
            max_rooms: parse(max_rooms, "max-rooms", 32)?,
            password,
            ..Config::default()
        },
    })
}

fn random_u64() -> u64 {
    let mut buf = [0u8; 8];
    getrandom::fill(&mut buf).expect("OS random source unavailable");
    u64::from_le_bytes(buf)
}

fn apply(host: &mut Host<UdpSocket>, relay: &Relay, actions: Vec<Action>) {
    for action in actions {
        match action {
            Action::Send {
                to,
                channel,
                mode,
                data,
            } => {
                let kind = match mode {
                    Mode::Reliable => PacketKind::Reliable,
                    Mode::UnreliableOrdered => PacketKind::AlwaysUnreliable { sequenced: true },
                    Mode::Unreliable => PacketKind::AlwaysUnreliable { sequenced: false },
                };
                if let Some(peer) = host.get_peer_mut(PeerID(to)) {
                    let _ = peer.send(channel, &Packet::new(data, kind));
                }
            }
            Action::Disconnect { conn, reason } => {
                let room = relay
                    .room_of(conn)
                    .map(|(code, id)| format!(" (room {code}, peer {id})"));
                log!(
                    "dropping conn {conn}{}: {}",
                    room.unwrap_or_default(),
                    reason.message()
                );
                if let Some(peer) = host.get_peer_mut(PeerID(conn)) {
                    // "Later" lets the REJECT message reach the client first.
                    peer.disconnect_later(reason as u32);
                }
            }
        }
    }
}

fn run(opts: Options) -> std::io::Result<()> {
    let socket = UdpSocket::bind(opts.bind)?;
    let mut host = Host::new(
        socket,
        HostSettings {
            peer_limit: opts.max_conns,
            channel_limit: CHANNELS,
            ..HostSettings::default()
        },
    )
    .map_err(|e| std::io::Error::other(format!("{e:?}")))?;

    log!(
        "detour-relay {} listening on udp {} (proto {}, max {} rooms, password {})",
        env!("CARGO_PKG_VERSION"),
        opts.bind,
        protocol::RELAY_PROTO,
        opts.relay.max_rooms,
        if opts.relay.password.is_some() {
            "on"
        } else {
            "off"
        },
    );

    let mut relay = Relay::new(opts.relay, Box::new(random_u64));
    let mut next_tick = Instant::now() + TICK_INTERVAL;
    let mut next_stats = Instant::now() + STATS_INTERVAL;

    loop {
        let mut busy = false;
        while let Some(event) = host.service()? {
            busy = true;
            let now = Instant::now();
            let actions = match event.no_ref() {
                EventNoRef::Connect { peer, .. } => {
                    let ip = host.peer(peer).address().map(|a| a.ip());
                    match ip {
                        Some(ip) => relay.on_connect(peer.0, ip, now),
                        None => Vec::new(),
                    }
                }
                EventNoRef::Disconnect { peer, .. } => relay.on_disconnect(peer.0),
                EventNoRef::Receive {
                    peer,
                    channel_id,
                    packet,
                } => relay.on_receive(peer.0, channel_id, packet.data(), now),
            };
            apply(&mut host, &relay, actions);
        }

        let now = Instant::now();
        if now >= next_tick {
            next_tick = now + TICK_INTERVAL;
            let actions = relay.tick(now);
            apply(&mut host, &relay, actions);
        }
        if now >= next_stats {
            next_stats = now + STATS_INTERVAL;
            let s = relay.stats();
            log!(
                "{} connections, {} rooms, {} players",
                s.conns,
                s.rooms,
                s.players
            );
        }
        if !busy {
            // The socket is non-blocking; 1 ms keeps relay latency negligible at ~0% CPU.
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

fn main() -> ExitCode {
    let opts = match parse_options() {
        Ok(o) => o,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::FAILURE;
        }
    };
    match run(opts) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log!("fatal: {e}");
            ExitCode::FAILURE
        }
    }
}
