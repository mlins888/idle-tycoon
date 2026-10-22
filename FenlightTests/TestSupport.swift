import Foundation
@testable import Fenlight

/// Many tests were written against the original 8×8 starting land with the stall on (11, 11) and the
/// cottage on (9, 12). This gives a new game that layout, so those tests keep their coordinates.
func useRoomyTestLayout(_ state: inout GameState) {
    state.cleansedChunks = [Chunk(cx: 2, cy: 2), Chunk(cx: 3, cy: 2), Chunk(cx: 2, cy: 3), Chunk(cx: 3, cy: 3)]
    if let i = state.buildings.firstIndex(where: { $0.defId == "reed_candles" }) { state.buildings[i].origin = Tile(c: 11, r: 11) }
    if let i = state.buildings.firstIndex(where: { $0.defId == "reed_cottage" }) { state.buildings[i].origin = Tile(c: 9, r: 12) }
}

/// A shop with one stage that pays `payout` every `cycle` seconds.
func testShopDef(_ id: String, size: Int = 1, cost: Double = 10, unlock: Int = 1, cycle: Double = 10, payout: Double = 100,
                 stages extra: [StageDef] = []) -> BuildingDef {
    BuildingDef(id: id, kind: .shop, size: size, cost: cost, unlockLevel: unlock, xp: 5, color: "#FFFFFF",
                stages: [StageDef(name: id, blurb: "", cycleSeconds: cycle, payout: payout)] + extra)
}
