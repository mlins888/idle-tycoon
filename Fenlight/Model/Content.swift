import Foundation

enum BuildingKind: String, Codable {
    /// Earns glimmer over time.
    case shop
    /// Gives beds so residents can move in.
    case house
    /// The Wisp Shrine, where rare residents are summoned.
    case shrine
    /// The Lamplighters' Guild, which unlocks Keeper's Charters (auto-collect).
    case guild
    /// Lanterns, trees, paths and the like. Most boost nearby shops.
    case decoration
}

/// A decoration's boost to nearby shops: shops within `radius` tiles earn `bonus` more (0.05 = +5%).
struct Aura: Codable, Hashable {
    let radius: Int
    let bonus: Double
}

/// Something that has to be true before a building stage or a quest unlocks.
/// In JSON: `{"type": "level", "level": 3}`, `{"type": "building", "building": "mossbread", "stage": 2}`,
/// `{"type": "resident", "resident": "marigold"}`, `{"type": "quest", "quest": "ovens_warm"}`,
/// `{"type": "restoration", "percent": 40}`.
/// Story kinds: `{"type": "flag", "flag": "x"}`, `{"type": "notFlag", "flag": "x"}`,
/// `{"type": "valueAtLeast", "value": "sealStrain", "amount": 3}`, `{"type": "valueAtMost", ...}`,
/// `{"type": "chapter", "chapter": 2}` (at least that chapter), `{"type": "sceneSeen", "scene": "id"}`.
enum Requirement: Hashable {
    case level(Int)
    case building(String, stage: Int)
    case resident(String)
    case quest(String)
    /// Fraction of the fen cleansed, 0...1.
    case restoration(Double)
    case flag(String)
    case notFlag(String)
    case valueAtLeast(String, Double)
    case valueAtMost(String, Double)
    case chapter(Int)
    case sceneSeen(String)
}

extension Requirement: Codable {
    private enum Keys: String, CodingKey {
        case type, level, building, stage, resident, quest, percent, flag, value, amount, chapter, scene
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "flag": self = .flag(try c.decode(String.self, forKey: .flag))
        case "notFlag": self = .notFlag(try c.decode(String.self, forKey: .flag))
        case "valueAtLeast": self = .valueAtLeast(try c.decode(String.self, forKey: .value), try c.decode(Double.self, forKey: .amount))
        case "valueAtMost": self = .valueAtMost(try c.decode(String.self, forKey: .value), try c.decode(Double.self, forKey: .amount))
        case "chapter": self = .chapter(try c.decode(Int.self, forKey: .chapter))
        case "sceneSeen": self = .sceneSeen(try c.decode(String.self, forKey: .scene))
        case "level": self = .level(try c.decode(Int.self, forKey: .level))
        case "building": self = .building(try c.decode(String.self, forKey: .building),
                                          stage: try c.decodeIfPresent(Int.self, forKey: .stage) ?? 1)
        case "resident": self = .resident(try c.decode(String.self, forKey: .resident))
        case "quest": self = .quest(try c.decode(String.self, forKey: .quest))
        case "restoration": self = .restoration(try c.decode(Double.self, forKey: .percent) / 100)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown requirement \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .level(let n):
            try c.encode("level", forKey: .type); try c.encode(n, forKey: .level)
        case .building(let id, let stage):
            try c.encode("building", forKey: .type); try c.encode(id, forKey: .building); try c.encode(stage, forKey: .stage)
        case .resident(let id):
            try c.encode("resident", forKey: .type); try c.encode(id, forKey: .resident)
        case .quest(let id):
            try c.encode("quest", forKey: .type); try c.encode(id, forKey: .quest)
        case .restoration(let fraction):
            try c.encode("restoration", forKey: .type); try c.encode(fraction * 100, forKey: .percent)
        case .flag(let f):
            try c.encode("flag", forKey: .type); try c.encode(f, forKey: .flag)
        case .notFlag(let f):
            try c.encode("notFlag", forKey: .type); try c.encode(f, forKey: .flag)
        case .valueAtLeast(let v, let n):
            try c.encode("valueAtLeast", forKey: .type); try c.encode(v, forKey: .value); try c.encode(n, forKey: .amount)
        case .valueAtMost(let v, let n):
            try c.encode("valueAtMost", forKey: .type); try c.encode(v, forKey: .value); try c.encode(n, forKey: .amount)
        case .chapter(let n):
            try c.encode("chapter", forKey: .type); try c.encode(n, forKey: .chapter)
        case .sceneSeen(let id):
            try c.encode("sceneSeen", forKey: .type); try c.encode(id, forKey: .scene)
        }
    }
}

/// One stage of a building: what it's called, what it sells and what it earns.
/// Stage 1 is what you build; later stages are reached by renovating.
struct StageDef: Codable, Hashable {
    let name: String
    let blurb: String
    /// Goods this stage sells, for display.
    var sells: [String] = []
    /// How long one production run takes, in seconds (shops).
    var cycleSeconds: Double = 0
    /// Glimmer paid out when a run finishes and you collect it (shops).
    var payout: Double = 0
    /// Beds (houses).
    var beds: Int = 0
    /// Glimmer to renovate into this stage. Unused for stage 1 (that's the building's build cost).
    var cost: Double = 0
    /// How long the renovation into this stage takes, in seconds.
    var buildSeconds: Double = 0
    var requirements: [Requirement] = []
}

extension StageDef {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        blurb = try c.decode(String.self, forKey: .blurb)
        sells = try c.decodeIfPresent([String].self, forKey: .sells) ?? []
        cycleSeconds = try c.decodeIfPresent(Double.self, forKey: .cycleSeconds) ?? 0
        payout = try c.decodeIfPresent(Double.self, forKey: .payout) ?? 0
        beds = try c.decodeIfPresent(Int.self, forKey: .beds) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        buildSeconds = try c.decodeIfPresent(Double.self, forKey: .buildSeconds) ?? 0
        requirements = try c.decodeIfPresent([Requirement].self, forKey: .requirements) ?? []
    }
}

/// One kind of building, as defined in `Content/buildings.json`.
/// Adding or rebalancing buildings means editing that file, not code.
struct BuildingDef: Codable, Identifiable, Hashable {
    let id: String
    let kind: BuildingKind
    /// Square footprint, in tiles per side.
    let size: Int
    /// Glimmer to build it (at stage 1).
    let cost: Double
    let unlockLevel: Int
    let xp: Double
    /// Placeholder colour (hex) used until real art exists.
    let color: String
    /// At least one. Stage 1 is index 0.
    let stages: [StageDef]
    /// Only one can be built per town (the shrine and the guild).
    var unique: Bool = false
    /// Decorations only: the boost they give nearby shops (nil for purely decorative ones, like paths).
    var aura: Aura?
    /// Decorations only: which placeholder shape to draw until real art exists
    /// (`lamp`, `tree`, `flowers`, `path`, `statue`, `pond`, `fountain`).
    var shape: String?
    /// Can only be built once unlocked on a festival's reward track.
    var eventOnly: Bool = false

    /// The stage-1 name, used in the build menu and lists.
    var name: String { stages[0].name }
    var blurb: String { stages[0].blurb }

    /// Stage `n`, counting from 1, clamped to the stages that exist.
    func stage(_ n: Int) -> StageDef {
        stages[min(max(n, 1), stages.count) - 1]
    }

    /// How many residents can work here. Big shops take two.
    var workerSlots: Int {
        kind == .shop ? (size >= 3 ? 2 : 1) : 0
    }
}

extension BuildingDef {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(BuildingKind.self, forKey: .kind)
        size = try c.decode(Int.self, forKey: .size)
        cost = try c.decode(Double.self, forKey: .cost)
        unlockLevel = try c.decode(Int.self, forKey: .unlockLevel)
        xp = try c.decode(Double.self, forKey: .xp)
        color = try c.decode(String.self, forKey: .color)
        stages = try c.decode([StageDef].self, forKey: .stages)
        unique = try c.decodeIfPresent(Bool.self, forKey: .unique) ?? false
        aura = try c.decodeIfPresent(Aura.self, forKey: .aura)
        shape = try c.decodeIfPresent(String.self, forKey: .shape)
        eventOnly = try c.decodeIfPresent(Bool.self, forKey: .eventOnly) ?? false
        guard !stages.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .stages, in: c, debugDescription: "\(id) has no stages")
        }
    }
}

enum Rarity: String, Codable, CaseIterable, Comparable {
    case common, uncommon, rare, legendary

    /// Relative chance of each rarity when summoning.
    var summonWeight: Double {
        switch self {
        case .common: return 0
        case .uncommon: return 70
        case .rare: return 25
        case .legendary: return 5
        }
    }

    static func < (a: Rarity, b: Rarity) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// How a resident comes to live in town.
enum ArrivalKind: String, Codable {
    /// Shows up on their own over time when there's a free bed.
    case wanderer
    /// Joins when the town reaches their unlock level.
    case story
    /// Only comes when summoned at the Wisp Shrine.
    case summon
    /// Earned on a festival's reward track.
    case event
}

/// One resident, as defined in `Content/residents.json`.
struct ResidentDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// What kind of being they are, e.g. "Frog-folk ferryman".
    let folk: String
    let blurb: String
    let rarity: Rarity
    let arrival: ArrivalKind
    let unlockLevel: Int
    /// The shop id where this resident gives their bigger bonus.
    let favoriteShop: String
    /// Placeholder portrait colour (hex) until real art exists.
    let color: String
    /// Things they say in speech bubbles around town.
    var chatter: [String] = []
}

extension ResidentDef {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        folk = try c.decode(String.self, forKey: .folk)
        blurb = try c.decode(String.self, forKey: .blurb)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        arrival = try c.decode(ArrivalKind.self, forKey: .arrival)
        unlockLevel = try c.decode(Int.self, forKey: .unlockLevel)
        favoriteShop = try c.decode(String.self, forKey: .favoriteShop)
        color = try c.decode(String.self, forKey: .color)
        chatter = try c.decodeIfPresent([String].self, forKey: .chatter) ?? []
    }
}

/// What a quest asks for. In JSON: `{"type": "collect", "shop": "mossbread", "amount": 200}`,
/// `{"type": "build", "building": "reed_cottage", "count": 2}`, `{"type": "stage", "building": "mossbread", "stage": 2}`,
/// `{"type": "cleanse", "count": 1}`, `{"type": "residents", "count": 4}`, `{"type": "level", "level": 5}`.
/// New kinds of objective (a puzzle, a fight) can be added here later.
enum Objective: Hashable {
    /// Collect this much glimmer from a kind of shop (or any shop when nil) after the quest starts.
    case collect(shop: String?, amount: Double)
    /// Own this many of a building.
    case build(String, count: Int)
    /// Own one of a building at this stage or higher.
    case stage(String, stage: Int)
    /// Cleanse this many chunks of murk after the quest starts.
    case cleanse(count: Int)
    /// Have this many residents living in town.
    case residents(count: Int)
    case level(Int)
}

extension Objective: Codable {
    private enum Keys: String, CodingKey { case type, shop, amount, building, count, stage, level }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "collect": self = .collect(shop: try c.decodeIfPresent(String.self, forKey: .shop),
                                        amount: try c.decode(Double.self, forKey: .amount))
        case "build": self = .build(try c.decode(String.self, forKey: .building),
                                    count: try c.decodeIfPresent(Int.self, forKey: .count) ?? 1)
        case "stage": self = .stage(try c.decode(String.self, forKey: .building),
                                    stage: try c.decode(Int.self, forKey: .stage))
        case "cleanse": self = .cleanse(count: try c.decode(Int.self, forKey: .count))
        case "residents": self = .residents(count: try c.decode(Int.self, forKey: .count))
        case "level": self = .level(try c.decode(Int.self, forKey: .level))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown objective \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .collect(let shop, let amount):
            try c.encode("collect", forKey: .type); try c.encodeIfPresent(shop, forKey: .shop); try c.encode(amount, forKey: .amount)
        case .build(let id, let count):
            try c.encode("build", forKey: .type); try c.encode(id, forKey: .building); try c.encode(count, forKey: .count)
        case .stage(let id, let stage):
            try c.encode("stage", forKey: .type); try c.encode(id, forKey: .building); try c.encode(stage, forKey: .stage)
        case .cleanse(let count):
            try c.encode("cleanse", forKey: .type); try c.encode(count, forKey: .count)
        case .residents(let count):
            try c.encode("residents", forKey: .type); try c.encode(count, forKey: .count)
        case .level(let n):
            try c.encode("level", forKey: .type); try c.encode(n, forKey: .level)
        }
    }
}

struct Reward: Codable, Hashable {
    var glimmer: Double = 0
    var wisps: Double = 0
    var xp: Double = 0
}

extension Reward {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glimmer = try c.decodeIfPresent(Double.self, forKey: .glimmer) ?? 0
        wisps = try c.decodeIfPresent(Double.self, forKey: .wisps) ?? 0
        xp = try c.decodeIfPresent(Double.self, forKey: .xp) ?? 0
    }
}

/// One quest, as defined in `Content/quests.json`.
struct QuestDef: Codable, Identifiable, Hashable {
    let id: String
    /// Story chapter, for grouping into the larger storyline later.
    let chapter: Int
    /// Resident id of who gives the quest. They have to live in town for it to appear.
    let giver: String
    let title: String
    let text: String
    /// Shown when the quest is ready to claim.
    let doneText: String
    let objective: Objective
    let reward: Reward
    var prerequisites: [Requirement] = []
}

extension QuestDef {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        chapter = try c.decodeIfPresent(Int.self, forKey: .chapter) ?? 1
        giver = try c.decode(String.self, forKey: .giver)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        doneText = try c.decode(String.self, forKey: .doneText)
        objective = try c.decode(Objective.self, forKey: .objective)
        reward = try c.decode(Reward.self, forKey: .reward)
        prerequisites = try c.decodeIfPresent([Requirement].self, forKey: .prerequisites) ?? []
    }
}

/// A month and day, e.g. `"10-15"` in JSON for 15 October.
struct MonthDay: Hashable, Codable {
    let month: Int
    let day: Int

    init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected MM-DD, got \(text)"))
        }
        month = parts[0]
        day = parts[1]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%02d-%02d", month, day))
    }
}

/// What a festival milestone gives you.
struct EventReward: Codable, Hashable {
    var glimmer: Double = 0
    var wisps: Double = 0
    /// An `eventOnly` decoration that becomes buildable.
    var decoration: String?
    /// A resident (arrival `event`) who moves in once there's a bed.
    var resident: String?
}

extension EventReward {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glimmer = try c.decodeIfPresent(Double.self, forKey: .glimmer) ?? 0
        wisps = try c.decodeIfPresent(Double.self, forKey: .wisps) ?? 0
        decoration = try c.decodeIfPresent(String.self, forKey: .decoration)
        resident = try c.decodeIfPresent(String.self, forKey: .resident)
    }
}

struct Milestone: Codable, Hashable {
    /// Festival tokens needed.
    let tokens: Double
    let reward: EventReward
}

/// A yearly festival, as defined in `Content/events.json`. Runs from `start` to `end` (inclusive) every
/// year; a window can wrap past New Year (e.g. 12-15 to 01-05).
struct EventDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let start: MonthDay
    let end: MonthDay
    /// The festival's currency, e.g. "moon-penny" / "moon-pennies".
    let token: String
    let tokens: String
    let color: String
    let milestones: [Milestone]
}

// MARK: - Story

/// When a scene plays. In JSON: `{"type": "gameStart"}`, `{"type": "chapterStart", "chapter": 2}`,
/// `{"type": "questStarted", "quest": "id"}`, `{"type": "questCompleted", "quest": "id"}`,
/// `{"type": "arrival", "resident": "id"}`, `{"type": "debug"}` (only from the debug menu).
enum SceneTrigger: Hashable {
    case gameStart
    case chapterStart(Int)
    case questStarted(String)
    case questCompleted(String)
    case arrival(String)
    case debug
}

extension SceneTrigger: Codable {
    private enum Keys: String, CodingKey { case type, chapter, quest, resident }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "gameStart": self = .gameStart
        case "chapterStart": self = .chapterStart(try c.decode(Int.self, forKey: .chapter))
        case "questStarted": self = .questStarted(try c.decode(String.self, forKey: .quest))
        case "questCompleted": self = .questCompleted(try c.decode(String.self, forKey: .quest))
        case "arrival": self = .arrival(try c.decode(String.self, forKey: .resident))
        case "debug": self = .debug
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown scene trigger \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .gameStart: try c.encode("gameStart", forKey: .type)
        case .chapterStart(let n): try c.encode("chapterStart", forKey: .type); try c.encode(n, forKey: .chapter)
        case .questStarted(let q): try c.encode("questStarted", forKey: .type); try c.encode(q, forKey: .quest)
        case .questCompleted(let q): try c.encode("questCompleted", forKey: .type); try c.encode(q, forKey: .quest)
        case .arrival(let r): try c.encode("arrival", forKey: .type); try c.encode(r, forKey: .resident)
        case .debug: try c.encode("debug", forKey: .type)
        }
    }
}

/// Something a scene or a choice changes. In JSON: `{"type": "setFlag", "flag": "x"}`,
/// `{"type": "clearFlag", "flag": "x"}`, `{"type": "addValue", "value": "courtStanding", "amount": 1}`,
/// `{"type": "startQuest", "quest": "id"}`, `{"type": "setChapter", "chapter": 2}`.
enum Effect: Hashable {
    case setFlag(String)
    case clearFlag(String)
    case addValue(String, Double)
    case startQuest(String)
    case setChapter(Int)
}

extension Effect: Codable {
    private enum Keys: String, CodingKey { case type, flag, value, amount, quest, chapter }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "setFlag": self = .setFlag(try c.decode(String.self, forKey: .flag))
        case "clearFlag": self = .clearFlag(try c.decode(String.self, forKey: .flag))
        case "addValue": self = .addValue(try c.decode(String.self, forKey: .value), try c.decode(Double.self, forKey: .amount))
        case "startQuest": self = .startQuest(try c.decode(String.self, forKey: .quest))
        case "setChapter": self = .setChapter(try c.decode(Int.self, forKey: .chapter))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown effect \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .setFlag(let f): try c.encode("setFlag", forKey: .type); try c.encode(f, forKey: .flag)
        case .clearFlag(let f): try c.encode("clearFlag", forKey: .type); try c.encode(f, forKey: .flag)
        case .addValue(let v, let n): try c.encode("addValue", forKey: .type); try c.encode(v, forKey: .value); try c.encode(n, forKey: .amount)
        case .startQuest(let q): try c.encode("startQuest", forKey: .type); try c.encode(q, forKey: .quest)
        case .setChapter(let n): try c.encode("setChapter", forKey: .type); try c.encode(n, forKey: .chapter)
        }
    }
}

/// One line of dialogue. `speaker` is a resident id, a character id from `characters.json`,
/// `"player"` or `"narrator"`. Text can use `{name}` and pronoun tokens (see `Story.render`).
struct SceneLine: Codable, Hashable {
    let speaker: String
    let text: String
    var mood: String?
}

struct SceneChoice: Codable, Hashable {
    let text: String
    var effects: [Effect] = []
}

extension SceneChoice {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
    }
}

/// A dialogue scene, as defined in `Content/scenes.json`. Plays once, when its trigger happens
/// and its requirements are met.
struct SceneDef: Codable, Identifiable, Hashable {
    let id: String
    let trigger: SceneTrigger
    var requires: [Requirement] = []
    let lines: [SceneLine]
    /// Shown after the last line. Empty means the scene just ends.
    var choices: [SceneChoice] = []
    /// Applied when the scene ends (before any choice's own effects).
    var effects: [Effect] = []
}

extension SceneDef {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        trigger = try c.decode(SceneTrigger.self, forKey: .trigger)
        requires = try c.decodeIfPresent([Requirement].self, forKey: .requires) ?? []
        lines = try c.decode([SceneLine].self, forKey: .lines)
        choices = try c.decodeIfPresent([SceneChoice].self, forKey: .choices) ?? []
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
    }
}

/// Someone who speaks in scenes but isn't a resident, from `Content/characters.json`.
struct CharacterDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Placeholder portrait colour (hex) until real art exists.
    let color: String
}

struct GameContent {
    let buildings: [BuildingDef]
    let residents: [ResidentDef]
    let quests: [QuestDef]
    let events: [EventDef]
    let scenes: [SceneDef]
    let characters: [CharacterDef]
    private let buildingsById: [String: BuildingDef]
    private let residentsById: [String: ResidentDef]
    private let questsById: [String: QuestDef]

    init(buildings: [BuildingDef], residents: [ResidentDef] = [], quests: [QuestDef] = [], events: [EventDef] = [],
         scenes: [SceneDef] = [], characters: [CharacterDef] = []) {
        self.buildings = buildings
        self.residents = residents
        self.quests = quests
        self.events = events
        self.scenes = scenes
        self.characters = characters
        self.buildingsById = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        self.residentsById = Dictionary(uniqueKeysWithValues: residents.map { ($0.id, $0) })
        self.questsById = Dictionary(uniqueKeysWithValues: quests.map { ($0.id, $0) })
    }

    func building(_ id: String) -> BuildingDef? { buildingsById[id] }
    func resident(_ id: String) -> ResidentDef? { residentsById[id] }
    func quest(_ id: String) -> QuestDef? { questsById[id] }
    func scene(_ id: String) -> SceneDef? { scenes.first { $0.id == id } }
    func character(_ id: String) -> CharacterDef? { characters.first { $0.id == id } }

    static func load(bundle: Bundle = .main) -> GameContent {
        GameContent(buildings: decode("buildings", bundle: bundle),
                    residents: decode("residents", bundle: bundle),
                    quests: decode("quests", bundle: bundle),
                    events: decode("events", bundle: bundle),
                    scenes: decode("scenes", bundle: bundle),
                    characters: decode("characters", bundle: bundle))
    }

    private static func decode<T: Decodable>(_ name: String, bundle: Bundle) -> [T] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            fatalError("\(name).json is missing from the app bundle")
        }
        do {
            return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
        } catch {
            fatalError("\(name).json could not be read: \(error)")
        }
    }
}
