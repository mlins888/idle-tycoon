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

### Shops work in production runs

Each shop stage has a **production time** (`cycleSeconds`) and a **payout**. A shop is either
*working* (a progress bar shows over it) or *ready* (a bubble shows the payout). You can only collect
when a run has finished, and a finished batch waits for you; batches don't stack up. Collecting pays
the batch and starts the next run. The first shop pays 5 glimmer a minute; later shops take longer
and pay far more (see the table in `buildings.json`).

Runs are worked out from timestamps, not timers: each shop remembers when its current run started
(`lastCollectedAt`), and "ready" just means `now − start ≥ cycle`. So time passing while the app is
closed needs no background work. **Keepers** collect every whole run that finished
(`Economy.runsCompleted`), up to 8 hours while you're away. Worker and decoration bonuses raise the
payout.

### One of each business

A town can have one of each kind of shop, plus a second once the first reaches its final stage
(`Game.canBuildMore`). The second costs 3× as much. Homes and decorations have no limit. A new town
starts on a single 4×4 patch, so each patch of murk you cleanse matters.

### Wisps

Wisps are scarce. About every 30–60 minutes a lost wisp drifts over town for 90 seconds; tap it to
catch it (`Game.catchWisp`). The schedule is saved (`nextWispAt`, `wispVisibleUntil`), so restarting
the app doesn't reroll it. Wisps also come from cleansing, levelling up and some quest and festival
rewards. Every gain shows a toast ("+3 wisps · cleansed the murk"), and tapping the wisp counter
explains where wisps come from and what they're for.

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

### Stages instead of levels

Buildings don't level up forever. Each has a few **stages** that change what it *is*: the Mossbread Oven
(sells mossbread) becomes the Mossbread Bakery (mossbread and honey cakes), then the Bogberry Patisserie.
Each stage has its own name, goods, earnings and art, and is reached by **renovating**: pay the cost
once its **requirements** are met (town level, another building at a stage, a resident living in town,
a finished quest, or how much of the fen is restored), then the building closes for a while and reopens
transformed. Growth comes from more kinds of buildings and more stages, defined in `buildings.json`.

### Decorations

Lanterns, flowers, paths, trees, statues, ponds and fountains are placed on the grid like buildings
(`kind: "decoration"` in `buildings.json`). Most have an **aura**: shops within `radius` tiles earn
`bonus` more (`World.distance` measures the gap between footprints). Auras from several decorations
stack, up to `Economy.maxDecorationBonus` (+50%) per shop, so where you put things matters. Paths
have no aura. Placing, moving or putting away a decoration first pays out every shop at its old rate,
so a new bonus never applies to time that already passed.

### Residents on the map

Residents walk around town, purely for show (none of it is saved). Each hangs around their workplace,
or their home if they don't have a job: they pick a nearby free tile, walk there along a route that
goes around buildings (`Walkways.path`), wait a few seconds, and repeat. Sometimes they visit another
shop instead. Now and then one says a line from their `chatter` in a speech bubble. Tap someone to see
who they are and give them a job. The **Registry** tab of the Townsfolk screen lists everyone in the
game, with folk you haven't met shown as silhouettes and a hint about how to meet them.

### Festivals

Four festivals (`events.json`) run on the same dates every year, so no server is needed: Bloom
Festival (spring), Midsummer Fireflies, Hollow Moon (autumn) and Midwinter Lights. `EventCalendar`
works out which one is running from the phone's date (a window can wrap past New Year). During a
festival, collecting by hand earns festival tokens: 1 per 5 minutes of production collected, so a
1-hour shop earns 12 per collect and the 1-minute stall earns a fifth of one. Token
milestones give wisps and glimmer, unlock festival-only decorations (`eventOnly`, buildable forever
once unlocked) and invite a festival resident (arrival `event`), who moves in when there's a bed.
Progress starts over when the festival comes round the next year.

### Quests

Residents ask for things: collect glimmer from a shop, build something, reach a stage, cleanse murk,
grow the town. Quests live in `quests.json`. Several stages require a quest, which is how the story
gates progress. Up to three are active at once; finishing one can unlock the next. Each quest has a
`chapter`, so a longer storyline (and later, other kinds of objectives) can grow out of this.

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
| `World.swift` | Fixed facts about the map: `Tile`, `Chunk`, the map size, the starting land, footprint and neighbour helpers, and the distance between two footprints (for decoration auras). |
| `Content.swift` | The shapes of the content files: `BuildingDef` (one *kind* of building) with its `StageDef`s, `Requirement`, `ResidentDef`, and `QuestDef` with its `Objective` and `Reward`. Loaded from `buildings.json`, `residents.json` and `quests.json`. |
| `GameState.swift` | Everything that gets saved: glimmer, wisps, XP, placed buildings (`PlacedBuilding`, with their stage and any renovation in progress), cleansed chunks, residents (`Resident`), when the next wanderer arrives, the random generator's state, lifetime counters for quests (`Stats`), active and finished quests. `newGame()` sets up a fresh town. Decodes older saves by filling in defaults for newer fields. |
| `Residents.swift` | Rules about residents as plain functions: beds, who's waiting for a bed, who can wander in next, summon odds and the summon roll. |
| `SeededRandom.swift` | A small repeatable random generator. Its state is saved, so summons can't be re-rolled by restarting the app. |
| `Economy.swift` | Game-wide balance formulas: payouts, when a run is ready, how many runs a keeper collects, worker bonuses, the decoration bonus cap, the refund for putting a decoration away, capacity, build/cleanse/charter costs, the wisp cost to finish a renovation early, wisps, summon cost, wanderer timing, the offline cap, XP per level. (Per-building numbers live in `buildings.json`.) |
| `Requirements.swift` | Checks a requirement (town level, a building at a stage, a resident, a finished quest, % restored) and describes it in plain words. Used by building stages and quests. |
| `EventCalendar.swift` | Festival dates: which festival is running at a given moment, its start and end, and the next one to come. |
| `Quests.swift` | Quest rules as plain functions: which quests can start, the counter value to remember when one starts, and how far along an objective is. |
| `GameClock.swift` | The one source of "now". |
| `Game.swift` | The heart of the game. Holds `GameState` and has a method for every action: `collect`, `collectAll` (both also earn festival tokens), `build`, `move`, `removeDecoration`, `startRenovation`, `finishRenovationNow`, `cleanse`, `assignWorker`, `summon`, `buyCharter`, `claimQuest`. Each checks the rules, changes the state and saves. `tick()` runs about once a second: renovations finish, keepers collect, festivals start and pay milestone rewards, residents arrive, quests start, level-ups pay wisps. Keeps the `announcements` queue (arrivals, finished renovations, finished quests), builds the "Welcome back" summary and has the debug helpers. |

### `Fenlight/Content`

| File | What it does |
|------|--------------|
| `buildings.json` | Every building and its **stages**. Each stage has a name, description, what it sells, earning rate and how long it holds (shops) or beds (houses), plus the renovation cost, time and requirements to reach it. Fields that don't apply can be left out. |
| `events.json` | The festivals: dates (`MM-DD`), token names, colour, and the milestone reward track. |
| `quests.json` | Every quest: chapter, who gives it, title, text, the objective, the reward, and prerequisites. |
| `residents.json` | Every resident: name, folk, description, rarity, how they arrive (`wanderer`, `story` or `summon`), unlock level, favourite shop, placeholder colour. |

### `Fenlight/Map`: the town you see

| File | What it does |
|------|--------------|
| `IsoMath.swift` | Tile ↔ screen conversions, where a building's picture is anchored, draw order, and outline shapes for footprints and chunks. |
| `TownScene.swift` | The SpriteKit scene. Shows the drifting lost wisp and handles catching it. Hosts the walking residents (`TownsfolkLayer`). Outlines a decoration's aura while placing it or when it's selected. Creates the ground tiles, redraws buildings and land when `layoutRevision` changes, refreshes glimmer bubbles a few times a second, calls `game.tick()` once a second, shows the placement preview, and handles pan, pinch and tap. |
| `BuildingNode.swift` | One building on the map: its picture, a progress bar while its run is going, the glimmer bubble above it (which bobs when full), coloured dots for its workers, and a glowing lantern when a keeper collects it. |
| `Walkways.swift` | Where residents can walk (cleansed land without buildings, plus paths), routes around buildings, nearby spots, and the nearest free tile. Plain functions, unit-tested. |
| `TownsfolkLayer.swift` | Residents walking around the map: picks where each one goes next, moves them along their route, keeps their draw order right, shows speech bubbles, and finds who was tapped. `ResidentNode` is one walking resident. |
| `MapInteraction.swift` | What the player is doing right now (browsing, placing, moving) and what's selected (a building, a murk chunk or a resident). Shared by the map and the HUD. |
| `ArtCatalog.swift` | Looks up art by name and falls back to drawn placeholders. The `Placeholder` section draws the stand-in buildings (shaped differently per kind and stage), decorations (by their `shape`), tiles, resident portraits, and the little walking figures (ears for animal-folk, wings for fae, hats for witches). Also small colour helpers. |

### `Fenlight/UI`: buttons and panels

| File | What it does |
|------|--------------|
| `Theme.swift` | UI colours (including rarity colours), fonts, the panel style (`fenPanel()`), button style, coin and wisp icons. Uses `ui.panel` / `ui.button` art when it exists. |
| `HUDView.swift` | The overlay. Top bar (glimmer, wisps, level, restoration %). The bottom area switches between Collect all + Townsfolk + Build, the placement Cancel/Confirm bar, the tapped building's panel (shop, house, shrine or guild), or the cleanse panel. |
| `Panels.swift` | `BuildMenu` (tabs: Shops, Homes, Decor, Special, with the reason anything is locked), `DecorationPanel` (what it boosts, move, put away), `BuildingPanel` (what it sells, worker slots, the Keeper's Charter, the next-stage card with its requirement checklist, and renovation progress), `HousePanel`, `ShrinePanel`, `GuildPanel`, `CleansePanel`, `BuildMenu`, `WelcomeBackView`, and `DebugMenu` (debug builds only). |
| `EventView.swift` | The festival banner under the top bar and the festival reward track sheet. |
| `WispInfoView.swift` | `ToastView` (the short "+3 wisps · …" messages) and the sheet explaining wisps. |
| `QuestLog.swift` | The quest log sheet, reward rows, and `NoticeCard` (the popup for finished renovations and quests). |
| `ResidentPanel.swift` | `ResidentPanel` (shown when you tap someone on the map, with a job picker) and `RegistryGrid` (everyone in the game, with hints for folk you haven't met). |
| `ResidentsView.swift` | The Townsfolk screen with In town (everyone here, where they work, who's on the way) and Registry tabs, resident `Portrait`s, and the `ArrivalCard`. |
| `Haptics.swift` | Small vibrations on collect, build and arrivals. |
| `Format.swift` | Short number and time text: 12,345 → "12.3K", 8,100 s → "2h 15m". |

### `Fenlight/Persistence`

| File | What it does |
|------|--------------|
| `SaveStore.swift` | Saves `GameState` as JSON in the app's Application Support folder and loads it back. Has a `migrate` step so old saves keep working when the save format changes. |

### `FenlightTests`

| File | What it does |
|------|--------------|
| `FenlightTests.swift` | Automated checks for earnings, collecting, levels, placement rules, cleansing, tile ↔ screen maths and saving. Uses a fake clock and its own small building list, so rebalancing `buildings.json` doesn't break them. |
| `EventTests.swift` | Checks for festival dates (including wrapping past New Year), earning tokens, milestone rewards, festival residents, progress resetting each year, loading version 3 saves, and that the shipped festivals are consistent and don't overlap. |
| `BalanceTests.swift` | Checks for the one-of-each rule, keepers collecting whole runs, lost wisps (schedule, catching, fading, surviving a restart), wisp toasts, and Registry sorting. |
| `TestSupport.swift` | Shared test helpers: a shop definition builder, and the roomier 8×8 layout many tests use. |
| `FenlightUITests/FenlightUITests.swift` | Launches the real app from a fresh town and taps through the Build tabs, Townsfolk and Registry, quests, the wisp info and the festival banner, failing if anything crashes or hangs. |
| `WalkwayTests.swift` | Checks for walkable land, walking on paths, routes around buildings, unreachable spots, and that every resident has something to say. |
| `DecorationTests.swift` | Checks for footprint distance, aura reach and stacking, the cap, paths, paying out before a change, moving, putting away and costs. |
| `StageQuestTests.swift` | Checks for stages and renovation (requirements, paying out, closing and reopening, finishing while away, finish-now, house beds), quests (starting, progress, claiming, follow-ups, the three-quest limit), and that every id referenced in the shipped JSON exists. |
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

### Renovating a building

1. The building's panel shows a **Next stage** card: the new name, what it will sell, the earnings change, and a checklist of requirements (`game.unmetRequirements`).
2. **Renovate** calls `game.startRenovation`, which pays out what the building had earned, takes the cost and sets `renovationEndsAt`.
3. While closed it earns nothing; the map shows scaffolding with a countdown, and the panel offers **Finish now** for wisps.
4. `tick()` finishes it when the time passes (even if the app was closed): the stage goes up, the art changes, and a "now the Bogberry Patisserie!" card is queued.

### Quests

1. `tick()` starts any quest whose giver lives in town and whose prerequisites are met, up to three at once. It remembers the relevant counter (for example glimmer collected from bakeries so far).
2. Progress is the counter now minus the counter then (`Quests.progress`). Collecting, cleansing and building update the counters.
3. When a quest is complete, a card announces it and the quest button shows a dot. **Claim reward** (`game.claimQuest`) pays the reward and lets follow-up quests start.

### Coming back after time away

1. When the app returns to the foreground, `RootView` calls `game.checkAway()`.
2. That runs `tick()` first, so keepers collect and residents arrive for the time you were gone.
3. If you were gone at least a minute and anything happened (glimmer waiting, keeper earnings or new residents), it creates an `AwaySummary`.
4. `RootView` shows `WelcomeBackView`, whose Collect all calls `game.collectAll()`.

## Common changes

| I want to… | Where |
|------------|-------|
| Add or rebalance a building, or its stages | `Fenlight/Content/buildings.json` |
| Add a quest | `Fenlight/Content/quests.json` |
| Add or change a festival | `Fenlight/Content/events.json`, plus any `eventOnly` decorations in `buildings.json` and `event` residents in `residents.json` |
| Add a decoration or change its aura | `Fenlight/Content/buildings.json` (`kind: "decoration"`, `aura`, `shape`) |
| Change how far decoration bonuses can stack | `maxDecorationBonus` in `Economy.swift` |
| Change how often lost wisps appear | `wispDelay` / `wispVisibleFor` in `Economy.swift` |
| Change the starting land | `startingChunks` / `startingCenter` in `World.swift`, and `GameState.newGame` |
| Add a new kind of requirement or quest objective | `Requirement` / `Objective` in `Content.swift`, then `Requirements.swift` / `Quests.swift` |
| Add a resident, or what they say | `Fenlight/Content/residents.json` (`chatter`) |
| Change how residents wander | `TownsfolkLayer.swift` (walk speed, wait times, how often they visit other shops or talk) |
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
