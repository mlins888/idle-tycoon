# Fenlight art spec

Every sprite and UI piece is looked up by name. To replace a placeholder, add a PNG to
`Fenlight/Assets.xcassets` with the **exact asset name** below. The game uses it automatically the
next time you build. Anything without art falls back to a drawn placeholder, so you can replace things
one at a time.

## Templates

Guide templates for every size below are in `art/templates/2x/` (the sizes in this spec) and
`art/templates/3x/`. Import one into Procreate or Figma as the bottom layer, lock it, draw above it,
and hide it before exporting. Regenerate them with `python3 tools/make_art_templates.py`.

- `building_1x1.png`, `building_2x2.png`, `building_3x3.png`: the footprint (blue), wall guides up
  from its corners (pink), the anchor (red) and a resident for scale.
- `tile.png`: one ground tile.
- `walker.png`: a walking figure, with the feet line.
- `portrait.png`: a portrait, with the circle crop.
- `town_mockup_grid.png`: an 8 × 8 tile grid for painting a whole-town style mockup.

Fenlight uses **2:1 isometric** (about 26.6°: two pixels across for one up). Procreate's built-in
isometric drawing guide is 30°, which won't line up with the tiles, so use these templates instead.

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

**Decorations** use the same naming and canvas rules (`building.rushlight_post`, `building.lily_pond`).
They're usually small, so most of the canvas can be transparent. Paths should be flat and fill the
footprint diamond.

## Resident portraits

Asset name: `resident.<id>`, where `<id>` is the resident's `id` in `Fenlight/Content/residents.json`
(for example `resident.wren`).

- Square, 512 × 512 (@2x) or 768 × 768 (@3x). Dialogue scenes show portraits at 150 pt, so smaller
  art looks soft. Shown cropped to a circle in lists, so keep the face in the middle.
- Until a portrait exists, the game shows the resident's initials on their `color`.

## Story portraits

Shown large in dialogue scenes (150 pt). Square, 512 × 512 (@2x) or 768 × 768 (@3x), transparent or
painted background.

| Asset name | Who |
|------------|-----|
| `resident.<id>` | A resident (the same portrait used everywhere) |
| `character.<id>` | Someone who speaks in scenes but isn't a resident (ids in `characters.json`) |
| `player` | The player character (the Surfaced) |

Until art exists, each shows initials on the character's colour.

## Walking residents

Asset name: `walker.<id>` (for example `walker.wren`). The small figure that walks around the map.

- 48 × 72 (@2x 96 × 144). Transparent background.
- Feet near the bottom centre (the game anchors the image 8% up from the bottom).
- Draw them facing right; the game flips the image when they walk left.

## Effects

| Asset name | What it is | Notes |
|------------|------------|-------|
| `fx.wisp`  | A lost wisp drifting over town | About 48 × 48 (@2x 96 × 96), glowing, transparent background |

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
