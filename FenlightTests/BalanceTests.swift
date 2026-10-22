import XCTest
@testable import Fenlight

private let content = GameContent(
    buildings: [
        testShopDef("reed_candles", cost: 25, cycle: 10, payout: 10, stages: [
            StageDef(name: "Chandler", blurb: "", cycleSeconds: 10, payout: 30, cost: 10, buildSeconds: 60),
        ]),
        BuildingDef(id: "reed_cottage", kind: .house, size: 1, cost: 40, unlockLevel: 1, xp: 5, color: "#FFFFFF",
                    stages: [StageDef(name: "Cottage", blurb: "", beds: 1)]),
        BuildingDef(id: "lamp", kind: .decoration, size: 1, cost: 5, unlockLevel: 1, xp: 1, color: "#FFFFFF",
                    stages: [StageDef(name: "Lamp", blurb: "")]),
    ],
    residents: [
        ResidentDef(id: "wren", name: "Wren", folk: "", blurb: "", rarity: .common, arrival: .story,
                    unlockLevel: 1, favoriteShop: "reed_candles", color: "#FFFFFF"),
    ]
)

private final class TestTime {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

@MainActor
private func makeGame(_ time: TestTime, glimmer: Double = 100_000) -> Game {
    var state = GameState.newGame(now: time.date)
    state.glimmer = glimmer
    useRoomyTestLayout(&state)
    return Game(content: content, state: state, clock: time.clock)
}

private let stall = 1

@MainActor
final class OnePerTownTests: XCTestCase {
    func testASecondShopOnlyOnceTheFirstIsFullyBuilt() {
        let time = TestTime()
        let game = makeGame(time)
        let def = content.building("reed_candles")!
        XCTAssertFalse(game.canBuildMore(def), "already have one at stage 1")
        XCTAssertFalse(game.build("reed_candles", at: Tile(c: 13, r: 13)))

        game.startRenovation(stall)
        XCTAssertFalse(game.canBuildMore(def), "not while it's still renovating")
        time.advance(60)
        game.tick()
        XCTAssertTrue(game.canBuildMore(def), "final stage reached")
        XCTAssertTrue(game.build("reed_candles", at: Tile(c: 13, r: 13)))
        XCTAssertFalse(game.canBuildMore(def), "never a third")
    }

    func testHomesAndDecorationsHaveNoLimit() {
        let game = makeGame(TestTime())
        XCTAssertTrue(game.build("reed_cottage", at: Tile(c: 13, r: 13)))
        XCTAssertTrue(game.canBuildMore(content.building("reed_cottage")!))
        XCTAssertTrue(game.build("lamp", at: Tile(c: 14, r: 14)))
        XCTAssertTrue(game.build("lamp", at: Tile(c: 14, r: 13)))
    }
}

@MainActor
final class KeeperRunTests: XCTestCase {
    func testKeepersCollectWholeRunsAndKeepTheirPlace() {
        let time = TestTime()
        var state = GameState.newGame(now: time.date)
        useRoomyTestLayout(&state)
        state.buildings[0].autoCollect = true
        state.residents = [Resident(defId: "wren", homeId: 2, workId: stall, arrivedAt: time.date)]
        let game = Game(content: content, state: state, clock: time.clock)
        let before = game.state.glimmer

        time.advance(25)
        game.tick()
        XCTAssertEqual(game.state.glimmer - before, 2 * 16, "two whole runs at 10 × 1.6")
        XCTAssertEqual(game.timeLeft(game.building(id: stall)!), 5, accuracy: 0.001, "halfway through the third")
    }
}

@MainActor
final class WispTests: XCTestCase {
    func testALostWispAppearsOnScheduleAndCanBeCaughtOnce() throws {
        let time = TestTime()
        let game = makeGame(time)
        let due = try XCTUnwrap(game.state.nextWispAt)
        XCTAssertTrue(Economy.wispDelay.contains(due.timeIntervalSince(time.date)))
        XCTAssertFalse(game.wispVisible)
        XCTAssertNil(game.catchWisp())

        time.date = due
        game.tick()
        XCTAssertTrue(game.wispVisible)
        let before = game.state.wisps
        let caught = try XCTUnwrap(game.catchWisp())
        XCTAssertTrue([1, 2].contains(caught))
        XCTAssertEqual(game.state.wisps, before + caught)
        XCTAssertTrue(game.toasts.contains { $0.text.contains("caught a lost wisp") })
        XCTAssertFalse(game.wispVisible)
        XCTAssertNil(game.catchWisp(), "only once")
        XCTAssertNotNil(game.state.nextWispAt, "the next one is scheduled")
    }

    func testAnUncaughtWispFadesAndTheNextIsScheduled() throws {
        let time = TestTime()
        let game = makeGame(time)
        time.date = try XCTUnwrap(game.state.nextWispAt)
        game.tick()
        time.advance(Economy.wispVisibleFor + 1)
        game.tick()
        XCTAssertFalse(game.wispVisible)
        let next = try XCTUnwrap(game.state.nextWispAt)
        XCTAssertGreaterThan(next, time.date)
    }

    func testAVisibleWispSurvivesARestart() throws {
        let time = TestTime()
        let game = makeGame(time)
        time.date = try XCTUnwrap(game.state.nextWispAt)
        game.tick()
        let saved = game.state
        time.advance(30)
        let back = Game(content: content, state: saved, clock: time.clock)
        XCTAssertTrue(back.wispVisible, "still drifting; restarting didn't reroll it")
    }

    func testWispGainsAreShownWithTheirSource() {
        let game = makeGame(TestTime())
        game.cleanse(Chunk(cx: 1, cy: 2))
        XCTAssertTrue(game.toasts.contains { $0.text == "+3 wisps · cleansed the murk" })
        game.debugAdd(xp: Economy.xpForLevel(2))
        XCTAssertTrue(game.toasts.contains { $0.text == "+5 wisps · reached level 2" })
    }
}

final class RegistryOrderTests: XCTestCase {
    func testEveryArrivalKindCanBeSorted() {
        let kinds: [ArrivalKind] = [.event, .summon, .wanderer, .story]
        let residents = kinds.enumerated().map { i, k in
            ResidentDef(id: "r\(i)", name: "", folk: "", blurb: "", rarity: .common, arrival: k,
                        unlockLevel: 1, favoriteShop: "", color: "#FFFFFF")
        }
        XCTAssertEqual(RegistryGrid.ordered(residents).map(\.arrival), [.story, .wanderer, .summon, .event])
    }

    func testShippedResidentsSortWithoutCrashing() {
        let shipped = GameContent.load(bundle: Bundle(for: Game.self))
        XCTAssertEqual(RegistryGrid.ordered(shipped.residents).count, shipped.residents.count)
    }
}

@MainActor
final class SkipTests: XCTestCase {
    func testTheLastThirtySecondsCanBeSkippedForFree() {
        let time = TestTime()
        var state = GameState.newGame(now: time.date)
        useRoomyTestLayout(&state)
        state.glimmer = 0
        let skippy = GameContent(buildings: [testShopDef("reed_candles", cycle: 60, payout: 5)])
        let game = Game(content: skippy, state: state, clock: time.clock)

        time.advance(29)
        XCTAssertFalse(game.canSkip(game.building(id: stall)!), "31 seconds left")
        XCTAssertEqual(game.skipAndCollect(stall), 0)
        time.advance(1)
        XCTAssertTrue(game.canSkip(game.building(id: stall)!), "30 seconds left")
        XCTAssertEqual(game.skipAndCollect(stall), 5)
        XCTAssertEqual(game.state.glimmer, 5)
        XCTAssertEqual(game.timeLeft(game.building(id: stall)!), 60, accuracy: 0.001, "the next run starts now")
    }

    func testRenovationsAreFreeToFinishInTheLastThirtySeconds() {
        XCTAssertEqual(Economy.finishNowCost(remaining: 30), 0)
        XCTAssertEqual(Economy.finishNowCost(remaining: 31), 1)
        XCTAssertEqual(Economy.finishNowCost(remaining: 601), 2)
    }
}

final class DrawOrderTests: XCTestCase {
    /// For every pair of square footprints (sizes 1–3) that don't overlap, if one is fully in front of
    /// the other along a grid axis while sharing a row or column, it must draw on top.
    func testFootprintsInFrontAlwaysDrawOnTop() {
        var checked = 0
        for sa in 1...3 {
            for sb in 1...3 {
                for dc in -4...4 {
                    for dr in -4...4 {
                        let a = Tile(c: 10, r: 10), b = Tile(c: 10 + dc, r: 10 + dr)
                        let aC = a.c...(a.c + sa - 1), aR = a.r...(a.r + sa - 1)
                        let bC = b.c...(b.c + sb - 1), bR = b.r...(b.r + sb - 1)
                        guard !(aC.overlaps(bC) && aR.overlaps(bR)) else { continue }
                        let bInFront = (b.c > aC.upperBound && bR.overlaps(aR)) || (b.r > aR.upperBound && bC.overlaps(aC))
                        let aInFront = (a.c > bC.upperBound && aR.overlaps(bR)) || (a.r > bR.upperBound && aC.overlaps(bC))
                        let za = IsoMath.zPosition(origin: a, size: sa), zb = IsoMath.zPosition(origin: b, size: sb)
                        if bInFront { XCTAssertGreaterThan(zb, za, "\(sb)×\(sb) at \(b) should be in front of \(sa)×\(sa) at \(a)"); checked += 1 }
                        if aInFront { XCTAssertGreaterThan(za, zb, "\(sa)×\(sa) at \(a) should be in front of \(sb)×\(sb) at \(b)"); checked += 1 }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }

    /// The reported bug: a 2×2 placed up and to the right of the starting cottage drew on top of it.
    func testABuildingBehindTheCottageTucksBehindIt() {
        let cottage = IsoMath.zPosition(origin: Tile(c: 8, r: 9), size: 1)
        let behind = IsoMath.zPosition(origin: Tile(c: 8, r: 7), size: 2)
        XCTAssertLessThan(behind, cottage)
    }

    /// A resident standing on a tile sorts like a 1×1 building on that tile.
    func testResidentsShareTheSameScale() {
        let t = Tile(c: 7, r: 4)
        XCTAssertEqual(IsoMath.depth(at: IsoMath.center(of: t)), IsoMath.zPosition(origin: t, size: 1), accuracy: 0.0001)
    }
}
