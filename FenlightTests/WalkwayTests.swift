import XCTest
@testable import Fenlight

private let content = GameContent(buildings: [
    testShopDef("reed_candles", cost: 25),
    BuildingDef(id: "reed_cottage", kind: .house, size: 1, cost: 40, unlockLevel: 1, xp: 5, color: "#FFFFFF",
                stages: [StageDef(name: "Cottage", blurb: "", beds: 1)]),
    testShopDef("big", size: 3, cost: 1),
    BuildingDef(id: "boardwalk", kind: .decoration, size: 1, cost: 1, unlockLevel: 1, xp: 1, color: "#FFFFFF",
                stages: [StageDef(name: "Boardwalk", blurb: "")], shape: "path"),
])

final class WalkwayTests: XCTestCase {
    private func state(_ extra: [PlacedBuilding] = []) -> GameState {
        var s = GameState.newGame(now: Date())
        useRoomyTestLayout(&s)
        s.buildings += extra
        return s
    }

    func testWalkableIsCleansedLandWithoutBuildings() {
        let walkable = Walkways.walkable(state(), content)
        XCTAssertEqual(walkable.count, 64 - 2, "8×8 starting land minus the stall and the cottage")
        XCTAssertFalse(walkable.contains(Tile(c: 11, r: 11)), "the stall")
        XCTAssertFalse(walkable.contains(Tile(c: 0, r: 0)), "murk")
        XCTAssertTrue(walkable.contains(Tile(c: 12, r: 12)))
    }

    func testPathsCanBeWalkedOn() {
        let path = PlacedBuilding(id: 9, defId: "boardwalk", origin: Tile(c: 13, r: 13), stage: 1, lastCollectedAt: Date())
        XCTAssertTrue(Walkways.walkable(state([path]), content).contains(Tile(c: 13, r: 13)))
    }

    func testRouteGoesAroundBuildings() throws {
        // A 3×3 building in the way between (10, 13) and (14, 13).
        let big = PlacedBuilding(id: 9, defId: "big", origin: Tile(c: 11, r: 12), stage: 1, lastCollectedAt: Date())
        let walkable = Walkways.walkable(state([big]), content)
        let route = try XCTUnwrap(Walkways.path(from: Tile(c: 10, r: 13), to: Tile(c: 14, r: 13), walkable: walkable))
        XCTAssertEqual(route.last, Tile(c: 14, r: 13))
        XCTAssertTrue(route.allSatisfy(walkable.contains), "never steps on a building")
        XCTAssertGreaterThan(route.count, 4, "has to detour")
        // Each step moves to a neighbouring tile.
        var previous = Tile(c: 10, r: 13)
        for step in route {
            XCTAssertEqual(abs(step.c - previous.c) + abs(step.r - previous.r), 1)
            previous = step
        }
    }

    func testNoRouteIntoMurkOrOntoBuildings() {
        let walkable = Walkways.walkable(state(), content)
        XCTAssertNil(Walkways.path(from: Tile(c: 9, r: 9), to: Tile(c: 0, r: 0), walkable: walkable))
        XCTAssertNil(Walkways.path(from: Tile(c: 9, r: 9), to: Tile(c: 11, r: 11), walkable: walkable))
    }

    func testRouteToWhereYouAlreadyAreIsEmpty() {
        let walkable = Walkways.walkable(state(), content)
        XCTAssertEqual(Walkways.path(from: Tile(c: 9, r: 9), to: Tile(c: 9, r: 9), walkable: walkable), [])
    }

    func testSpotsAroundABuildingAreOutsideItAndWithinReach() {
        let walkable = Walkways.walkable(state(), content)
        let spots = Walkways.around(Tile(c: 11, r: 11), size: 1, radius: 1, in: walkable)
        XCTAssertEqual(spots.count, 8, "all eight neighbours of the stall are free")
        XCTAssertFalse(spots.contains(Tile(c: 11, r: 11)))
    }

    func testStrandedResidentsFindTheNearestFreeTile() {
        let walkable = Walkways.walkable(state(), content)
        let safe = Walkways.nearest(to: Tile(c: 11, r: 11), in: walkable)
        XCTAssertEqual(safe.map { World.distance($0, size: 1, Tile(c: 11, r: 11), size: 1) }, 1)
    }

    func testEveryResidentHasChatter() {
        let shipped = GameContent.load(bundle: Bundle(for: Game.self))
        for r in shipped.residents {
            XCTAssertFalse(r.chatter.isEmpty, "\(r.id) has nothing to say")
        }
    }
}
