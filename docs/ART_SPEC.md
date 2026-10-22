# Fenlight art spec

Every sprite and UI piece is looked up by name. To replace a placeholder, add a PNG to
`Fenlight/Assets.xcassets` with the **exact asset name** below. The game uses it automatically the
next time you build. Anything without art falls back to a drawn placeholder, so you can replace things
one at a time.

## Ground tiles

| Asset name   | What it is                     | Size (@2x) |
|--------------|--------------------------------|------------|
| `tile.grass` | Restored, cleansed ground      | 256 × 128  |
| `tile.murk`  | Murk-choked bog (locked land)  | 256 × 128  |

- 2:1 isometric diamond: the diamond touches all four edges of the canvas.
- Transparent outside the diamond.
- Draw restored ground fairly bright and saturated. The game tints it grey and gloomy early on and
  removes the tint as the fen is restored, so you only draw one version.

## Buildings

Asset name: `building.<id>`, where `<id>` is the building's `id` in `Fenlight/Content/buildings.json`
(for example `building.mossbread`, `building.reed_cottage`, `building.wisp_shrine`).

**Stages:** stage 1 uses `building.<id>`. Later stages add the stage number: `building.mossbread.2`
(Mossbread Bakery), `building.mossbread.3` (Bogberry Patisserie). Same canvas width as stage 1; later
stages can be taller. Stage names are in `buildings.json`.

- Footprints are square: 1×1, 2×2 or 3×3 tiles (`size` in buildings.json).
- **Canvas width** = 256 × size (@2x). So a 2×2 building is 512 px wide.
- **Canvas height** is up to you (taller buildings are fine).
- **Anchor:** the bottom-centre pixel of the canvas sits on the bottom corner of the footprint diamond.
  In other words, draw the footprint diamond touching the bottom edge and both side edges of the canvas,
  and let the building rise above it.
- Transparent background.

| Size | Canvas width (@2x) | Footprint diamond (@2x) |
|------|--------------------|-------------------------|
| 1×1  | 256                | 256 × 128               |
| 2×2  | 512                | 512 × 256               |
| 3×3  | 768                | 768 × 384               |

## Resident portraits

Asset name: `resident.<id>`, where `<id>` is the resident's `id` in `Fenlight/Content/residents.json`
(for example `resident.wren`).

- Square, 256 × 256 (@2x). Shown cropped to a circle, so keep the face in the middle.
- Until a portrait exists, the game shows the resident's initials on their `color`.

## UI

| Asset name  | What it is                     | Notes                                  |
|-------------|--------------------------------|----------------------------------------|
| `ui.panel`  | Background of every HUD panel  | Stretchable; keep 24 pt corners plain  |
| `ui.button` | Background of every button     | Stretchable; keep 24 pt corners plain  |

Panel and button art is stretched with 24 pt cap insets: the outer 24 points on each side are kept
as drawn and the middle stretches. Colours and fonts live in `Fenlight/UI/Theme.swift`.

## Resolutions

Supply @2x and @3x where you can (Xcode's image set has slots for both). If you only have one size,
put the @2x image in the 2x slot.
