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
        case .flag(let f):
            return state.flags.contains(f)
        case .notFlag(let f):
            return !state.flags.contains(f)
        case .valueAtLeast(let v, let n):
            return (state.storyValues[v] ?? 0) >= n
        case .valueAtMost(let v, let n):
            return (state.storyValues[v] ?? 0) <= n
        case .chapter(let n):
            return state.chapter >= n
        case .sceneSeen(let id):
            return state.seenScenes.contains(id)
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
        // Story requirements are hidden from players; these descriptions are for debugging.
        case .flag(let f): return "Flag \(f) set"
        case .notFlag(let f): return "Flag \(f) not set"
        case .valueAtLeast(let v, let n): return "\(v) at least \(n)"
        case .valueAtMost(let v, let n): return "\(v) at most \(n)"
        case .chapter(let n): return "Chapter \(n)"
        case .sceneSeen(let id): return "Seen scene \(id)"
        }
    }
}
