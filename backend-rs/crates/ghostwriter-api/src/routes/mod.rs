pub mod devices;
pub mod documents;
pub mod folders;
pub mod octo;
pub mod projects;
pub mod runs;
pub mod system;

use octo_common::ApiError;
use serde::{Deserialize, Deserializer};

/// Trims `value` and rejects it when longer than `max` characters. An empty
/// string becomes `None`, so "not sent" and "sent blank" mean the same.
pub(crate) fn clean_text(
    value: Option<String>,
    max: usize,
    name: &str,
) -> Result<Option<String>, ApiError> {
    let Some(value) = value else { return Ok(None) };
    let value = value.trim();
    if value.chars().count() > max {
        return Err(ApiError::bad_request(format!(
            "{name} is longer than {max} characters"
        )));
    }
    Ok((!value.is_empty()).then(|| value.to_string()))
}

/// Tells a field that was sent as `null` apart from one that was not sent.
pub(crate) fn present<'de, T, D>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    T: Deserialize<'de>,
    D: Deserializer<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}
