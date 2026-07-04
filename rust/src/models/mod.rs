//! Models Module
//!
//! Contains data structures shared across the API and database layers,
//! such as `Song`, `Tag`, `AudioVersion`, and `Playlist`.
//!
//! # High Cohesion & Loose Coupling
//! - Pure data objects.
//! - Does not contain business logic or database queries.

pub mod playlist;
pub mod song;

pub use playlist::Playlist;
pub use song::{AudioVersion, PreviewInfo, Song, Tag};
