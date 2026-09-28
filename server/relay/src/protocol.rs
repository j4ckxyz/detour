//! Wire protocol between game clients and the relay (`RELAY_PROTO`).
//!
//! ENet channel 0 carries control messages; channels `1..CHANNELS` carry game data, where
//! ENet channel `n` is Godot transfer channel `n - 1`. The relay never looks inside payloads.
//!
//! Control (first byte = type):
//! - client → relay `HELLO`: `u16 proto, u8 action (1 create / 2 join), u8 len, code, u8 len, password`
//! - relay → client `WELCOME`: `i32 your_id, u8 len, code, u8 n, i32 peer_ids[n]`
//! - relay → client `REJECT`: `u8 reason, u8 len, utf-8 message` (then disconnect)
//! - relay → client `PEER_JOINED` / `PEER_LEFT`: `i32 peer_id`
//! - host → relay `KICK`: `i32 peer_id`
//!
//! Data: client → relay `u8 mode, i32 target, payload`; relay → client
//! `u8 mode, i32 source, payload`. `mode` uses Godot's `TransferMode` numbering. `target` 0 is
//! everyone else in the room, `n > 0` one peer, `-n` everyone except `n`. All integers are
//! little-endian. Must match `game/src/net/relay_multiplayer_peer.gd`.

pub const RELAY_PROTO: u16 = 1;
/// 1 control channel + 4 game channels.
pub const CHANNELS: usize = 5;
pub const CONTROL_CHANNEL: u8 = 0;

pub const MSG_HELLO: u8 = 1;
pub const MSG_WELCOME: u8 = 2;
pub const MSG_REJECT: u8 = 3;
pub const MSG_PEER_JOINED: u8 = 4;
pub const MSG_PEER_LEFT: u8 = 5;
pub const MSG_KICK: u8 = 6;

pub const ACTION_CREATE: u8 = 1;
pub const ACTION_JOIN: u8 = 2;

/// Godot `MultiplayerPeer.TransferMode`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Unreliable = 0,
    UnreliableOrdered = 1,
    Reliable = 2,
}

impl Mode {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Unreliable),
            1 => Some(Self::UnreliableOrdered),
            2 => Some(Self::Reliable),
            _ => None,
        }
    }
}

/// Why a connection was refused or dropped. Also sent as the ENet disconnect data.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reason {
    BadProtocol = 1,
    RoomNotFound = 2,
    RoomFull = 3,
    BadPassword = 4,
    ServerFull = 5,
    RateLimited = 6,
    Malformed = 7,
    HostLeft = 8,
    Kicked = 9,
    Timeout = 10,
}

impl Reason {
    pub fn message(self) -> &'static str {
        match self {
            Self::BadProtocol => "game and relay versions are incompatible",
            Self::RoomNotFound => "no room with that code",
            Self::RoomFull => "that room is full",
            Self::BadPassword => "wrong server password",
            Self::ServerFull => "the relay is full, try again later",
            Self::RateLimited => "too many requests",
            Self::Malformed => "malformed message",
            Self::HostLeft => "the host left",
            Self::Kicked => "removed by the host",
            Self::Timeout => "timed out",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Hello {
    Create { password: String },
    Join { code: String, password: String },
}

#[derive(Debug, PartialEq, Eq)]
pub enum HelloError {
    Malformed,
    BadProtocol,
}

struct Reader<'a> {
    buf: &'a [u8],
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        if self.buf.len() < n {
            return None;
        }
        let (head, rest) = self.buf.split_at(n);
        self.buf = rest;
        Some(head)
    }
    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|b| b[0])
    }
    fn u16(&mut self) -> Option<u16> {
        self.take(2).map(|b| u16::from_le_bytes([b[0], b[1]]))
    }
    fn str8(&mut self) -> Option<String> {
        let len = self.u8()? as usize;
        String::from_utf8(self.take(len)?.to_vec()).ok()
    }
}

pub fn parse_hello(msg: &[u8]) -> Result<Hello, HelloError> {
    let mut r = Reader { buf: msg };
    if r.u8() != Some(MSG_HELLO) {
        return Err(HelloError::Malformed);
    }
    let proto = r.u16().ok_or(HelloError::Malformed)?;
    if proto != RELAY_PROTO {
        return Err(HelloError::BadProtocol);
    }
    let action = r.u8().ok_or(HelloError::Malformed)?;
    let code = r.str8().ok_or(HelloError::Malformed)?;
    let password = r.str8().ok_or(HelloError::Malformed)?;
    match action {
        ACTION_CREATE => Ok(Hello::Create { password }),
        ACTION_JOIN => Ok(Hello::Join { code, password }),
        _ => Err(HelloError::Malformed),
    }
}

/// The client side of `parse_hello` (clients are GDScript; this is for tests).
#[cfg(test)]
pub fn encode_hello(hello: &Hello) -> Vec<u8> {
    let (action, code, password) = match hello {
        Hello::Create { password } => (ACTION_CREATE, "", password.as_str()),
        Hello::Join { code, password } => (ACTION_JOIN, code.as_str(), password.as_str()),
    };
    let mut out = vec![MSG_HELLO];
    out.extend_from_slice(&RELAY_PROTO.to_le_bytes());
    out.push(action);
    push_str8(&mut out, code);
    push_str8(&mut out, password);
    out
}

fn push_str8(out: &mut Vec<u8>, s: &str) {
    let bytes = &s.as_bytes()[..s.len().min(255)];
    out.push(bytes.len() as u8);
    out.extend_from_slice(bytes);
}

pub fn encode_welcome(your_id: i32, code: &str, peers: &[i32]) -> Vec<u8> {
    let mut out = vec![MSG_WELCOME];
    out.extend_from_slice(&your_id.to_le_bytes());
    push_str8(&mut out, code);
    out.push(peers.len() as u8);
    for p in peers {
        out.extend_from_slice(&p.to_le_bytes());
    }
    out
}

pub fn encode_reject(reason: Reason) -> Vec<u8> {
    let mut out = vec![MSG_REJECT, reason as u8];
    push_str8(&mut out, reason.message());
    out
}

pub fn encode_peer_event(kind: u8, peer_id: i32) -> Vec<u8> {
    let mut out = vec![kind];
    out.extend_from_slice(&peer_id.to_le_bytes());
    out
}

/// Parses `KICK`; returns the target peer id.
pub fn parse_kick(msg: &[u8]) -> Option<i32> {
    match msg {
        [MSG_KICK, a, b, c, d] => Some(i32::from_le_bytes([*a, *b, *c, *d])),
        _ => None,
    }
}

pub const DATA_HEADER: usize = 5;

/// Splits a client data packet into `(mode, target, payload)`.
pub fn parse_data(msg: &[u8]) -> Option<(Mode, i32, &[u8])> {
    if msg.len() < DATA_HEADER {
        return None;
    }
    let mode = Mode::from_u8(msg[0])?;
    let target = i32::from_le_bytes([msg[1], msg[2], msg[3], msg[4]]);
    Some((mode, target, &msg[DATA_HEADER..]))
}

/// Builds the forwarded packet: the target field is replaced by the source.
pub fn encode_data(mode: Mode, source: i32, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(DATA_HEADER + payload.len());
    out.push(mode as u8);
    out.extend_from_slice(&source.to_le_bytes());
    out.extend_from_slice(payload);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_round_trip() {
        for h in [
            Hello::Create {
                password: "pw".into(),
            },
            Hello::Join {
                code: "ABC123".into(),
                password: String::new(),
            },
        ] {
            assert_eq!(parse_hello(&encode_hello(&h)), Ok(h));
        }
    }

    #[test]
    fn hello_rejects_bad_input() {
        assert_eq!(parse_hello(&[]), Err(HelloError::Malformed));
        assert_eq!(
            parse_hello(&[MSG_HELLO, 99, 0]),
            Err(HelloError::BadProtocol)
        );
        let mut truncated = encode_hello(&Hello::Join {
            code: "ABCDEF".into(),
            password: String::new(),
        });
        truncated.truncate(7);
        assert_eq!(parse_hello(&truncated), Err(HelloError::Malformed));
        let mut bad_action = encode_hello(&Hello::Create {
            password: String::new(),
        });
        bad_action[3] = 9;
        assert_eq!(parse_hello(&bad_action), Err(HelloError::Malformed));
    }

    #[test]
    fn data_round_trip() {
        let (mode, target, payload) = parse_data(&[2, 0xFE, 0xFF, 0xFF, 0xFF, 7, 8]).unwrap();
        assert_eq!((mode, target, payload), (Mode::Reliable, -2, &[7u8, 8][..]));
        let fwd = encode_data(mode, 1234, payload);
        assert_eq!(parse_data(&fwd).unwrap().1, 1234);
        assert!(parse_data(&[2, 0, 0]).is_none());
        assert!(parse_data(&[7, 0, 0, 0, 0]).is_none());
    }
}
