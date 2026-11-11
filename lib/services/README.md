# Services Layer

Code that talks to things outside the Flutter app, other than the Rust core.

| File | Role |
| --- | --- |
| `lyric_search_service.dart` | Finds lyric candidates: embedded tags and local `.lrc` files (through the Rust core), then NetEase, QQ, Kugou and LRCLIB |
| `native_audio_helper.dart` | Platform channel `com.aetheria.app/notification`: media notification, floating lyrics and SuperLyric, saving to Downloads, multicast lock for LAN sync, device name, desktop window info |

The Rust core is called through the generated bindings in `lib/src/rust/`,
mostly from the providers in `lib/core/providers/`.
