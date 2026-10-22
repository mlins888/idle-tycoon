import Foundation

/// All balance formulas live here so they can be tuned and tested in one place.
enum Economy {
    static func rate(_ def: BuildingDef, level: Int) -> Double {
        def.baseRate * pow(1.45, Double(level - 1))
    }

    static func capacity(_ def: BuildingDef, level: Int) -> Double {
        rate(def, level: level) * def.capSeconds
    }

    /// Glimmer waiting in a shop right now. Grows with time and stops at capacity.
    static func pending(_ b: PlacedBuilding, _ def: BuildingDef, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(b.lastCollectedAt))
        return min(capacity(def, level: b.level), rate(def, level: b.level) * elapsed)
    }

    static func isFull(_ b: PlacedBuilding, _ def: BuildingDef, now: Date) -> Bool {
        pending(b, def, now: now) >= capacity(def, level: b.level) * 0.999
    }

    /// Each extra copy of the same shop costs more.
    static func buildCost(_ def: BuildingDef, owned: Int) -> Double {
        (def.cost * pow(1.35, Double(owned))).rounded()
    }

    static func upgradeCost(_ def: BuildingDef, level: Int) -> Double {
        (def.cost * 0.6 * pow(1.8, Double(level))).rounded()
    }

    static func cleanseCost(cleansedSoFar: Int) -> Double {
        let extra = max(0, cleansedSoFar - World.startingChunks.count)
        return (250 * pow(2.1, Double(extra))).rounded()
    }

    static func cleanseXP(cleansedSoFar: Int) -> Double {
        Double(25 * max(1, cleansedSoFar - World.startingChunks.count + 1))
    }

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
