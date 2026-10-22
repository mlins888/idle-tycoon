import SpriteKit
import SwiftUI

struct RootView: View {
    @State private var game: Game
    @State private var ui: MapInteraction
    @State private var scene: TownScene
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
            HUDView(game: game, ui: ui) { amount in
                scene.celebrateCollectAll(amount: amount)
            }
        }
        .sheet(item: $game.awaySummary) { summary in
            WelcomeBackView(summary: summary) {
                scene.celebrateCollectAll(amount: game.collectAll())
                game.awaySummary = nil
            } onLater: {
                game.awaySummary = nil
            }
            .presentationDetents([.medium])
            .presentationBackground(Theme.panel)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: game.checkAway()
            case .inactive, .background: game.save()
            @unknown default: break
            }
        }
        .preferredColorScheme(.dark)
    }
}
