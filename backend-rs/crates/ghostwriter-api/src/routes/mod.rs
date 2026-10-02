pub mod folders;
pub mod projects;
pub mod system;

use octo_common::ApiError;

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
