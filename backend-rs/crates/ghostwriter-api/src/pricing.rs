//! OctoCredit prices. A port of `pricing.py` on octopilot-api (Finance-approved,
//! Pricing Final v1.0) — keep the two in step.

const GEN_WORDS_PER_DOLLAR: f64 = 30_000.0;
const HUM_WORDS_PER_DOLLAR: f64 = 3_000.0;
const SOURCES_PER_DOLLAR: f64 = 50.0;
const OC_PER_DOLLAR: f64 = 100.0;
const MIN_CHARGE: i32 = 100;
const ROUND_TO: f64 = 100.0;

/// What one operation costs: its estimated API cost in OctoCredits, rounded up
/// to the next 100, and never less than 100.
pub fn charge(words_generated: i64, words_humanized: i64, sources: i64) -> i32 {
    let cost_usd = words_generated.max(0) as f64 / GEN_WORDS_PER_DOLLAR
        + words_humanized.max(0) as f64 / HUM_WORDS_PER_DOLLAR
        + sources.max(0) as f64 / SOURCES_PER_DOLLAR;
    let credits = ((cost_usd * OC_PER_DOLLAR) / ROUND_TO).ceil() * ROUND_TO;
    (credits as i32).max(MIN_CHARGE)
}

/// Words in `text`, split on whitespace.
pub fn count_words(text: &str) -> i64 {
    text.split_whitespace().count() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_the_python_table() {
        // Almost everything lands on the minimum.
        assert_eq!(charge(800, 0, 0), 100);
        assert_eq!(charge(0, 0, 5), 100);
        assert_eq!(charge(30_000, 0, 0), 100);
        // Past $1 of cost it steps up in hundreds.
        assert_eq!(charge(30_001, 0, 0), 200);
        assert_eq!(charge(0, 3_000, 0), 100);
        assert_eq!(charge(0, 6_500, 0), 300);
        assert_eq!(charge(0, 0, 51), 200);
        // Nothing done still costs the minimum, as in the original.
        assert_eq!(charge(0, 0, 0), 100);
        assert_eq!(charge(-5, 0, 0), 100);
    }

    #[test]
    fn counts_words() {
        assert_eq!(count_words("  the tide\nis   rising "), 4);
        assert_eq!(count_words(""), 0);
    }
}
