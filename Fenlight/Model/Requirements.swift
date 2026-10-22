import Foundation

/// Checks requirements (for building stages and quests) against the current state.
enum Requirements {
    static func isMet(_ r: Requirement, _ state: GameState, _ content: GameContent) -> Bool {
        switch r {
        case .level(let n):
            return Economy.level(forXP: state.xp) >= n
        case .building(let id, let stage):
            return state.buildings.contains { $0.defId == id && $0.stage >= stage }
        case .resident(let id):
            return Residents.lives(id, in: state)
        case .quest(let id):
            return state.completedQuests.contains(id)
        case .restoration(let fraction):
            return Double(state.cleansedChunks.count) / Double(World.chunkCount) >= fraction - 0.0001
        }
    }

    static func unmet(_ rs: [Requirement], _ state: GameState, _ content: GameContent) -> [Requirement] {
        rs.filter { !isMet($0, state, content) }
    }

    /// Plain-language description, e.g. "Town level 3" or "Marigold Fen lives in town".
    static func describe(_ r: Requirement, _ content: GameContent) -> String {
        switch r {
        case .level(let n):
            return "Town level \(n)"
        case .building(let id, let stage):
            guard let def = content.building(id) else { return id }
            return stage <= 1 ? "Build a \(def.name)" : "Upgrade to the \(def.stage(stage).name)"
        case .resident(let id):
            return "\(content.resident(id)?.name ?? id) lives in town"
        case .quest(let id):
            return "Finish “\(content.quest(id)?.title ?? id)”"
        case .restoration(let fraction):
            return "\(Int((fraction * 100).rounded()))% of the fen restored"
        }
    }
}
