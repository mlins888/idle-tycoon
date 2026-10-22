import SwiftUI

/// Everything drawn over the map: the top bar, and a bottom area that changes with what you're doing.
struct HUDView: View {
    let game: Game
    let ui: MapInteraction
    var onCollectAll: (Double) -> Void
    var onSummon: (SummonResult) -> Void

    @State private var showBuildMenu = false
    @State private var showResidents = false
    @State private var showQuests = false
    @State private var showEvent = false
    @State private var showDebug = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(game: game, onDebug: { showDebug = true })
            if let event = game.activeEvent {
                EventBanner(game: game, event: event) { showEvent = true }
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
            bottom
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $showBuildMenu) {
            BuildMenu(game: game) { defId in
                showBuildMenu = false
                ui.startPlacing(defId)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.panel)
        }
        .sheet(isPresented: $showResidents) {
            ResidentsView(game: game)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.panel)
        }
        .sheet(isPresented: $showQuests) {
            QuestLog(game: game)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.panel)
        }
        .sheet(isPresented: $showEvent) {
            if let event = game.activeEvent {
                EventView(game: game, event: event)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.panel)
            }
        }
        .sheet(isPresented: $showDebug) {
            DebugMenu(game: game)
                .presentationDetents([.medium])
                .presentationBackground(Theme.panel)
        }
    }

    @ViewBuilder
    private var bottom: some View {
        switch ui.mode {
        case .placing, .moving:
            PlacementBar(game: game, ui: ui)
        case .browse:
            if let id = ui.selectedBuildingId, let b = game.building(id: id), let def = game.def(for: b) {
                switch def.kind {
                case .shop: BuildingPanel(game: game, ui: ui, building: b)
                case .house: HousePanel(game: game, ui: ui, building: b)
                case .shrine: ShrinePanel(game: game, ui: ui, building: b, onSummon: onSummon)
                case .guild: GuildPanel(game: game, ui: ui, building: b)
                case .decoration: DecorationPanel(game: game, ui: ui, building: b)
                }
            } else if let rid = ui.selectedResidentId, let def = game.content.resident(rid), game.resident(rid) != nil {
                ResidentPanel(game: game, ui: ui, def: def)
            } else if let chunk = ui.selectedChunk {
                CleansePanel(game: game, ui: ui, chunk: chunk)
            } else {
                MainBar(game: game,
                        onBuild: { showBuildMenu = true },
                        onResidents: { showResidents = true },
                        onQuests: { showQuests = true },
                        onCollectAll: onCollectAll)
            }
        }
    }
}

private struct TopBar: View {
    let game: Game
    var onDebug: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    GlimmerIcon(size: 22)
                    Text(Format.compact(game.state.glimmer))
                        .font(Theme.title(24))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: game.state.glimmer)
                }
                HStack(spacing: 6) {
                    WispIcon(size: 16)
                    Text("\(Int(game.state.wisps)) wisps")
                        .font(Theme.body(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.wisp)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Level \(game.level)")
                    .font(Theme.body(13, weight: .bold))
                ProgressView(value: game.levelProgress)
                    .tint(Theme.lantern)
                    .frame(width: 90)
                Text("Fen restored \(Int((game.restoration * 100).rounded()))%")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textDim)
            }
            #if DEBUG
            Button(action: onDebug) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .foregroundStyle(Theme.textDim)
            .accessibilityLabel("Debug menu")
            #endif
        }
        .fenPanel()
    }
}

private struct MainBar: View {
    let game: Game
    var onBuild: () -> Void
    var onResidents: () -> Void
    var onQuests: () -> Void
    var onCollectAll: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let waiting = game.totalPending()
            HStack(spacing: 10) {
                Button {
                    let amount = game.collectAll()
                    if amount >= 1 { Haptics.collect() }
                    onCollectAll(amount)
                } label: {
                    HStack(spacing: 8) {
                        GlimmerIcon(size: 18)
                        Text(waiting >= 1 ? "Collect all · \(Format.compact(waiting))" : "Nothing to collect")
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FenButtonStyle(prominent: true))
                .disabled(waiting < 1)

                Button(action: onQuests) {
                    Image(systemName: "scroll.fill")
                        .overlay(alignment: .topTrailing) {
                            if game.readyQuestCount > 0 {
                                Circle().fill(Theme.ember).frame(width: 10, height: 10).offset(x: 6, y: -6)
                            }
                        }
                }
                .buttonStyle(FenButtonStyle())
                .accessibilityLabel(game.readyQuestCount > 0 ? "Quests, reward ready" : "Quests")

                Button(action: onResidents) {
                    Image(systemName: "person.3.fill")
                }
                .buttonStyle(FenButtonStyle())
                .accessibilityLabel("Townsfolk")

                Button(action: onBuild) {
                    Image(systemName: "hammer.fill")
                }
                .buttonStyle(FenButtonStyle())
                .accessibilityLabel("Build")
            }
            .fenPanel()
        }
    }
}

private struct PlacementBar: View {
    let game: Game
    let ui: MapInteraction

    var body: some View {
        let (defId, movingId) = target
        let def = defId.flatMap { game.content.building($0) }
        let valid = ui.ghostOrigin.map { game.canPlace(defId ?? "", at: $0, ignoring: movingId) } ?? false

        VStack(alignment: .leading, spacing: 10) {
            Text(movingId == nil ? "Build \(def?.name ?? "")" : "Move \(def?.name ?? "")")
                .font(Theme.title(18))
            Text(valid ? "Tap the map to choose a spot, then confirm."
                       : "That spot is blocked or still under murk. Tap somewhere else.")
                .font(Theme.body(13))
                .foregroundStyle(valid ? Theme.textDim : Theme.ember)
            if let def, let aura = def.aura, let origin = ui.ghostOrigin {
                let probe = PlacedBuilding(id: movingId ?? -1, defId: def.id, origin: origin, stage: 1, lastCollectedAt: .now)
                let count = game.shopsReached(by: probe).count
                Text("+\(Int((aura.bonus * 100).rounded()))% to shops within \(aura.radius) tile\(aura.radius == 1 ? "" : "s"). Here it would boost \(count) shop\(count == 1 ? "" : "s").")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.wisp)
            }
            HStack(spacing: 10) {
                Button("Cancel") { ui.finishPlacement() }
                    .buttonStyle(FenButtonStyle())
                Button {
                    guard let origin = ui.ghostOrigin, let defId else { return }
                    let done = movingId.map { game.move($0, to: origin) } ?? game.build(defId, at: origin)
                    if done {
                        Haptics.build()
                        ui.finishPlacement()
                    }
                } label: {
                    if let def, movingId == nil {
                        HStack(spacing: 6) {
                            Text("Build for")
                            GlimmerIcon(size: 14)
                            Text(Format.compact(game.buildCost(def)))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Place here").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(FenButtonStyle(prominent: true))
                .disabled(!valid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }

    private var target: (String?, Int?) {
        switch ui.mode {
        case .placing(let defId): return (defId, nil)
        case .moving(let id): return (game.building(id: id)?.defId, id)
        case .browse: return (nil, nil)
        }
    }
}
