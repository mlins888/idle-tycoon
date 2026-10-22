import Foundation

enum BuildingKind: String, Codable {
    case shop
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
    /// Glimmer per second at level 1.
    let baseRate: Double
    /// Seconds of production a shop can hold before it's full and stops.
    let capSeconds: Double
    let xp: Double
    let maxLevel: Int
    /// Placeholder colour (hex) used until real art exists.
    let color: String
}

struct GameContent {
    let buildings: [BuildingDef]
    private let byId: [String: BuildingDef]

    init(buildings: [BuildingDef]) {
        self.buildings = buildings
        self.byId = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
    }

    func building(_ id: String) -> BuildingDef? { byId[id] }

    static func load(bundle: Bundle = .main) -> GameContent {
        guard let url = bundle.url(forResource: "buildings", withExtension: "json") else {
            fatalError("buildings.json is missing from the app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return GameContent(buildings: try JSONDecoder().decode([BuildingDef].self, from: data))
        } catch {
            fatalError("buildings.json could not be read: \(error)")
        }
    }
}
