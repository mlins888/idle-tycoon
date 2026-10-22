import Foundation
import Observation

struct AwaySummary: Identifiable {
    let id = UUID()
    let duration: TimeInterval
    let waiting: Double
}

/// The live game: holds the saved state and every action the player can take.
/// The map and the HUD both read from this and call into it; neither changes state directly.
@MainActor
@Observable
final class Game {
    let content: GameContent
    let clock: GameClock
    private(set) var state: GameState
    /// Bumped whenever buildings or land change, so the map knows to redraw them.
    private(set) var layoutRevision = 0
    var awaySummary: AwaySummary?

    @ObservationIgnored private let store: SaveStore?

    init(content: GameContent, state: GameState? = nil, clock: GameClock = GameClock(), store: SaveStore? = nil) {
        self.content = content
        self.clock = clock
        self.store = store
        self.state = state ?? store?.load() ?? .newGame(now: clock.now)
        checkAway()
    }

    var now: Date { clock.now }

    // MARK: - Reading

    var level: Int { Economy.level(forXP: state.xp) }

    /// 0...1 progress through the current level.
    var levelProgress: Double {
        let lo = Economy.xpForLevel(level), hi = Economy.xpForLevel(level + 1)
        return hi > lo ? (state.xp - lo) / (hi - lo) : 0
    }

    /// How much of the fen has been reclaimed, 0...1.
    var restoration: Double {
        Double(state.cleansedChunks.count) / Double(World.chunkCount)
    }

    func building(id: Int) -> PlacedBuilding? {
        state.buildings.first { $0.id == id }
    }

    func def(for b: PlacedBuilding) -> BuildingDef? {
        content.building(b.defId)
    }

    func pending(_ b: PlacedBuilding) -> Double {
        guard let def = def(for: b) else { return 0 }
        return Economy.pending(b, def, now: now)
    }

    func isFull(_ b: PlacedBuilding) -> Bool {
        guard let def = def(for: b) else { return false }
        return Economy.isFull(b, def, now: now)
    }

    func totalPending() -> Double {
        state.buildings.reduce(0) { $0 + pending($1) }
    }

    func owned(_ defId: String) -> Int {
        state.buildings.filter { $0.defId == defId }.count
    }

    func buildCost(_ def: BuildingDef) -> Double {
        Economy.buildCost(def, owned: owned(def.id))
    }

    func isUnlocked(_ def: BuildingDef) -> Bool {
        level >= def.unlockLevel
    }

    func isCleansed(_ tile: Tile) -> Bool {
        state.cleansedChunks.contains(World.chunk(of: tile))
    }

    func occupant(at tile: Tile) -> PlacedBuilding? {
        state.buildings.first { b in
            guard let def = def(for: b) else { return false }
            return tile.c >= b.origin.c && tile.c < b.origin.c + def.size
                && tile.r >= b.origin.r && tile.r < b.origin.r + def.size
        }
    }

    /// Whether a building of `defId` fits at `origin`: on cleansed land, inside the map, not overlapping.
    func canPlace(_ defId: String, at origin: Tile, ignoring ignoredId: Int? = nil) -> Bool {
        guard let def = content.building(defId) else { return false }
        return World.footprint(origin: origin, size: def.size).allSatisfy { tile in
            guard World.inBounds(tile), isCleansed(tile) else { return false }
            if let other = occupant(at: tile), other.id != ignoredId { return false }
            return true
        }
    }

    var cleanseCost: Double {
        Economy.cleanseCost(cleansedSoFar: state.cleansedChunks.count)
    }

    /// Murk can only be cleansed next to land that's already clear.
    func canCleanse(_ chunk: Chunk) -> Bool {
        World.inBounds(chunk)
            && !state.cleansedChunks.contains(chunk)
            && World.neighbors(of: chunk).contains { state.cleansedChunks.contains($0) }
    }

    // MARK: - Actions

    @discardableResult
    func collect(_ id: Int) -> Double {
        guard let i = state.buildings.firstIndex(where: { $0.id == id }) else { return 0 }
        let amount = pending(state.buildings[i])
        guard amount >= 1 else { return 0 }
        state.buildings[i].lastCollectedAt = now
        state.glimmer += amount
        state.xp += 1
        save()
        return amount
    }

    @discardableResult
    func collectAll() -> Double {
        var total = 0.0
        var collected = 0
        let t = now
        for i in state.buildings.indices {
            let amount = pending(state.buildings[i])
            guard amount >= 1 else { continue }
            state.buildings[i].lastCollectedAt = t
            total += amount
            collected += 1
        }
        state.glimmer += total
        state.xp += Double(collected)
        save()
        return total
    }

    @discardableResult
    func build(_ defId: String, at origin: Tile) -> Bool {
        guard let def = content.building(defId), isUnlocked(def) else { return false }
        let cost = buildCost(def)
        guard state.glimmer >= cost, canPlace(defId, at: origin) else { return false }
        state.glimmer -= cost
        state.xp += def.xp
        state.buildings.append(PlacedBuilding(id: state.nextBuildingId, defId: defId, origin: origin,
                                              level: 1, lastCollectedAt: now))
        state.nextBuildingId += 1
        layoutRevision += 1
        save()
        return true
    }

    @discardableResult
    func move(_ id: Int, to origin: Tile) -> Bool {
        guard let i = state.buildings.firstIndex(where: { $0.id == id }),
              canPlace(state.buildings[i].defId, at: origin, ignoring: id) else { return false }
        state.buildings[i].origin = origin
        layoutRevision += 1
        save()
        return true
    }

    func upgradeCost(_ b: PlacedBuilding) -> Double? {
        guard let def = def(for: b), b.level < def.maxLevel else { return nil }
        return Economy.upgradeCost(def, level: b.level)
    }

    @discardableResult
    func upgrade(_ id: Int) -> Bool {
        guard let i = state.buildings.firstIndex(where: { $0.id == id }),
              let def = def(for: state.buildings[i]),
              let cost = upgradeCost(state.buildings[i]),
              state.glimmer >= cost else { return false }
        // Collect first, so the new rate doesn't apply retroactively.
        let waiting = pending(state.buildings[i])
        state.glimmer += waiting - cost
        state.buildings[i].lastCollectedAt = now
        state.buildings[i].level += 1
        state.xp += def.xp * Double(state.buildings[i].level)
        layoutRevision += 1
        save()
        return true
    }

    @discardableResult
    func cleanse(_ chunk: Chunk) -> Bool {
        let cost = cleanseCost
        guard canCleanse(chunk), state.glimmer >= cost else { return false }
        state.glimmer -= cost
        state.xp += Economy.cleanseXP(cleansedSoFar: state.cleansedChunks.count)
        state.cleansedChunks.insert(chunk)
        layoutRevision += 1
        save()
        return true
    }

    // MARK: - Saving and time away

    func save() {
        state.savedAt = now
        store?.save(state)
    }

    /// Shows a "while you were away" summary if the player was gone a while and shops filled up.
    func checkAway() {
        guard awaySummary == nil else { return }
        let away = now.timeIntervalSince(state.savedAt)
        let waiting = totalPending()
        if away >= 60, waiting >= 1 {
            awaySummary = AwaySummary(duration: away, waiting: waiting)
        }
    }

    // MARK: - Debug

    func debugAdd(glimmer: Double) {
        state.glimmer += glimmer
        save()
    }

    func debugAdd(xp: Double) {
        state.xp += xp
        save()
    }

    func debugSkip(_ seconds: TimeInterval) {
        clock.offset += seconds
    }

    func debugReset() {
        clock.offset = 0
        state = .newGame(now: now)
        awaySummary = nil
        layoutRevision += 1
        save()
    }
}
