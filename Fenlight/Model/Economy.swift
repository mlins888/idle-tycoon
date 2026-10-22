import Foundation

/// All balance formulas live here so they can be tuned and tested in one place.
enum Economy {
    // MARK: Shops

    /// Shop levels that double that shop's speed.
    static let milestoneLevels = [5, 10]

    static func milestoneMultiplier(level: Int) -> Double {
        milestoneLevels.reduce(1) { level >= $1 ? $0 * 2 : $0 }
    }

    /// Glimmer per second for a shop at `level`, before worker bonuses.
    static func rate(_ def: BuildingDef, level: Int) -> Double {
        def.baseRate * pow(1.45, Double(level - 1)) * milestoneMultiplier(level: level)
    }

    /// Bonus a worker adds to a shop's rate (0.25 = +25%).
    static func workerBonus(isFavorite: Bool) -> Double {
        isFavorite ? 0.6 : 0.25
    }

    /// Glimmer per second for a shop including its workers' bonuses.
    static func rate(_ def: BuildingDef, level: Int, workers: [ResidentDef]) -> Double {
        let bonus = workers.reduce(0) { $0 + workerBonus(isFavorite: $1.favoriteShop == def.id) }
        return rate(def, level: level) * (1 + bonus)
    }

    /// How much a shop holds before it's full, given its current rate.
    static func capacity(rate: Double, _ def: BuildingDef) -> Double {
        rate * def.capSeconds
    }

    /// Glimmer waiting in a shop right now. Grows with time and stops at capacity.
    static func pending(since lastCollected: Date, rate: Double, capacity: Double, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(lastCollected))
        return min(capacity, rate * elapsed)
    }

    /// Each extra copy of the same building costs more.
    static func buildCost(_ def: BuildingDef, owned: Int) -> Double {
        (def.cost * pow(1.35, Double(owned))).rounded()
    }

    static func upgradeCost(_ def: BuildingDef, level: Int) -> Double {
        (def.cost * 0.6 * pow(1.8, Double(level))).rounded()
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
