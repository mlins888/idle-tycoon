# Plan: Fantasy idle town builder (native iOS)

## Context
The user plays *My Little Pony: Magic Princess* and is frustrated that it is outdated: every shop must be tapped by hand to collect, and there is no automation. Attempts to automate the real game didn't work (iPhone Mirroring input is ignored, and the game traffic is not accessible), so the user wants to build their own game instead.

Decisions already made:
- **Platform:** native iOS app.
- **Theme:** original fantasy world with humanoid mythical beings (magical humans, elves, animal-folk, and so on).
- **Map:** isometric, build anywhere on a grid (MLP-style), pan and zoom.
- **Art:** the user will draw all world and UI art eventually. Until then we use placeholders, so the code must make swapping art trivial.
- **Extras wanted:** collectible characters, decorations, timed events.
- **Core fixes over MLP:** Collect all, automation, offline earnings.

Starting point: there is no existing code; this is a new project. Xcode is installed at `/Applications/Xcode.app`, but the active developer directory points to Command Line Tools. The user must run `sudo xcode-select -s /Applications/Xcode.app` once (it needs their password).

Name: **Fenlight**. Currency: **glimmer**. Premise: the Lantern Thief stole every light in the fen and the town sank into gloom; the player cleanses the murk (this is how land expands) and the town regains colour as it is restored.

## Architecture

**Stack:** SwiftUI app shell and HUD/menus, plus a SpriteKit scene for the map (embedded with `SpriteView`). No server, ads or purchases. Target iOS 18+, iPhone first.

**Three strict layers**, so game logic can be tested and art can be swapped:
1. **Model (pure Swift, no UI imports):** `GameState`, economy rules, grid occupancy, residents, events. Fully unit-testable.
2. **Content (data files):** JSON definitions for buildings, residents, decorations and events. New content means editing JSON, not code.
3. **Presentation:** SpriteKit for the map, SwiftUI for the HUD and panels. Reads the model and sends actions to it.

**Time-based economy (not timers):** each shop stores `lastCollectedAt`. Earnings are computed as `min(cap, rate × elapsed)`. This makes offline earnings, Collect all and save/load automatic and exact. A single game clock is used everywhere so tests can fake time.

**Isometric grid:**
- 2:1 diamond tiles, 256×128 px art at @2x.
- Grid to screen: `x = (c − r)·W/2`, `y = −(c + r)·H/2`. Screen to grid uses the inverse, for taps and placement.
- Buildings have footprints (1×1, 2×2, 3×3) stored in an occupancy grid. Placement shows a green or red ghost, and buildings can be moved or put into storage.
- Depth sorting: `zPosition` comes from the footprint's front corner `(c + r)`, so tall buildings overlap correctly.
- Land expands in purchasable chunks (like MLP), so the map grows with the town.
- Camera: `SKCameraNode` with pan and pinch zoom, clamped to the owned land.

**Art pipeline (built for the user's own art):**
- Every sprite is looked up by ID through one `ArtCatalog` (for example `building.bakery.lv1`, `tile.grass`). Missing art falls back to a generated placeholder (a colored diamond or box with a label), so the game never breaks while art is unfinished.
- An **Art spec** doc in the repo lists the tile size, canvas size per footprint, anchor point (bottom center of the footprint diamond), naming, @2x/@3x, and transparent PNG.
- The UI uses theme tokens (colors, fonts) plus 9-slice image slots for panels and buttons, so the user's UI art drops in without layout changes.
- Placeholders: free CC0 isometric packs from Kenney.nl.

**Saving:** Codable JSON in Application Support, versioned for future migrations. Autosaves on every meaningful action and when the app goes to the background. iCloud sync comes later.

## Proposed project layout
```
Fenlight/
  App/            FenlightApp.swift, RootView.swift
  Model/          GameState, Economy, Grid, Building, Resident, Decoration, EventCalendar, GameClock
  Content/        buildings.json, residents.json, decorations.json, events.json
  Map/            TownScene (SpriteKit), IsoMath, CameraController, PlacementController, ArtCatalog
  UI/             HUDView, ShopPanel, BuildMenu, ResidentsView, Theme
  Persistence/    SaveStore
  Assets.xcassets (placeholders → user art)
FenlightTests/  EconomyTests, IsoMathTests, GridTests, SaveTests
docs/ART_SPEC.md
```

## Roadmap (each phase ends playable on the phone)

**Phase 0: Setup**
- Xcode project, folders, test target, Git repo.
- Placeholder art imported; `ArtCatalog` with fallback sprites.

**Phase 1: Build anywhere, earn, collect**
- An isometric map with pan and zoom, starting land, and expansions.
- A build menu: place, move and store buildings with valid/invalid ghosts.
- 6–8 shop types with timer-based earnings and storage caps. Tap to collect, with a floating "+X" animation.
- **Collect all** button. Upgrades raise a shop's rate and cap.
- Saving, plus offline earnings with a "While you were away…" summary.
- Town level and XP that unlock new buildings.

**Phase 2: Residents as helpers (automation)**
- First residents (for example a human hedge-mage, an elf herbalist, a fox-folk merchant) move into **houses**. Houses are buildings, and their capacity limits how many residents you have.
- Assign a resident to a shop: it **auto-collects** that shop and adds a race or skill bonus. This makes the automation part of the fantasy instead of a menu toggle.
- Milestone speed boosts, local "shop is full" notifications, sounds and haptics.

**Phase 3: Characters as a collection**
- More races: elves, dwarves, fae, beast-folk (wolf, owl, cat, stag), merfolk and others. Each has rarity, a favorite shop type and a portrait slot.
- Residents walk around the map: simple hops between free adjacent tiles, idling near their workplace.
- A collection screen ("Townsfolk registry"), with arrivals unlocked by town level and special buildings.

**Phase 4: Decorations**
- Decorations placed on the grid with the same placement system, from 1×1 lanterns up to 2×2 fountains.
- Aura bonuses: shops within N tiles get +X% speed. The aura radius is shown while placing.

**Phase 5: Timed events**
- `events.json` holds yearly date windows (for example Midwinter Lights, Bloom Festival, Harvest Moon) that repeat every year, so no server is needed.
- Event currency, limited shops, decorations and residents, plus an event progress track.

**Later:** the user's final art and UI, iCloud sync, TestFlight for friends, and the App Store (needs the $99/year Apple Developer Program; running on your own phone is free).

## Verification
- **Unit tests (XCTest):**
  - Economy: earnings over elapsed time, caps, offline and Collect all totals, with a fake clock.
  - Iso math: round-trip grid ↔ screen.
  - Grid: overlap and bounds rejection for footprints.
  - Save: encode → decode equality and version migration.
- **Simulator:** build and run each phase in the iOS Simulator. Verify pan/zoom, placement ghosts, depth ordering of overlapping buildings, collect and Collect all, and offline earnings (by changing the fake clock offset in a debug menu).
- **Device:** run on the user's iPhone 15 Pro (free Apple ID signing, Developer Mode on) at the end of each phase.
- **Debug menu (debug builds only):** add currency, skip time, reset save. This speeds up manual testing.

## Open items (can be decided during Phase 1)
- Final names for the town, currency and app.
- Starting shop list and balance numbers. I'll propose a first-pass table in Phase 1, and you can tune it.
- Offline earning cap (proposed: 8 hours).

## Status

- **Phase 0–1: done.** Isometric map, cleansing, build anywhere, collect / Collect all, upgrades, levels, saving, offline summary.
- **Phase 2: done.** As built:
  - Arrivals are a mix: *story* residents join at set town levels, *wanderers* turn up every 20–40 minutes when there's a free bed, and rarer residents are *summoned* at the Wisp Shrine with wisps (earned from cleansing and levelling up; no real money).
  - Houses (Reed Cottage, Stilt House, Willow Lodge) provide beds.
  - Workers give +25% to a shop, +60% at their favourite. Collecting stays by hand until the Lamplighters' Guild (level 7) unlocks Keeper's Charters, which let a shop's worker collect automatically (up to 8 hours while away).
  - Shop levels 5 and 10 double that shop's speed. One "shop is full" reminder is scheduled when the app goes to the background. Haptics on collect, build and arrivals.
- **Stages and quests: done.** Endless levels 1–10 were replaced by 2–3 **stages** per building (e.g. Mossbread Oven → Mossbread Bakery → Bogberry Patisserie), each selling more goods and earning about 3× more. Reaching a stage needs requirements (town level, other buildings, residents, quests, % restored) and a timed **renovation** behind scaffolding (finish early with wisps). 12 shops, 3 houses with stages. A simple **quest** system (15 quests, chapter 1) where residents ask for things; several stages require quests.
- **Phase 4 (decorations): done.** 8 decorations (boardwalk, marsh marigolds, rushlight post, weeping willow, frog-king statue, lily pond, wisp fountain, lantern arch). Most boost shops within a few tiles (+3% to +15%), stacking up to +50% per shop. The aura is outlined while placing; decorations can be moved or put away for half their cost. New quest: "Light the Way".
- **Future direction:** a larger overarching storyline (chasing the Lantern Thief) built on the quest chapters, possibly with puzzle or combat gameplay as new quest objective types.
- **Still to do:** Phase 3 (residents walking around the map, a fuller collection screen), Phase 5 (timed events), a playtest and balance pass.
