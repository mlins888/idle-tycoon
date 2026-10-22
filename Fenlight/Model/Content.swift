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

/// One kind of building, as defined in `Content/buildings.json`.
/// Adding or rebalancing buildings means editing that file, not code.
struct BuildingDef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let kind: BuildingKind
    /// Square footprint, in tiles per side.
    let size: Int
    let cost: Double
    let unlockLevel: Int
    /// Glimmer per second at level 1 (shops only).
    let baseRate: Double
    /// Seconds of production a shop can hold before it's full and stops (shops only).
    let capSeconds: Double
    let xp: Double
    let maxLevel: Int
    /// Placeholder colour (hex) used until real art exists.
    let color: String
    /// Beds this building provides (houses only).
    var beds: Int = 0
    /// Only one can be built per town (the shrine and the guild).
    var unique: Bool = false

    /// How many residents can work here. Big shops take two.
    var workerSlots: Int {
        kind == .shop ? (size >= 3 ? 2 : 1) : 0
    }
}

extension BuildingDef {
    /// Fields that don't apply to a kind of building can be left out of the JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        blurb = try c.decode(String.self, forKey: .blurb)
        kind = try c.decode(BuildingKind.self, forKey: .kind)
        size = try c.decode(Int.self, forKey: .size)
        cost = try c.decode(Double.self, forKey: .cost)
        unlockLevel = try c.decode(Int.self, forKey: .unlockLevel)
        baseRate = try c.decodeIfPresent(Double.self, forKey: .baseRate) ?? 0
        capSeconds = try c.decodeIfPresent(Double.self, forKey: .capSeconds) ?? 0
        xp = try c.decode(Double.self, forKey: .xp)
        maxLevel = try c.decodeIfPresent(Int.self, forKey: .maxLevel) ?? 1
        color = try c.decode(String.self, forKey: .color)
        beds = try c.decodeIfPresent(Int.self, forKey: .beds) ?? 0
        unique = try c.decodeIfPresent(Bool.self, forKey: .unique) ?? false
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

struct GameContent {
    let buildings: [BuildingDef]
    let residents: [ResidentDef]
    private let buildingsById: [String: BuildingDef]
    private let residentsById: [String: ResidentDef]

    init(buildings: [BuildingDef], residents: [ResidentDef] = []) {
        self.buildings = buildings
        self.residents = residents
        self.buildingsById = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        self.residentsById = Dictionary(uniqueKeysWithValues: residents.map { ($0.id, $0) })
    }

    func building(_ id: String) -> BuildingDef? { buildingsById[id] }
    func resident(_ id: String) -> ResidentDef? { residentsById[id] }

    static func load(bundle: Bundle = .main) -> GameContent {
        GameContent(buildings: decode("buildings", bundle: bundle),
                    residents: decode("residents", bundle: bundle))
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
