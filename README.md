# O-Crew

A first-person store-management game for iPhone. Run a shop: order stock, fill the shelves, set prices, ring people up, count out change, catch shoplifters, and hit each store's goals to unlock the next one.

Built with Swift, SceneKit and SwiftUI. No third-party code or art: every model, texture and sound is generated in code.

## Install on your iPhone

1. Open the latest release: **Releases → O-Crew build N → `O-Crew.ipa`**.
2. Sign and install it with your usual tool (Sideloadly, AltStore, SideStore, a dev cert, etc.).

Every push to `main` builds a fresh unsigned `.ipa` automatically (see `.github/workflows/build.yml`).

## What's in it

- **7 stores**, each its own level with day count, profit goal and rating goal: Corner Grocery, Hardware Depot, Neighborhood Pharmacy, Electronics Outlet, Pet Supply Co., Garden Center, City Supermarket.
- **Real store loop**: order from the computer, boxes land in the loading area, carry them to shelves / fridges / freezers, stock item by item.
- **Customers** with shopping lists, patience, price sensitivity and opinions. Empty shelves, high prices, long lines and wrong change hurt your rating.
- **Checkout**: scan each item, card payments at the reader, cash payments by counting change from the drawer.
- **Shoplifters**: spot them heading for the door and stop them.
- **Skills with cooldowns**: Sprint, Rush Restock, Express Scan, Crowd Calm, Eagle Eye.
- **Lunch and after-work rushes**, daily rent, star ratings per store.
- **Lots of settings**: HUD size/opacity/text size, every HUD element toggleable, crosshair style/color/size, FOV, head bob, camera smoothing, frame rate, left-handed layout, floating or fixed stick, stick/button size, look sensitivity, invert Y, colorblind modes, high-contrast HUD, reduce motion, haptics, currency symbol, plus game rules (difficulty presets, day length, traffic, patience, price sensitivity, shoplifters, cash share, rent, delivery speed, cooldowns, walk speed, manual change, and more).

## Controls

- **Left side**: move (floating stick).
- **Right side**: drag to look, tap something to interact with it.
- **Hand button**: interact with whatever's under the crosshair (hold it on a shelf to stock fast).
- **Drop**: put your box down, or take one item back off a shelf.
- **Skill buttons**: arc above the hand button.

## Building locally (Mac)

```bash
brew install xcodegen
xcodegen generate
open OCrew.xcodeproj
```
