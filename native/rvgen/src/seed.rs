//! Shareable seed codes, e.g. `DT1-7KQ2X-M9PA3`.
//!
//! Layout: `DT` + generator version (decimal) + 10 Crockford base32 characters carrying
//! 50 bits, most significant first: `[2 trip][4 flags][40 seed][4 check]`. Hyphens, spaces
//! and letter case are ignored when parsing; `I`/`L` read as `1` and `O` as `0`.

use core::fmt;

use crate::hash;

/// Bump on **any** change that alters generated output. Old codes then fail
/// [`SeedCode::check_supported`] instead of silently producing a different world.
/// Bumped on any generator change that alters worlds (v2: trips with roads and obstacles;
/// v3: biomes, fords, ice, lakes and caves; v4: the road's walled valley, bridge planks off in
/// the trees; v5: long winding trips through a wide valley, bridges, beams, jumps and hills,
/// places to explore).
pub const GEN_VERSION: u16 = 5;
/// Longest text [`SeedCode::from_text`] reads (the rest is ignored).
pub const TEXT_SEED_MAX: usize = 20;

const PREFIX: &str = "DT";
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const PAYLOAD_CHARS: usize = 10;
const SEED_BITS: u32 = 40;
const SEED_MASK: u64 = (1 << SEED_BITS) - 1;
const FLAG_MASK: u8 = 0xF;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TripLength {
    Short = 0,
    Medium = 1,
    Long = 2,
}

impl TripLength {
    /// Gas stations (checkpoints) on the trip.
    pub const fn stations(self) -> u32 {
        match self {
            Self::Short => 3,
            Self::Medium => 6,
            Self::Long => 12,
        }
    }

    pub const fn from_index(i: u8) -> Option<Self> {
        match i {
            0 => Some(Self::Short),
            1 => Some(Self::Medium),
            2 => Some(Self::Long),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SeedCode {
    pub gen_version: u16,
    pub trip: TripLength,
    /// Reserved for world options (4 bits).
    pub flags: u8,
    /// 40-bit seed.
    pub seed: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SeedCodeError {
    BadPrefix,
    BadLength,
    BadChar(char),
    BadChecksum,
    BadTrip,
    UnsupportedVersion(u16),
}

impl fmt::Display for SeedCodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::BadPrefix => write!(f, "seed codes start with \"{PREFIX}\""),
            Self::BadLength => write!(f, "seed code has the wrong length"),
            Self::BadChar(c) => write!(f, "'{c}' is not valid in a seed code"),
            Self::BadChecksum => write!(f, "seed code has a typo (checksum mismatch)"),
            Self::BadTrip => write!(f, "seed code has an unknown trip length"),
            Self::UnsupportedVersion(v) => write!(
                f,
                "seed code is for world generator v{v}, this game uses v{GEN_VERSION}"
            ),
        }
    }
}

impl std::error::Error for SeedCodeError {}

impl SeedCode {
    pub fn new(trip: TripLength, seed: u64) -> Self {
        Self {
            gen_version: GEN_VERSION,
            trip,
            flags: 0,
            seed: seed & SEED_MASK,
        }
    }

    /// Fresh code from arbitrary entropy (time, OS randomness, ...).
    pub fn from_entropy(trip: TripLength, entropy: u64) -> Self {
        Self::new(trip, hash::mix64(entropy))
    }

    /// Any text as a seed, like Minecraft: a seed code is itself, a whole number is that
    /// seed, and anything else (up to [`TEXT_SEED_MAX`] characters, spaces at the ends
    /// ignored) is hashed. Blank text is `None` (roll a new trip). A code with a typo or for
    /// another generator version is an error, not a new seed.
    pub fn from_text(trip: TripLength, text: &str) -> Option<Result<Self, SeedCodeError>> {
        let text: String = text.trim().chars().take(TEXT_SEED_MAX).collect();
        let text = text.trim();
        if text.is_empty() {
            return None;
        }
        match Self::parse(text) {
            Ok(code) => return Some(code.check_supported().map(|_| code)),
            Err(e @ (SeedCodeError::BadChecksum | SeedCodeError::BadTrip)) => return Some(Err(e)),
            Err(_) => {}
        }
        if text.len() <= 13 && text.bytes().all(|b| b.is_ascii_digit()) {
            let n: u64 = text.parse().unwrap_or(0);
            return Some(Ok(Self::new(trip, n)));
        }
        // FNV-1a over the UTF-8, mixed so similar words land far apart.
        Some(Ok(Self::new(
            trip,
            hash::mix64(hash::fnv1a64(text.as_bytes())),
        )))
    }

    /// The 64-bit seed all generation derives from.
    pub fn world_seed(&self) -> u64 {
        hash::combine(hash::mix64(self.seed), self.flags as u64)
    }

    pub fn check_supported(&self) -> Result<(), SeedCodeError> {
        if self.gen_version == GEN_VERSION {
            Ok(())
        } else {
            Err(SeedCodeError::UnsupportedVersion(self.gen_version))
        }
    }

    /// CRC-4 (x^4 + x + 1) over the version and body. Being a CRC, it catches every
    /// single-bit error and every burst of up to 4 bits, which covers most one-character typos.
    fn checksum(gen_version: u16, body: u64) -> u64 {
        let mut crc: u8 = 0;
        for (value, bits) in [(gen_version as u64, 16), (body, 46)] {
            for i in (0..bits).rev() {
                let bit = ((value >> i) & 1) as u8;
                let top = (crc >> 3) & 1;
                crc = (crc << 1) & 0xF;
                if top ^ bit == 1 {
                    crc ^= 0x3;
                }
            }
        }
        crc as u64
    }

    pub fn parse(input: &str) -> Result<Self, SeedCodeError> {
        let cleaned: String = input
            .chars()
            .filter(|c| !matches!(c, '-' | ' ' | '_'))
            .map(|c| c.to_ascii_uppercase())
            .collect();
        let rest = cleaned
            .strip_prefix(PREFIX)
            .ok_or(SeedCodeError::BadPrefix)?;
        if rest.len() <= PAYLOAD_CHARS {
            return Err(SeedCodeError::BadLength);
        }
        let (version_str, payload) = rest.split_at(rest.len() - PAYLOAD_CHARS);
        if version_str.len() > 5 || !version_str.bytes().all(|b| b.is_ascii_digit()) {
            return Err(SeedCodeError::BadLength);
        }
        let gen_version: u16 = version_str.parse().map_err(|_| SeedCodeError::BadLength)?;

        let mut bits: u64 = 0;
        for c in payload.chars() {
            bits = (bits << 5) | decode_char(c)? as u64;
        }
        let check = bits & 0xF;
        let body = bits >> 4;
        if Self::checksum(gen_version, body) != check {
            return Err(SeedCodeError::BadChecksum);
        }
        let seed = body & SEED_MASK;
        let flags = ((body >> SEED_BITS) as u8) & FLAG_MASK;
        let trip = TripLength::from_index((body >> (SEED_BITS + 4)) as u8 & 0x3)
            .ok_or(SeedCodeError::BadTrip)?;
        Ok(Self {
            gen_version,
            trip,
            flags,
            seed,
        })
    }
}

impl fmt::Display for SeedCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let body = ((self.trip as u64) << (SEED_BITS + 4))
            | (((self.flags & FLAG_MASK) as u64) << SEED_BITS)
            | (self.seed & SEED_MASK);
        let bits = (body << 4) | Self::checksum(self.gen_version, body);
        let mut chars = [0u8; PAYLOAD_CHARS];
        for (i, slot) in chars.iter_mut().enumerate() {
            let shift = 5 * (PAYLOAD_CHARS - 1 - i);
            *slot = ALPHABET[((bits >> shift) & 0x1F) as usize];
        }
        let s = core::str::from_utf8(&chars).expect("alphabet is ASCII");
        write!(f, "{PREFIX}{}-{}-{}", self.gen_version, &s[..5], &s[5..])
    }
}

impl core::str::FromStr for SeedCode {
    type Err = SeedCodeError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s)
    }
}

fn decode_char(c: char) -> Result<u8, SeedCodeError> {
    let c = match c {
        'I' | 'L' => '1',
        'O' => '0',
        other => other,
    };
    ALPHABET
        .iter()
        .position(|&a| a as char == c)
        .map(|p| p as u8)
        .ok_or(SeedCodeError::BadChar(c))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        for (i, trip) in [TripLength::Short, TripLength::Medium, TripLength::Long]
            .into_iter()
            .enumerate()
        {
            let code = SeedCode::from_entropy(trip, 0xDEAD_BEEF + i as u64);
            let text = code.to_string();
            assert!(text.starts_with(&format!("DT{GEN_VERSION}-")), "{text}");
            assert_eq!(text.len(), "DT3-XXXXX-XXXXX".len());
            assert_eq!(SeedCode::parse(&text), Ok(code));
        }
    }

    #[test]
    fn forgiving_input() {
        let code = SeedCode::new(TripLength::Medium, 0x12_3456_789A);
        let text = code.to_string();
        let messy = text.to_lowercase().replace('-', " ").replace('0', "o");
        assert_eq!(SeedCode::parse(&messy), Ok(code));
    }

    #[test]
    fn detects_typos() {
        let text = SeedCode::new(TripLength::Short, 987_654_321).to_string();
        // Swap one payload character for a different valid one at every position.
        for pos in 4..text.len() {
            let original = text.as_bytes()[pos];
            if original == b'-' {
                continue;
            }
            let value = decode_char(original as char).unwrap();
            // Flip a low bit: the checksum covers every bit, so this must be caught.
            let replacement = ALPHABET[(value ^ 1) as usize];
            let mut bytes = text.clone().into_bytes();
            bytes[pos] = replacement;
            let typo = String::from_utf8(bytes).unwrap();
            assert!(SeedCode::parse(&typo).is_err(), "typo not caught: {typo}");
        }
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(SeedCode::parse("hello"), Err(SeedCodeError::BadPrefix));
        assert_eq!(SeedCode::parse("DT1-ABC"), Err(SeedCodeError::BadLength));
        assert_eq!(
            SeedCode::parse("DT1-UUUUU-UUUUU"),
            Err(SeedCodeError::BadChar('U'))
        );
    }

    #[test]
    fn any_text_is_a_seed() {
        let t = TripLength::Short;
        assert_eq!(SeedCode::from_text(t, "   "), None);
        let a = SeedCode::from_text(t, "Hello world").unwrap().unwrap();
        assert_eq!(SeedCode::from_text(t, " Hello world ").unwrap(), Ok(a));
        assert_ne!(SeedCode::from_text(t, "hello world").unwrap(), Ok(a));
        assert_eq!(
            SeedCode::from_text(t, "12345").unwrap(),
            Ok(SeedCode::new(t, 12345))
        );
        // Only the first 20 characters count.
        let long = SeedCode::from_text(t, "abcdefghijklmnopqrstuvwxyz").unwrap();
        assert_eq!(
            long,
            SeedCode::from_text(t, "abcdefghijklmnopqrst").unwrap()
        );
        // A code is itself (its own trip length wins); a typo'd code is an error.
        let code = SeedCode::new(TripLength::Long, 99);
        assert_eq!(SeedCode::from_text(t, &code.to_string()).unwrap(), Ok(code));
        let text = code.to_string();
        let last = text.chars().last().unwrap();
        let typo = format!(
            "{}{}",
            &text[..text.len() - 1],
            if last == '0' { '1' } else { '0' }
        );
        assert!(SeedCode::from_text(t, &typo).unwrap().is_err());
        // Non-ASCII is fine.
        assert!(SeedCode::from_text(t, "café ☕").unwrap().is_ok());
    }

    #[test]
    fn other_versions_parse_but_are_unsupported() {
        let mut code = SeedCode::new(TripLength::Long, 42);
        code.gen_version = GEN_VERSION + 1;
        let parsed = SeedCode::parse(&code.to_string()).unwrap();
        assert_eq!(parsed.gen_version, GEN_VERSION + 1);
        assert!(parsed.check_supported().is_err());
    }
}
