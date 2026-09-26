//! Shared building blocks for the Octopilot Rust services (`octopilot-rs` for
//! Doc Oct, `octonotes-api` for OctoNotes): Firebase auth, the API error type,
//! identity + OctoCredits from the shared octopilot DB, and Postgres helpers.

pub mod auth;
pub mod credits;
pub mod db;
pub mod error;
pub mod identity;
pub mod llm;

pub use auth::{AuthedUser, FirebaseAuth, HasFirebase};
pub use error::{db_err, ApiError};
