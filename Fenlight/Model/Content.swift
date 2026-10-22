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
}

/// Something that has to be true before a building stage or a quest unlocks.
/// In JSON: `{"type": "level", "level": 3}`, `{"type": "building", "building": "mossbread", "stage": 2}`,
/// `{"type": "resident", "resident": "marigold"}`, `{"type": "quest", "quest": "ovens_warm"}`,
/// `{"type": "restoration", "percent": 40}`.
enum Requirement: Hashable {
    case level(Int)
    case building(String, stage: Int)
    case resident(String)
    case quest(String)
    /// Fraction of the fen cleansed, 0...1.
    case restoration(Double)
}

extension Requirement: Codable {
    private enum Keys: String, CodingKey { case type, level, building, stage, resident, quest, percent }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
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
    /// Glimmer per second (shops).
    var rate: Double = 0
    /// Seconds of production it holds before it's full and stops (shops).
    var capSeconds: Double = 0
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
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 0
        capSeconds = try c.decodeIfPresent(Double.self, forKey: .capSeconds) ?? 0
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

struct GameContent {
    let buildings: [BuildingDef]
    let residents: [ResidentDef]
    let quests: [QuestDef]
    private let buildingsById: [String: BuildingDef]
    private let residentsById: [String: ResidentDef]
    private let questsById: [String: QuestDef]

    init(buildings: [BuildingDef], residents: [ResidentDef] = [], quests: [QuestDef] = []) {
        self.buildings = buildings
        self.residents = residents
        self.quests = quests
        self.buildingsById = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        self.residentsById = Dictionary(uniqueKeysWithValues: residents.map { ($0.id, $0) })
        self.questsById = Dictionary(uniqueKeysWithValues: quests.map { ($0.id, $0) })
    }

    func building(_ id: String) -> BuildingDef? { buildingsById[id] }
    func resident(_ id: String) -> ResidentDef? { residentsById[id] }
    func quest(_ id: String) -> QuestDef? { questsById[id] }

    static func load(bundle: Bundle = .main) -> GameContent {
        GameContent(buildings: decode("buildings", bundle: bundle),
                    residents: decode("residents", bundle: bundle),
                    quests: decode("quests", bundle: bundle))
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
