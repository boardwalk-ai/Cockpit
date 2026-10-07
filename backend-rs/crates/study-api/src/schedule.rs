//! Spaced repetition (SM-2 variant), a port of `Backend/app/services/schedule.py`
//! and the app's `domain/card_schedule.dart`: grade 0 Again, 1 Hard, 2 Good,
//! 3 Easy.

use chrono::Duration;

pub const MIN_EASE: f64 = 1.3;
pub const MAX_EASE: f64 = 3.0;
pub const START_EASE: f64 = 2.5;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CardState {
    pub reps: i32,
    pub interval_days: f64,
    pub ease: f64,
    pub lapses: i32,
}

impl Default for CardState {
    fn default() -> Self {
        Self { reps: 0, interval_days: 0.0, ease: START_EASE, lapses: 0 }
    }
}

/// Clamped and rounded to 2 places, as Python's `round(x, 2)`.
fn ease(v: f64) -> f64 {
    (v.clamp(MIN_EASE, MAX_EASE) * 100.0).round() / 100.0
}

fn days(d: f64) -> Duration {
    Duration::microseconds((d * 86_400_000_000.0).round() as i64)
}

/// The card after a review graded `grade`, and how long until it's due.
pub fn next_state(s: CardState, grade: i32) -> (CardState, Duration) {
    match grade.clamp(0, 3) {
        0 => (
            CardState { reps: 0, interval_days: 0.0, ease: ease(s.ease - 0.20), lapses: s.lapses + 1 },
            Duration::minutes(1),
        ),
        1 if s.reps == 0 => (
            CardState { reps: 0, interval_days: 0.0, ease: ease(s.ease - 0.15), lapses: s.lapses },
            Duration::minutes(10),
        ),
        1 => {
            let d = (s.interval_days * 1.2).max(1.0);
            (
                CardState { reps: s.reps + 1, interval_days: d, ease: ease(s.ease - 0.15), lapses: s.lapses },
                days(d),
            )
        }
        2 => {
            let d = match s.reps {
                0 => 1.0,
                1 => 3.0,
                _ => (s.interval_days * s.ease).max(1.0),
            };
            (CardState { reps: s.reps + 1, interval_days: d, ease: s.ease, lapses: s.lapses }, days(d))
        }
        _ => {
            let d = if s.reps == 0 { 4.0 } else { (s.interval_days * s.ease * 1.3).max(1.0) };
            (
                CardState { reps: s.reps + 1, interval_days: d, ease: ease(s.ease + 0.15), lapses: s.lapses },
                days(d),
            )
        }
    }
}

/// The app's `FlashcardStatus` for a stored card (reviewed at least once).
pub fn status(s: &CardState) -> &'static str {
    if s.reps >= 2 {
        "review"
    } else {
        "learning"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(grades: &[i32]) -> (CardState, Duration) {
        let mut s = CardState::default();
        let mut wait = Duration::zero();
        for &g in grades {
            (s, wait) = next_state(s, g);
        }
        (s, wait)
    }

    #[test]
    fn matches_python_sequences() {
        // Values from Backend/app/services/schedule.py with the same grades.
        let (s, w) = run(&[2, 2, 2]);
        assert_eq!((s.reps, s.interval_days, s.ease, s.lapses), (3, 7.5, 2.5, 0));
        assert_eq!(w, days(7.5));

        let (s, w) = run(&[3]);
        assert_eq!((s.reps, s.interval_days, s.ease), (1, 4.0, 2.65));
        assert_eq!(w, Duration::days(4));

        let (s, w) = run(&[2, 2, 0]);
        assert_eq!((s.reps, s.interval_days, s.ease, s.lapses), (0, 0.0, 2.3, 1));
        assert_eq!(w, Duration::minutes(1));

        let (s, w) = run(&[1]);
        assert_eq!((s.reps, s.ease), (0, 2.35));
        assert_eq!(w, Duration::minutes(10));

        let (s, _) = run(&[0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(s.ease, MIN_EASE);
        assert_eq!(status(&run(&[2, 2]).0), "review");
        assert_eq!(status(&run(&[2]).0), "learning");
    }
}
