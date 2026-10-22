import XCTest
@testable import Fenlight

private let content = GameContent(
    buildings: [
        BuildingDef(id: "reed_candles", kind: .shop, size: 1, cost: 25, unlockLevel: 1, xp: 5, color: "#FFFFFF", stages: [
            StageDef(name: "Stall", blurb: "", sells: ["Rushlights"], rate: 1, capSeconds: 100),
            StageDef(name: "Chandler", blurb: "", sells: ["Rushlights", "Tapers"], rate: 3, capSeconds: 100,
                     cost: 50, buildSeconds: 600, requirements: [.level(2)]),
            StageDef(name: "Chandlery", blurb: "", rate: 9, capSeconds: 100,
                     cost: 100, buildSeconds: 0, requirements: [.quest("first_light")]),
        ]),
        BuildingDef(id: "bakery", kind: .shop, size: 2, cost: 100, unlockLevel: 1, xp: 5, color: "#FFFFFF", stages: [
            StageDef(name: "Oven", blurb: "", rate: 2, capSeconds: 50),
            StageDef(name: "Bakery", blurb: "", rate: 6, capSeconds: 50, cost: 10, buildSeconds: 60,
                     requirements: [.building("reed_candles", stage: 2), .resident("pip"), .restoration(0.2)]),
        ]),
        BuildingDef(id: "reed_cottage", kind: .house, size: 1, cost: 40, unlockLevel: 1, xp: 5, color: "#FFFFFF", stages: [
            StageDef(name: "Cottage", blurb: "", beds: 1),
            StageDef(name: "House", blurb: "", beds: 2, cost: 10, buildSeconds: 60),
        ]),
    ],
    residents: [
        ResidentDef(id: "wren", name: "Wren", folk: "", blurb: "", rarity: .common, arrival: .story,
                    unlockLevel: 1, favoriteShop: "reed_candles", color: "#FFFFFF"),
        ResidentDef(id: "pip", name: "Pip", folk: "", blurb: "", rarity: .common, arrival: .wanderer,
                    unlockLevel: 1, favoriteShop: "bakery", color: "#FFFFFF"),
    ],
    quests: [
        QuestDef(id: "first_light", chapter: 1, giver: "wren", title: "First Light", text: "", doneText: "",
                 objective: .collect(shop: "reed_candles", amount: 20), reward: Reward(glimmer: 5, wisps: 1, xp: 10)),
        QuestDef(id: "murk", chapter: 1, giver: "wren", title: "Murk", text: "", doneText: "",
                 objective: .cleanse(count: 1), reward: Reward(wisps: 3), prerequisites: [.quest("first_light")]),
        QuestDef(id: "cottages", chapter: 1, giver: "wren", title: "Cottages", text: "", doneText: "",
                 objective: .build("reed_cottage", count: 2), reward: Reward(glimmer: 1)),
        QuestDef(id: "pips_quest", chapter: 1, giver: "pip", title: "Pip's", text: "", doneText: "",
                 objective: .residents(count: 3), reward: Reward(glimmer: 1)),
        QuestDef(id: "level_up", chapter: 1, giver: "wren", title: "Grow", text: "", doneText: "",
                 objective: .level(3), reward: Reward(glimmer: 1)),
    ]
)

private final class TestTime {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

@MainActor
private func makeGame(_ time: TestTime, glimmer: Double = 10_000) -> Game {
    var state = GameState.newGame(now: time.date)
    state.glimmer = glimmer
    return Game(content: content, state: state, clock: time.clock)
}

/// The starting Rushlight Stall.
private let stall = 1

@MainActor
final class StageTests: XCTestCase {
    func testRateAndCapacityComeFromTheStage() {
        let def = content.building("reed_candles")!
        XCTAssertEqual(Economy.rate(def, stage: 1), 1)
        XCTAssertEqual(Economy.rate(def, stage: 2), 3)
        XCTAssertEqual(Economy.capacity(rate: 3, def.stage(2)), 300)
    }

    func testRenovationWaitsForRequirements() {
        let game = makeGame(TestTime())
        let b = game.building(id: stall)!
        XCTAssertEqual(game.unmetRequirements(b), [.level(2)])
        XCTAssertFalse(game.startRenovation(stall))
        game.debugAdd(xp: Economy.xpForLevel(2))
        XCTAssertTrue(game.unmetRequirements(game.building(id: stall)!).isEmpty)
        XCTAssertTrue(game.startRenovation(stall))
    }

    func testEveryRequirementTypeIsChecked() {
        let time = TestTime()
        let game = makeGame(time)
        let state = game.state
        XCTAssertFalse(Requirements.isMet(.building("reed_candles", stage: 2), state, content))
        XCTAssertTrue(Requirements.isMet(.building("reed_candles", stage: 1), state, content))
        XCTAssertTrue(Requirements.isMet(.resident("wren"), state, content))
        XCTAssertFalse(Requirements.isMet(.resident("pip"), state, content))
        XCTAssertFalse(Requirements.isMet(.quest("first_light"), state, content))
        XCTAssertTrue(Requirements.isMet(.restoration(0.1), state, content), "4 of 36 chunks is 11%")
        XCTAssertFalse(Requirements.isMet(.restoration(0.2), state, content))
        XCTAssertTrue(Requirements.isMet(.level(1), state, content))
    }

    func testRenovationPaysOutClosesThenReopens() {
        let time = TestTime()
        let game = makeGame(time, glimmer: 100)
        game.debugAdd(xp: Economy.xpForLevel(2))
        time.advance(30)

        XCTAssertTrue(game.startRenovation(stall))
        XCTAssertEqual(game.state.glimmer, 100 + 30 - 50, accuracy: 0.001, "paid out 30, then the 50 cost")
        XCTAssertTrue(game.building(id: stall)!.isRenovating)

        time.advance(300)
        game.tick()
        XCTAssertEqual(game.pending(game.building(id: stall)!), 0, "earns nothing while closed")
        XCTAssertEqual(game.building(id: stall)!.stage, 1)

        time.advance(300)
        game.tick()
        let b = game.building(id: stall)!
        XCTAssertEqual(b.stage, 2)
        XCTAssertFalse(b.isRenovating)
        XCTAssertEqual(game.name(b), "Chandler")
        XCTAssertTrue(game.announcements.contains { $0.id == "transformed-reed_candles-2" })
        time.advance(10)
        XCTAssertEqual(game.pending(game.building(id: stall)!), 30, accuracy: 0.001, "stage 2 rate")
    }

    func testRenovationFinishesWhileAway() {
        let time = TestTime()
        let game = makeGame(time)
        game.debugAdd(xp: Economy.xpForLevel(2))
        game.startRenovation(stall)
        let saved = game.state

        time.advance(3600)
        let back = Game(content: content, state: saved, clock: time.clock)
        let b = back.building(id: stall)!
        XCTAssertEqual(b.stage, 2)
        XCTAssertEqual(back.pending(b), 300, accuracy: 0.001, "earning (and full) since it reopened")
    }

    func testFinishNowCostsWisps() {
        let time = TestTime()
        let game = makeGame(time)
        game.debugAdd(xp: Economy.xpForLevel(2))
        game.startRenovation(stall)
        let cost = game.finishNowCost(game.building(id: stall)!)!
        XCTAssertEqual(cost, 1, "10 minutes left")

        let wisps = game.state.wisps
        XCTAssertTrue(game.finishRenovationNow(stall))
        XCTAssertEqual(game.state.wisps, wisps - cost)
        XCTAssertEqual(game.building(id: stall)!.stage, 2)
    }

    func testWorkersStayThroughRenovation() {
        let time = TestTime()
        let game = makeGame(time)
        game.assignWorker("wren", to: stall)
        game.debugAdd(xp: Economy.xpForLevel(2))
        game.startRenovation(stall)
        time.advance(600)
        game.tick()
        XCTAssertEqual(game.workers(at: stall).map(\.id), ["wren"])
        XCTAssertEqual(game.rate(game.building(id: stall)!), 3 * 1.6, accuracy: 0.001)
    }

    func testInstantStagesCompleteRightAway() {
        let time = TestTime()
        let game = makeGame(time)
        game.debugAdd(xp: Economy.xpForLevel(2))
        game.finishRenovationNow(stall)
        game.startRenovation(stall)
        game.finishRenovationNow(stall)
        XCTAssertEqual(game.building(id: stall)!.stage, 2)
        XCTAssertNotNil(game.nextStage(game.building(id: stall)!))
        XCTAssertFalse(game.startRenovation(stall), "stage 3 needs the first_light quest")
    }

    func testHouseStagesAddBeds() {
        let time = TestTime()
        let game = makeGame(time)
        XCTAssertEqual(game.totalBeds, 1)
        XCTAssertTrue(game.startRenovation(2))
        time.advance(60)
        game.tick()
        XCTAssertEqual(game.totalBeds, 2)
    }

    func testLastStageHasNoNext() {
        var state = GameState.newGame(now: Date())
        state.buildings[0].stage = 3
        let game = Game(content: content, state: state)
        XCTAssertNil(game.nextStage(game.building(id: stall)!))
    }

    func testStagesAboveTheMaximumAreClampedOnLoad() {
        var state = GameState.newGame(now: Date())
        state.buildings[1].stage = 9
        let game = Game(content: content, state: state)
        XCTAssertEqual(game.building(id: 2)!.stage, 2)
    }
}

@MainActor
final class QuestTests: XCTestCase {
    func testQuestsStartWhenTheirGiverAndPrerequisitesAreThere() {
        let game = makeGame(TestTime())
        XCTAssertEqual(Set(game.activeQuests.map(\.id)), ["first_light", "cottages", "level_up"],
                       "murk needs first_light; Pip doesn't live here yet")
    }

    func testCollectProgressCountsFromWhenTheQuestStarted() {
        let time = TestTime()
        let game = makeGame(time)
        let q = content.quest("first_light")!
        XCTAssertEqual(game.progress(q).current, 0)
        time.advance(15)
        game.collect(stall)
        XCTAssertEqual(game.progress(q).current, 15, accuracy: 0.001)
        XCTAssertFalse(game.isReady(q))
        time.advance(10)
        game.collectAll()
        XCTAssertTrue(game.isReady(q))
        XCTAssertEqual(game.progress(q).current, 20, "capped at the target")
    }

    func testClaimingGivesTheRewardOnceAndUnlocksFollowUps() {
        let time = TestTime()
        let game = makeGame(time, glimmer: 0)
        time.advance(20)
        game.collect(stall)
        game.tick()
        XCTAssertTrue(game.announcements.contains { $0.id == "quest-first_light" })

        XCTAssertTrue(game.claimQuest("first_light"))
        XCTAssertEqual(game.state.glimmer, 20 + 5, accuracy: 0.001)
        XCTAssertEqual(game.state.wisps, 1)
        XCTAssertTrue(game.state.completedQuests.contains("first_light"))
        XCTAssertFalse(game.claimQuest("first_light"), "only once")
        XCTAssertTrue(game.activeQuests.contains { $0.id == "murk" }, "follow-up started")
    }

    func testCleanseProgressIgnoresEarlierCleansing() {
        let time = TestTime()
        var state = GameState.newGame(now: time.date)
        state.glimmer = 100_000
        state.stats.chunksCleansed = 5
        state.completedQuests = ["first_light"]
        let game = Game(content: content, state: state, clock: time.clock)
        let q = content.quest("murk")!
        XCTAssertEqual(game.progress(q).current, 0)
        XCTAssertTrue(game.cleanse(Chunk(cx: 1, cy: 2)))
        XCTAssertTrue(game.isReady(q))
    }

    func testAtMostThreeQuestsAtOnce() {
        let time = TestTime()
        let game = makeGame(time)
        game.build("reed_cottage", at: Tile(c: 13, r: 13))
        game.debugWandererNow()   // Pip arrives, so Pip's quest becomes available
        XCTAssertNotNil(game.resident("pip"))
        XCTAssertEqual(game.activeQuests.count, Quests.maxActive)
        XCTAssertFalse(game.activeQuests.contains { $0.id == "pips_quest" }, "waits for a free slot")
    }

    func testBuildAndLevelObjectives() {
        let game = makeGame(TestTime())
        XCTAssertFalse(game.isReady(content.quest("cottages")!))
        game.build("reed_cottage", at: Tile(c: 13, r: 13))
        XCTAssertTrue(game.isReady(content.quest("cottages")!))
        game.debugAdd(xp: Economy.xpForLevel(3))
        XCTAssertTrue(game.isReady(content.quest("level_up")!))
    }

    func testShippedContentIsConsistent() {
        let shipped = GameContent.load(bundle: Bundle(for: Game.self))
        let buildingIds = Set(shipped.buildings.map(\.id))
        let residentIds = Set(shipped.residents.map(\.id))
        let questIds = Set(shipped.quests.map(\.id))

        func check(_ r: Requirement, _ owner: String) {
            switch r {
            case .building(let id, let stage):
                XCTAssertTrue(buildingIds.contains(id), "\(owner): unknown building \(id)")
                XCTAssertLessThanOrEqual(stage, shipped.building(id)?.stages.count ?? 0, "\(owner): \(id) has no stage \(stage)")
            case .resident(let id): XCTAssertTrue(residentIds.contains(id), "\(owner): unknown resident \(id)")
            case .quest(let id): XCTAssertTrue(questIds.contains(id), "\(owner): unknown quest \(id)")
            case .level, .restoration: break
            }
        }
        for b in shipped.buildings {
            for s in b.stages { s.requirements.forEach { check($0, b.id) } }
        }
        for r in shipped.residents {
            XCTAssertTrue(buildingIds.contains(r.favoriteShop), "\(r.id): unknown favourite shop \(r.favoriteShop)")
        }
        for q in shipped.quests {
            XCTAssertTrue(residentIds.contains(q.giver), "\(q.id): unknown giver \(q.giver)")
            q.prerequisites.forEach { check($0, q.id) }
            switch q.objective {
            case .collect(let shop, _):
                if let shop { XCTAssertTrue(buildingIds.contains(shop), "\(q.id): unknown shop \(shop)") }
            case .build(let id, _), .stage(let id, _):
                XCTAssertTrue(buildingIds.contains(id), "\(q.id): unknown building \(id)")
            default: break
            }
        }
    }
}
