import Foundation

/// Where residents can walk and how they get there. Pure functions, so they're easy to test.
/// Walking is only for show: it never changes the saved game.
enum Walkways {
    /// Cleansed tiles that aren't covered by a building. Paths (decorations with `shape: "path"`) can be walked on.
    static func walkable(_ state: GameState, _ content: GameContent) -> Set<Tile> {
        var blocked = Set<Tile>()
        for b in state.buildings {
            guard let def = content.building(b.defId), def.shape != "path" else { continue }
            blocked.formUnion(World.footprint(origin: b.origin, size: def.size))
        }
        var tiles = Set<Tile>()
        for c in 0..<World.size {
            for r in 0..<World.size {
                let t = Tile(c: c, r: r)
                if state.cleansedChunks.contains(World.chunk(of: t)), !blocked.contains(t) {
                    tiles.insert(t)
                }
            }
        }
        return tiles
    }

    /// Walkable tiles within `radius` of a footprint (not inside it), closest first.
    static func around(_ origin: Tile, size: Int, radius: Int, in walkable: Set<Tile>) -> [Tile] {
        var result: [(Tile, Int)] = []
        for c in (origin.c - radius)...(origin.c + size - 1 + radius) {
            for r in (origin.r - radius)...(origin.r + size - 1 + radius) {
                let t = Tile(c: c, r: r)
                guard walkable.contains(t) else { continue }
                let d = World.distance(t, size: 1, origin, size: size)
                if d >= 1, d <= radius { result.append((t, d)) }
            }
        }
        return result.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Shortest route from `start` to `goal` stepping between neighbouring walkable tiles
    /// (up, down, left, right on the grid). Excludes `start`, includes `goal`. Nil if there's no way.
    /// `start` itself doesn't need to be walkable, so someone standing where a building was just placed can walk off.
    static func path(from start: Tile, to goal: Tile, walkable: Set<Tile>) -> [Tile]? {
        guard walkable.contains(goal) else { return nil }
        if start == goal { return [] }
        var cameFrom: [Tile: Tile] = [start: start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for next in [Tile(c: current.c + 1, r: current.r), Tile(c: current.c - 1, r: current.r),
                         Tile(c: current.c, r: current.r + 1), Tile(c: current.c, r: current.r - 1)]
            where walkable.contains(next) && cameFrom[next] == nil {
                cameFrom[next] = current
                if next == goal {
                    var route = [goal]
                    var step = goal
                    while let prev = cameFrom[step], prev != start {
                        route.append(prev)
                        step = prev
                    }
                    return route.reversed()
                }
                queue.append(next)
            }
        }
        return nil
    }

    /// The walkable tile closest to `tile` (for someone stranded when a building lands on them).
    static func nearest(to tile: Tile, in walkable: Set<Tile>) -> Tile? {
        walkable.min { a, b in
            World.distance(a, size: 1, tile, size: 1) < World.distance(b, size: 1, tile, size: 1)
        }
    }
}
