import XCTest
@testable import Fenlight

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

private let autumn = EventDef(
    id: "autumn", name: "Autumn", blurb: "", start: MonthDay(month: 10, day: 15), end: MonthDay(month: 11, day: 5),
    token: "acorn", tokens: "acorns", color: "#FFFFFF",
    milestones: [
        Milestone(tokens: 2, reward: EventReward(wisps: 5)),
        Milestone(tokens: 4, reward: EventReward(decoration: "gourd")),
        Milestone(tokens: 6, reward: EventReward(resident: "hob")),
    ])

private let winter = EventDef(
    id: "winter", name: "Winter", blurb: "", start: MonthDay(month: 12, day: 15), end: MonthDay(month: 1, day: 5),
    token: "spark", tokens: "sparks", color: "#FFFFFF", milestones: [])

private let content = GameContent(
    buildings: [
        testShopDef("reed_candles", cost: 25, cycle: 300, payout: 5),
        BuildingDef(id: "reed_cottage", kind: .house, size: 1, cost: 40, unlockLevel: 1, xp: 5, color: "#FFFFFF",
                    stages: [StageDef(name: "Cottage", blurb: "", beds: 1)]),
        BuildingDef(id: "gourd", kind: .decoration, size: 1, cost: 10, unlockLevel: 1, xp: 1, color: "#FFFFFF",
                    stages: [StageDef(name: "Gourd", blurb: "")], aura: Aura(radius: 1, bonus: 0.1), eventOnly: true),
    ],
    residents: [
        ResidentDef(id: "hob", name: "Hob", folk: "", blurb: "", rarity: .rare, arrival: .event,
                    unlockLevel: 1, favoriteShop: "reed_candles", color: "#FFFFFF"),
    ],
    events: [autumn, winter]
)

private final class TestTime {
    var date: Date
    init(_ d: Date) { date = d }
    lazy var clock = GameClock { self.date }
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

/// The starting Rushlight Stall (a 5-minute run, so each collect earns 1 token).
private let stall = 1

final class EventCalendarTests: XCTestCase {
    func testFestivalIsActiveOnlyInsideItsDates() {
        XCTAssertEqual(EventCalendar.active([autumn], at: date(2026, 10, 22), calendar: utc)?.0.id, "autumn")
        XCTAssertEqual(EventCalendar.active([autumn], at: date(2026, 10, 15, hour: 0), calendar: utc)?.0.id, "autumn", "first day")
        XCTAssertEqual(EventCalendar.active([autumn], at: date(2026, 11, 5, hour: 23), calendar: utc)?.0.id, "autumn", "last day")
        XCTAssertNil(EventCalendar.active([autumn], at: date(2026, 11, 6, hour: 0), calendar: utc))
        XCTAssertNil(EventCalendar.active([autumn], at: date(2026, 10, 14), calendar: utc))
    }

    func testFestivalsCanWrapPastNewYear() throws {
        let (_, w) = try XCTUnwrap(EventCalendar.active([winter], at: date(2027, 1, 3), calendar: utc))
        XCTAssertEqual(w.year, 2026, "January belongs to the run that started in December")
        XCTAssertNotNil(EventCalendar.active([winter], at: date(2026, 12, 31), calendar: utc))
        XCTAssertNil(EventCalendar.active([winter], at: date(2027, 1, 7), calendar: utc))
    }

    func testNextFestival() throws {
        let (e, w) = try XCTUnwrap(EventCalendar.next([autumn, winter], after: date(2026, 11, 20), calendar: utc))
        XCTAssertEqual(e.id, "winter")
        XCTAssertEqual(w.start, date(2026, 12, 15, hour: 0))
        let (e2, w2) = try XCTUnwrap(EventCalendar.next([autumn], after: date(2026, 11, 20), calendar: utc))
        XCTAssertEqual(e2.id, "autumn")
        XCTAssertEqual(w2.year, 2027, "this year's has passed")
    }
}

@MainActor
final class EventProgressTests: XCTestCase {
    private func makeGame(_ time: TestTime) -> Game {
        var state = GameState.newGame(now: time.date)
        state.glimmer = 10_000
        useRoomyTestLayout(&state)
        return Game(content: content, state: state, clock: time.clock)
    }

    // These use the device's calendar, so test dates sit safely inside or outside the windows.

    func testAFestivalStartingIsAnnouncedOnce() {
        let time = TestTime(date(2026, 10, 22))
        let game = makeGame(time)
        XCTAssertEqual(game.activeEvent?.id, "autumn")
        XCTAssertEqual(game.announcements.filter { $0.id == "event-autumn" }.count, 1)
        game.tick()
        XCTAssertEqual(game.announcements.filter { $0.id == "event-autumn" }.count, 1)
    }

    func testTokensComeFromProductionCollected() {
        let time = TestTime(date(2026, 10, 22))
        let game = makeGame(time)
        time.advance(100)
        game.collect(stall)
        XCTAssertEqual(game.eventProgress(autumn).tokens, 0, "not ready, nothing collected")
        time.advance(200)
        game.collect(stall)
        XCTAssertEqual(game.eventProgress(autumn).tokens, 1, accuracy: 0.0001, "5 minutes of production")
        time.advance(300)
        game.collectAll()
        XCTAssertEqual(game.eventProgress(autumn).tokens, 2, accuracy: 0.0001)
    }

    func testNoTokensOutsideAFestival() {
        let time = TestTime(date(2026, 8, 1))
        let game = makeGame(time)
        XCTAssertNil(game.activeEvent)
        time.advance(300)
        game.collect(stall)
        XCTAssertTrue(game.state.eventProgress.isEmpty)
    }

    func testMilestonesGiveTheirRewardsOnce() {
        let time = TestTime(date(2026, 10, 22))
        let game = makeGame(time)
        let wisps = game.state.wisps
        XCTAssertFalse(game.isUnlocked(content.building("gourd")!), "festival decorations start locked")

        game.debugAdd(eventTokens: 4)
        XCTAssertEqual(game.eventProgress(autumn).reached, 2)
        XCTAssertEqual(game.state.wisps, wisps + 5)
        XCTAssertTrue(game.isUnlocked(content.building("gourd")!))
        XCTAssertTrue(game.announcements.contains { $0.id == "event-autumn-1" })

        game.tick()
        XCTAssertEqual(game.state.wisps, wisps + 5, "not given twice")
    }

    func testFestivalResidentMovesInWhenThereIsABed() {
        let time = TestTime(date(2026, 10, 22))
        var state = GameState.newGame(now: time.date)
        state.glimmer = 10_000
        useRoomyTestLayout(&state)
        state.buildings.removeAll { $0.defId == "reed_cottage" }
        let game = Game(content: content, state: state, clock: time.clock)

        game.debugAdd(eventTokens: 6)
        XCTAssertTrue(game.state.invitedResidents.contains("hob"))
        XCTAssertNil(game.resident("hob"), "no bed yet")
        XCTAssertEqual(game.waitingForBed.map(\.id), ["hob"])
        game.build("reed_cottage", at: Tile(c: 9, r: 12))
        XCTAssertNotNil(game.resident("hob"))
    }

    func testProgressStartsOverNextYear() {
        let time = TestTime(date(2026, 10, 22))
        let game = makeGame(time)
        game.debugAdd(eventTokens: 4)
        XCTAssertEqual(game.eventProgress(autumn).tokens, 4)

        time.date = date(2027, 10, 20)
        game.tick()
        XCTAssertEqual(game.eventProgress(autumn).tokens, 0)
        XCTAssertEqual(game.eventProgress(autumn).reached, 0)
        XCTAssertTrue(game.isUnlocked(content.building("gourd")!), "unlocked decorations stay unlocked")
    }

    func testJumpingToTheNextFestival() {
        let time = TestTime(date(2026, 8, 1))
        let game = makeGame(time)
        game.debugJumpToNextEvent()
        XCTAssertEqual(game.activeEvent?.id, "autumn")
    }

    func testVersionThreeSavesLoadWithoutFestivalProgress() throws {
        var old = GameState.newGame(now: Date(timeIntervalSinceReferenceDate: 500))
        old.version = 3
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["eventProgress", "unlockedDecorations", "invitedResidents"] { json[key] = nil }
        let data = try JSONSerialization.data(withJSONObject: json)
        let loaded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertTrue(loaded.eventProgress.isEmpty)
        XCTAssertTrue(loaded.unlockedDecorations.isEmpty)
        XCTAssertTrue(loaded.invitedResidents.isEmpty)
    }

    func testShippedFestivalsAreConsistent() {
        let shipped = GameContent.load(bundle: Bundle(for: Game.self))
        XCTAssertFalse(shipped.events.isEmpty)
        for e in shipped.events {
            XCTAssertEqual(e.milestones.map(\.tokens), e.milestones.map(\.tokens).sorted(), "\(e.id): milestones in order")
            for m in e.milestones {
                if let d = m.reward.decoration {
                    XCTAssertEqual(shipped.building(d)?.eventOnly, true, "\(e.id): \(d) should be an eventOnly decoration")
                }
                if let r = m.reward.resident {
                    XCTAssertEqual(shipped.resident(r)?.arrival, .event, "\(e.id): \(r) should arrive via an event")
                }
            }
        }
        // No two festivals overlap in a year.
        let year = 2026
        let windows = shipped.events.map { EventCalendar.window($0, startingIn: year) }.sorted { $0.start < $1.start }
        for (a, b) in zip(windows, windows.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start)
        }
    }
}
