//! Room bookkeeping and routing. Pure logic: the ENet loop in `main.rs` feeds events in and
//! applies the returned [`Action`]s, which keeps this testable without sockets.

use std::collections::{BTreeMap, HashMap};
use std::net::IpAddr;
use std::time::{Duration, Instant};

use crate::limits::TokenBucket;
use crate::protocol::{self, CONTROL_CHANNEL, Hello, HelloError, Mode, Reason};

pub type ConnId = usize;

#[derive(Debug, PartialEq, Eq)]
pub enum Action {
    Send {
        to: ConnId,
        channel: u8,
        mode: Mode,
        data: Vec<u8>,
    },
    Disconnect {
        conn: ConnId,
        reason: Reason,
    },
}

#[derive(Clone, Debug)]
pub struct Config {
    pub max_rooms: usize,
    pub max_peers_per_room: usize,
    pub max_conns_per_ip: usize,
    pub password: Option<String>,
    pub handshake_timeout: Duration,
    pub packets_per_sec: f64,
    pub bytes_per_sec: f64,
    pub max_reliable_bytes: usize,
    pub max_unreliable_bytes: usize,
    /// Failed joins (bad code or password) allowed per IP per minute, to stop code guessing.
    pub failed_joins_per_minute: u32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            max_rooms: 32,
            max_peers_per_room: 4,
            max_conns_per_ip: 8,
            password: None,
            handshake_timeout: Duration::from_secs(5),
            packets_per_sec: 300.0,
            bytes_per_sec: 64.0 * 1024.0,
            max_reliable_bytes: 64 * 1024,
            max_unreliable_bytes: 4 * 1024,
            failed_joins_per_minute: 10,
        }
    }
}

/// Crockford base32 without I, L, O, U: unambiguous when read aloud or typed.
const CODE_ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LEN: usize = 6;
/// Disconnect a peer after this many rate-limited packets.
const MAX_DROPPED: u32 = 2_000;

struct Member {
    room: String,
    peer_id: i32,
}

struct Conn {
    ip: IpAddr,
    connected_at: Instant,
    member: Option<Member>,
    packets: TokenBucket,
    bytes: TokenBucket,
    dropped: u32,
}

struct Room {
    /// Godot peer id → connection. The host is always peer 1.
    members: BTreeMap<i32, ConnId>,
}

pub struct Relay {
    cfg: Config,
    conns: HashMap<ConnId, Conn>,
    rooms: HashMap<String, Room>,
    per_ip: HashMap<IpAddr, usize>,
    failed_joins: HashMap<IpAddr, (u32, Instant)>,
    random: Box<dyn FnMut() -> u64>,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Stats {
    pub conns: usize,
    pub rooms: usize,
    pub players: usize,
}

/// Normalises user-typed room codes: case, spaces and look-alike letters.
pub fn normalize_code(code: &str) -> String {
    code.chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .map(|c| match c.to_ascii_uppercase() {
            'O' => '0',
            'I' | 'L' => '1',
            other => other,
        })
        .collect()
}

impl Relay {
    pub fn new(cfg: Config, random: Box<dyn FnMut() -> u64>) -> Self {
        Self {
            cfg,
            conns: HashMap::new(),
            rooms: HashMap::new(),
            per_ip: HashMap::new(),
            failed_joins: HashMap::new(),
            random,
        }
    }

    pub fn stats(&self) -> Stats {
        Stats {
            conns: self.conns.len(),
            rooms: self.rooms.len(),
            players: self.rooms.values().map(|r| r.members.len()).sum(),
        }
    }

    pub fn room_of(&self, conn: ConnId) -> Option<(&str, i32)> {
        let m = self.conns.get(&conn)?.member.as_ref()?;
        Some((m.room.as_str(), m.peer_id))
    }

    pub fn on_connect(&mut self, conn: ConnId, ip: IpAddr, now: Instant) -> Vec<Action> {
        let count = self.per_ip.entry(ip).or_default();
        *count += 1;
        self.conns.insert(
            conn,
            Conn {
                ip,
                connected_at: now,
                member: None,
                packets: TokenBucket::new(
                    self.cfg.packets_per_sec,
                    self.cfg.packets_per_sec * 2.0,
                    now,
                ),
                bytes: TokenBucket::new(self.cfg.bytes_per_sec, self.cfg.bytes_per_sec * 2.0, now),
                dropped: 0,
            },
        );
        if *count > self.cfg.max_conns_per_ip {
            return reject(conn, Reason::RateLimited);
        }
        Vec::new()
    }

    pub fn on_disconnect(&mut self, conn: ConnId) -> Vec<Action> {
        let Some(c) = self.conns.remove(&conn) else {
            return Vec::new();
        };
        if let Some(n) = self.per_ip.get_mut(&c.ip) {
            *n -= 1;
            if *n == 0 {
                self.per_ip.remove(&c.ip);
            }
        }
        match c.member {
            Some(m) => self.leave_room(&m.room, m.peer_id),
            None => Vec::new(),
        }
    }

    pub fn on_receive(
        &mut self,
        conn: ConnId,
        channel: u8,
        data: &[u8],
        now: Instant,
    ) -> Vec<Action> {
        let Some(c) = self.conns.get_mut(&conn) else {
            return Vec::new();
        };
        let allowed = c.packets.try_take(1.0, now) && c.bytes.try_take(data.len() as f64, now);
        if !allowed {
            c.dropped += 1;
            return if c.dropped > MAX_DROPPED {
                reject(conn, Reason::RateLimited)
            } else {
                Vec::new()
            };
        }
        let member = c.member.as_ref().map(|m| (m.room.clone(), m.peer_id));
        let ip = c.ip;

        match (channel, member) {
            (CONTROL_CHANNEL, None) => self.handle_hello(conn, ip, data, now),
            (CONTROL_CHANNEL, Some((room, peer_id))) => {
                // Only the host may kick; unknown control messages are ignored so newer
                // clients can add messages without breaking older relays.
                match protocol::parse_kick(data) {
                    Some(target) if peer_id == 1 && target != 1 => self.kick(&room, target),
                    _ => Vec::new(),
                }
            }
            (_, None) => reject(conn, Reason::Malformed),
            (_, Some((room, source))) => self.route(&room, source, channel, data),
        }
    }

    /// Periodic housekeeping: handshake timeouts and expiring join-failure counters.
    pub fn tick(&mut self, now: Instant) -> Vec<Action> {
        let timeout = self.cfg.handshake_timeout;
        let mut out = Vec::new();
        for (&id, c) in &self.conns {
            if c.member.is_none() && now.saturating_duration_since(c.connected_at) > timeout {
                out.extend(reject(id, Reason::Timeout));
            }
        }
        self.failed_joins.retain(|_, (_, since)| {
            now.saturating_duration_since(*since) < Duration::from_secs(60)
        });
        out
    }

    fn handle_hello(&mut self, conn: ConnId, ip: IpAddr, data: &[u8], now: Instant) -> Vec<Action> {
        let hello = match protocol::parse_hello(data) {
            Ok(h) => h,
            Err(HelloError::BadProtocol) => return reject(conn, Reason::BadProtocol),
            Err(HelloError::Malformed) => return reject(conn, Reason::Malformed),
        };
        if self.join_blocked(ip, now) {
            return reject(conn, Reason::RateLimited);
        }
        let password = match &hello {
            Hello::Create { password } | Hello::Join { password, .. } => password,
        };
        if let Some(expected) = &self.cfg.password
            && password != expected
        {
            self.note_failed_join(ip, now);
            return reject(conn, Reason::BadPassword);
        }
        match hello {
            Hello::Create { .. } => self.create_room(conn),
            Hello::Join { code, .. } => self.join_room(conn, ip, &normalize_code(&code), now),
        }
    }

    fn join_blocked(&self, ip: IpAddr, now: Instant) -> bool {
        self.failed_joins.get(&ip).is_some_and(|(n, since)| {
            *n >= self.cfg.failed_joins_per_minute
                && now.saturating_duration_since(*since) < Duration::from_secs(60)
        })
    }

    fn note_failed_join(&mut self, ip: IpAddr, now: Instant) {
        let entry = self.failed_joins.entry(ip).or_insert((0, now));
        if now.saturating_duration_since(entry.1) >= Duration::from_secs(60) {
            *entry = (0, now);
        }
        entry.0 += 1;
    }

    fn create_room(&mut self, conn: ConnId) -> Vec<Action> {
        if self.rooms.len() >= self.cfg.max_rooms {
            return reject(conn, Reason::ServerFull);
        }
        let code = loop {
            let code = self.new_code();
            if !self.rooms.contains_key(&code) {
                break code;
            }
        };
        self.rooms.insert(
            code.clone(),
            Room {
                members: BTreeMap::from([(1, conn)]),
            },
        );
        self.set_member(conn, &code, 1);
        vec![control(conn, protocol::encode_welcome(1, &code, &[]))]
    }

    fn join_room(&mut self, conn: ConnId, ip: IpAddr, code: &str, now: Instant) -> Vec<Action> {
        let Some(room) = self.rooms.get(code) else {
            self.note_failed_join(ip, now);
            return reject(conn, Reason::RoomNotFound);
        };
        if room.members.len() >= self.cfg.max_peers_per_room {
            return reject(conn, Reason::RoomFull);
        }
        let peer_id = loop {
            // Godot peer ids are positive i32s; 1 is reserved for the host.
            let id = ((self.random)() % (i32::MAX as u64 - 1)) as i32 + 2;
            if !room.members.contains_key(&id) {
                break id;
            }
        };
        let existing: Vec<i32> = room.members.keys().copied().collect();
        let others: Vec<ConnId> = room.members.values().copied().collect();
        self.rooms
            .get_mut(code)
            .expect("room exists")
            .members
            .insert(peer_id, conn);
        self.set_member(conn, code, peer_id);

        let mut out = vec![control(
            conn,
            protocol::encode_welcome(peer_id, code, &existing),
        )];
        let joined = protocol::encode_peer_event(protocol::MSG_PEER_JOINED, peer_id);
        out.extend(others.into_iter().map(|c| control(c, joined.clone())));
        out
    }

    fn kick(&mut self, room: &str, target: i32) -> Vec<Action> {
        let Some(conn) = self
            .rooms
            .get(room)
            .and_then(|r| r.members.get(&target).copied())
        else {
            return Vec::new();
        };
        if let Some(c) = self.conns.get_mut(&conn) {
            c.member = None;
        }
        let mut out = reject(conn, Reason::Kicked);
        out.extend(self.leave_room(room, target));
        out
    }

    fn leave_room(&mut self, code: &str, peer_id: i32) -> Vec<Action> {
        let Some(room) = self.rooms.get_mut(code) else {
            return Vec::new();
        };
        room.members.remove(&peer_id);
        if peer_id == 1 {
            // No host migration in 1.0: the room closes and everyone else is told why.
            let room = self.rooms.remove(code).expect("room exists");
            let mut out = Vec::new();
            for conn in room.members.into_values() {
                if let Some(c) = self.conns.get_mut(&conn) {
                    c.member = None;
                }
                out.extend(reject(conn, Reason::HostLeft));
            }
            return out;
        }
        let left = protocol::encode_peer_event(protocol::MSG_PEER_LEFT, peer_id);
        room.members
            .values()
            .map(|&c| control(c, left.clone()))
            .collect()
    }

    fn route(&mut self, code: &str, source: i32, channel: u8, data: &[u8]) -> Vec<Action> {
        let Some((mode, target, payload)) = protocol::parse_data(data) else {
            return Vec::new();
        };
        let limit = if mode == Mode::Reliable {
            self.cfg.max_reliable_bytes
        } else {
            self.cfg.max_unreliable_bytes
        };
        if payload.len() > limit {
            return Vec::new();
        }
        let Some(room) = self.rooms.get(code) else {
            return Vec::new();
        };
        let forwarded = protocol::encode_data(mode, source, payload);
        let recipients: Vec<ConnId> = room
            .members
            .iter()
            .filter(|&(&id, _)| {
                id != source
                    && match target {
                        0 => true,
                        t if t > 0 => id == t,
                        t => id != -t,
                    }
            })
            .map(|(_, &c)| c)
            .collect();
        recipients
            .into_iter()
            .map(|to| Action::Send {
                to,
                channel,
                mode,
                data: forwarded.clone(),
            })
            .collect()
    }

    fn set_member(&mut self, conn: ConnId, room: &str, peer_id: i32) {
        if let Some(c) = self.conns.get_mut(&conn) {
            c.member = Some(Member {
                room: room.to_string(),
                peer_id,
            });
        }
    }

    fn new_code(&mut self) -> String {
        let mut bits = (self.random)();
        (0..CODE_LEN)
            .map(|_| {
                let c = CODE_ALPHABET[(bits & 31) as usize] as char;
                bits >>= 5;
                c
            })
            .collect()
    }

    #[cfg(test)]
    fn host_of(&self, code: &str) -> Option<ConnId> {
        self.rooms
            .get(code)
            .and_then(|r| r.members.get(&1).copied())
    }
}

fn control(to: ConnId, data: Vec<u8>) -> Action {
    Action::Send {
        to,
        channel: CONTROL_CHANNEL,
        mode: Mode::Reliable,
        data,
    }
}

fn reject(conn: ConnId, reason: Reason) -> Vec<Action> {
    vec![
        control(conn, protocol::encode_reject(reason)),
        Action::Disconnect { conn, reason },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{MSG_PEER_JOINED, MSG_PEER_LEFT, MSG_WELCOME, encode_hello};
    use std::net::Ipv4Addr;

    const IP: IpAddr = IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1));

    fn relay(cfg: Config) -> Relay {
        let mut n = 0u64;
        Relay::new(
            cfg,
            Box::new(move || {
                n += 1;
                n.wrapping_mul(0x9E37_79B9_7F4A_7C15)
            }),
        )
    }

    fn hello_create() -> Vec<u8> {
        encode_hello(&Hello::Create {
            password: String::new(),
        })
    }

    fn hello_join(code: &str) -> Vec<u8> {
        encode_hello(&Hello::Join {
            code: code.into(),
            password: String::new(),
        })
    }

    /// Returns (room code, peer id) from a WELCOME in `actions`.
    fn welcome(actions: &[Action]) -> (String, i32) {
        for a in actions {
            if let Action::Send { data, .. } = a
                && data[0] == MSG_WELCOME
            {
                let id = i32::from_le_bytes(data[1..5].try_into().unwrap());
                let len = data[5] as usize;
                return (String::from_utf8(data[6..6 + len].to_vec()).unwrap(), id);
            }
        }
        panic!("no WELCOME in {actions:?}");
    }

    fn rejected(actions: &[Action]) -> Option<Reason> {
        actions.iter().find_map(|a| match a {
            Action::Disconnect { reason, .. } => Some(*reason),
            _ => None,
        })
    }

    fn data(mode: Mode, target: i32, payload: &[u8]) -> Vec<u8> {
        let mut v = vec![mode as u8];
        v.extend_from_slice(&target.to_le_bytes());
        v.extend_from_slice(payload);
        v
    }

    /// Host on conn 1, two clients on conns 2 and 3. Returns (relay, code, id2, id3).
    fn room_of_three() -> (Relay, String, i32, i32) {
        let t = Instant::now();
        let mut r = relay(Config::default());
        for c in 1..=3 {
            assert!(r.on_connect(c, IP, t).is_empty());
        }
        let (code, host_id) = welcome(&r.on_receive(1, 0, &hello_create(), t));
        assert_eq!(host_id, 1);
        let (_, id2) = welcome(&r.on_receive(2, 0, &hello_join(&code), t));
        let (_, id3) = welcome(&r.on_receive(3, 0, &hello_join(&code.to_lowercase()), t));
        assert!(id2 > 1 && id3 > 1 && id2 != id3);
        (r, code, id2, id3)
    }

    #[test]
    fn create_and_join() {
        let t = Instant::now();
        let mut r = relay(Config::default());
        r.on_connect(1, IP, t);
        r.on_connect(2, IP, t);
        let (code, _) = welcome(&r.on_receive(1, 0, &hello_create(), t));
        assert_eq!(code.len(), 6);
        assert_eq!(r.host_of(&code), Some(1));
        let out = r.on_receive(2, 0, &hello_join(&code), t);
        let (_, id) = welcome(&out);
        // The joiner learns about the host; the host learns about the joiner.
        let welcome_msg = out.iter().find_map(|a| match a {
            Action::Send { to: 2, data, .. } => Some(data.clone()),
            _ => None,
        });
        let w = welcome_msg.unwrap();
        let peers_at = 6 + w[5] as usize;
        assert_eq!(w[peers_at], 1);
        assert_eq!(
            i32::from_le_bytes(w[peers_at + 1..peers_at + 5].try_into().unwrap()),
            1
        );
        assert!(out.contains(&Action::Send {
            to: 1,
            channel: 0,
            mode: Mode::Reliable,
            data: protocol::encode_peer_event(MSG_PEER_JOINED, id),
        }));
        assert_eq!(
            r.stats(),
            Stats {
                conns: 2,
                rooms: 1,
                players: 2
            }
        );
    }

    #[test]
    fn routing_targets() {
        let (mut r, _, id2, id3) = room_of_three();
        let t = Instant::now();
        let to = |actions: Vec<Action>| -> Vec<ConnId> {
            let mut v: Vec<ConnId> = actions
                .into_iter()
                .map(|a| match a {
                    Action::Send { to, .. } => to,
                    other => panic!("{other:?}"),
                })
                .collect();
            v.sort();
            v
        };
        // Broadcast from the host reaches both clients, never the sender.
        assert_eq!(
            to(r.on_receive(1, 1, &data(Mode::Reliable, 0, b"hi"), t)),
            [2, 3]
        );
        // Direct client-to-client.
        assert_eq!(
            to(r.on_receive(2, 1, &data(Mode::Reliable, id3, b"hi"), t)),
            [3]
        );
        // Everyone except one.
        assert_eq!(
            to(r.on_receive(1, 1, &data(Mode::Reliable, -id2, b"hi"), t)),
            [3]
        );
        // To the host.
        assert_eq!(
            to(r.on_receive(3, 2, &data(Mode::Unreliable, 1, b"hi"), t)),
            [1]
        );
        // Unknown target: dropped.
        assert!(
            r.on_receive(3, 2, &data(Mode::Reliable, 777, b"hi"), t)
                .is_empty()
        );
    }

    #[test]
    fn forwarded_packets_carry_source_and_mode() {
        let (mut r, _, id2, _) = room_of_three();
        let out = r.on_receive(
            2,
            3,
            &data(Mode::UnreliableOrdered, 1, b"payload"),
            Instant::now(),
        );
        assert_eq!(
            out,
            vec![Action::Send {
                to: 1,
                channel: 3,
                mode: Mode::UnreliableOrdered,
                data: protocol::encode_data(Mode::UnreliableOrdered, id2, b"payload"),
            }]
        );
    }

    #[test]
    fn client_leaving_notifies_others() {
        let (mut r, _, id2, _) = room_of_three();
        let out = r.on_disconnect(2);
        let left = protocol::encode_peer_event(MSG_PEER_LEFT, id2);
        assert_eq!(out.len(), 2);
        assert!(
            out.iter()
                .all(|a| matches!(a, Action::Send { data, .. } if *data == left))
        );
        assert_eq!(r.stats().players, 2);
    }

    #[test]
    fn host_leaving_closes_room() {
        let (mut r, code, _, _) = room_of_three();
        let out = r.on_disconnect(1);
        assert_eq!(rejected(&out), Some(Reason::HostLeft));
        assert_eq!(
            out.iter()
                .filter(|a| matches!(a, Action::Disconnect { .. }))
                .count(),
            2
        );
        assert!(r.host_of(&code).is_none());
        // Their later disconnect events don't produce anything.
        assert!(r.on_disconnect(2).is_empty());
    }

    #[test]
    fn host_can_kick_clients_cannot() {
        let (mut r, _, id2, id3) = room_of_three();
        let t = Instant::now();
        let kick = |id: i32| {
            let mut v = vec![protocol::MSG_KICK];
            v.extend_from_slice(&id.to_le_bytes());
            v
        };
        assert!(r.on_receive(2, 0, &kick(id3), t).is_empty());
        let out = r.on_receive(1, 0, &kick(id2), t);
        assert_eq!(rejected(&out), Some(Reason::Kicked));
        assert_eq!(r.stats().players, 2);
    }

    #[test]
    fn room_limits() {
        let t = Instant::now();
        let mut r = relay(Config {
            max_rooms: 1,
            max_peers_per_room: 2,
            ..Config::default()
        });
        for c in 1..=4 {
            r.on_connect(c, IP, t);
        }
        let (code, _) = welcome(&r.on_receive(1, 0, &hello_create(), t));
        welcome(&r.on_receive(2, 0, &hello_join(&code), t));
        assert_eq!(
            rejected(&r.on_receive(3, 0, &hello_join(&code), t)),
            Some(Reason::RoomFull)
        );
        assert_eq!(
            rejected(&r.on_receive(4, 0, &hello_create(), t)),
            Some(Reason::ServerFull)
        );
    }

    #[test]
    fn code_guessing_is_rate_limited() {
        let t = Instant::now();
        let mut r = relay(Config::default());
        let mut blocked = false;
        for c in 0..12 {
            r.on_connect(c, IP, t);
            let out = r.on_receive(c, 0, &hello_join("ZZZZZZ"), t);
            if rejected(&out) == Some(Reason::RateLimited) {
                blocked = true;
            }
            r.on_disconnect(c);
        }
        assert!(blocked);
    }

    #[test]
    fn password_and_protocol_checks() {
        let t = Instant::now();
        let mut r = relay(Config {
            password: Some("secret".into()),
            ..Config::default()
        });
        r.on_connect(1, IP, t);
        assert_eq!(
            rejected(&r.on_receive(1, 0, &hello_create(), t)),
            Some(Reason::BadPassword)
        );
        r.on_connect(2, IP, t);
        let ok = encode_hello(&Hello::Create {
            password: "secret".into(),
        });
        welcome(&r.on_receive(2, 0, &ok, t));
        r.on_connect(3, IP, t);
        let mut old = hello_create();
        old[1] = 0xEE;
        assert_eq!(
            rejected(&r.on_receive(3, 0, &old, t)),
            Some(Reason::BadProtocol)
        );
    }

    #[test]
    fn data_before_hello_and_handshake_timeout() {
        let t = Instant::now();
        let mut r = relay(Config::default());
        r.on_connect(1, IP, t);
        assert_eq!(
            rejected(&r.on_receive(1, 1, &data(Mode::Reliable, 0, b"x"), t)),
            Some(Reason::Malformed)
        );
        r.on_connect(2, IP, t);
        assert!(r.tick(t + Duration::from_secs(1)).is_empty());
        let late = r.tick(t + Duration::from_secs(6));
        assert!(late.iter().any(|a| matches!(
            a,
            Action::Disconnect {
                conn: 2,
                reason: Reason::Timeout
            }
        )));
    }

    #[test]
    fn per_ip_connection_cap() {
        let t = Instant::now();
        let mut r = relay(Config {
            max_conns_per_ip: 2,
            ..Config::default()
        });
        assert!(r.on_connect(1, IP, t).is_empty());
        assert!(r.on_connect(2, IP, t).is_empty());
        assert_eq!(rejected(&r.on_connect(3, IP, t)), Some(Reason::RateLimited));
        let other = IpAddr::V4(Ipv4Addr::new(10, 0, 0, 2));
        assert!(r.on_connect(4, other, t).is_empty());
    }

    #[test]
    fn flooding_is_dropped_then_disconnected() {
        let (mut r, _, _, _) = room_of_three();
        let t = Instant::now();
        let msg = data(Mode::Unreliable, 1, &[0; 8]);
        let mut forwarded = 0;
        let mut kicked = false;
        for _ in 0..5_000 {
            let out = r.on_receive(2, 2, &msg, t);
            forwarded += out
                .iter()
                .filter(|a| matches!(a, Action::Send { .. }))
                .count();
            if rejected(&out) == Some(Reason::RateLimited) {
                kicked = true;
                break;
            }
        }
        assert!(forwarded <= 600 + 2, "burst limit exceeded: {forwarded}");
        assert!(kicked);
    }

    #[test]
    fn oversized_unreliable_dropped() {
        let (mut r, _, _, _) = room_of_three();
        let big = data(Mode::Unreliable, 0, &vec![0; 5_000]);
        assert!(r.on_receive(1, 2, &big, Instant::now()).is_empty());
    }

    #[test]
    fn codes_normalise() {
        assert_eq!(normalize_code(" ab-c0o "), "ABC00");
        assert_eq!(normalize_code("il"), "11");
    }
}
