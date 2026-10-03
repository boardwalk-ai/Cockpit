//! Word counting for charges. Prices come from the shared `pricing_config`
//! table (octo-common `ai::Pricing`), times the run's model multiplier.

/// Words in `text`, split on whitespace.
pub fn count_words(text: &str) -> i64 {
    text.split_whitespace().count() as i64
}
