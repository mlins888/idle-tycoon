import CoreGraphics

/// Converts between grid tiles and scene points for a 2:1 isometric map.
/// Tile (0,0) is the top corner of the map; scene y points up, so rows go downward.
enum IsoMath {
    static let tileWidth: CGFloat = 128
    static let tileHeight: CGFloat = 64

    static func center(of t: Tile) -> CGPoint {
        CGPoint(x: CGFloat(t.c - t.r) * tileWidth / 2,
                y: -CGFloat(t.c + t.r) * tileHeight / 2)
    }

    /// The tile whose diamond contains `p`.
    static func tile(at p: CGPoint) -> Tile {
        let a = p.x / (tileWidth / 2)      // c - r
        let b = -p.y / (tileHeight / 2)    // c + r
        return Tile(c: Int(((a + b) / 2).rounded()), r: Int(((b - a) / 2).rounded()))
    }

    /// The bottom corner of a square footprint. Building sprites are anchored here.
    static func anchor(origin: Tile, size: Int) -> CGPoint {
        let front = center(of: Tile(c: origin.c + size - 1, r: origin.r + size - 1))
        return CGPoint(x: front.x, y: front.y - tileHeight / 2)
    }

    /// Draw order for a footprint, from the centre of its footprint (`c + r` of the centre point).
    /// Using the centre, not the front corner, keeps buildings of different sizes in the right order:
    /// whenever one footprint is fully in front of another along a grid axis and they share a row or
    /// column, its centre sum is at least 1 larger. Walking residents use the same scale (`depth(at:)`).
    static func zPosition(origin: Tile, size: Int) -> CGFloat {
        10 + CGFloat(origin.c + origin.r + size)
    }

    /// Draw order for something standing at a scene point (a walking resident's feet), on the same scale
    /// as `zPosition`: a tile's centre gives the same value as a 1×1 footprint on that tile.
    static func depth(at p: CGPoint) -> CGFloat {
        10 + (-p.y) / (tileHeight / 2) + 1
    }

    /// The four corners (top, right, bottom, left) of a square block of tiles.
    static func corners(origin: Tile, size: Int) -> [CGPoint] {
        let last = size - 1
        let top = center(of: origin)
        let right = center(of: Tile(c: origin.c + last, r: origin.r))
        let bottom = center(of: Tile(c: origin.c + last, r: origin.r + last))
        let left = center(of: Tile(c: origin.c, r: origin.r + last))
        return [
            CGPoint(x: top.x, y: top.y + tileHeight / 2),
            CGPoint(x: right.x + tileWidth / 2, y: right.y),
            CGPoint(x: bottom.x, y: bottom.y - tileHeight / 2),
            CGPoint(x: left.x - tileWidth / 2, y: left.y),
        ]
    }

    static func diamondPath(origin: Tile, size: Int) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: corners(origin: origin, size: size))
        path.closeSubpath()
        return path
    }
}
