# Aetheria UI Contract

Rules for all Flutter UI in this repo. Prefer fixing at the primitive layer over one-off page styling.

## Colors
- Read colors only from `AppThemeConfig` / `context.tokens`.
- Prefer semantic names: `textPrimary`, `textSecondary`, `borderSubtle`, `bg0`–`bg3`.
- Legacy aliases (`textMain`, `textSub`, `border`, `bgPanel`) remain for compatibility; do not introduce new usages.
- Hardcoded `Color(0x…)` is allowed only in theme/palette definitions.

## Space / Type / Radius / Icons
- Spacing: `AetherSpace.*` only.
- Type: `AetherType.*` / `AetherType.*Style(color)`.
- Corners: `AetherRadius.*`.
- Icons: `AetherIconSize.*` (or documented control sizes on `AetherIconButton`).

## Interaction
- Tappable chrome uses `AetherPressable` or a wrapper built on it (`AetherButton`, `AetherIconButton`, `AetherListTile`, `AetherChip`, …).
- No raw `InkWell` / Material splash for product chrome (theme uses `NoSplash`).
- Press scale: `AetherMotion.pressScale` / `pressScaleSubtle`. Never animate from `scale(0)`.

## Feedback surfaces
- Dialogs: `showAetherDialog` / `showAetherConfirmDialog` / `AetherDialog`.
- Sheets: `showAetherSheet` / `AetherSheet`.
- Toasts: `showAetherToast`.
- Progress blocking: `showAetherProgressDialog`.
- Empty states: `AetherEmptyState`.

## Motion
- Durations/curves: `AetherMotion` only.
- UI under ~300ms. Exit ≈ enter × 0.7.
- Enter uses ease-out; keyboard / seek / ultra-high-frequency actions: no decorative motion.
- Honor `AetherMotion.reduce` / `MediaQuery.disableAnimationsOf`.
- Animate `transform` / `opacity` only — not layout width/height for polish.

## Menus & overlays
- Context / desktop menus: `showAetherMenu` / `AetherMenuItem` (never raw `showMenu` / `PopupMenuButton`).
- Large page modals (Settings, Tag Manager): `showAetherModalPage`.
- Dropdowns: `AetherDropdown` (never raw `DropdownButtonFormField`).

## Forms & controls
- Text: `AetherTextField` (`outlined` default, `plain` for inline title/artist edits).
- Sliders / seek: `AetherSlider` / `AetherSeekBar`.
- Tabs: `AetherTabBar`.
- Switches / chips / sections: matching `Aether*` primitives.

## Platform
- Desktop: deep workflows, hover, focus ring via `borderFocus`.
- Mobile: hit targets ≥ ~44 logical px on primary controls; sheets for menus.

## Do not animate
- Table row select / multi-select / marquee
- Search filter result updates
- Seek and volume scrubbing
- Keyboard-triggered instant state flips (unless opacity crossfade under 120ms)
