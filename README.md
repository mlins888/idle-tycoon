# Fenlight

An idle town-builder for iPhone. The Lantern Thief stole every light in the fen and the town sank
into gloom. Cleanse the murk, rebuild the shops, and bring the town back to life, one lantern at a time.

Built with SwiftUI and SpriteKit. No server, ads or purchases.

## Running it

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open Fenlight.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't checked in. Run `xcodegen generate`
again after adding or removing files.

Run the tests (unit tests, plus a UI test that taps through the main screens) from the command line:

```bash
xcodebuild test -scheme Fenlight -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Layout

| Folder                  | What's there                                                      |
|-------------------------|-------------------------------------------------------------------|
| `Fenlight/Model`        | Game rules and state. Plain Swift, no UI, fully unit-tested.      |
| `Fenlight/Content`      | Building definitions (`buildings.json`). Tune balance here.       |
| `Fenlight/Map`          | The isometric SpriteKit map, placeholder art and the art catalog. |
| `Fenlight/UI`           | SwiftUI HUD, panels, menus and theme.                             |
| `Fenlight/Persistence`  | Save file.                                                        |
| `docs/`                 | Plan and art spec.                                                |

How the code works, file by file: see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Adding your own art: see [docs/ART_SPEC.md](docs/ART_SPEC.md).

Debug builds have a wrench button in the top bar for adding glimmer, skipping time and resetting.
