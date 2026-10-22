import SpriteKit
import SwiftUI

struct RootView: View {
    @State private var game: Game
    @State private var ui: MapInteraction
    @State private var scene: TownScene
    @State private var summonResult: SummonResult?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let game = Game(content: .load(), store: SaveStore())
        let ui = MapInteraction()
        _game = State(initialValue: game)
        _ui = State(initialValue: ui)
        _scene = State(initialValue: TownScene(game: game, ui: ui))
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
        .animation(.spring(duration: 0.35), value: game.arrivalQueue.first)
        .sensoryFeedback(.success, trigger: game.arrivalQueue.first) { _, new in new != nil }
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
                Reminders.scheduleShopFull(game)
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
        if let result = summonResult {
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
        } else if game.awaySummary == nil, let next = game.arrivalQueue.first {
            dimmed {
                ArrivalCard(def: next) { game.arrivalQueue.removeFirst() }
            }
        }
    }

    private func dimmed<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            content()
        }
    }
}
