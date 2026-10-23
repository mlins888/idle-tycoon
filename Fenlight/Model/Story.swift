import Foundation

/// Something that happened in the game that a scene can be triggered by.
enum StoryEvent: Equatable {
    case gameStart
    case chapterStart(Int)
    case questStarted(String)
    case questCompleted(String)
    case arrival(String)

    func matches(_ trigger: SceneTrigger) -> Bool {
        switch (self, trigger) {
        case (.gameStart, .gameStart): return true
        case (.chapterStart(let a), .chapterStart(let b)): return a == b
        case (.questStarted(let a), .questStarted(let b)): return a == b
        case (.questCompleted(let a), .questCompleted(let b)): return a == b
        case (.arrival(let a), .arrival(let b)): return a == b
        default: return false
        }
    }
}

/// Story rules as plain functions: which scenes an event triggers, applying effects, and filling in
/// the player's name and pronouns in scene text.
enum Story {
    /// Scenes that should play because of `event`: matching trigger, requirements met, not already
    /// seen or waiting to play. In `scenes.json` order.
    static func scenes(for event: StoryEvent, _ state: GameState, _ content: GameContent) -> [SceneDef] {
        content.scenes.filter { scene in
            event.matches(scene.trigger)
                && !state.seenScenes.contains(scene.id)
                && !state.pendingScenes.contains(scene.id)
                && Requirements.unmet(scene.requires, state, content).isEmpty
        }
    }

    /// Effects that change only story state (flags, values, chapter). Quest starts are returned for
    /// `Game` to handle, since starting a quest has game rules of its own.
    static func apply(_ effects: [Effect], to state: inout GameState) -> (questsToStart: [String], chapterChanged: Bool) {
        var quests: [String] = []
        var chapterChanged = false
        for effect in effects {
            switch effect {
            case .setFlag(let f): state.flags.insert(f)
            case .clearFlag(let f): state.flags.remove(f)
            case .addValue(let v, let n): state.storyValues[v, default: 0] += n
            case .startQuest(let q): quests.append(q)
            case .setChapter(let n):
                if n != state.chapter {
                    state.chapter = n
                    chapterChanged = true
                }
            }
        }
        return (quests, chapterChanged)
    }

    /// Fills in `{name}` and pronoun tokens. Lower-case tokens give lower-case words; capitalised
    /// tokens (`{They}`) give capitalised words.
    ///
    /// | Token | they | she |
    /// |---|---|---|
    /// | `{they}` | they | she |
    /// | `{them}` | them | her |
    /// | `{their}` | their | her |
    /// | `{theirs}` | theirs | hers |
    /// | `{themself}` | themself | herself |
    /// | `{are}` | are | is |
    /// | `{were}` | were | was |
    /// | `{have}` | have | has |
    /// | `{s}` (verb ending: "{they} walk{s}") | (nothing) | s |
    static func render(_ text: String, player: PlayerProfile) -> String {
        let p = player.pronouns
        let words: [String: String] = [
            "name": player.name,
            "they": p.subject,
            "them": p.object,
            "their": p.possessive,
            "theirs": p.possessivePronoun,
            "themself": p.reflexive,
            "are": p.pluralVerbs ? "are" : "is",
            "were": p.pluralVerbs ? "were" : "was",
            "have": p.pluralVerbs ? "have" : "has",
            "s": p.pluralVerbs ? "" : "s",
        ]
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                result += rest[open...]   // a lone "{" with no closing brace is kept as written
                rest = ""
                break
            }
            let token = String(rest[rest.index(after: open)..<close])
            if let word = words[token] {
                result += word
            } else if let word = words[token.lowercased()], token.first?.isUppercase == true {
                result += word.prefix(1).uppercased() + word.dropFirst()
            } else {
                result += "{\(token)}"   // unknown tokens are left visible so they're easy to spot
            }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    /// Every token `render` understands, for content checks.
    static let knownTokens: Set<String> = ["name", "they", "them", "their", "theirs", "themself", "are", "were", "have", "s"]
}
