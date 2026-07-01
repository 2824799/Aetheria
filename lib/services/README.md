# Services Layer

This layer is responsible for interacting with external systems, APIs, or the Rust backend.

## Contents
- **Rust Bridge Wrappers**: Helper classes that wrap the raw generated `rust.dart` functions with error handling and logging.
- **Audio Service**: Abstraction over the audio player package (e.g. `just_audio` or `audioplayers`).

## Guidelines
- Service instances should be provided via Dependency Injection or State Management (e.g., Riverpod Providers).
- UI code should NEVER call `rust.dart` directly; it must go through a Service.
