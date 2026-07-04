//! Audio Module
//!
//! This module is responsible for the local HTTP streaming server used by Flutter
//! to play audio files using the native mediaplayer.
//!
//! # High Cohesion & Loose Coupling
//! - Does not depend on the database layer or Tauri/Flutter specific structs.
//! - Exposes a simple `start_server` method and `get_port` to return the HTTP port.

pub mod dsp;
pub mod player;
pub mod rubberband;
pub mod server;
