import SwiftUI

/// Details for a tapped building: what it makes, upgrade and move.
struct BuildingPanel: View {
    let game: Game
    let ui: MapInteraction
    let building: PlacedBuilding

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let def = game.def(for: building) {
                content(def)
            }
        }
    }

    private func content(_ def: BuildingDef) -> some View {
        let rate = Economy.rate(def, level: building.level)
        let capacity = Economy.capacity(def, level: building.level)
        let waiting = game.pending(building)
        let upgradeCost = game.upgradeCost(building)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(def.name).font(Theme.title(19))
                Spacer()
                Text("Lv \(building.level)/\(def.maxLevel)")
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                Button {
                    ui.clearSelection()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .foregroundStyle(Theme.textDim)
                .accessibilityLabel("Close")
            }
            Text(def.blurb)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                stat("Makes", "\(Format.compact(rate * 60))/min")
                stat("Holds", Format.compact(capacity))
                stat("Waiting", Format.compact(waiting), highlight: game.isFull(building))
            }
            ProgressView(value: min(1, waiting / max(1, capacity)))
                .tint(game.isFull(building) ? Theme.ember : Theme.lantern)

            HStack(spacing: 10) {
                Button("Move") { ui.startMoving(building.id, from: building.origin) }
                    .buttonStyle(FenButtonStyle())
                if let upgradeCost {
                    Button {
                        game.upgrade(building.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Upgrade")
                            GlimmerIcon(size: 14)
                            Text(Format.compact(upgradeCost)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FenButtonStyle(prominent: true))
                    .disabled(game.state.glimmer < upgradeCost)
                } else {
                    Text("Fully upgraded")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.moss)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }

    private func stat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.body(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)
            Text(value)
                .font(Theme.body(16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(highlight ? Theme.ember : Theme.text)
        }
    }
}

/// Offered when the player taps murk: reclaim that block of land.
struct CleansePanel: View {
    let game: Game
    let ui: MapInteraction
    let chunk: Chunk

    var body: some View {
        let cost = game.cleanseCost
        let reachable = game.canCleanse(chunk)
        let tiles = World.chunkSize * World.chunkSize

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Murk-choked bog").font(Theme.title(19))
                Spacer()
                Button {
                    ui.clearSelection()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .foregroundStyle(Theme.textDim)
                .accessibilityLabel("Close")
            }
            Text(reachable
                 ? "The Lantern Thief's gloom still clings here. Cleanse it to reclaim \(tiles) tiles of land."
                 : "This murk is too deep to reach. Cleanse the land next to your town first.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if game.cleanse(chunk) { ui.clearSelection() }
            } label: {
                HStack(spacing: 6) {
                    Text("Cleanse for")
                    GlimmerIcon(size: 14)
                    Text(Format.compact(cost)).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FenButtonStyle(prominent: true))
            .disabled(!reachable || game.state.glimmer < cost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }
}

/// The list of buildings you can build, with locked ones shown greyed out.
struct BuildMenu: View {
    let game: Game
    var onChoose: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Build")
                    .font(Theme.title(24))
                    .padding(.top, 20)
                ForEach(game.content.buildings) { def in
                    row(def)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.text)
    }

    private func row(_ def: BuildingDef) -> some View {
        let unlocked = game.isUnlocked(def)
        let cost = game.buildCost(def)
        let affordable = game.state.glimmer >= cost

        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: def.color))
                .frame(width: 44, height: 44)
                .overlay(Text("\(def.size)×\(def.size)")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.lanternInk))
            VStack(alignment: .leading, spacing: 4) {
                Text(def.name).font(Theme.body(16, weight: .bold))
                Text(def.blurb)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Makes \(Format.compact(Economy.rate(def, level: 1) * 60))/min")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.moss)
            }
            Spacer(minLength: 8)
            if unlocked {
                Button {
                    onChoose(def.id)
                } label: {
                    HStack(spacing: 4) {
                        GlimmerIcon(size: 13)
                        Text(Format.compact(cost)).monospacedDigit()
                    }
                }
                .buttonStyle(FenButtonStyle(prominent: affordable))
                .disabled(!affordable)
            } else {
                Text("Level \(def.unlockLevel)")
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 12)
            }
        }
        .opacity(unlocked ? 1 : 0.55)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.button.opacity(0.6)))
    }
}

/// "While you were away" summary shown on return.
struct WelcomeBackView: View {
    let summary: AwaySummary
    var onCollect: () -> Void
    var onLater: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome back")
                .font(Theme.title(26))
            Text("You were gone \(Format.duration(summary.duration)). Your shops kept their lights burning.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                GlimmerIcon(size: 26)
                Text(Format.compact(summary.waiting))
                    .font(Theme.title(32))
                    .monospacedDigit()
            }
            Button {
                onCollect()
            } label: {
                Text("Collect all").frame(maxWidth: .infinity)
            }
            .buttonStyle(FenButtonStyle(prominent: true))
            Button("Later", action: onLater)
                .buttonStyle(FenButtonStyle())
        }
        .padding(24)
        .foregroundStyle(Theme.text)
    }
}

/// Testing shortcuts. Only included in debug builds.
struct DebugMenu: View {
    let game: Game
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Debug").font(Theme.title(22))
            HStack {
                Button("+1K glimmer") { game.debugAdd(glimmer: 1_000) }
                Button("+100K") { game.debugAdd(glimmer: 100_000) }
                Button("+1 level") { game.debugAdd(xp: Economy.xpForLevel(game.level + 1) - game.state.xp) }
            }
            HStack {
                Button("Skip 10m") { game.debugSkip(600) }
                Button("Skip 1h") { game.debugSkip(3600) }
                Button("Skip 8h") { game.debugSkip(8 * 3600) }
            }
            Text("Time offset: \(Format.duration(game.clock.offset))")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textDim)
            Button(confirmReset ? "Tap again to erase your town" : "Reset save") {
                if confirmReset {
                    game.debugReset()
                    confirmReset = false
                } else {
                    confirmReset = true
                }
            }
            .foregroundStyle(Theme.ember)
        }
        .buttonStyle(FenButtonStyle())
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.text)
    }
}
