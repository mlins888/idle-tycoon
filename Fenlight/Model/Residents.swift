import Foundation

/// Rules about who lives in town and who can arrive next. Pure functions over the state and
/// content, so they're easy to test. `Game` calls these when it needs to make a decision.
enum Residents {
    static func lives(_ defId: String, in state: GameState) -> Bool {
        state.residents.contains { $0.defId == defId }
    }

    static func occupants(of houseId: Int, in state: GameState) -> [Resident] {
        state.residents.filter { $0.homeId == houseId }
    }

    static func workers(at shopId: Int, in state: GameState) -> [Resident] {
        state.residents.filter { $0.workId == shopId }
    }

    static func beds(_ b: PlacedBuilding, _ content: GameContent) -> Int {
        content.building(b.defId)?.stage(b.stage).beds ?? 0
    }

    static func totalBeds(_ state: GameState, _ content: GameContent) -> Int {
        state.buildings.reduce(0) { $0 + beds($1, content) }
    }

    /// The first house with an empty bed, if any.
    static func houseWithFreeBed(_ state: GameState, _ content: GameContent) -> Int? {
        state.buildings.first { b in
            let n = beds(b, content)
            return n > 0 && occupants(of: b.id, in: state).count < n
        }?.id
    }

    /// Residents who are due to move in as soon as there's a bed: story residents the town has reached
    /// the level for, and festival residents who've been invited.
    static func waitingStory(_ state: GameState, _ content: GameContent, level: Int) -> [ResidentDef] {
        content.residents
            .filter { r in
                guard !lives(r.id, in: state) else { return false }
                switch r.arrival {
                case .story: return r.unlockLevel <= level
                case .event: return state.invitedResidents.contains(r.id)
                case .wanderer, .summon: return false
                }
            }
            .sorted { ($0.arrival == .story ? 0 : 1, $0.unlockLevel) < ($1.arrival == .story ? 0 : 1, $1.unlockLevel) }
    }

    /// Story residents still locked behind a higher level, soonest first.
    static func upcomingStory(_ state: GameState, _ content: GameContent, level: Int) -> [ResidentDef] {
        content.residents
            .filter { $0.arrival == .story && $0.unlockLevel > level }
            .sorted { $0.unlockLevel < $1.unlockLevel }
    }

    /// Wanderers who could turn up next.
    static func wandererPool(_ state: GameState, _ content: GameContent, level: Int) -> [ResidentDef] {
        content.residents.filter { $0.arrival == .wanderer && $0.unlockLevel <= level && !lives($0.id, in: state) }
    }

    static func summonPool(_ content: GameContent) -> [ResidentDef] {
        content.residents.filter { $0.arrival == .summon }
    }

    /// Chance (0...1) of each rarity in the summon pool, for showing odds to the player.
    static func summonOdds(_ content: GameContent) -> [(Rarity, Double)] {
        let present = Set(summonPool(content).map(\.rarity))
        let weights = Rarity.allCases.filter(present.contains).map { ($0, $0.summonWeight) }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        return weights.filter { $0.1 > 0 }.map { ($0.0, $0.1 / total) }
    }

    /// Rolls a rarity by weight, then picks someone of that rarity.
    static func rollSummon(_ content: GameContent, rng: inout SeededRandom) -> ResidentDef? {
        let pool = summonPool(content)
        let rarities = Rarity.allCases.filter { r in pool.contains { $0.rarity == r } }
        guard let rarity = rng.weighted(rarities.map { ($0, $0.summonWeight) }) else { return nil }
        return rng.pick(pool.filter { $0.rarity == rarity })
    }
}
