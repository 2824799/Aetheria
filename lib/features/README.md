# Features Layer

One folder per area of the app. State lives in `lib/core/providers/`
(`provider` + `ChangeNotifier`); features hold UI and the actions behind it.

| Folder | Contents |
| --- | --- |
| `layout/` | Desktop shell (`main_layout.dart`) and phone layout (`mobile_layout.dart`, `mobile/`) |
| `library/` | Song table, tag filter, tag manager, import flow, settings |
| `player/` | Play bar, detail pane, lyric panels, audio-version actions |
| `lyrics/` | Lyric timeline parsing, floating-lyrics and SuperLyric bridges |
| `sidebar/` | Desktop navigation |

## Conventions

- `ui/` holds widgets. Files next to it (`song_actions.dart`,
  `playlist_actions.dart`, `version_actions.dart`, `song_metadata.dart`) hold
  dialogs-plus-provider-calls that desktop and mobile both use. Put a new
  action there instead of writing it once per layout.
- Widgets shared by both layouts live with the feature, not under `mobile/`:
  `library/ui/song_badges.dart`, `library/ui/song_list_summary.dart`,
  `player/ui/detail/`.
- Keep UI files under roughly 500 lines; split by widget, not by line count.
- Follow `lib/core/theme/UI_CONTRACT.md` for colours, type, spacing and motion.

## Checking how a change looks

```bash
AETHERIA_SHOTS=/tmp/aetheria-shots flutter test test/visual/screenshots_test.dart
```

renders the main desktop and phone screens to PNG files with fake data. It is
skipped in a normal `flutter test` run.
