# O-Crew

A first-person organizing game for iPhone. Every level opens on a wrecked store with products all over the floor. Read the aisle signs and shelf labels, fill your basket, and put every item back in its right section as fast as you can.

Built with Swift, SceneKit and SwiftUI. No third-party code or art: every model, texture and sound is generated in code.

## Install on your iPhone

1. Open the latest release: **Releases → O-Crew build N → `O-Crew.ipa`**.
2. Sign and install it with your usual tool (Sideloadly, AltStore, SideStore, a dev cert, etc.).

Every push to `main` builds a fresh unsigned `.ipa` automatically (see `.github/workflows/build.yml`).

## What's in it

- **21 levels** (about 90–650 items each): 7 stores (Corner Grocery, Hardware Depot, Neighborhood Pharmacy, Electronics Outlet, Pet Supply Co., Garden Center, City Supermarket) × 3 stages each: *Morning Mess*, *Wrong Aisles* (items start on the wrong shelves) and *Total Chaos* (bigger mess plus expired stock for the trash).
- **Signs-only sorting**: aisle signs and shelf-row labels tell you the section. No outlines. Identical items go together, and cold stuff goes in fridges and freezers.
- **Basket** with limited space. Choose what to place from the basket bar.
- **Skills with cooldowns**: Sprint, Magnet, Scanner, Auto-Sort, Time Freeze.
- **Score and combos**: chained correct placements multiply points (up to x5), with bonuses for finished sections, speed and clean runs.
- **Locker**: glove and basket colors unlocked with stars, plus lifetime stats.
- **Stars for speed**: a relaxed timer, with no fail state. Progress saves mid-level.
- **Lots of settings**: HUD size/opacity/text size, every HUD element toggleable, sign size, row labels, crosshair style/color/size, FOV, head bob, camera smoothing, frame rate, left-handed layout, floating or fixed stick, stick/button size, look sensitivity, invert Y, colorblind modes, high-contrast HUD, reduce motion, haptics, plus game rules (difficulty presets, basket capacity, reach, mess size, twists on/off, placement feedback, auto-match, keep-together rule, star time targets, cooldowns, walk speed).

## Controls

- **Left side**: move (floating stick).
- **Right side**: drag to look, tap an item or shelf spot to use it.
- **Hand button**: grab / place whatever's under the crosshair (hold to repeat).
- **Drop**: take one item off the shelf you're looking at, or drop your selected item.
- **Basket bar** (bottom): tap an item to choose what you place next.
- **Skill buttons**: arc above the hand button.

## Building locally (Mac)

```bash
brew install xcodegen
xcodegen generate
open OCrew.xcodeproj
```
