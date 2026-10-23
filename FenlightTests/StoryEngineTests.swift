import XCTest
@testable import Fenlight

private func line(_ speaker: String, _ text: String) -> SceneLine { SceneLine(speaker: speaker, text: text) }

private let content = GameContent(
    buildings: [
        testShopDef("reed_candles", cost: 25),
        BuildingDef(id: "reed_cottage", kind: .house, size: 1, cost: 40, unlockLevel: 1, xp: 5, color: "#FFFFFF",
                    stages: [StageDef(name: "Cottage", blurb: "", beds: 1), StageDef(name: "House", blurb: "", beds: 2)]),
    ],
    residents: [
        ResidentDef(id: "wren", name: "Wren", folk: "", blurb: "", rarity: .common, arrival: .story,
                    unlockLevel: 1, favoriteShop: "reed_candles", color: "#FFFFFF"),
        ResidentDef(id: "pip", name: "Pip", folk: "", blurb: "", rarity: .common, arrival: .wanderer,
                    unlockLevel: 1, favoriteShop: "reed_candles", color: "#FFFFFF"),
    ],
    quests: [
        QuestDef(id: "q1", chapter: 1, giver: "wren", title: "One", text: "", doneText: "",
                 objective: .collect(shop: "reed_candles", amount: 10), reward: Reward()),
        QuestDef(id: "q_scene", chapter: 1, giver: "wren", title: "From a scene", text: "", doneText: "",
                 objective: .level(99), reward: Reward(), prerequisites: [.flag("never")]),
    ],
    scenes: [
        SceneDef(id: "opening", trigger: .gameStart, lines: [line("narrator", "Start.")]),
        SceneDef(id: "chapter1", trigger: .chapterStart(1), lines: [line("narrator", "Chapter one.")]),
        SceneDef(id: "q1_start", trigger: .questStarted("q1"), lines: [line("wren", "Do this.")]),
        SceneDef(id: "q1_done", trigger: .questCompleted("q1"), lines: [line("wren", "Done.")],
                 effects: [.setFlag("q1_thanked")]),
        SceneDef(id: "pip_arrives", trigger: .arrival("pip"), lines: [line("pip", "Hello.")]),
        SceneDef(id: "gated", trigger: .questCompleted("q1"), requires: [.flag("door_open")],
                 lines: [line("narrator", "Only if the door is open.")]),
        SceneDef(id: "choice", trigger: .debug, lines: [line("player", "Which?")], choices: [
            SceneChoice(text: "Raise", effects: [.addValue("courtStanding", 2), .setFlag("raised")]),
            SceneChoice(text: "Start a quest", effects: [.startQuest("q_scene"), .setChapter(2)]),
        ]),
        SceneDef(id: "chapter2", trigger: .chapterStart(2), lines: [line("narrator", "Chapter two.")]),
    ],
    characters: [CharacterDef(id: "narrator", name: "", color: "#FFFFFF")]
)

private final class TestTime {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

@MainActor
private func makeGame(_ time: TestTime = TestTime()) -> Game {
    var state = GameState.newGame(now: time.date)
    useRoomyTestLayout(&state)
    return Game(content: content, state: state, clock: time.clock)
}

/// Plays every queued scene to the end without choosing anything.
@MainActor
private func playAll(_ game: Game) {
    while let scene = game.currentScene { game.finishScene(scene.id) }
}

@MainActor
final class StoryTriggerTests: XCTestCase {
    func testANewGameQueuesItsOpeningScenes() {
        let game = makeGame()
        XCTAssertEqual(Array(game.state.pendingScenes.prefix(2)), ["opening", "chapter1"])
        XCTAssertEqual(game.currentScene?.id, "opening")
    }

    func testOpeningScenesAreQueuedOnlyOnce() {
        let game = makeGame()
        playAll(game)
        let saved = game.state
        let again = Game(content: content, state: saved)
        XCTAssertFalse(again.state.pendingScenes.contains("opening"))
    }

    func testQuestStartAndCompletionTriggerScenes() {
        let time = TestTime()
        let game = makeGame(time)
        XCTAssertTrue(game.state.pendingScenes.contains("q1_start"), "q1 started at game start (Wren lives here)")
        playAll(game)
        time.advance(10); game.collect(1)
        XCTAssertTrue(game.claimQuest("q1"))
        XCTAssertEqual(game.currentScene?.id, "q1_done")
        XCTAssertFalse(game.state.pendingScenes.contains("gated"), "requirement not met")
    }

    func testAnArrivalTriggersItsScene() {
        let game = makeGame()
        playAll(game)
        game.build("reed_cottage", at: Tile(c: 13, r: 13))
        game.debugWandererNow()
        XCTAssertNotNil(game.resident("pip"))
        XCTAssertTrue(game.state.pendingScenes.contains("pip_arrives"))
    }

    func testAScenePlaysOnlyOnce() {
        let game = makeGame()
        playAll(game)
        XCTAssertTrue(game.state.seenScenes.contains("opening"))
        game.fire(.gameStart)
        XCTAssertNil(game.currentScene)
    }

    func testDebugScenesOnlyPlayFromTheDebugMenu() {
        let game = makeGame()
        XCTAssertFalse(game.state.pendingScenes.contains("choice"))
        game.debugPlayScene("choice")
        XCTAssertEqual(game.currentScene?.id, "choice")
    }

    func testPendingScenesSurviveARestart() {
        let game = makeGame()
        let saved = game.state
        let back = Game(content: content, state: saved)
        XCTAssertEqual(back.currentScene?.id, "opening")
    }
}

@MainActor
final class StoryEffectTests: XCTestCase {
    func testSceneEffectsApplyWhenItEnds() {
        let time = TestTime()
        let game = makeGame(time)
        playAll(game)
        time.advance(10); game.collect(1)
        game.claimQuest("q1")
        game.finishScene("q1_done")
        XCTAssertTrue(game.state.flags.contains("q1_thanked"))
    }

    func testAChoiceAppliesOnlyItsOwnEffects() {
        let game = makeGame()
        playAll(game)
        game.debugPlayScene("choice")
        game.finishScene("choice", choice: 0)
        XCTAssertEqual(game.state.storyValues["courtStanding"], 2)
        XCTAssertTrue(game.state.flags.contains("raised"))
        XCTAssertEqual(game.state.chapter, 1)
        XCTAssertNil(game.state.activeQuests["q_scene"])
    }

    func testAChoiceCanStartAQuestAndAChapter() {
        let game = makeGame()
        playAll(game)
        game.debugPlayScene("choice")
        game.finishScene("choice", choice: 1)
        XCTAssertNotNil(game.state.activeQuests["q_scene"], "started even though its prerequisites aren't met")
        XCTAssertEqual(game.state.chapter, 2)
        XCTAssertEqual(game.currentScene?.id, "chapter2", "the new chapter's scene is queued")
    }

    func testStoryRequirements() {
        var state = GameState.newGame(now: Date())
        state.flags = ["a"]
        state.storyValues = ["sealStrain": 3]
        state.chapter = 2
        state.seenScenes = ["s"]
        let checks: [(Requirement, Bool)] = [
            (.flag("a"), true), (.flag("b"), false),
            (.notFlag("a"), false), (.notFlag("b"), true),
            (.valueAtLeast("sealStrain", 3), true), (.valueAtLeast("sealStrain", 4), false),
            (.valueAtMost("sealStrain", 3), true), (.valueAtMost("sealStrain", 2), false),
            (.valueAtLeast("kindling", 0), true),
            (.chapter(2), true), (.chapter(3), false),
            (.sceneSeen("s"), true), (.sceneSeen("t"), false),
        ]
        for (r, expected) in checks {
            XCTAssertEqual(Requirements.isMet(r, state, content), expected, "\(r)")
        }
    }

    func testResettingTheStoryKeepsTheTown() {
        let game = makeGame()
        playAll(game)
        game.debugToggle(flag: "x")
        game.debugAdd(storyValue: "sealStrain", 5)
        let buildings = game.state.buildings
        game.debugResetStory()
        XCTAssertTrue(game.state.flags.isEmpty)
        XCTAssertTrue(game.state.storyValues.isEmpty)
        XCTAssertEqual(game.state.buildings, buildings)
        XCTAssertEqual(game.currentScene?.id, "opening", "the story starts over")
    }
}

final class TemplatingTests: XCTestCase {
    private func render(_ text: String, _ pronouns: Pronouns, name: String = "Ash") -> String {
        Story.render(text, player: PlayerProfile(name: name, pronouns: pronouns))
    }

    func testTheyThem() {
        XCTAssertEqual(render("{They} {are} {name}. {they} walk{s} home with {their} lamp; it's {theirs}.", .they),
                       "They are Ash. they walk home with their lamp; it's theirs.")
    }

    func testSheHer() {
        XCTAssertEqual(render("{They} {are} {name}. {They} walk{s}. I saw {them}. {They} {were} {themself}. {They} {have} it.", .she),
                       "She is Ash. She walks. I saw her. She was herself. She has it.")
    }

    func testHeHim() {
        XCTAssertEqual(render("{Their} lamp, {his}, {theirs}.", .he), "His lamp, {his}, his.", "unknown tokens stay visible")
    }

    func testCustomPronouns() {
        let xe = Pronouns(subject: "xe", object: "xem", possessive: "xyr", possessivePronoun: "xyrs",
                          reflexive: "xemself", pluralVerbs: false)
        XCTAssertEqual(render("{They} {are} here and {they} know{s} {themself}.", xe), "Xe is here and xe knows xemself.")
    }

    func testBracesWithoutTokensAreLeftAlone() {
        XCTAssertEqual(render("A lone { brace", .they), "A lone { brace")
        XCTAssertEqual(render("No tokens at all.", .they), "No tokens at all.")
    }
}

final class StorySaveTests: XCTestCase {
    func testVersionFiveSavesLoadWithStoryDefaults() throws {
        var old = GameState.newGame(now: Date(timeIntervalSinceReferenceDate: 500))
        old.version = 5
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["chapter", "flags", "storyValues", "seenScenes", "pendingScenes", "fragments", "player", "storyStarted"] {
            json[key] = nil
        }
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.chapter, 1)
        XCTAssertTrue(loaded.flags.isEmpty)
        XCTAssertEqual(loaded.player, PlayerProfile())
        XCTAssertFalse(loaded.storyStarted)
    }
}

final class ShippedStoryContentTests: XCTestCase {
    func testEveryScenePointsAtThingsThatExist() {
        let shipped = GameContent.load(bundle: Bundle(for: Game.self))
        let residents = Set(shipped.residents.map(\.id))
        let characters = Set(shipped.characters.map(\.id))
        let quests = Set(shipped.quests.map(\.id))
        XCTAssertEqual(Set(shipped.scenes.map(\.id)).count, shipped.scenes.count, "scene ids are unique")

        for scene in shipped.scenes {
            XCTAssertFalse(scene.lines.isEmpty, "\(scene.id) has lines")
            for l in scene.lines {
                XCTAssertTrue(l.speaker == "player" || residents.contains(l.speaker) || characters.contains(l.speaker),
                              "\(scene.id): unknown speaker \(l.speaker)")
                for token in tokens(in: l.text) {
                    XCTAssertTrue(Story.knownTokens.contains(token.lowercased()), "\(scene.id): unknown token {\(token)}")
                }
            }
            switch scene.trigger {
            case .questStarted(let q), .questCompleted(let q):
                XCTAssertTrue(quests.contains(q), "\(scene.id): unknown quest \(q)")
            case .arrival(let r):
                XCTAssertTrue(residents.contains(r), "\(scene.id): unknown resident \(r)")
            case .gameStart, .chapterStart, .debug:
                break
            }
            for e in scene.effects + scene.choices.flatMap(\.effects) {
                if case .startQuest(let q) = e { XCTAssertTrue(quests.contains(q), "\(scene.id): unknown quest \(q)") }
            }
        }
    }

    private func tokens(in text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }
}
