import Foundation

struct PlacedBuilding: Codable, Identifiable, Hashable {
    let id: Int
    let defId: String
    /// Top corner of the footprint.
    var origin: Tile
    /// Which stage the building is at, counting from 1.
    var stage: Int
    /// Earnings are worked out from this timestamp, which is what makes offline earnings work.
    var lastCollectedAt: Date
    /// Has a Keeper's Charter: its worker collects it automatically.
    var autoCollect: Bool = false
    /// Set while the building is closed for renovation into the next stage.
    var renovationEndsAt: Date?

    var isRenovating: Bool { renovationEndsAt != nil }
}

/// Someone who lives in town.
struct Resident: Codable, Hashable, Identifiable {
    var id: String { defId }
    let defId: String
    /// The house they sleep in.
    var homeId: Int
    /// The shop they work at, if any.
    var workId: Int?
    let arrivedAt: Date
}

/// Running totals that quests measure progress against.
struct Stats: Codable, Equatable {
    /// Glimmer collected, per building id, plus "*" for all shops together.
    var collected: [String: Double] = [:]
    var chunksCleansed: Int = 0

    static let anyShop = "*"
}

extension Stats {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collected = try c.decodeIfPresent([String: Double].self, forKey: .collected) ?? [:]
        chunksCleansed = try c.decodeIfPresent(Int.self, forKey: .chunksCleansed) ?? 0
    }
}

/// How far the player got in one year's run of a festival.
struct EventProgress: Codable, Equatable {
    /// The year this run started; progress resets when the festival comes round again.
    var year: Int
    var tokens: Double = 0
    /// How many milestones have been reached (and their rewards given).
    var reached: Int = 0
}

/// The words used for the player in scene text. Presets for he, she and they; any custom set works too.
struct Pronouns: Codable, Equatable, Hashable {
    var subject: String      // they
    var object: String       // them
    var possessive: String   // their
    var possessivePronoun: String // theirs
    var reflexive: String    // themself
    /// "they are" rather than "she is".
    var pluralVerbs: Bool

    static let they = Pronouns(subject: "they", object: "them", possessive: "their", possessivePronoun: "theirs",
                               reflexive: "themself", pluralVerbs: true)
    static let she = Pronouns(subject: "she", object: "her", possessive: "her", possessivePronoun: "hers",
                              reflexive: "herself", pluralVerbs: false)
    static let he = Pronouns(subject: "he", object: "him", possessive: "his", possessivePronoun: "his",
                             reflexive: "himself", pluralVerbs: false)
}

/// The player character (the Surfaced). Filled in by character creation; until then, these defaults.
struct PlayerProfile: Codable, Equatable {
    var name = "Surfaced"
    var pronouns = Pronouns.they
    /// Placeholder portrait colour (hex) until real art exists.
    var color = "#7FE3D6"
}

extension PlayerProfile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Surfaced"
        pronouns = try c.decodeIfPresent(Pronouns.self, forKey: .pronouns) ?? .they
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#7FE3D6"
    }
}

/// Everything that gets saved. Kept as plain data so it can be encoded and tested easily.
struct GameState: Codable, Equatable {
    static let currentVersion = 6

    var version: Int = GameState.currentVersion
    var glimmer: Double
    var xp: Double
    var buildings: [PlacedBuilding]
    var cleansedChunks: Set<Chunk>
    var nextBuildingId: Int
    var savedAt: Date

    // Added in version 2.
    var residents: [Resident] = []
    var wisps: Double = 0
    /// When the next wanderer reaches town. Nil while there's no free bed.
    var nextWandererAt: Date?
    /// State of the seeded random generator, so summons and arrivals are fair and repeatable.
    var rngState: UInt64 = 0x9E37_79B9_7F4A_7C15
    /// The highest level that has already paid out its wisps.
    var rewardedLevel: Int = 1

    // Added in version 3.
    var stats = Stats()
    /// Quests in progress, with the counter value when each started (for "collect N more" goals).
    var activeQuests: [String: Double] = [:]
    var completedQuests: Set<String> = []

    // Added in version 4.
    /// Festival progress by festival id.
    var eventProgress: [String: EventProgress] = [:]
    /// Festival decorations that can now be built.
    var unlockedDecorations: Set<String> = []
    /// Festival residents who've been invited and will move in when there's a bed.
    var invitedResidents: Set<String> = []

    // Added in version 5. (Shops' `lastCollectedAt` now means "when the current production run started".)
    /// When the next lost wisp drifts over town.
    var nextWispAt: Date?
    /// While a lost wisp is drifting over town, when it fades away.
    var wispVisibleUntil: Date?

    // Added in version 6: the story.
    var chapter: Int = 1
    var flags: Set<String> = []
    /// Named story values: `sealStrain`, `courtStanding`, `kindling`.
    var storyValues: [String: Double] = [:]
    var seenScenes: Set<String> = []
    /// Scenes waiting to play, in order (saved so closing the app doesn't lose them).
    var pendingScenes: [String] = []
    /// Memory fragments found.
    var fragments: Set<String> = []
    var player = PlayerProfile()
    /// Whether the game-start scenes have been queued for this save.
    var storyStarted = false

    static func newGame(now: Date) -> GameState {
        GameState(
            glimmer: 60,
            xp: 0,
            buildings: [
                PlacedBuilding(id: 1, defId: "reed_candles", origin: Tile(c: 10, r: 10),
                               stage: 1, lastCollectedAt: now),
                PlacedBuilding(id: 2, defId: "reed_cottage", origin: Tile(c: 8, r: 9),
                               stage: 1, lastCollectedAt: now),
            ],
            cleansedChunks: World.startingChunks,
            nextBuildingId: 3,
            savedAt: now,
            rngState: UInt64(now.timeIntervalSinceReferenceDate * 1000) | 1
        )
    }
}

// Decoding by hand so saves from older versions (missing the newer fields) still load.

extension PlacedBuilding {
    private enum LegacyKeys: String, CodingKey { case level }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        defId = try c.decode(String.self, forKey: .defId)
        origin = try c.decode(Tile.self, forKey: .origin)
        lastCollectedAt = try c.decode(Date.self, forKey: .lastCollectedAt)
        autoCollect = try c.decodeIfPresent(Bool.self, forKey: .autoCollect) ?? false
        renovationEndsAt = try c.decodeIfPresent(Date.self, forKey: .renovationEndsAt)
        if let stage = try c.decodeIfPresent(Int.self, forKey: .stage) {
            self.stage = stage
        } else {
            // Before version 3 buildings had levels 1–10. Map them onto stages
            // (`Game` clamps this to however many stages the building has).
            let level = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Int.self, forKey: .level) ?? 1
            self.stage = level >= 10 ? 3 : level >= 5 ? 2 : 1
        }
    }
}

extension GameState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        glimmer = try c.decode(Double.self, forKey: .glimmer)
        xp = try c.decode(Double.self, forKey: .xp)
        buildings = try c.decode([PlacedBuilding].self, forKey: .buildings)
        cleansedChunks = try c.decode(Set<Chunk>.self, forKey: .cleansedChunks)
        nextBuildingId = try c.decode(Int.self, forKey: .nextBuildingId)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        residents = try c.decodeIfPresent([Resident].self, forKey: .residents) ?? []
        wisps = try c.decodeIfPresent(Double.self, forKey: .wisps) ?? 0
        nextWandererAt = try c.decodeIfPresent(Date.self, forKey: .nextWandererAt)
        rngState = try c.decodeIfPresent(UInt64.self, forKey: .rngState)
            ?? (UInt64(savedAt.timeIntervalSinceReferenceDate * 1000) | 1)
        rewardedLevel = try c.decodeIfPresent(Int.self, forKey: .rewardedLevel)
            ?? Economy.level(forXP: xp)
        stats = try c.decodeIfPresent(Stats.self, forKey: .stats) ?? Stats()
        activeQuests = try c.decodeIfPresent([String: Double].self, forKey: .activeQuests) ?? [:]
        completedQuests = try c.decodeIfPresent(Set<String>.self, forKey: .completedQuests) ?? []
        eventProgress = try c.decodeIfPresent([String: EventProgress].self, forKey: .eventProgress) ?? [:]
        unlockedDecorations = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedDecorations) ?? []
        invitedResidents = try c.decodeIfPresent(Set<String>.self, forKey: .invitedResidents) ?? []
        nextWispAt = try c.decodeIfPresent(Date.self, forKey: .nextWispAt)
        wispVisibleUntil = try c.decodeIfPresent(Date.self, forKey: .wispVisibleUntil)
        chapter = try c.decodeIfPresent(Int.self, forKey: .chapter) ?? 1
        flags = try c.decodeIfPresent(Set<String>.self, forKey: .flags) ?? []
        storyValues = try c.decodeIfPresent([String: Double].self, forKey: .storyValues) ?? [:]
        seenScenes = try c.decodeIfPresent(Set<String>.self, forKey: .seenScenes) ?? []
        pendingScenes = try c.decodeIfPresent([String].self, forKey: .pendingScenes) ?? []
        fragments = try c.decodeIfPresent(Set<String>.self, forKey: .fragments) ?? []
        player = try c.decodeIfPresent(PlayerProfile.self, forKey: .player) ?? PlayerProfile()
        storyStarted = try c.decodeIfPresent(Bool.self, forKey: .storyStarted) ?? false
    }
}
