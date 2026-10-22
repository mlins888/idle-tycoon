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

/// Something worth a popup card: shown one at a time over the map.
enum Announcement: Identifiable, Equatable {
    case arrival(ResidentDef)
    case transformed(BuildingDef, from: Int, to: Int)
    case questReady(QuestDef)

    var id: String {
        switch self {
        case .arrival(let r): return "arrival-\(r.id)"
        case .transformed(let def, _, let to): return "transformed-\(def.id)-\(to)"
        case .questReady(let q): return "quest-\(q.id)"
        }
    }
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
    /// Popups waiting to be shown (oldest first).
    var announcements: [Announcement] = []

    @ObservationIgnored private let store: SaveStore?
    @ObservationIgnored private var lastSaved = Date.distantPast
    /// Quests already announced as ready, so each is only announced once.
    @ObservationIgnored private var announcedReady: Set<String> = []

    init(content: GameContent, state: GameState? = nil, clock: GameClock = GameClock(), store: SaveStore? = nil) {
        self.content = content
        self.clock = clock
        self.store = store
        var loaded = state ?? store?.load() ?? .newGame(now: clock.now)
        // Older saves may have stages a building doesn't have; keep them in range.
        for i in loaded.buildings.indices {
            if let def = content.building(loaded.buildings[i].defId) {
                loaded.buildings[i].stage = min(max(1, loaded.buildings[i].stage), def.stages.count)
            }
        }
        self.state = loaded
        announcedReady = Set(activeQuests.filter(isReady).map(\.id))
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

    /// The building's current stage.
    func stageDef(_ b: PlacedBuilding) -> StageDef? {
        def(for: b)?.stage(b.stage)
    }

    /// What the building is called at its current stage.
    func name(_ b: PlacedBuilding) -> String {
        stageDef(b)?.name ?? b.defId
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

    /// Glimmer per second, including worker bonuses. Zero while renovating.
    func rate(_ b: PlacedBuilding) -> Double {
        guard let def = def(for: b), def.kind == .shop, !b.isRenovating else { return 0 }
        return Economy.rate(def, stage: b.stage, workers: workers(at: b.id))
    }

    func capacity(_ b: PlacedBuilding) -> Double {
        guard let stage = stageDef(b) else { return 0 }
        return Economy.capacity(rate: rate(b), stage)
    }

    /// True when a keeper collects this shop automatically (needs a charter and a worker).
    func isAuto(_ b: PlacedBuilding) -> Bool {
        b.autoCollect && !Residents.workers(at: b.id, in: state).isEmpty
    }

    /// Glimmer waiting to be collected by hand. Always 0 for auto-collected or renovating shops.
    func pending(_ b: PlacedBuilding) -> Double {
        guard !isAuto(b), !b.isRenovating else { return 0 }
        return Economy.pending(since: b.lastCollectedAt, rate: rate(b), capacity: capacity(b), now: now)
    }

    func isFull(_ b: PlacedBuilding) -> Bool {
        let cap = capacity(b)
        return cap > 0 && !isAuto(b) && pending(b) >= cap * 0.999
    }

    func totalPending() -> Double {
        state.buildings.reduce(0) { $0 + pending($1) }
    }

    func charterCost(_ b: PlacedBuilding) -> Double? {
        guard let def = def(for: b), def.kind == .shop, !b.autoCollect else { return nil }
        return Economy.charterCost(def)
    }

    /// The soonest moment a hand-collected shop fills up, for the "shop is full" reminder.
    func nextShopFull() -> (date: Date, name: String)? {
        state.buildings.compactMap { b -> (Date, String)? in
            guard !isAuto(b), !b.isRenovating else { return nil }
            let r = rate(b), cap = capacity(b)
            guard r > 0, cap > 0 else { return nil }
            let fullAt = b.lastCollectedAt.addingTimeInterval(cap / r)
            return fullAt > now ? (fullAt, name(b)) : nil
        }
        .min { $0.0 < $1.0 }
    }

    // MARK: - Reading: stages

    /// The stage this building would renovate into, if it has one.
    func nextStage(_ b: PlacedBuilding) -> StageDef? {
        guard let def = def(for: b), b.stage < def.stages.count else { return nil }
        return def.stage(b.stage + 1)
    }

    /// Requirements for the next stage that aren't met yet.
    func unmetRequirements(_ b: PlacedBuilding) -> [Requirement] {
        guard let next = nextStage(b) else { return [] }
        return Requirements.unmet(next.requirements, state, content)
    }

    func canRenovate(_ b: PlacedBuilding) -> Bool {
        guard let next = nextStage(b), !b.isRenovating else { return false }
        return unmetRequirements(b).isEmpty && state.glimmer >= next.cost
    }

    func renovationRemaining(_ b: PlacedBuilding) -> TimeInterval? {
        b.renovationEndsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    func finishNowCost(_ b: PlacedBuilding) -> Double? {
        renovationRemaining(b).map { Economy.finishNowCost(remaining: $0) }
    }

    /// The soonest renovation to finish, for the "renovation done" reminder.
    func nextRenovationDone() -> (date: Date, name: String)? {
        state.buildings.compactMap { b -> (Date, String)? in
            guard let end = b.renovationEndsAt, end > now, let next = nextStage(b) else { return nil }
            return (end, next.name)
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

    // MARK: - Reading: quests

    /// Quests in progress, in the order they appear in quests.json.
    var activeQuests: [QuestDef] {
        content.quests.filter { state.activeQuests[$0.id] != nil }
    }

    func progress(_ q: QuestDef) -> (current: Double, target: Double) {
        Quests.progress(q.objective, baseline: state.activeQuests[q.id] ?? 0, state)
    }

    func isReady(_ q: QuestDef) -> Bool {
        Quests.isComplete(q, state)
    }

    var readyQuestCount: Int {
        activeQuests.filter(isReady).count
    }

    // MARK: - Actions: shops

    @discardableResult
    func collect(_ id: Int) -> Double {
        guard let i = index(of: id) else { return 0 }
        let amount = pending(state.buildings[i])
        guard amount >= 1 else { return 0 }
        state.buildings[i].lastCollectedAt = now
        credit(amount, from: state.buildings[i].defId)
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
            credit(amount, from: state.buildings[i].defId)
            total += amount
            collected += 1
        }
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
                                              stage: 1, lastCollectedAt: now))
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

    /// Pays the cost and closes the building for renovation into its next stage.
    @discardableResult
    func startRenovation(_ id: Int) -> Bool {
        guard let i = index(of: id), let def = def(for: state.buildings[i]),
              let next = nextStage(state.buildings[i]), canRenovate(state.buildings[i]) else { return false }
        settle(i)
        state.glimmer -= next.cost
        state.xp += def.xp * Double(state.buildings[i].stage + 1)
        if next.buildSeconds <= 0 {
            completeRenovation(i, at: now)
        } else {
            state.buildings[i].renovationEndsAt = now.addingTimeInterval(next.buildSeconds)
        }
        layoutRevision += 1
        save()
        return true
    }

    /// Spends wisps to finish a renovation right away.
    @discardableResult
    func finishRenovationNow(_ id: Int) -> Bool {
        guard let i = index(of: id), let cost = finishNowCost(state.buildings[i]),
              state.wisps >= cost else { return false }
        state.wisps -= cost
        completeRenovation(i, at: now)
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
        state.stats.chunksCleansed += 1
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

    // MARK: - Actions: quests

    /// Hands in a finished quest for its reward.
    @discardableResult
    func claimQuest(_ id: String) -> Bool {
        guard let q = content.quest(id), isReady(q) else { return false }
        state.activeQuests[id] = nil
        state.completedQuests.insert(id)
        state.glimmer += q.reward.glimmer
        state.wisps += q.reward.wisps
        state.xp += q.reward.xp
        announcedReady.remove(id)
        startQuests()
        save()
        return true
    }

    // MARK: - Time passing

    /// Runs about once a second, and when the app opens: renovations finish, keepers collect,
    /// residents arrive, quests start, level-ups pay out wisps.
    func tick() {
        let glimmerBefore = state.glimmer
        let announcementsBefore = announcements.count
        let questsBefore = state.activeQuests.count

        completeDueRenovations()
        for i in state.buildings.indices where isAuto(state.buildings[i]) {
            settle(i)
        }
        processArrivals()
        startQuests()
        awardLevelWisps()
        announceReadyQuests()

        let eventful = announcements.count != announcementsBefore || state.activeQuests.count != questsBefore
        if eventful || (state.glimmer != glimmerBefore && now.timeIntervalSince(lastSaved) > 15) {
            save()
        }
    }

    private func completeDueRenovations() {
        let t = now
        for i in state.buildings.indices {
            if let end = state.buildings[i].renovationEndsAt, end <= t {
                completeRenovation(i, at: end)
            }
        }
    }

    private func completeRenovation(_ i: Int, at date: Date) {
        guard let def = def(for: state.buildings[i]) else { return }
        let from = state.buildings[i].stage
        state.buildings[i].stage = min(from + 1, def.stages.count)
        state.buildings[i].renovationEndsAt = nil
        state.buildings[i].lastCollectedAt = date
        announcements.append(.transformed(def, from: from, to: state.buildings[i].stage))
        layoutRevision += 1
        processArrivals()   // a bigger house may have room for someone now
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
        if announce { announcements.append(.arrival(def)) }
    }

    /// Starts available quests until the quest log is full.
    private func startQuests() {
        for q in Quests.available(state, content) where state.activeQuests.count < Quests.maxActive {
            state.activeQuests[q.id] = Quests.baseline(q.objective, state)
        }
    }

    private func announceReadyQuests() {
        for q in activeQuests where isReady(q) && !announcedReady.contains(q.id) {
            announcedReady.insert(q.id)
            announcements.append(.questReady(q))
        }
    }

    private func awardLevelWisps() {
        let current = level
        guard current > state.rewardedLevel else { return }
        state.wisps += Double(current - state.rewardedLevel) * Economy.wispsPerLevel
        state.rewardedLevel = current
    }

    /// Adds collected glimmer to the wallet and to the counters quests measure.
    private func credit(_ amount: Double, from defId: String) {
        guard amount > 0 else { return }
        state.glimmer += amount
        state.stats.collected[defId, default: 0] += amount
        state.stats.collected[Stats.anyShop, default: 0] += amount
    }

    /// Pays out whatever a shop has earned so far and restarts its timer. Used before anything
    /// changes its rate, so a new rate never applies to time that already passed.
    private func settle(_ i: Int) {
        let b = state.buildings[i]
        if isAuto(b) {
            let elapsed = min(Economy.offlineCap, max(0, now.timeIntervalSince(b.lastCollectedAt)))
            credit(rate(b) * elapsed, from: b.defId)
        } else {
            credit(pending(b), from: b.defId)
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

    /// When the player returns: lets renovations finish, keepers collect and residents arrive,
    /// then shows a "while you were away" summary if anything happened.
    func checkAway() {
        guard awaySummary == nil else { return }
        let away = now.timeIntervalSince(state.savedAt)
        let glimmerBefore = state.glimmer
        let announcedBefore = announcements.count
        tick()
        let keepers = state.glimmer - glimmerBefore
        let fresh = announcements.dropFirst(announcedBefore)
        let arrivals = fresh.compactMap { a -> ResidentDef? in
            if case .arrival(let r) = a { return r }
            return nil
        }
        let waiting = totalPending()
        if away >= 60, waiting >= 1 || keepers >= 1 || !arrivals.isEmpty {
            awaySummary = AwaySummary(duration: away, waiting: waiting, keepers: keepers, arrivals: arrivals)
            // The summary already introduces new residents; keep the other cards.
            announcements = Array(announcements.prefix(announcedBefore)) + fresh.filter {
                if case .arrival = $0 { return false }
                return true
            }
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
        announcements = []
        announcedReady = []
        layoutRevision += 1
        tick()
        save()
    }
}
