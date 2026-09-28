//! Rate limiting.

use std::time::Instant;

/// Classic token bucket: refills at `rate` per second up to `burst`.
#[derive(Clone, Debug)]
pub struct TokenBucket {
    rate: f64,
    burst: f64,
    tokens: f64,
    last: Instant,
}

impl TokenBucket {
    pub fn new(rate: f64, burst: f64, now: Instant) -> Self {
        Self {
            rate,
            burst,
            tokens: burst,
            last: now,
        }
    }

    /// Takes `cost` tokens if available.
    pub fn try_take(&mut self, cost: f64, now: Instant) -> bool {
        let elapsed = now.saturating_duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + elapsed * self.rate).min(self.burst);
        if self.tokens >= cost {
            self.tokens -= cost;
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn refills_over_time() {
        let t0 = Instant::now();
        let mut b = TokenBucket::new(10.0, 5.0, t0);
        for _ in 0..5 {
            assert!(b.try_take(1.0, t0));
        }
        assert!(!b.try_take(1.0, t0));
        assert!(b.try_take(1.0, t0 + Duration::from_millis(100)));
        assert!(!b.try_take(1.0, t0 + Duration::from_millis(100)));
        // Never exceeds the burst.
        let later = t0 + Duration::from_secs(60);
        for _ in 0..5 {
            assert!(b.try_take(1.0, later));
        }
        assert!(!b.try_take(1.0, later));
    }
}
