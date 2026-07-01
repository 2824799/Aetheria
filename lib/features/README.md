# Features Layer

This layer implements the Clean Architecture "Feature-first" approach.
Each sub-folder corresponds to a specific feature of the application (e.g., `library`, `player`, `settings`).

## Structure of a Feature
- `ui/`: The Flutter Widgets and Screens for this feature.
- `logic/`: Providers or State Controllers.
- `models/`: Feature-specific data structures.

## Guidelines
- File Size Limit: UI files must be broken down into smaller sub-widgets to strictly stay under 300-500 lines.
- Inter-feature communication should happen via state management or routing, not tight coupling.
