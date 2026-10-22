import XCTest
@testable import Fenlight

private let testContent = GameContent(buildings: [
    testShopDef("reed_candles", cost: 25, cycle: 60, payout: 5),
    testShopDef("bakery", size: 2, cost: 100, cycle: 180, payout: 30),
    testShopDef("inn", size: 3, cost: 10, unlock: 5, cycle: 60, payout: 5),
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
    useRoomyTestLayout(&state)
    return Game(content: testContent, state: state, clock: time.clock)
}

/// The starting Rushlight Stall: 5 glimmer every minute here.
private let stall = 1

@MainActor
final class EconomyTests: XCTestCase {
    func testNothingToCollectUntilTheRunFinishes() {
        let time = TestTime()
        let game = makeGame(time: time)
        time.advance(59)
        XCTAssertFalse(game.isReady(game.building(id: stall)!))
        XCTAssertEqual(game.pending(game.building(id: stall)!), 0)
        XCTAssertEqual(game.collect(stall), 0, "can't collect a half-done run")
        XCTAssertEqual(game.timeLeft(game.building(id: stall)!), 1, accuracy: 0.001)
        time.advance(1)
        XCTAssertTrue(game.isReady(game.building(id: stall)!))
        XCTAssertEqual(game.pending(game.building(id: stall)!), 5)
    }

    func testReadyBatchesDontStackUp() {
        let time = TestTime()
        let game = makeGame(time: time)
        time.advance(60 * 10)
        XCTAssertEqual(game.pending(game.building(id: stall)!), 5, "one batch waits; ten minutes away isn't ten batches")
    }

    func testCollectPaysTheBatchAndStartsTheNextRun() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 0)
        time.advance(60)
        XCTAssertEqual(game.collect(stall), 5)
        XCTAssertEqual(game.state.glimmer, 5)
        XCTAssertFalse(game.isReady(game.building(id: stall)!))
        XCTAssertEqual(game.timeLeft(game.building(id: stall)!), 60, accuracy: 0.001)
    }

    func testCollectAllGathersEveryReadyShop() {
        let time = TestTime()
        let game = makeGame(time: time, glimmer: 100)
        XCTAssertTrue(game.build("bakery", at: Tile(c: 13, r: 13)))
        XCTAssertEqual(game.state.glimmer, 0)

        time.advance(60)
        XCTAssertEqual(game.collectAll(), 5, "only the stall is ready")
        time.advance(120)
        XCTAssertEqual(game.collectAll(), 35, "stall again, and the bakery's first batch")
        XCTAssertEqual(game.totalPending(), 0)
    }

    func testOfflineEarningsShowAWelcomeBackSummary() {
        let time = TestTime()
        var state = GameState.newGame(now: time.date)
        useRoomyTestLayout(&state)
        state.savedAt = time.date
        time.advance(2 * 3600)

        let game = Game(content: testContent, state: state, clock: time.clock)
        let summary = try? XCTUnwrap(game.awaySummary)
        XCTAssertEqual(summary?.duration ?? 0, 7200, accuracy: 0.001)
        XCTAssertEqual(summary?.waiting ?? 0, 5, "one batch is ready")
    }

    func testSecondCopyOfAShopCostsThreeTimesAsMuch() {
        let def = testContent.building("reed_candles")!
        XCTAssertEqual(Economy.buildCost(def, owned: 0), 25)
        XCTAssertEqual(Economy.buildCost(def, owned: 1), 75)
    }

    func testRunsCompletedCountsWholeRunsUpToTheCap() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(Economy.runsCompleted(since: start, cycle: 10, now: start.addingTimeInterval(25), cap: 100), 2)
        XCTAssertEqual(Economy.runsCompleted(since: start, cycle: 10, now: start.addingTimeInterval(500), cap: 100), 10)
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
    func testANewTownStartsWithOneSixteenTilePatch() {
        let state = GameState.newGame(now: Date())
        XCTAssertEqual(state.cleansedChunks, World.startingChunks)
        XCTAssertEqual(state.cleansedChunks.count * World.chunkSize * World.chunkSize, 16)
        for b in state.buildings {
            XCTAssertTrue(state.cleansedChunks.contains(World.chunk(of: b.origin)), "\(b.defId) starts on cleansed land")
        }
    }

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

    func testCleanseCostStartsLowAndClimbs() {
        XCTAssertEqual(Economy.cleanseCost(cleansedSoFar: 1), 100)
        XCTAssertEqual(Economy.cleanseCost(cleansedSoFar: 2), 240)
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
        state.nextWispAt = Date(timeIntervalSinceReferenceDate: 900)
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

    func testVersionFourSavesLoadWithoutWispFields() throws {
        var old = GameState.newGame(now: Date(timeIntervalSinceReferenceDate: 500))
        old.version = 4
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json["nextWispAt"] = nil
        json["wispVisibleUntil"] = nil
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(loaded.nextWispAt)
        XCTAssertNil(loaded.wispVisibleUntil)
        XCTAssertEqual(loaded.buildings, old.buildings)
    }
}
