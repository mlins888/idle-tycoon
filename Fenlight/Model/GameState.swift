import Foundation

struct PlacedBuilding: Codable, Identifiable, Hashable {
    let id: Int
    let defId: String
    /// Top corner of the footprint.
    var origin: Tile
    var level: Int
    /// Earnings are worked out from this timestamp, which is what makes offline earnings work.
    var lastCollectedAt: Date
}

/// Everything that gets saved. Kept as plain data so it can be encoded and tested easily.
struct GameState: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = GameState.currentVersion
    var glimmer: Double
    var xp: Double
    var buildings: [PlacedBuilding]
    var cleansedChunks: Set<Chunk>
    var nextBuildingId: Int
    var savedAt: Date

    static func newGame(now: Date) -> GameState {
        GameState(
            glimmer: 60,
            xp: 0,
            buildings: [
                PlacedBuilding(id: 1, defId: "reed_candles", origin: Tile(c: 11, r: 11),
                               level: 1, lastCollectedAt: now),
            ],
            cleansedChunks: World.startingChunks,
            nextBuildingId: 2,
            savedAt: now
        )
    }
}
