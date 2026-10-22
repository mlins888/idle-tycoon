import Foundation

/// A square on the isometric grid. `c` runs down-right on screen, `r` runs down-left.
struct Tile: Hashable, Codable {
    var c: Int
    var r: Int
}

/// A block of murk that is cleansed all at once (`World.chunkSize` tiles per side).
struct Chunk: Hashable, Codable {
    var cx: Int
    var cy: Int
}

/// Fixed facts about the map: its size and how land is grouped into cleansable chunks.
enum World {
    static let size = 24
    static let chunkSize = 4
    static var chunksPerSide: Int { size / chunkSize }
    static var chunkCount: Int { chunksPerSide * chunksPerSide }

    /// The patch of fen that is already clear when a new game starts: one 4×4 chunk near the middle.
    static let startingChunks: Set<Chunk> = [Chunk(cx: 2, cy: 2)]

    /// Where the camera starts: the middle of the starting land.
    static let startingCenter = Tile(c: 10, r: 10)

    static func inBounds(_ t: Tile) -> Bool {
        t.c >= 0 && t.r >= 0 && t.c < size && t.r < size
    }

    static func inBounds(_ ch: Chunk) -> Bool {
        ch.cx >= 0 && ch.cy >= 0 && ch.cx < chunksPerSide && ch.cy < chunksPerSide
    }

    static func chunk(of t: Tile) -> Chunk {
        Chunk(cx: t.c / chunkSize, cy: t.r / chunkSize)
    }

    static func origin(of ch: Chunk) -> Tile {
        Tile(c: ch.cx * chunkSize, r: ch.cy * chunkSize)
    }

    /// Every tile covered by a square footprint whose top corner is `origin`.
    static func footprint(origin: Tile, size: Int) -> [Tile] {
        var tiles: [Tile] = []
        for dc in 0..<size {
            for dr in 0..<size {
                tiles.append(Tile(c: origin.c + dc, r: origin.r + dr))
            }
        }
        return tiles
    }

    /// The origin that centres a footprint of `size` on `tile` (used when the player taps a spot).
    static func origin(centeredOn tile: Tile, size: Int) -> Tile {
        let back = (size - 1) / 2
        return Tile(c: tile.c - back, r: tile.r - back)
    }

    /// How many tiles apart two square footprints are: 1 when side by side or diagonal, 0 when overlapping.
    static func distance(_ a: Tile, size sa: Int, _ b: Tile, size sb: Int) -> Int {
        let dc = max(0, max(a.c - (b.c + sb - 1), b.c - (a.c + sa - 1)))
        let dr = max(0, max(a.r - (b.r + sb - 1), b.r - (a.r + sa - 1)))
        return max(dc, dr)
    }

    static func neighbors(of ch: Chunk) -> [Chunk] {
        [Chunk(cx: ch.cx + 1, cy: ch.cy), Chunk(cx: ch.cx - 1, cy: ch.cy),
         Chunk(cx: ch.cx, cy: ch.cy + 1), Chunk(cx: ch.cx, cy: ch.cy - 1)]
            .filter(inBounds)
    }
}
