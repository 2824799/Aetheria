//! SQLite access: connection setup and schema migration.
//!
//! Queries live next to the domain logic in `crate::library`; this module only
//! knows how to open the database and bring its schema up to date.

pub mod connection;
pub mod schema;
