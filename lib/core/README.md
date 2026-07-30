# Core Layer

Reusable, app-wide building blocks. Do **not** import from `features/` or
`services/` into this layer.

## Theme (`lib/core/theme/`)

| File | Role |
| --- | --- |
| `tokens/space.dart` | Spacing scale |
| `tokens/radius.dart` | Radius scale |
| `tokens/typography.dart` | Type scale helpers |
| `tokens/motion.dart` | Duration / curve / press-scale / reduced-motion |
| `tokens/icon_size.dart` | Icon size ladder |
| `tokens/palettes.dart` | Fixed swatches (lyric presets, parse fallbacks) |
| `app_theme_config.dart` | Dark / Light / Pink color configs |
| `aetheria_theme.dart` | `ThemeExtension` + `context.tokens` |
| `theme.dart` | Barrel export |

### Usage

```dart
final cfg = context.tokens; // or context.cfg
Text('Hello', style: AetherType.bodyStyle(cfg.textPrimary));
```

Legacy fields (`textMain`, `bgPanel`, `border`, …) remain on `AppThemeConfig`
so existing screens keep compiling. Prefer semantic names in new code:
`textPrimary`, `bgElevated`, `danger`, `scrim`, …

### Hard rules for feature UI

- **No** hardcoded `Color(0x…)` / `Colors.*` outside `app_theme_config.dart`
  and `tokens/palettes.dart`
- **No** raw `fontSize: 12` — use `AetherType`
- **No** magic padding/radius — use `AetherSpace` / `AetherRadius`
- **No** raw `SwitchListTile` / `ChoiceChip` / `ListTile` / `showDialog` /
  `showModalBottomSheet` / `SnackBar` / `CircularProgressIndicator` in features —
  use the Aether primitives below
- Prefer `import '.../widgets/widgets.dart'` + `import '.../theme/theme.dart'`

### Motion rules

- High-frequency actions (row select, search filter, shortcuts): **no animation**
- Press feedback: ~120ms, scale 0.97–0.98, ease-out
- Modals/sheets: 200–240ms, enter ease-out, exit faster
  (`showAetherDialog` / `showAetherSheet` already wire reverse durations)
- Never animate from `scale(0)`; start ~0.96 + opacity
- Always go through `AetherMotion.duration(context, …)` /
  `AetherMotion.reduce(context)` so reduced-motion users get instant UI

```dart
final d = AetherMotion.duration(context, AetherMotion.fast);
final exit = AetherMotion.exitOf(context, AetherMotion.panel);
```

## Widgets (`lib/core/widgets/`)

Primitives for the UI refactor:

| Widget | Replaces |
| --- | --- |
| `AetherSurface` | ad-hoc `Container` + blur |
| `AetherPressable` | ink / manual scale hacks |
| `AetherButton` / `AetherIconButton` | `ElevatedButton` / `IconButton` |
| `AetherTextField` / `AetherSearchField` | raw `TextField` |
| `AetherSlider` / `AetherSeekBar` | raw `Slider` |
| `AetherChip` / `AetherBadge` | raw `Chip` |
| `AetherChoiceGroup` | `ChoiceChip` groups |
| `AetherSwitch` / `AetherSwitchTile` | `Switch` / `SwitchListTile` |
| `AetherListTile` | raw `ListTile` |
| `AetherSectionHeader` / `AetherFormRow` / `AetherDivider` | ad-hoc section labels |
| `AetherProgress` / `AetherInlineLoading` / `AetherLoading` | raw progress indicators |
| `showAetherDialog` / `AetherDialog` / `showAetherConfirmDialog` | `showDialog` |
| `showAetherModalPage` | ad-hoc `showGeneralDialog` page modals |
| `showAetherMenu` / `AetherMenuItem` | raw `showMenu` / `PopupMenuButton` |
| `AetherDropdown` | raw `DropdownButtonFormField` |
| `showAetherSheet` / `AetherSheet` | `showModalBottomSheet` (`decorate: false` for custom chrome) |
| `AetherEmptyState` | hand-rolled empty views |
| `showAetherProgressDialog` | blocking progress dialogs |
| `showAetherToast` | `SnackBar` |
| `GlassPanel` | thin wrapper over glass `AetherSurface` (compat) |

Import barrel:

```dart
import 'package:aetheria/core/widgets/widgets.dart';
import 'package:aetheria/core/theme/theme.dart';
```

## Guidelines

- Prefer tokens over magic numbers.
- Keep generic widgets free of feature imports.
- File size target for UI units: 300–500 lines.
