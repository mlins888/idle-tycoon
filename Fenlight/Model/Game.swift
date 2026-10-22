import Foundation
import Observation

/// A short message near the top of the screen, e.g. "+3 wisps · cleansed the murk".
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

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
    case eventStarted(EventDef)
    case eventMilestone(EventDef, index: Int)

    var id: String {
        switch self {
        case .eventStarted(let e): return "event-\(e.id)"
        case .eventMilestone(let e, let i): return "event-\(e.id)-\(i)"
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
    /// Short messages waiting to be shown (oldest first).
    var toasts: [Toast] = []

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
        level >= def.unlockLevel && (!def.eventOnly || state.unlockedDecorations.contains(def.id))
    }

    /// Each business can be built once, plus a second once the first reaches its final stage.
    /// Unique buildings (the shrine and the guild) only once. Homes and decorations have no limit.
    func canBuildMore(_ def: BuildingDef) -> Bool {
        let copies = state.buildings.filter { $0.defId == def.id }
        if def.unique { return copies.isEmpty }
        guard def.kind == .shop else { return true }
        if copies.isEmpty { return true }
        return copies.count == 1 && copies[0].stage >= def.stages.count && !copies[0].isRenovating
    }

    // MARK: - Reading: shops

    func workers(at shopId: Int) -> [ResidentDef] {
        Residents.workers(at: shopId, in: state).compactMap { content.resident($0.defId) }
    }

    /// Glimmer a shop pays per finished run, including worker and decoration bonuses. Zero while renovating.
    func payout(_ b: PlacedBuilding) -> Double {
        guard let def = def(for: b), def.kind == .shop, !b.isRenovating else { return 0 }
        return Economy.payout(def, stage: b.stage, workers: workers(at: b.id), decorationBonus: decorationBonus(b))
    }

    /// How long one production run takes (0 for buildings that don't produce).
    func cycle(_ b: PlacedBuilding) -> TimeInterval {
        guard let def = def(for: b), def.kind == .shop else { return 0 }
        return def.stage(b.stage).cycleSeconds
    }

    /// Whether the current production run has finished and is waiting to be collected.
    func isReady(_ b: PlacedBuilding) -> Bool {
        !b.isRenovating && Economy.isReady(since: b.lastCollectedAt, cycle: cycle(b), now: now)
    }

    /// Seconds until the current run finishes.
    func timeLeft(_ b: PlacedBuilding) -> TimeInterval {
        Economy.timeLeft(since: b.lastCollectedAt, cycle: cycle(b), now: now)
    }

    /// 0...1 through the current run.
    func runProgress(_ b: PlacedBuilding) -> Double {
        let c = cycle(b)
        return c > 0 ? min(1, max(0, now.timeIntervalSince(b.lastCollectedAt) / c)) : 0
    }

    // MARK: - Reading: decorations

    /// Whether decoration `d` reaches shop `s` with its aura.
    func reaches(_ d: PlacedBuilding, _ s: PlacedBuilding) -> Bool {
        guard let dd = def(for: d), let aura = dd.aura, let sd = def(for: s), sd.kind == .shop else { return false }
        return World.distance(d.origin, size: dd.size, s.origin, size: sd.size) <= aura.radius
    }

    /// Total boost from nearby decorations, before the cap.
    func decorationBonusUncapped(_ shop: PlacedBuilding) -> Double {
        state.buildings.reduce(0) { total, d in
            reaches(d, shop) ? total + (def(for: d)?.aura?.bonus ?? 0) : total
        }
    }

    /// Boost from nearby decorations, capped at `Economy.maxDecorationBonus`.
    func decorationBonus(_ shop: PlacedBuilding) -> Double {
        min(Economy.maxDecorationBonus, decorationBonusUncapped(shop))
    }

    /// Shops a decoration boosts (or would boost, if it stood at `origin`).
    func shopsReached(by decoration: PlacedBuilding, at origin: Tile? = nil) -> [PlacedBuilding] {
        var d = decoration
        if let origin { d.origin = origin }
        return state.buildings.filter { $0.id != d.id && reaches(d, $0) }
    }

    /// True when a keeper collects this shop automatically (needs a charter and a worker).
    func isAuto(_ b: PlacedBuilding) -> Bool {
        b.autoCollect && !Residents.workers(at: b.id, in: state).isEmpty
    }

    /// Glimmer ready to collect by hand: the payout once a run has finished, otherwise 0.
    /// Always 0 for auto-collected or renovating shops.
    func pending(_ b: PlacedBuilding) -> Double {
        guard !isAuto(b), isReady(b) else { return 0 }
        return payout(b)
    }

    func totalPending() -> Double {
        state.buildings.reduce(0) { $0 + pending($1) }
    }

    func charterCost(_ b: PlacedBuilding) -> Double? {
        guard let def = def(for: b), def.kind == .shop, !b.autoCollect else { return nil }
        return Economy.charterCost(def)
    }

    /// The soonest moment a hand-collected shop finishes its run, for the "shop is ready" reminder.
    func nextShopReady() -> (date: Date, name: String)? {
        state.buildings.compactMap { b -> (Date, String)? in
            guard !isAuto(b), !b.isRenovating, cycle(b) > 0 else { return nil }
            let readyAt = b.lastCollectedAt.addingTimeInterval(cycle(b))
            return readyAt > now ? (readyAt, name(b)) : nil
        }
        .min { $0.0 < $1.0 }
    }

    // MARK: - Reading: wisps

    /// Whether a lost wisp is drifting over town right now.
    var wispVisible: Bool {
        state.wispVisibleUntil.map { now < $0 } ?? false
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

    // MARK: - Reading: festivals

    /// The festival running right now, if any.
    var activeEvent: EventDef? {
        EventCalendar.active(content.events, at: now)?.0
    }

    /// Time left in the current festival.
    var eventTimeLeft: TimeInterval? {
        EventCalendar.active(content.events, at: now).map { $0.1.end.timeIntervalSince(now) }
    }

    /// Progress in this year's run of a festival (zero if it hasn't been touched this year).
    func eventProgress(_ e: EventDef) -> EventProgress {
        guard let w = EventCalendar.window(e, containing: now), let p = state.eventProgress[e.id], p.year == w.year else {
            return EventProgress(year: EventCalendar.window(e, containing: now)?.year ?? 0)
        }
        return p
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
        earnEventToken(for: state.buildings[i])
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
            earnEventToken(for: state.buildings[i])
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
        if def.kind == .decoration { settleAllShops() }
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
        // Moving changes which decorations reach which shops, so pay out at the old rates first.
        if def(for: state.buildings[i])?.kind == .decoration { settleAllShops() } else { settle(i) }
        state.buildings[i].origin = origin
        layoutRevision += 1
        save()
        return true
    }

    /// Puts a decoration away, refunding half its base cost.
    @discardableResult
    func removeDecoration(_ id: Int) -> Bool {
        guard let i = index(of: id), let def = def(for: state.buildings[i]), def.kind == .decoration else { return false }
        settleAllShops()
        state.buildings.remove(at: i)
        state.glimmer += Economy.removalRefund(def)
        layoutRevision += 1
        save()
        return true
    }

    /// Pays the cost and closes the building for renovation into its next stage.
    @discardableResult
    func startRenovation(_ id: Int) -> Bool {
        guard let i = index(of: id), let def = def(for: state.buildings[i]),
              let next = nextStage(state.buildings[i]), canRenovate(state.buildings[i]) else { return false }
        // Hand over anything that's ready before the shop closes.
        let ready = pending(state.buildings[i])
        if ready > 0 { credit(ready, from: state.buildings[i].defId) }
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
        gainWisps(Economy.wispsPerCleanse, "cleansed the murk")
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
            gainWisps(Economy.duplicateRefund, "returned by the shrine")
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
        if q.reward.wisps > 0 { gainWisps(q.reward.wisps, "for “\(q.title)”") }
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
        updateEvent()
        updateWisp()
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

    /// During a festival, collecting by hand earns tokens: one per 5 minutes of production collected.
    private func earnEventToken(for b: PlacedBuilding) {
        guard let (e, w) = EventCalendar.active(content.events, at: now) else { return }
        var p = state.eventProgress[e.id].flatMap { $0.year == w.year ? $0 : nil } ?? EventProgress(year: w.year)
        p.tokens += cycle(b) * Economy.tokensPerProductionSecond
        state.eventProgress[e.id] = p
    }

    /// Adds wisps and shows where they came from.
    private func gainWisps(_ amount: Double, _ reason: String) {
        guard amount > 0 else { return }
        state.wisps += amount
        let n = Int(amount)
        toasts.append(Toast(text: "+\(n) wisp\(n == 1 ? "" : "s") · \(reason)"))
    }

    /// Schedules lost wisps: one drifts over town every 30–60 minutes and fades after 90 seconds.
    private func updateWisp() {
        let t = now
        if let until = state.wispVisibleUntil {
            guard t >= until else { return }
            state.wispVisibleUntil = nil
            state.nextWispAt = nil
        }
        guard let due = state.nextWispAt else {
            state.nextWispAt = t.addingTimeInterval(withRandom { $0.range(Economy.wispDelay) })
            return
        }
        if t >= due {
            state.wispVisibleUntil = t.addingTimeInterval(Economy.wispVisibleFor)
            state.nextWispAt = nil
        }
    }

    /// Catches the drifting wisp, if there is one. Returns how many wisps it was worth.
    @discardableResult
    func catchWisp() -> Double? {
        guard wispVisible else { return nil }
        let amount: Double = withRandom { $0.unit() } < Economy.doubleWispChance ? 2 : 1
        gainWisps(amount, "caught a lost wisp")
        state.wispVisibleUntil = nil
        state.nextWispAt = now.addingTimeInterval(withRandom { $0.range(Economy.wispDelay) })
        save()
        return amount
    }

    /// Starts this year's run of a festival (announcing it once) and hands out milestone rewards.
    private func updateEvent() {
        guard let (e, w) = EventCalendar.active(content.events, at: now) else { return }
        if state.eventProgress[e.id]?.year != w.year {
            state.eventProgress[e.id] = EventProgress(year: w.year)
            announcements.append(.eventStarted(e))
        }
        guard var p = state.eventProgress[e.id] else { return }
        while p.reached < e.milestones.count, p.tokens >= e.milestones[p.reached].tokens {
            let reward = e.milestones[p.reached].reward
            state.glimmer += reward.glimmer
            if reward.wisps > 0 { gainWisps(reward.wisps, "\(e.name) reward") }
            if let deco = reward.decoration { state.unlockedDecorations.insert(deco) }
            if let resident = reward.resident { state.invitedResidents.insert(resident) }
            announcements.append(.eventMilestone(e, index: p.reached))
            p.reached += 1
        }
        state.eventProgress[e.id] = p
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
        gainWisps(Double(current - state.rewardedLevel) * Economy.wispsPerLevel, "reached level \(current)")
        state.rewardedLevel = current
    }

    /// Adds collected glimmer to the wallet and to the counters quests measure.
    private func credit(_ amount: Double, from defId: String) {
        guard amount > 0 else { return }
        state.glimmer += amount
        state.stats.collected[defId, default: 0] += amount
        state.stats.collected[Stats.anyShop, default: 0] += amount
    }

    /// Lets a keeper collect every run its shop has finished (up to the offline cap), keeping any
    /// progress on the current run. Hand-collected shops are left alone: they pay when you collect.
    private func settle(_ i: Int) {
        let b = state.buildings[i]
        guard isAuto(b), !b.isRenovating else { return }
        let c = cycle(b)
        let runs = Economy.runsCompleted(since: b.lastCollectedAt, cycle: c, now: now, cap: Economy.offlineCap)
        guard runs > 0 else { return }
        credit(Double(runs) * payout(b), from: b.defId)
        if now.timeIntervalSince(b.lastCollectedAt) > Economy.offlineCap {
            state.buildings[i].lastCollectedAt = now
        } else {
            state.buildings[i].lastCollectedAt = b.lastCollectedAt.addingTimeInterval(Double(runs) * c)
        }
    }

    private func settleAllShops() {
        for i in state.buildings.indices where def(for: state.buildings[i])?.kind == .shop {
            settle(i)
        }
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

    func debugAdd(eventTokens: Double) {
        guard let (e, w) = EventCalendar.active(content.events, at: now) else { return }
        var p = state.eventProgress[e.id].flatMap { $0.year == w.year ? $0 : nil } ?? EventProgress(year: w.year)
        p.tokens += eventTokens
        state.eventProgress[e.id] = p
        tick()
    }

    /// Fast-forwards the clock to the start of the next festival.
    func debugJumpToNextEvent() {
        guard let (_, w) = EventCalendar.next(content.events, after: now) else { return }
        clock.offset += w.start.timeIntervalSince(now) + 60
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
