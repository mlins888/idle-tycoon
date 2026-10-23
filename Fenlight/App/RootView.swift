import SpriteKit
import SwiftUI

struct RootView: View {
    @State private var game: Game
    @State private var ui: MapInteraction
    @State private var scene: TownScene
    @State private var summonResult: SummonResult?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let game = Game(content: .load(), store: RootView.makeStore())
        #if DEBUG
        // `-playScene <id>` opens a scene straight away (for screenshots and testing).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-playScene"), args.indices.contains(i + 1) {
            game.debugPlayScene(args[i + 1])
        }
        #endif
        let ui = MapInteraction()
        _game = State(initialValue: game)
        _ui = State(initialValue: ui)
        _scene = State(initialValue: TownScene(game: game, ui: ui))
    }

    /// UI tests launch with `-uiTesting` to start from a fresh town every time, without touching the real save.
    private static func makeStore() -> SaveStore {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return SaveStore() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fenlight-uitest.json")
        try? FileManager.default.removeItem(at: url)
        return SaveStore(url: url)
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()
            HUDView(game: game, ui: ui,
                    onCollectAll: { scene.celebrateCollectAll(amount: $0) },
                    onSummon: { summonResult = $0 })
            cards
        }
        .animation(.spring(duration: 0.35), value: summonResult)
        .animation(.easeInOut(duration: 0.3), value: game.currentScene?.id)
        .animation(.spring(duration: 0.35), value: game.announcements.first)
        .sensoryFeedback(.success, trigger: game.announcements.first) { _, new in new != nil }
        .sheet(item: $game.awaySummary) { summary in
            WelcomeBackView(summary: summary) {
                scene.celebrateCollectAll(amount: game.collectAll())
                game.awaySummary = nil
            } onLater: {
                game.awaySummary = nil
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.panel)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Reminders.cancel()
                game.checkAway()
            case .background:
                game.save()
                Reminders.schedule(game)
            case .inactive:
                game.save()
            @unknown default:
                break
            }
        }
        .onChange(of: game.state.buildings.count) { old, new in
            // Ask about notifications once the player has built something of their own.
            if new > old, new >= 3 { Reminders.requestPermission() }
        }
        .preferredColorScheme(.dark)
    }

    /// Summon results and "moved in!" cards, one at a time, over a dimmed map.
    @ViewBuilder
    private var cards: some View {
        if ui.mode == .browse, game.awaySummary == nil, let scene = game.currentScene {
            // Story scenes come first, and wait while you're placing or moving something.
            SceneView(game: game, scene: scene)
                .id(scene.id)
                .transition(.opacity)
        } else if let result = summonResult {
            dimmed {
                switch result {
                case .newResident(let def):
                    ArrivalCard(def: def, title: "answered the call!") { summonResult = nil }
                case .duplicate(let def, let refund):
                    ArrivalCard(def: def, title: "came to visit",
                                subtitle: "They already live in Fenlight. \(Int(refund)) wisps were returned.") {
                        summonResult = nil
                    }
                }
            }
        } else if game.awaySummary == nil, let next = game.announcements.first {
            dimmed {
                announcementCard(next) { game.announcements.removeFirst() }
            }
        }
    }

    @ViewBuilder
    private func announcementCard(_ a: Announcement, dismiss: @escaping () -> Void) -> some View {
        switch a {
        case .arrival(let def):
            ArrivalCard(def: def, onDismiss: dismiss)
        case .transformed(let def, let from, let to):
            let stage = def.stage(to)
            NoticeCard(eyebrow: "Renovation finished",
                       title: "The \(def.stage(from).name) is now the \(stage.name)!",
                       message: stage.blurb,
                       detail: stage.sells.isEmpty ? nil : "Now selling " + stage.sells.joined(separator: ", ").lowercased(),
                       button: "Wonderful", onDismiss: dismiss)
        case .eventStarted(let e):
            NoticeCard(eyebrow: "A festival begins",
                       title: e.name,
                       message: e.blurb,
                       detail: "Collect from shops to earn \(e.tokens) and unlock festival rewards.",
                       button: "Let's celebrate", onDismiss: dismiss)
        case .eventMilestone(let e, let index):
            NoticeCard(eyebrow: "\(e.name) reward",
                       title: "\(Int(e.milestones[index].tokens)) \(e.tokens)!",
                       message: EventRewards.describe(e.milestones[index].reward, game.content),
                       detail: e.milestones[index].reward.decoration != nil ? "Find it in the Build menu under Decorations." : nil,
                       button: "Lovely", onDismiss: dismiss)
        case .questReady(let q):
            NoticeCard(eyebrow: "Quest complete",
                       title: q.title,
                       message: q.doneText,
                       detail: "Claim your reward in the quest log.",
                       button: "Got it", onDismiss: dismiss)
        }
    }

    private func dimmed<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            content()
        }
    }
}
