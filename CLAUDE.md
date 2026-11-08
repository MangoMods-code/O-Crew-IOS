# O-Crew — notes for Claude

iOS game (Swift 5 mode, iOS 17+, SceneKit + SwiftUI). No Mac in the dev container: the only compiler is GitHub Actions (`.github/workflows/build.yml`), which runs XcodeGen and builds an unsigned IPA into a Release. The repo is private, so macOS minutes are expensive (10x): review carefully before pushing and batch fixes.

## Layout
- `project.yml` — XcodeGen spec (the .xcodeproj is generated, not committed).
- `OCrew/Data` — product catalog and the 7 store levels (pure data).
- `OCrew/Core` — settings (Display + Game, merged over defaults on load), save/progress, sound/haptics, colors.
- `OCrew/World` — SceneKit world: `GameWorld` (+Shop, +Customers, +Day extensions), `Layout` (store layout + A* nav grid), `Fixture`/`Slot`, `Customer`, `Models` (all meshes/textures generated in code), `Skills`.
- `OCrew/Game` — UIKit game screen: `GameViewController`, touch `ControlsView`, `HUDView`.
- `OCrew/UI` — SwiftUI menus and overlays (computer, change drawer, summary, pause, settings, how-to-play).
- `tools/` — sound generator and icon SVG.

## Conventions
- Everything touching SceneKit/UIKit/settings is `@MainActor`; data types in `Data/` and `Layout.swift` stay nonisolated.
- Interactable nodes are found by `node.name` prefixes (`slot:f:s`, `fbox:id`, `belt:i`, `cust:id`, `register`, `terminal`, `computer`, `sign`, `bin`).
- New settings: add a field with a default to `DisplaySettings`/`GameSettings` — old saves merge automatically.
