import XCTest
@testable import Fenlight

/// A small fixed set of buildings so tests don't depend on balance changes in buildings.json.
private let testContent = GameContent(buildings: [
    BuildingDef(id: "reed_candles", name: "Stall", blurb: "", kind: .shop, size: 1, cost: 25,
                unlockLevel: 1, baseRate: 1, capSeconds: 100, xp: 5, maxLevel: 10, color: "#FFFFFF"),
    BuildingDef(id: "bakery", name: "Bakery", blurb: "", kind: .shop, size: 2, cost: 100,
                unlockLevel: 1, baseRate: 2, capSeconds: 50, xp: 10, maxLevel: 3, color: "#FFFFFF"),
    BuildingDef(id: "inn", name: "Inn", blurb: "", kind: .shop, size: 3, cost: 10,
                unlockLevel: 5, baseRate: 5, capSeconds: 50, xp: 10, maxLevel: 10, color: "#FFFFFF"),
])

/// A clock the test controls.
private final class TestTime {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

@MainActor
private func makeGame(time: TestTime, glimmer: Double = 1_000) -> Game {
    var state = GameState.newGame(now: time.date)
    state.glimmer = glimmer
    return Game(content: testContent, state: state, clock: time.clock)
}

@MainActor
final class EconomyTests: XCTestCase {
    func testEarningsGrowWithTimeAndStopAtCapacity() {
        let time = TestTime()
        let game = makeGame(time: time)
        let stall = game.state.buildings[0]

        XCTAssertEqual(game.pending(stall), 0)
        time.advance(30)
        XCTAssertEqual(game.pending(stall), 30, accuracy: 0.001)
        time.advance(1_000)
        XCTAssertEqual(game.pending(stall), 100, accuracy: 0.001, "should stop at capSeconds × rate")
        XCTAssertTrue(game.isFull(stall))
    }

    func testCollectAddsGlimmerAndResetsTheShop() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 0)
        time.advance(40)

        XCTAssertEqual(game.collect(1), 40, accuracy: 0.001)
        XCTAssertEqual(game.state.glimmer, 40, accuracy: 0.001)
        XCTAssertEqual(game.pending(game.state.buildings[0]), 0)
    }

    func testCollectAllGathersEveryShop() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 100)
        XCTAssertTrue(game.build("bakery", at: Tile(c: 13, r: 13)))
        XCTAssertEqual(game.state.glimmer, 0)

        time.advance(10)   // stall: 10, bakery: 20
        XCTAssertEqual(game.collectAll(), 30, accuracy: 0.001)
        XCTAssertEqual(game.totalPending(), 0)
    }

    func testOfflineEarningsShowAWelcomeBackSummary() {
        let time = TestTime()
        var state = GameState.newGame(now: time.date)
        state.savedAt = time.date
        time.advance(2 * 3600)

        let game = Game(content: testContent, state: state, clock: time.clock)
        let summary = try? XCTUnwrap(game.awaySummary)
        XCTAssertEqual(summary?.duration ?? 0, 7200, accuracy: 0.001)
        XCTAssertEqual(summary?.waiting ?? 0, 100, accuracy: 0.001, "capped at the stall's capacity")
    }

    func testUpgradeCollectsFirstThenRaisesTheRate() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 1_000)
        time.advance(10)
        let cost = game.upgradeCost(game.state.buildings[0])!

        XCTAssertTrue(game.upgrade(1))
        XCTAssertEqual(game.state.glimmer, 1_000 + 10 - cost, accuracy: 0.001)
        XCTAssertEqual(game.state.buildings[0].level, 2)
        time.advance(10)
        XCTAssertEqual(game.pending(game.state.buildings[0]), 14.5, accuracy: 0.001)
    }

    func testCannotUpgradePastMaxLevel() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 1_000_000)
        XCTAssertTrue(game.build("bakery", at: Tile(c: 13, r: 13)))
        let id = game.state.buildings.last!.id
        XCTAssertTrue(game.upgrade(id))
        XCTAssertTrue(game.upgrade(id))
        XCTAssertFalse(game.upgrade(id), "maxLevel is 3")
        XCTAssertNil(game.upgradeCost(game.building(id: id)!))
    }

    func testBuildingCostRisesWithEachCopy() {
        let def = testContent.building("reed_candles")!
        XCTAssertEqual(Economy.buildCost(def, owned: 0), 25)
        XCTAssertGreaterThan(Economy.buildCost(def, owned: 1), 25)
    }

    func testLevelsComeFromXP() {
        XCTAssertEqual(Economy.level(forXP: 0), 1)
        XCTAssertEqual(Economy.level(forXP: Economy.xpForLevel(2)), 2)
        XCTAssertEqual(Economy.level(forXP: Economy.xpForLevel(5) - 1), 4)
    }

    func testLockedBuildingsCannotBeBuilt() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 1_000)
        XCTAssertFalse(game.build("inn", at: Tile(c: 13, r: 13)), "inn unlocks at level 5")
    }
}

@MainActor
final class GridTests: XCTestCase {
    func testPlacementRejectsOverlap() {
        let time = TestTime()
        let game = makeGame(time: time)
        // The starting stall sits on (11, 11).
        XCTAssertFalse(game.canPlace("bakery", at: Tile(c: 10, r: 10)))
        XCTAssertTrue(game.canPlace("bakery", at: Tile(c: 12, r: 12)))
    }

    func testPlacementRejectsMurkAndMapEdges() {
        let time = TestTime()
        let game = makeGame(time: time)
        XCTAssertFalse(game.canPlace("reed_candles", at: Tile(c: 0, r: 0)), "murk")
        XCTAssertFalse(game.canPlace("bakery", at: Tile(c: 15, r: 15)), "footprint runs into murk at 16")
        XCTAssertFalse(game.canPlace("reed_candles", at: Tile(c: -1, r: 10)), "off the map")
    }

    func testMovingIgnoresTheBuildingsOwnFootprint() {
        let time = TestTime()
        let game = makeGame(time: time)
        XCTAssertTrue(game.build("bakery", at: Tile(c: 12, r: 12)))
        let id = game.state.buildings.last!.id
        XCTAssertTrue(game.move(id, to: Tile(c: 13, r: 12)), "overlaps only itself")
        XCTAssertEqual(game.building(id: id)?.origin, Tile(c: 13, r: 12))
    }

    func testCleanseOnlyNextToCleansedLand() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 10_000)
        XCTAssertFalse(game.canCleanse(Chunk(cx: 0, cy: 0)), "not adjacent")
        XCTAssertFalse(game.canCleanse(Chunk(cx: 2, cy: 2)), "already clean")
        XCTAssertTrue(game.cleanse(Chunk(cx: 1, cy: 2)))
        XCTAssertTrue(game.isCleansed(Tile(c: 4, r: 8)))
        XCTAssertTrue(game.canCleanse(Chunk(cx: 0, cy: 2)), "now adjacent")
    }

    func testCleanseCostRises() {
        XCTAssertLessThan(Economy.cleanseCost(cleansedSoFar: 4), Economy.cleanseCost(cleansedSoFar: 5))
    }
}

final class IsoMathTests: XCTestCase {
    func testTileRoundTripsThroughScreenSpace() {
        for c in 0..<World.size {
            for r in 0..<World.size {
                let t = Tile(c: c, r: r)
                XCTAssertEqual(IsoMath.tile(at: IsoMath.center(of: t)), t)
            }
        }
    }

    func testPointsNearATileCornerStayInThatTile() {
        let t = Tile(c: 5, r: 7)
        let center = IsoMath.center(of: t)
        let inset: CGFloat = 4
        let nearTop = CGPoint(x: center.x, y: center.y + IsoMath.tileHeight / 2 - inset)
        let nearRight = CGPoint(x: center.x + IsoMath.tileWidth / 2 - inset * 2, y: center.y)
        XCTAssertEqual(IsoMath.tile(at: nearTop), t)
        XCTAssertEqual(IsoMath.tile(at: nearRight), t)
    }

    func testFrontmostFootprintsDrawOnTop() {
        let back = IsoMath.zPosition(origin: Tile(c: 2, r: 2), size: 2)
        let front = IsoMath.zPosition(origin: Tile(c: 4, r: 4), size: 1)
        XCTAssertGreaterThan(front, back)
    }
}

final class SaveTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("save.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SaveStore(url: url)
        var state = GameState.newGame(now: Date(timeIntervalSinceReferenceDate: 500))
        state.glimmer = 1234.5
        state.cleansedChunks.insert(Chunk(cx: 1, cy: 2))
        store.save(state)

        XCTAssertEqual(try XCTUnwrap(store.load()), state)
    }

    func testMissingSaveLoadsNothing() {
        let store = SaveStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("nope/save.json"))
        XCTAssertNil(store.load())
    }

    func testCorruptSaveLoadsNothing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(SaveStore(url: url).load())
    }
}
