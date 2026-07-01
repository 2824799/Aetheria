# Core Layer

This layer contains reusable, app-wide components that do not depend on specific features.

## Contents
- **Theme**: Colors, typography, and Material 3 theme configurations.
- **Constants**: App-wide constants (e.g., margins, padding).
- **Widgets**: Reusable UI components (e.g., custom buttons, dialogs, empty states).

## Guidelines
- High Cohesion: Everything here should be generically useful.
- Loose Coupling: Do not import anything from `features/` or `services/` into `core/`.
