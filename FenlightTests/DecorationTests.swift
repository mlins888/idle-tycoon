import XCTest
@testable import Fenlight

private func deco(_ id: String, size: Int = 1, radius: Int?, bonus: Double = 0) -> BuildingDef {
    BuildingDef(id: id, kind: .decoration, size: size, cost: 100, unlockLevel: 1, xp: 1, color: "#FFFFFF",
                stages: [StageDef(name: id, blurb: "")],
                aura: radius.map { Aura(radius: $0, bonus: bonus) })
}

private let content = GameContent(buildings: [
    testShopDef("reed_candles", cost: 25, cycle: 10, payout: 100),
    BuildingDef(id: "reed_cottage", kind: .house, size: 1, cost: 40, unlockLevel: 1, xp: 5, color: "#FFFFFF",
                stages: [StageDef(name: "Cottage", blurb: "", beds: 1)]),
    deco("lamp", radius: 1, bonus: 0.1),
    deco("tree", radius: 2, bonus: 0.2),
    deco("fountain", size: 2, radius: 1, bonus: 0.3),
    deco("path", radius: nil),
])

private final class TestTime {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

@MainActor
private func makeGame(_ time: TestTime, glimmer: Double = 10_000) -> Game {
    var state = GameState.newGame(now: time.date)
    state.glimmer = glimmer
    useRoomyTestLayout(&state)
    return Game(content: content, state: state, clock: time.clock)
}

/// The starting Rushlight Stall, on tile (11, 11).
private let stall = 1

@MainActor
final class DecorationTests: XCTestCase {
    func testDistanceBetweenFootprints() {
        XCTAssertEqual(World.distance(Tile(c: 5, r: 5), size: 1, Tile(c: 6, r: 5), size: 1), 1, "side by side")
        XCTAssertEqual(World.distance(Tile(c: 5, r: 5), size: 1, Tile(c: 6, r: 6), size: 1), 1, "diagonal")
        XCTAssertEqual(World.distance(Tile(c: 5, r: 5), size: 1, Tile(c: 8, r: 5), size: 1), 3)
        XCTAssertEqual(World.distance(Tile(c: 5, r: 5), size: 2, Tile(c: 7, r: 5), size: 1), 1, "measured from the footprint's edge")
    }

    func testANearbyDecorationBoostsAShop() {
        let game = makeGame(TestTime())
        XCTAssertTrue(game.build("lamp", at: Tile(c: 12, r: 11)))
        XCTAssertEqual(game.decorationBonus(game.building(id: stall)!), 0.1, accuracy: 0.0001)
        XCTAssertEqual(game.payout(game.building(id: stall)!), 110)
    }

    func testAuraRadiusLimitsReach() {
        let game = makeGame(TestTime())
        XCTAssertTrue(game.build("lamp", at: Tile(c: 13, r: 11)))   // two tiles away, radius 1
        XCTAssertEqual(game.decorationBonus(game.building(id: stall)!), 0)
        XCTAssertTrue(game.build("tree", at: Tile(c: 13, r: 13)))   // two tiles away, radius 2
        XCTAssertEqual(game.decorationBonus(game.building(id: stall)!), 0.2, accuracy: 0.0001)
    }

    func testBonusesStackUpToTheCap() {
        let game = makeGame(TestTime())
        game.build("tree", at: Tile(c: 12, r: 11))
        game.build("tree", at: Tile(c: 10, r: 11))
        game.build("fountain", at: Tile(c: 12, r: 12))
        let shop = game.building(id: stall)!
        XCTAssertEqual(game.decorationBonusUncapped(shop), 0.7, accuracy: 0.0001)
        XCTAssertEqual(game.decorationBonus(shop), Economy.maxDecorationBonus)
        XCTAssertEqual(game.payout(shop), 150)
    }

    func testDecorationsDontBoostHouses() {
        let game = makeGame(TestTime())
        game.build("lamp", at: Tile(c: 10, r: 12))   // next to the cottage at (9, 12)
        XCTAssertFalse(game.shopsReached(by: game.state.buildings.last!).contains { $0.defId == "reed_cottage" })
    }

    func testPathsHaveNoAura() {
        let game = makeGame(TestTime())
        game.build("path", at: Tile(c: 12, r: 11))
        XCTAssertEqual(game.decorationBonus(game.building(id: stall)!), 0)
    }

    func testABonusAppliesToTheRunInProgress() {
        let time = TestTime()
        let game = makeGame(time, glimmer: 100)
        time.advance(5)
        XCTAssertTrue(game.build("lamp", at: Tile(c: 12, r: 11)))
        time.advance(5)
        XCTAssertEqual(game.collect(stall), 110, "paid at the boosted amount when collected")
    }

    func testMovingADecorationChangesWhatItBoosts() {
        let game = makeGame(TestTime())
        game.build("lamp", at: Tile(c: 12, r: 11))
        let lamp = game.state.buildings.last!.id
        XCTAssertTrue(game.move(lamp, to: Tile(c: 14, r: 14)))
        XCTAssertEqual(game.decorationBonus(game.building(id: stall)!), 0)
    }

    func testRemovingADecorationRefundsHalf() {
        let game = makeGame(TestTime(), glimmer: 1_000)
        game.build("lamp", at: Tile(c: 12, r: 11))
        let lamp = game.state.buildings.last!.id
        let before = game.state.glimmer
        XCTAssertTrue(game.removeDecoration(lamp))
        XCTAssertEqual(game.state.glimmer, before + 50, accuracy: 0.001)
        XCTAssertNil(game.building(id: lamp))
        XCTAssertFalse(game.removeDecoration(stall), "only decorations can be put away")
    }

    func testExtraDecorationsCostOnlyALittleMore() {
        let def = content.building("lamp")!
        XCTAssertEqual(Economy.buildCost(def, owned: 1), 112)
    }
}
