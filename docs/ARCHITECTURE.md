# How Fenlight is built

This doc explains how the code is organised and what each file does. Start here if you're new to
the project or coming back after a break.

## The three layers

The code is split so each part has one job:

| Layer     | Folder           | Job                                                                 | Built with |
|-----------|------------------|---------------------------------------------------------------------|------------|
| **Model** | `Fenlight/Model` | The rules of the game: money, buildings, land, earnings. No UI code. | Plain Swift |
| **Map**   | `Fenlight/Map`   | Draws the isometric town and turns taps, drags and pinches into actions. | SpriteKit (Apple's 2D game engine) |
| **UI**    | `Fenlight/UI`    | Buttons and panels on top of the map: top bar, Collect all, menus. | SwiftUI (Apple's UI framework) |

**The Map and UI never change game data directly.** They ask the Model ("build this here",
"collect this shop") and the Model decides whether that's allowed. All the rules live in one place,
and the Model can be tested without running the app.

```
            taps, drags                     button presses
   ┌───────────────────────┐          ┌───────────────────────┐
   │   Map (TownScene)     │          │   UI (HUDView, panels) │
   └──────────┬────────────┘          └───────────┬───────────┘
              │ game.collect(), game.build() …     │
              ▼                                    ▼
        ┌──────────────────────────────────────────────┐
        │  Model: Game  (rules + actions)               │
        │    └─ GameState (everything that gets saved)  │
        └───────────────────────┬──────────────────────┘
                                │ save / load
                                ▼
                     Persistence: SaveStore (JSON file)
```

Both the Map and the UI also read from `MapInteraction`, which tracks what the player is doing right
now (browsing, placing a building, moving one) and what's selected.

## Key ideas

### Earnings use timestamps, not timers

Shops don't count up every second. Each placed building remembers **when it was last collected**
(`lastCollectedAt`). Whenever the game needs to know what a shop holds, it calculates:

> waiting = min(capacity, rate × seconds since last collected)

This makes offline earnings free. Close the app for three hours and the same formula gives the right
answer when you reopen it, with no background processing. Collecting resets `lastCollectedAt` to now.
The formulas are in `Economy.swift`.

### One clock

Everything asks `GameClock` for the current time. Tests replace it with a fake clock they control,
and the debug menu's "Skip 1h" adds an offset to it.

### Content lives in data, not code

Every kind of building is described in `Fenlight/Content/buildings.json`. Adding a shop or changing
its cost, size or earning rate means editing that file, with no code changes.

### Art is looked up by name

Every picture is requested by a name like `building.mossbread` or `tile.grass` through `ArtCatalog`.
If `Assets.xcassets` has an image with that name, it's used. Otherwise a placeholder is drawn in code,
so the game always runs while art is unfinished. Names and sizes are in [ART_SPEC.md](ART_SPEC.md).

### SwiftUI updates itself

`Game` and `MapInteraction` are marked `@Observable`. SwiftUI automatically redraws any part of the
screen that reads a value from them when that value changes. That's why the glimmer number in the top
bar updates on its own after a collect.

The SpriteKit map doesn't work that way, so `Game` keeps a `layoutRevision` counter that goes up
whenever buildings or land change. The map checks it every frame and redraws when it changes.

### Isometric grid

The map is a 24 × 24 grid of square tiles, drawn as 2:1 diamonds. A `Tile` has `c` (column, runs
down-right on screen) and `r` (row, runs down-left). Land is grouped into 4 × 4 **chunks**; a chunk is
the block of murk you cleanse all at once. `IsoMath` converts between tiles and screen points, and
decides draw order so buildings lower on the screen draw in front.

## File by file

### Project setup

| File | What it does |
|------|--------------|
| `project.yml` | Recipe XcodeGen uses to generate `Fenlight.xcodeproj`. The generated project isn't in Git; run `xcodegen generate` after adding or removing files. |
| `.gitignore` | Keeps generated and build files out of Git. |

### `Fenlight/App`: startup

| File | What it does |
|------|--------------|
| `FenlightApp.swift` | The app's entry point (`@main`). Opens one window showing `RootView`. |
| `RootView.swift` | Creates the three main objects once (`Game`, `MapInteraction`, `TownScene`), puts the map behind the HUD, shows the "Welcome back" sheet and the "moved in!" / summon cards, and saves when the app goes to the background. |
| `Reminders.swift` | The "your shop is full" local notification: scheduled when the app goes to the background, cancelled when it comes back. |

### `Fenlight/Model`: the rules

| File | What it does |
|------|--------------|
| `World.swift` | Fixed facts about the map: `Tile`, `Chunk`, the map size, the starting land, footprint and neighbour helpers. |
| `Content.swift` | `BuildingDef` (one *kind* of building: shop, house, shrine or guild) and `ResidentDef` (one resident), loaded from `buildings.json` and `residents.json`. |
| `GameState.swift` | Everything that gets saved: glimmer, wisps, XP, placed buildings (`PlacedBuilding`), cleansed chunks, residents (`Resident`), when the next wanderer arrives, and the random generator's state. `newGame()` sets up a fresh town. Decodes older saves by filling in defaults for newer fields. |
| `Residents.swift` | Rules about residents as plain functions: beds, who's waiting for a bed, who can wander in next, summon odds and the summon roll. |
| `SeededRandom.swift` | A small repeatable random generator. Its state is saved, so summons can't be re-rolled by restarting the app. |
| `Economy.swift` | All balance formulas: earning rates, milestone speed-ups, worker bonuses, capacity, build/upgrade/cleanse/charter costs, wisps, summon cost, wanderer timing, the offline cap, XP per level. Tune the game here. |
| `GameClock.swift` | The one source of "now". |
| `Game.swift` | The heart of the game. Holds `GameState` and has a method for every action: `collect`, `collectAll`, `build`, `move`, `upgrade`, `cleanse`, `assignWorker`, `summon`, `buyCharter`. Each checks the rules, changes the state and saves. `tick()` runs about once a second: keepers collect, residents arrive, level-ups pay wisps. Also builds the "Welcome back" summary and has the debug helpers. |

### `Fenlight/Content`

| File | What it does |
|------|--------------|
| `buildings.json` | Every building: shops (earning rate, how long they take to fill, max level), houses (beds), the Wisp Shrine and the Lamplighters' Guild. Fields that don't apply to a kind can be left out. |
| `residents.json` | Every resident: name, folk, description, rarity, how they arrive (`wanderer`, `story` or `summon`), unlock level, favourite shop, placeholder colour. |

### `Fenlight/Map`: the town you see

| File | What it does |
|------|--------------|
| `IsoMath.swift` | Tile ↔ screen conversions, where a building's picture is anchored, draw order, and outline shapes for footprints and chunks. |
| `TownScene.swift` | The SpriteKit scene. Creates the ground tiles, redraws buildings and land when `layoutRevision` changes, refreshes glimmer bubbles a few times a second, calls `game.tick()` once a second, shows the placement preview, and handles pan, pinch and tap. |
| `BuildingNode.swift` | One building on the map: its picture, the glimmer bubble above it (which bobs when full), coloured dots for its workers, and a glowing lantern when a keeper collects it. |
| `MapInteraction.swift` | What the player is doing right now (browsing, placing, moving) and what's selected. Shared by the map and the HUD. |
| `ArtCatalog.swift` | Looks up art by name and falls back to drawn placeholders. The `Placeholder` section draws the stand-in buildings (shaped differently per kind), tiles and resident portraits. Also small colour helpers. |

### `Fenlight/UI`: buttons and panels

| File | What it does |
|------|--------------|
| `Theme.swift` | UI colours (including rarity colours), fonts, the panel style (`fenPanel()`), button style, coin and wisp icons. Uses `ui.panel` / `ui.button` art when it exists. |
| `HUDView.swift` | The overlay. Top bar (glimmer, wisps, level, restoration %). The bottom area switches between Collect all + Townsfolk + Build, the placement Cancel/Confirm bar, the tapped building's panel (shop, house, shrine or guild), or the cleanse panel. |
| `Panels.swift` | `BuildingPanel` (with worker slots and the Keeper's Charter), `HousePanel`, `ShrinePanel`, `GuildPanel`, `CleansePanel`, `BuildMenu`, `WelcomeBackView`, and `DebugMenu` (debug builds only). |
| `ResidentsView.swift` | The Townsfolk screen (everyone in town, where they work, who's on the way), resident `Portrait`s, and the `ArrivalCard`. |
| `Haptics.swift` | Small vibrations on collect, build and arrivals. |
| `Format.swift` | Short number and time text: 12,345 → "12.3K", 8,100 s → "2h 15m". |

### `Fenlight/Persistence`

| File | What it does |
|------|--------------|
| `SaveStore.swift` | Saves `GameState` as JSON in the app's Application Support folder and loads it back. Has a `migrate` step so old saves keep working when the save format changes. |

### `FenlightTests`

| File | What it does |
|------|--------------|
| `FenlightTests.swift` | Automated checks for earnings, collecting, upgrades, levels, placement rules, cleansing, tile ↔ screen maths and saving. Uses a fake clock and its own small building list, so rebalancing `buildings.json` doesn't break them. |
| `ResidentTests.swift` | Checks for arrivals (story, wanderers, while away), summoning (odds, repeatability, duplicates), worker bonuses, auto-collect and the offline cap, wisps, and loading version 1 saves. |

## Walkthroughs

### Tapping a shop to collect

1. `TownScene.handleTap` receives the tap and converts the screen point to a tile with `IsoMath.tile(at:)`.
2. `buildingHit` finds which building was tapped.
3. It calls `game.collect(id)`. `Game` works out the waiting glimmer, adds it to your total, resets the shop's `lastCollectedAt` and saves.
4. The scene shows a floating "+X" and hides the bubble.
5. SwiftUI sees `glimmer` changed and the top bar updates.

If the shop had nothing to collect, the tap selects it instead and `HUDView` shows its `BuildingPanel`.

### Building a shop

1. Choosing a shop in `BuildMenu` calls `ui.startPlacing(defId)`, switching `MapInteraction` to *placing*.
2. Each frame, `TownScene` draws a preview ("ghost") at `ui.ghostOrigin`, green or red depending on `game.canPlace`.
3. Taps on the map move `ghostOrigin`.
4. Confirm in `PlacementBar` calls `game.build`, which checks level, cost and space, deducts the cost and adds the building.
5. `layoutRevision` goes up, so the scene adds the new building on its next frame.

### Cleansing murk

1. Tapping a murk tile selects its chunk; the scene outlines it and `HUDView` shows `CleansePanel`.
2. `game.canCleanse` only allows chunks next to land that's already clear.
3. `game.cleanse` deducts the cost, adds XP and wisps, and marks the chunk cleansed.
4. The scene redraws the ground, and `applyRestorationTint` makes the whole fen a little less grey.

### Residents arriving

Residents need a bed, so houses come first. `tick()` calls `processArrivals()`:

1. **Story residents** whose unlock level you've reached move in straight away if there's a bed (Wren, the first one, takes the starting cottage).
2. **Wanderers**: if there's a free bed and someone left to come, `nextWandererAt` is set 20–40 minutes ahead. When that time passes they move in, and the next one is scheduled. Because this compares timestamps, wanderers also arrive while the app is closed.
3. Each arrival goes into `arrivalQueue`, and `RootView` shows a "moved in!" card for each. If you were away, the Welcome back screen lists them instead.

**Summoning** is separate: at the Wisp Shrine, `game.summon()` spends wisps, rolls a rarity by weight and picks someone of that rarity. If they already live in town, some wisps come back.

### Workers and auto-collect

1. A shop's panel has a worker slot (big shops have two). `game.assignWorker` puts a resident there. Their bonus is +25%, or +60% at their favourite shop.
2. Before any change to a shop's rate (assigning, removing, upgrading), `settle` pays out what the shop earned so far, so a new rate never applies to time that already passed.
3. Once the Lamplighters' Guild is built (level 7), a shop with a worker can get a **Keeper's Charter** (`game.buyCharter`). From then on `isAuto` is true: the shop shows a lantern instead of a bubble, and `tick()` pays its earnings straight into your glimmer. While you're away it keeps earning past the normal shop limit, up to `Economy.offlineCap` (8 hours).

### Coming back after time away

1. When the app returns to the foreground, `RootView` calls `game.checkAway()`.
2. That runs `tick()` first, so keepers collect and residents arrive for the time you were gone.
3. If you were gone at least a minute and anything happened (glimmer waiting, keeper earnings or new residents), it creates an `AwaySummary`.
4. `RootView` shows `WelcomeBackView`, whose Collect all calls `game.collectAll()`.

## Common changes

| I want to… | Where |
|------------|-------|
| Add or rebalance a building | `Fenlight/Content/buildings.json` |
| Add a resident | `Fenlight/Content/residents.json` |
| Change how fast things grow or cost | `Fenlight/Model/Economy.swift` |
| Change the map size or starting land | `Fenlight/Model/World.swift` |
| Change what a new game starts with | `GameState.newGame` in `Fenlight/Model/GameState.swift` |
| Add a new player action | A method on `Game` in `Fenlight/Model/Game.swift`, then a button in `Fenlight/UI` |
| Add my own art | Assets.xcassets, using the names in [ART_SPEC.md](ART_SPEC.md) |
| Change UI colours or fonts | `Fenlight/UI/Theme.swift` |
| Change the save format | `GameState`, bump `currentVersion`, add a step in `SaveStore.migrate` |

After adding or removing files, run `xcodegen generate`. After changing any rules, run the tests:

```bash
xcodebuild test -scheme Fenlight -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
