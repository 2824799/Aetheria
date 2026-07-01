//! Database Module
//!
//! Handles SQLite database connection, schema migration, and basic query utilities.
//!
//! # High Cohesion & Loose Coupling
//! - Encapsulates `rusqlite` dependencies.
//! - Uses standard generic errors rather than UI-specific ones.

pub mod connection;
pub mod schema;
