import Foundation
import Observation

/// What the player is currently doing on the map. Shared by the scene (taps) and the HUD (panels).
@MainActor
@Observable
final class MapInteraction {
    enum Mode: Equatable {
        case browse
        case placing(defId: String)
        case moving(buildingId: Int)
    }

    var mode: Mode = .browse
    /// Where the ghost building sits while placing or moving.
    var ghostOrigin: Tile?
    var selectedBuildingId: Int?
    var selectedChunk: Chunk?

    func startPlacing(_ defId: String) {
        clearSelection()
        ghostOrigin = nil
        mode = .placing(defId: defId)
    }

    func startMoving(_ buildingId: Int, from origin: Tile) {
        clearSelection()
        ghostOrigin = origin
        mode = .moving(buildingId: buildingId)
    }

    func finishPlacement() {
        mode = .browse
        ghostOrigin = nil
    }

    func clearSelection() {
        selectedBuildingId = nil
        selectedChunk = nil
    }
}
