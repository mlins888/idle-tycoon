import Foundation

/// All balance formulas live here so they can be tuned and tested in one place.
/// Per-building numbers (production times, payouts, renovation costs and times) live in `buildings.json`.
enum Economy {
    // MARK: Shops

    /// Bonus a worker adds to a shop's payout (0.25 = +25%).
    static func workerBonus(isFavorite: Bool) -> Double {
        isFavorite ? 0.6 : 0.25
    }

    /// The most decorations can add to one shop, however many are nearby.
    static let maxDecorationBonus = 0.5

    /// Glimmer a shop pays per finished run at `stage`, including worker and decoration bonuses.
    static func payout(_ def: BuildingDef, stage: Int, workers: [ResidentDef] = [], decorationBonus: Double = 0) -> Double {
        let bonus = workers.reduce(0) { $0 + workerBonus(isFavorite: $1.favoriteShop == def.id) }
        return (def.stage(stage).payout * (1 + bonus + min(maxDecorationBonus, decorationBonus))).rounded()
    }

    /// Whether a production run that started at `start` has finished.
    static func isReady(since start: Date, cycle: TimeInterval, now: Date) -> Bool {
        cycle > 0 && now.timeIntervalSince(start) >= cycle
    }

    /// Seconds until the run finishes (0 when ready).
    static func timeLeft(since start: Date, cycle: TimeInterval, now: Date) -> TimeInterval {
        max(0, cycle - now.timeIntervalSince(start))
    }

    /// Whole runs finished since `start`, counting at most `cap` seconds (for keepers collecting while you're away).
    static func runsCompleted(since start: Date, cycle: TimeInterval, now: Date, cap: TimeInterval) -> Int {
        guard cycle > 0 else { return 0 }
        let elapsed = min(cap, max(0, now.timeIntervalSince(start)))
        return Int(elapsed / cycle)
    }

    /// Cost of a building. A second copy of a shop costs 3× the first; homes and decorations get a bit
    /// pricier with each copy.
    static func buildCost(_ def: BuildingDef, owned: Int) -> Double {
        let growth: Double = switch def.kind {
        case .shop: 3
        case .decoration: 1.12
        default: 1.35
        }
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

    /// Auto-collected shops keep working while you're away, up to this long.
    static let offlineCap: TimeInterval = 8 * 3600

    // MARK: Land

    /// Each patch of murk costs more than the last.
    static func cleanseCost(cleansedSoFar: Int) -> Double {
        let extra = max(0, cleansedSoFar - World.startingChunks.count)
        return (100 * pow(2.4, Double(extra))).rounded()
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
    /// How long until the next lost wisp drifts over town, in seconds.
    static let wispDelay: ClosedRange<Double> = 30 * 60 ... 60 * 60
    /// How long a lost wisp drifts before fading away.
    static let wispVisibleFor: TimeInterval = 90
    /// Chance a caught wisp is worth two.
    static let doubleWispChance = 0.2

    // MARK: Festivals

    /// Festival tokens per second of production collected (1 token per 5 minutes of production).
    static let tokensPerProductionSecond = 1.0 / 300

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
