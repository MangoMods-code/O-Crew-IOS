# O-Crew — notes for Claude

iOS first-person *organizing* game (Swift 5 mode, iOS 17+, SceneKit + SwiftUI): levels start with the store's products scattered on the floor; the player reads aisle signs/row labels and puts everything in the right section. It is NOT a shop-management sim (that was tried and rejected). No Mac in the dev container: the only compiler is GitHub Actions (`.github/workflows/build.yml`), which runs XcodeGen and builds an unsigned IPA into a Release. The repo is private, so macOS minutes are expensive (10x): review carefully before pushing and batch fixes.

## Layout
- `project.yml` — XcodeGen spec (the .xcodeproj is generated, not committed).
- `OCrew/Data` — product catalog; `Levels` = 7 store themes x 3 stages (pure data).
- `OCrew/Core` — settings (Display + Game, merged over defaults on load), save/progress, sound/haptics, colors.
- `OCrew/World` — SceneKit world: `GameWorld` (scene, mess generation, save/restore, player) + `GameWorld+Sort` (basket, pick/place rules, skills, completion, tutorial), `Layout` (store sized to fit the needed fixtures), `Fixture`/`Slot`/`Item` (rows carry a category label; a slot is correct when its row category matches), `Models` (meshes/textures generated in code), `Skills`.
- `OCrew/Game` — UIKit game screen: `GameViewController`, touch `ControlsView`, `HUDView`.
- `OCrew/UI` — SwiftUI menus and overlays (level select, pause, level complete, settings, how-to-play).
- `tools/` — sound generator and icon SVG.

## Conventions
- Everything touching SceneKit/UIKit/settings is `@MainActor`; data types in `Data/` and `Layout.swift` stay nonisolated.
- Interactable nodes are found by `node.name` prefixes (`item:id`, `slot:f:s`, `bin`).
- New settings: add a field with a default to `DisplaySettings`/`GameSettings` — old saves merge automatically.
- User's design choices: signs-only hints (no ghost outlines), basket with capacity, relaxed pace with stars for speed.
