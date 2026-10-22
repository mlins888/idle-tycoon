import XCTest
@testable import Fenlight

private func shop(_ id: String, rate: Double, cap: Double = 100, size: Int = 1, cost: Double = 10) -> BuildingDef {
    BuildingDef(id: id, name: id, blurb: "", kind: .shop, size: size, cost: cost, unlockLevel: 1,
                baseRate: rate, capSeconds: cap, xp: 1, maxLevel: 10, color: "#FFFFFF")
}

private func other(_ id: String, _ kind: BuildingKind, beds: Int = 0, unique: Bool = false) -> BuildingDef {
    BuildingDef(id: id, name: id, blurb: "", kind: kind, size: kind == .house && beds == 1 ? 1 : 2, cost: 10,
                unlockLevel: 1, baseRate: 0, capSeconds: 0, xp: 1, maxLevel: 1, color: "#FFFFFF",
                beds: beds, unique: unique)
}

private func person(_ id: String, _ arrival: ArrivalKind, rarity: Rarity = .common, level: Int = 1,
                    favorite: String = "none") -> ResidentDef {
    ResidentDef(id: id, name: id, folk: "", blurb: "", rarity: rarity, arrival: arrival,
                unlockLevel: level, favoriteShop: favorite, color: "#FFFFFF")
}

private let content = GameContent(
    buildings: [
        shop("reed_candles", rate: 1),
        shop("bakery", rate: 2, size: 2),
        other("reed_cottage", .house, beds: 1),
        other("stilt_house", .house, beds: 3),
        other("shrine", .shrine, unique: true),
        other("guild", .guild, unique: true),
    ],
    residents: [
        person("wren", .story, favorite: "reed_candles"),
        person("scholar", .story, level: 3),
        person("pip", .wanderer),
        person("marigold", .wanderer),
        person("unc", .summon, rarity: .uncommon),
        person("rare", .summon, rarity: .rare),
        person("leg", .summon, rarity: .legendary),
    ]
)

private final class TestTime {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

// Free spots on the starting land (the stall is on 11,11 and the cottage on 9,12).
private let stiltSpot = Tile(c: 13, r: 13)
private let shrineSpot = Tile(c: 8, r: 8)
private let guildSpot = Tile(c: 13, r: 8)
private let bakerySpot = Tile(c: 10, r: 14)

@MainActor
private func makeGame(_ time: TestTime, glimmer: Double = 100_000, content c: GameContent = content) -> Game {
    var state = GameState.newGame(now: time.date)
    state.glimmer = glimmer
    return Game(content: c, state: state, clock: time.clock)
}

@MainActor
final class ArrivalTests: XCTestCase {
    func testStoryResidentMovesInWhenThereIsABed() {
        let game = makeGame(TestTime())
        XCTAssertNotNil(game.resident("wren"), "the starting cottage has a bed for Wren")
        XCTAssertEqual(game.arrivalQueue.map(\.id), ["wren"])
        XCTAssertEqual(game.freeBeds, 0)
        XCTAssertNil(game.state.nextWandererAt, "no bed, so no one is on the road")
    }

    func testStoryResidentWaitsForABed() {
        let time = TestTime()
        var state = GameState.newGame(now: time.date)
        state.glimmer = 1_000
        state.buildings.removeAll { $0.defId == "reed_cottage" }
        let game = Game(content: content, state: state, clock: time.clock)

        XCTAssertNil(game.resident("wren"))
        XCTAssertEqual(game.waitingForBed.map(\.id), ["wren"])
        XCTAssertTrue(game.build("reed_cottage", at: Tile(c: 9, r: 12)))
        XCTAssertNotNil(game.resident("wren"), "joins as soon as a bed exists")
    }

    func testLockedStoryResidentWaitsForTheirLevel() {
        let game = makeGame(TestTime())
        XCTAssertTrue(game.build("stilt_house", at: stiltSpot))
        XCTAssertNil(game.resident("scholar"))
        game.debugAdd(xp: Economy.xpForLevel(3))
        game.tick()
        XCTAssertNotNil(game.resident("scholar"))
    }

    func testWanderersArriveOverTime() throws {
        let time = TestTime()
        let game = makeGame(time)
        XCTAssertTrue(game.build("stilt_house", at: stiltSpot))
        let due = try XCTUnwrap(game.state.nextWandererAt)
        let wait = due.timeIntervalSince(time.date)
        XCTAssertTrue(Economy.wandererDelay.contains(wait))

        time.advance(wait - 1)
        game.tick()
        XCTAssertEqual(game.state.residents.count, 1, "not yet")
        time.advance(1)
        game.tick()
        XCTAssertEqual(game.state.residents.count, 2)
        XCTAssertEqual(game.state.residents.last?.arrivedAt, due)
    }

    func testWanderersArriveWhileYouAreAway() {
        let time = TestTime()
        let first = makeGame(time)
        XCTAssertTrue(first.build("stilt_house", at: stiltSpot))
        var saved = first.state
        saved.savedAt = time.date

        time.advance(3 * 3600)
        let game = Game(content: content, state: saved, clock: time.clock)
        let arrivals = game.awaySummary?.arrivals.map(\.id).sorted()
        XCTAssertEqual(arrivals, ["marigold", "pip"], "both wanderers arrived while away")
        XCTAssertTrue(game.arrivalQueue.isEmpty, "the summary introduces them instead of separate cards")
        XCTAssertNil(game.state.nextWandererAt, "no wanderers left to come")
    }
}

@MainActor
final class SummonTests: XCTestCase {
    func testSummonNeedsTheShrineWispsAndABed() {
        let game = makeGame(TestTime())
        game.debugAdd(wisps: 100)
        XCTAssertFalse(game.canSummon, "no shrine")
        XCTAssertTrue(game.build("shrine", at: shrineSpot))
        XCTAssertFalse(game.canSummon, "no free bed (Wren has the cottage)")
        XCTAssertTrue(game.build("stilt_house", at: stiltSpot))
        XCTAssertTrue(game.canSummon)
    }

    func testSummonIsRepeatableFromTheSameSeed() {
        func roll() -> SummonResult? {
            let game = makeGame(TestTime())
            game.debugAdd(wisps: 100)
            game.build("shrine", at: shrineSpot)
            game.build("stilt_house", at: stiltSpot)
            return game.summon()
        }
        XCTAssertNotNil(roll())
        XCTAssertEqual(roll(), roll())
    }

    func testSummonOddsFollowRarityWeights() {
        var rng = SeededRandom(state: 42)
        var counts: [Rarity: Int] = [:]
        let n = 20_000
        for _ in 0..<n {
            counts[Residents.rollSummon(content, rng: &rng)!.rarity, default: 0] += 1
        }
        XCTAssertEqual(Double(counts[.uncommon] ?? 0) / Double(n), 0.70, accuracy: 0.02)
        XCTAssertEqual(Double(counts[.rare] ?? 0) / Double(n), 0.25, accuracy: 0.02)
        XCTAssertEqual(Double(counts[.legendary] ?? 0) / Double(n), 0.05, accuracy: 0.01)
        XCTAssertNil(counts[.common], "commons never come from summoning")
    }

    func testDuplicateSummonRefundsWisps() {
        let solo = GameContent(buildings: content.buildings,
                               residents: [person("wren", .story), person("only", .summon, rarity: .rare)])
        let game = makeGame(TestTime(), content: solo)
        game.build("shrine", at: shrineSpot)
        game.build("stilt_house", at: stiltSpot)
        game.debugAdd(wisps: 20 - game.state.wisps)

        XCTAssertEqual(game.summon(), .newResident(solo.resident("only")!))
        XCTAssertEqual(game.summon(), .duplicate(solo.resident("only")!, refund: Economy.duplicateRefund))
        XCTAssertEqual(game.state.wisps, 20 - 2 * Economy.summonCost + Economy.duplicateRefund, accuracy: 0.001)
        XCTAssertEqual(game.state.residents.count, 2)
    }
}

@MainActor
final class WorkerTests: XCTestCase {
    func testFavouriteShopGivesTheBiggerBonus() {
        let game = makeGame(TestTime())
        game.build("stilt_house", at: stiltSpot)
        game.debugWandererNow()
        game.build("bakery", at: bakerySpot)
        let stall = game.state.buildings[0]
        let bakery = game.state.buildings.first { $0.defId == "bakery" }!
        let wanderer = game.state.residents.first { $0.defId != "wren" }!.defId

        XCTAssertTrue(game.assignWorker("wren", to: stall.id))
        XCTAssertTrue(game.assignWorker(wanderer, to: bakery.id))
        XCTAssertEqual(game.rate(game.building(id: stall.id)!), 1.6, accuracy: 0.001, "favourite: +60%")
        XCTAssertEqual(game.rate(game.building(id: bakery.id)!), 2.5, accuracy: 0.001, "other: +25%")
    }

    func testOneWorkerPerSmallShop() {
        let game = makeGame(TestTime())
        game.build("stilt_house", at: stiltSpot)
        game.debugWandererNow()
        let stall = game.state.buildings[0].id
        let wanderer = game.state.residents.first { $0.defId != "wren" }!.defId
        XCTAssertTrue(game.assignWorker("wren", to: stall))
        XCTAssertFalse(game.assignWorker(wanderer, to: stall))
    }

    func testAssigningPaysOutWhatTheShopEarnedSoFar() {
        let time = TestTime()
        let game = makeGame(time, glimmer: 0)
        time.advance(10)
        XCTAssertTrue(game.assignWorker("wren", to: game.state.buildings[0].id))
        XCTAssertEqual(game.state.glimmer, 10, accuracy: 0.001, "earned at the old rate")
        XCTAssertEqual(game.pending(game.state.buildings[0]), 0)
    }

    func testMilestoneLevelsDoubleSpeed() {
        let def = shop("x", rate: 1)
        XCTAssertEqual(Economy.rate(def, level: 5), pow(1.45, 4) * 2, accuracy: 0.0001)
        XCTAssertEqual(Economy.rate(def, level: 10), pow(1.45, 9) * 4, accuracy: 0.0001)
    }
}

@MainActor
final class AutoCollectTests: XCTestCase {
    func testCharterNeedsTheGuildAndAWorker() {
        let game = makeGame(TestTime())
        let stall = game.state.buildings[0].id
        XCTAssertFalse(game.buyCharter(stall), "no guild")
        XCTAssertTrue(game.build("guild", at: guildSpot))
        XCTAssertFalse(game.buyCharter(stall), "no worker")
        game.assignWorker("wren", to: stall)
        XCTAssertTrue(game.buyCharter(stall))
        XCTAssertTrue(game.isAuto(game.building(id: stall)!))
    }

    func testKeepersPayStraightIntoGlimmer() {
        let time = TestTime()
        let game = makeGame(time)
        let stall = game.state.buildings[0].id
        game.build("guild", at: guildSpot)
        game.assignWorker("wren", to: stall)
        game.buyCharter(stall)
        let before = game.state.glimmer

        time.advance(500)   // well past the stall's normal 100-glimmer limit
        game.tick()
        XCTAssertEqual(game.state.glimmer - before, 1.6 * 500, accuracy: 0.01)
        XCTAssertEqual(game.pending(game.building(id: stall)!), 0, "nothing to tap")
        XCTAssertEqual(game.totalPending(), 0)
    }

    func testKeepersStopAtTheOfflineCap() {
        let time = TestTime()
        let game = makeGame(time)
        let stall = game.state.buildings[0].id
        game.build("guild", at: guildSpot)
        game.assignWorker("wren", to: stall)
        game.buyCharter(stall)
        let saved = game.state

        time.advance(20 * 3600)
        let back = Game(content: content, state: saved, clock: time.clock)
        XCTAssertEqual(back.awaySummary?.keepers ?? 0, 1.6 * Economy.offlineCap, accuracy: 0.01)
    }

    func testRemovingTheWorkerStopsAutoCollect() {
        let game = makeGame(TestTime())
        let stall = game.state.buildings[0].id
        game.build("guild", at: guildSpot)
        game.assignWorker("wren", to: stall)
        game.buyCharter(stall)
        game.unassignWorker("wren")
        XCTAssertFalse(game.isAuto(game.building(id: stall)!), "the charter stays, but needs a worker")
        XCTAssertTrue(game.building(id: stall)!.autoCollect)
    }
}

@MainActor
final class WispAndSaveTests: XCTestCase {
    func testLevelsAndCleansingGiveWisps() {
        let game = makeGame(TestTime())
        XCTAssertEqual(game.state.wisps, 0)
        game.debugAdd(xp: Economy.xpForLevel(3))
        XCTAssertEqual(game.state.wisps, 2 * Economy.wispsPerLevel, "levels 2 and 3")
        XCTAssertTrue(game.cleanse(Chunk(cx: 1, cy: 2)))
        XCTAssertEqual(game.state.wisps, 2 * Economy.wispsPerLevel + Economy.wispsPerCleanse)
    }

    func testVersionOneSavesStillLoad() throws {
        var old = GameState.newGame(now: Date(timeIntervalSinceReferenceDate: 500))
        old.version = 1
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["residents", "wisps", "nextWandererAt", "rngState", "rewardedLevel"] {
            json[key] = nil
        }
        var buildings = try XCTUnwrap(json["buildings"] as? [[String: Any]])
        for i in buildings.indices { buildings[i]["autoCollect"] = nil }
        json["buildings"] = buildings

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let loaded = try XCTUnwrap(SaveStore(url: url).load())
        XCTAssertEqual(loaded.version, GameState.currentVersion)
        XCTAssertTrue(loaded.residents.isEmpty)
        XCTAssertEqual(loaded.wisps, 0)
        XCTAssertFalse(loaded.buildings.contains(where: \.autoCollect))
        XCTAssertEqual(loaded.glimmer, old.glimmer)
    }
}
