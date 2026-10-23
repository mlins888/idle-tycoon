import XCTest

/// Launches the real app and taps through the main screens, failing if anything crashes or hangs.
/// Each run starts from a fresh town (`-uiTesting`), so it never touches a real save.
final class FenlightUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        dismissCards()
    }

    /// Taps through any popup cards (new resident, festival starting, quest finished...).
    private func dismissCards() {
        let labels = ["Welcome to Fenlight", "Let's celebrate", "Got it", "Wonderful", "Lovely", "Back to town", "Later"]
        for _ in 0..<6 {
            guard let button = labels.lazy.map({ self.app.buttons[$0] }).first(where: { $0.waitForExistence(timeout: 1) }) else { return }
            button.tap()
        }
    }

    /// Closes a half-height sheet by tapping the map above it.
    private func closeSheet() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
    }

    private func button(startingWith label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    func testBuildMenuTabs() {
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 5))
        app.buttons["Build"].tap()
        for tab in ["Shops", "Homes", "Decor", "Special"] {
            XCTAssertTrue(app.buttons[tab].waitForExistence(timeout: 3), "\(tab) tab")
            app.buttons[tab].tap()
        }
        XCTAssertTrue(app.staticTexts["Wisp Shrine"].waitForExistence(timeout: 3), "Special tab shows the shrine")
        app.buttons["Shops"].tap()
        XCTAssertTrue(app.staticTexts["Mossbread Oven"].waitForExistence(timeout: 3))
        closeSheet()
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testTownsfolkAndRegistry() {
        XCTAssertTrue(app.buttons["Townsfolk"].waitForExistence(timeout: 5))
        app.buttons["Townsfolk"].tap()
        XCTAssertTrue(app.buttons["Registry"].waitForExistence(timeout: 3))
        app.buttons["Registry"].tap()
        let found = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Found'")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 3), "registry opened")
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["In town"].tap()
        closeSheet()
    }

    func testQuestLogWispInfoAndFestival() {
        let quests = button(startingWith: "Quests")
        XCTAssertTrue(quests.waitForExistence(timeout: 5))
        quests.tap()
        XCTAssertTrue(app.staticTexts["The First Light"].waitForExistence(timeout: 3), "Wren's first quest is active")
        closeSheet()

        let wisps = button(startingWith: "0 wisps")
        XCTAssertTrue(wisps.waitForExistence(timeout: 3))
        wisps.tap()
        XCTAssertTrue(app.staticTexts["WHERE THEY COME FROM"].waitForExistence(timeout: 3))
        closeSheet()

        // The festival banner only shows during a festival.
        let banner = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Show rewards'")).firstMatch
        if banner.waitForExistence(timeout: 2) {
            banner.tap()
            sleep(1)
            closeSheet()
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testPlayingAStorySceneAndMakingAChoice() {
        let debug = app.buttons["Debug menu"]
        XCTAssertTrue(debug.waitForExistence(timeout: 5))
        debug.tap()

        let play = app.buttons["Play debug_engine_test"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        play.tap()

        let line = app.buttons["sceneLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the scene player opened")
        XCTAssertTrue(line.label.contains("test of the scene engine"))
        line.tap()
        XCTAssertTrue(line.label.contains("Surfaced"), "the player's default name was filled in")
        line.tap()
        line.tap()

        let choice = app.buttons["Set the test flag"]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
        XCTAssertFalse(app.buttons["sceneLine"].waitForExistence(timeout: 2), "the scene closed")

        debug.tap()
        let flag = app.switches["engine_test_choice"]
        XCTAssertTrue(flag.waitForExistence(timeout: 3))
        XCTAssertEqual(flag.value as? String, "1", "the choice set the flag")
    }
}
