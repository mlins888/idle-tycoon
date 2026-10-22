import Foundation

/// Quest rules as plain functions: which quests can start, and how far along an objective is.
enum Quests {
    /// How many quests can be in progress at once.
    static let maxActive = 3

    /// Quests that could start now: not done, not already active, giver lives in town, prerequisites met.
    /// In file order, so earlier quests in `quests.json` start first.
    static func available(_ state: GameState, _ content: GameContent) -> [QuestDef] {
        content.quests.filter { q in
            !state.completedQuests.contains(q.id)
                && state.activeQuests[q.id] == nil
                && Residents.lives(q.giver, in: state)
                && Requirements.unmet(q.prerequisites, state, content).isEmpty
        }
    }

    /// The counter value to remember when a quest starts, so progress counts from then.
    static func baseline(_ objective: Objective, _ state: GameState) -> Double {
        switch objective {
        case .collect(let shop, _):
            return state.stats.collected[shop ?? Stats.anyShop] ?? 0
        case .cleanse:
            return Double(state.stats.chunksCleansed)
        case .build, .stage, .residents, .level:
            return 0
        }
    }

    /// How far along an objective is, as (current, target). Current never exceeds target.
    static func progress(_ objective: Objective, baseline: Double, _ state: GameState) -> (current: Double, target: Double) {
        let (current, target): (Double, Double)
        switch objective {
        case .collect(let shop, let amount):
            current = (state.stats.collected[shop ?? Stats.anyShop] ?? 0) - baseline
            target = amount
        case .build(let id, let count):
            current = Double(state.buildings.filter { $0.defId == id }.count)
            target = Double(count)
        case .stage(let id, let stage):
            current = state.buildings.contains { $0.defId == id && $0.stage >= stage } ? 1 : 0
            target = 1
        case .cleanse(let count):
            current = Double(state.stats.chunksCleansed) - baseline
            target = Double(count)
        case .residents(let count):
            current = Double(state.residents.count)
            target = Double(count)
        case .level(let n):
            current = Double(Economy.level(forXP: state.xp))
            target = Double(n)
        }
        return (min(max(0, current), target), target)
    }

    static func isComplete(_ q: QuestDef, _ state: GameState) -> Bool {
        guard let baseline = state.activeQuests[q.id] else { return false }
        let p = progress(q.objective, baseline: baseline, state)
        return p.current >= p.target
    }
}
