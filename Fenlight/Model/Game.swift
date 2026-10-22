import Foundation
import Observation

struct AwaySummary: Identifiable {
    let id = UUID()
    let duration: TimeInterval
    /// Glimmer waiting in shops you collect by hand.
    let waiting: Double
    /// Glimmer your keepers already collected for you.
    let keepers: Double
    /// Residents who moved in while you were gone.
    let arrivals: [ResidentDef]
}

enum SummonResult: Equatable {
    case newResident(ResidentDef)
    case duplicate(ResidentDef, refund: Double)
}

/// The live game: holds the saved state and every action the player can take.
/// The map and the HUD both read from this and call into it; neither changes state directly.
@MainActor
@Observable
final class Game {
    let content: GameContent
    let clock: GameClock
    private(set) var state: GameState
    /// Bumped whenever buildings, land or workers change, so the map knows to redraw them.
    private(set) var layoutRevision = 0
    var awaySummary: AwaySummary?
    /// Residents who just arrived and haven't been announced yet (oldest first).
    var arrivalQueue: [ResidentDef] = []

    @ObservationIgnored private let store: SaveStore?
    @ObservationIgnored private var lastSaved = Date.distantPast

    init(content: GameContent, state: GameState? = nil, clock: GameClock = GameClock(), store: SaveStore? = nil) {
        self.content = content
        self.clock = clock
        self.store = store
        self.state = state ?? store?.load() ?? .newGame(now: clock.now)
        checkAway()
    }

    var now: Date { clock.now }

    // MARK: - Reading: town

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

    func owned(_ defId: String) -> Int {
        state.buildings.filter { $0.defId == defId }.count
    }

    func hasBuilt(_ kind: BuildingKind) -> Bool {
        state.buildings.contains { def(for: $0)?.kind == kind }
    }

    func buildCost(_ def: BuildingDef) -> Double {
        Economy.buildCost(def, owned: owned(def.id))
    }

    func isUnlocked(_ def: BuildingDef) -> Bool {
        level >= def.unlockLevel
    }

    /// Unique buildings (the shrine and the guild) can only be built once.
    func canBuildMore(_ def: BuildingDef) -> Bool {
        !def.unique || owned(def.id) == 0
    }

    // MARK: - Reading: shops

    func workers(at shopId: Int) -> [ResidentDef] {
        Residents.workers(at: shopId, in: state).compactMap { content.resident($0.defId) }
    }

    /// Glimmer per second, including worker bonuses.
    func rate(_ b: PlacedBuilding) -> Double {
        guard let def = def(for: b), def.kind == .shop else { return 0 }
        return Economy.rate(def, level: b.level, workers: workers(at: b.id))
    }

    func capacity(_ b: PlacedBuilding) -> Double {
        guard let def = def(for: b) else { return 0 }
        return Economy.capacity(rate: rate(b), def)
    }

    /// True when a keeper collects this shop automatically (needs a charter and a worker).
    func isAuto(_ b: PlacedBuilding) -> Bool {
        b.autoCollect && !Residents.workers(at: b.id, in: state).isEmpty
    }

    /// Glimmer waiting to be collected by hand. Always 0 for auto-collected shops.
    func pending(_ b: PlacedBuilding) -> Double {
        guard !isAuto(b) else { return 0 }
        return Economy.pending(since: b.lastCollectedAt, rate: rate(b), capacity: capacity(b), now: now)
    }

    func isFull(_ b: PlacedBuilding) -> Bool {
        let cap = capacity(b)
        return cap > 0 && !isAuto(b) && pending(b) >= cap * 0.999
    }

    func totalPending() -> Double {
        state.buildings.reduce(0) { $0 + pending($1) }
    }

    func upgradeCost(_ b: PlacedBuilding) -> Double? {
        guard let def = def(for: b), def.kind == .shop, b.level < def.maxLevel else { return nil }
        return Economy.upgradeCost(def, level: b.level)
    }

    func charterCost(_ b: PlacedBuilding) -> Double? {
        guard let def = def(for: b), def.kind == .shop, !b.autoCollect else { return nil }
        return Economy.charterCost(def)
    }

    /// The soonest moment a hand-collected shop fills up, for the "shop is full" reminder.
    func nextShopFull() -> (date: Date, name: String)? {
        state.buildings.compactMap { b -> (Date, String)? in
            guard let def = def(for: b), !isAuto(b) else { return nil }
            let r = rate(b), cap = capacity(b)
            guard r > 0, cap > 0 else { return nil }
            let fullAt = b.lastCollectedAt.addingTimeInterval(cap / r)
            return fullAt > now ? (fullAt, def.name) : nil
        }
        .min { $0.0 < $1.0 }
    }

    // MARK: - Reading: land

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

    // MARK: - Reading: residents

    var residentDefs: [ResidentDef] {
        state.residents.compactMap { content.resident($0.defId) }
    }

    func resident(_ defId: String) -> Resident? {
        state.residents.first { $0.defId == defId }
    }

    var totalBeds: Int { Residents.totalBeds(state, content) }
    var freeBeds: Int { totalBeds - state.residents.count }

    /// Story residents who've unlocked but are waiting for a bed.
    var waitingForBed: [ResidentDef] {
        Residents.waitingStory(state, content, level: level)
    }

    var upcomingStory: [ResidentDef] {
        Residents.upcomingStory(state, content, level: level)
    }

    var summonCost: Double { Economy.summonCost }

    var canSummon: Bool {
        hasBuilt(.shrine) && state.wisps >= summonCost && freeBeds > 0
            && !Residents.summonPool(content).isEmpty
    }

    // MARK: - Actions: shops

    @discardableResult
    func collect(_ id: Int) -> Double {
        guard let i = index(of: id) else { return 0 }
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
        guard let def = content.building(defId), isUnlocked(def), canBuildMore(def) else { return false }
        let cost = buildCost(def)
        guard state.glimmer >= cost, canPlace(defId, at: origin) else { return false }
        state.glimmer -= cost
        state.xp += def.xp
        state.buildings.append(PlacedBuilding(id: state.nextBuildingId, defId: defId, origin: origin,
                                              level: 1, lastCollectedAt: now))
        state.nextBuildingId += 1
        layoutRevision += 1
        processArrivals()
        save()
        return true
    }

    @discardableResult
    func move(_ id: Int, to origin: Tile) -> Bool {
        guard let i = index(of: id),
              canPlace(state.buildings[i].defId, at: origin, ignoring: id) else { return false }
        state.buildings[i].origin = origin
        layoutRevision += 1
        save()
        return true
    }

    @discardableResult
    func upgrade(_ id: Int) -> Bool {
        guard let i = index(of: id),
              let def = def(for: state.buildings[i]),
              let cost = upgradeCost(state.buildings[i]),
              state.glimmer >= cost else { return false }
        // Collect first, so the new rate doesn't apply retroactively.
        settle(i)
        state.glimmer -= cost
        state.buildings[i].level += 1
        state.xp += def.xp * Double(state.buildings[i].level)
        layoutRevision += 1
        save()
        return true
    }

    // MARK: - Actions: land

    @discardableResult
    func cleanse(_ chunk: Chunk) -> Bool {
        let cost = cleanseCost
        guard canCleanse(chunk), state.glimmer >= cost else { return false }
        state.glimmer -= cost
        state.xp += Economy.cleanseXP(cleansedSoFar: state.cleansedChunks.count)
        state.wisps += Economy.wispsPerCleanse
        state.cleansedChunks.insert(chunk)
        layoutRevision += 1
        save()
        return true
    }

    // MARK: - Actions: residents

    /// Puts a resident to work at a shop, taking them off any other shop first.
    @discardableResult
    func assignWorker(_ defId: String, to shopId: Int) -> Bool {
        guard let r = state.residents.firstIndex(where: { $0.defId == defId }),
              let s = index(of: shopId), let def = def(for: state.buildings[s]), def.kind == .shop,
              Residents.workers(at: shopId, in: state).count < def.workerSlots else { return false }
        if let oldShop = state.residents[r].workId, let o = index(of: oldShop) { settle(o) }
        settle(s)
        state.residents[r].workId = shopId
        layoutRevision += 1
        save()
        return true
    }

    func unassignWorker(_ defId: String) {
        guard let r = state.residents.firstIndex(where: { $0.defId == defId }),
              let shopId = state.residents[r].workId else { return }
        if let s = index(of: shopId) { settle(s) }
        state.residents[r].workId = nil
        layoutRevision += 1
        save()
    }

    /// Spends wisps at the shrine for a random rare resident.
    func summon() -> SummonResult? {
        guard canSummon else { return nil }
        let roll = withRandom { Residents.rollSummon(content, rng: &$0) }
        guard let def = roll else { return nil }
        state.wisps -= summonCost
        if Residents.lives(def.id, in: state) {
            state.wisps += Economy.duplicateRefund
            save()
            return .duplicate(def, refund: Economy.duplicateRefund)
        }
        guard let house = Residents.houseWithFreeBed(state, content) else { return nil }
        join(def, house: house, at: now, announce: false)
        save()
        return .newResident(def)
    }

    /// Gives a shop a Keeper's Charter so its worker collects it automatically.
    @discardableResult
    func buyCharter(_ shopId: Int) -> Bool {
        guard hasBuilt(.guild), let i = index(of: shopId),
              let cost = charterCost(state.buildings[i]), state.glimmer >= cost,
              !Residents.workers(at: shopId, in: state).isEmpty else { return false }
        settle(i)
        state.glimmer -= cost
        state.buildings[i].autoCollect = true
        layoutRevision += 1
        save()
        return true
    }

    // MARK: - Time passing

    /// Runs about once a second, and when the app opens: keepers collect, residents arrive,
    /// level-ups pay out wisps.
    func tick() {
        let before = state.glimmer
        let residentsBefore = state.residents.count
        for i in state.buildings.indices where isAuto(state.buildings[i]) {
            settle(i)
        }
        processArrivals()
        awardLevelWisps()
        let arrived = state.residents.count != residentsBefore
        if arrived || (state.glimmer != before && now.timeIntervalSince(lastSaved) > 15) {
            save()
        }
    }

    /// Moves in story residents who are due, then any wanderers whose arrival time has passed.
    private func processArrivals() {
        let t = now
        for def in Residents.waitingStory(state, content, level: level) {
            guard let house = Residents.houseWithFreeBed(state, content) else { break }
            join(def, house: house, at: t, announce: true)
        }
        while true {
            let pool = Residents.wandererPool(state, content, level: level)
            guard let house = Residents.houseWithFreeBed(state, content), !pool.isEmpty else {
                state.nextWandererAt = nil
                return
            }
            guard let due = state.nextWandererAt else {
                state.nextWandererAt = t.addingTimeInterval(withRandom { $0.range(Economy.wandererDelay) })
                return
            }
            guard due <= t, let def = withRandom({ $0.pick(pool) }) else { return }
            join(def, house: house, at: due, announce: true)
            state.nextWandererAt = due.addingTimeInterval(withRandom { $0.range(Economy.wandererDelay) })
        }
    }

    private func join(_ def: ResidentDef, house: Int, at date: Date, announce: Bool) {
        state.residents.append(Resident(defId: def.id, homeId: house, workId: nil, arrivedAt: date))
        layoutRevision += 1
        if announce { arrivalQueue.append(def) }
    }

    private func awardLevelWisps() {
        let current = level
        guard current > state.rewardedLevel else { return }
        state.wisps += Double(current - state.rewardedLevel) * Economy.wispsPerLevel
        state.rewardedLevel = current
    }

    /// Pays out whatever a shop has earned so far and restarts its timer. Used before anything
    /// changes its rate, so a new rate never applies to time that already passed.
    private func settle(_ i: Int) {
        let b = state.buildings[i]
        if isAuto(b) {
            let elapsed = min(Economy.offlineCap, max(0, now.timeIntervalSince(b.lastCollectedAt)))
            state.glimmer += rate(b) * elapsed
        } else {
            state.glimmer += pending(b)
        }
        state.buildings[i].lastCollectedAt = now
    }

    private func index(of id: Int) -> Int? {
        state.buildings.firstIndex { $0.id == id }
    }

    private func withRandom<T>(_ body: (inout SeededRandom) -> T) -> T {
        var rng = SeededRandom(state: state.rngState)
        let value = body(&rng)
        state.rngState = rng.state
        return value
    }

    // MARK: - Saving and time away

    func save() {
        awardLevelWisps()
        state.savedAt = now
        lastSaved = now
        store?.save(state)
    }

    /// When the player returns: lets keepers collect and residents arrive, then shows a
    /// "while you were away" summary if anything happened.
    func checkAway() {
        guard awaySummary == nil else { return }
        let away = now.timeIntervalSince(state.savedAt)
        let glimmerBefore = state.glimmer
        let queuedBefore = arrivalQueue.count
        tick()
        let keepers = state.glimmer - glimmerBefore
        let arrivals = Array(arrivalQueue.dropFirst(queuedBefore))
        let waiting = totalPending()
        if away >= 60, waiting >= 1 || keepers >= 1 || !arrivals.isEmpty {
            awaySummary = AwaySummary(duration: away, waiting: waiting, keepers: keepers, arrivals: arrivals)
            // The summary already introduces them.
            arrivalQueue.removeLast(arrivals.count)
        }
    }

    // MARK: - Debug

    func debugAdd(glimmer: Double) {
        state.glimmer += glimmer
        save()
    }

    func debugAdd(wisps: Double) {
        state.wisps += wisps
        save()
    }

    func debugAdd(xp: Double) {
        state.xp += xp
        save()
    }

    func debugSkip(_ seconds: TimeInterval) {
        clock.offset += seconds
        tick()
    }

    /// Makes the next wanderer arrive right now (if there's a bed and anyone left to come).
    func debugWandererNow() {
        state.nextWandererAt = now
        tick()
    }

    func debugReset() {
        clock.offset = 0
        state = .newGame(now: now)
        awaySummary = nil
        arrivalQueue = []
        layoutRevision += 1
        tick()
        save()
    }
}
