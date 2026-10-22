import Foundation

/// All balance formulas live here so they can be tuned and tested in one place.
/// Per-building numbers (earning rates, renovation costs and times) live in `buildings.json`.
enum Economy {
    // MARK: Shops

    /// Bonus a worker adds to a shop's rate (0.25 = +25%).
    static func workerBonus(isFavorite: Bool) -> Double {
        isFavorite ? 0.6 : 0.25
    }

    /// The most decorations can add to one shop, however many are nearby.
    static let maxDecorationBonus = 0.5

    /// Glimmer per second for a shop at `stage`, including worker and decoration bonuses.
    static func rate(_ def: BuildingDef, stage: Int, workers: [ResidentDef] = [], decorationBonus: Double = 0) -> Double {
        let bonus = workers.reduce(0) { $0 + workerBonus(isFavorite: $1.favoriteShop == def.id) }
        return def.stage(stage).rate * (1 + bonus + min(maxDecorationBonus, decorationBonus))
    }

    /// How much a shop holds before it's full, given its current rate.
    static func capacity(rate: Double, _ stage: StageDef) -> Double {
        rate * stage.capSeconds
    }

    /// Glimmer waiting in a shop right now. Grows with time and stops at capacity.
    static func pending(since lastCollected: Date, rate: Double, capacity: Double, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(lastCollected))
        return min(capacity, rate * elapsed)
    }

    /// Each extra copy of the same building costs more (decorations only a little more).
    static func buildCost(_ def: BuildingDef, owned: Int) -> Double {
        let growth = def.kind == .decoration ? 1.12 : 1.35
        return (def.cost * pow(growth, Double(owned))).rounded()
    }

    /// Glimmer back when a decoration is put away.
    static func removalRefund(_ def: BuildingDef) -> Double {
        (def.cost * 0.5).rounded()
    }

    // MARK: Renovation

    /// Wisps to finish a renovation right away: one per 10 minutes left (at least one).
    static func finishNowCost(remaining: TimeInterval) -> Double {
        max(1, (remaining / 600).rounded(.up))
    }

    // MARK: Auto-collect

    /// One-time cost to give a shop a Keeper's Charter.
    static func charterCost(_ def: BuildingDef) -> Double {
        (def.cost * 4).rounded()
    }

    /// Auto-collected shops keep earning while you're away, up to this long.
    static let offlineCap: TimeInterval = 8 * 3600

    // MARK: Land

    static func cleanseCost(cleansedSoFar: Int) -> Double {
        let extra = max(0, cleansedSoFar - World.startingChunks.count)
        return (250 * pow(2.1, Double(extra))).rounded()
    }

    static func cleanseXP(cleansedSoFar: Int) -> Double {
        Double(25 * max(1, cleansedSoFar - World.startingChunks.count + 1))
    }

    // MARK: Residents and wisps

    static let wispsPerCleanse: Double = 3
    static let wispsPerLevel: Double = 5
    static let summonCost: Double = 10
    /// Wisps given back when a summon finds someone who already lives in town.
    static let duplicateRefund: Double = 4
    /// How long until the next wanderer arrives, in seconds.
    static let wandererDelay: ClosedRange<Double> = 20 * 60 ... 40 * 60

    // MARK: Levels

    /// Total XP needed to reach `level`.
    static func xpForLevel(_ level: Int) -> Double {
        level <= 1 ? 0 : (40 * pow(Double(level - 1), 1.7)).rounded()
    }

    static func level(forXP xp: Double) -> Int {
        var level = 1
        while xp >= xpForLevel(level + 1) { level += 1 }
        return level
    }
}
