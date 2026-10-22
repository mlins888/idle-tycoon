import SwiftUI

/// Shared top row for bottom panels: title, optional detail on the right, and a close button.
private struct PanelHeader: View {
    let title: String
    var detail: String?
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.title(19))
            Spacer()
            if let detail {
                Text(detail)
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .foregroundStyle(Theme.textDim)
            .accessibilityLabel("Close")
        }
    }
}

private struct Blurb: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CostLabel: View {
    let verb: String
    let cost: Double
    var icon: AnyView = AnyView(GlimmerIcon(size: 14))

    var body: some View {
        HStack(spacing: 6) {
            Text(verb)
            icon
            Text(Format.compact(cost)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
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

// MARK: - Shops

/// Details for a tapped shop: what it sells and makes, its workers, its next stage, charter and move.
struct BuildingPanel: View {
    let game: Game
    let ui: MapInteraction
    let building: PlacedBuilding

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let def = game.def(for: building), let stage = game.stageDef(building) {
                ScrollIfNeeded {
                    content(def, stage)
                }
                .fenPanel()
            }
        }
    }

    private func content(_ def: BuildingDef, _ stage: StageDef) -> some View {
        let rate = game.rate(building)
        let capacity = game.capacity(building)
        let waiting = game.pending(building)
        let auto = game.isAuto(building)

        return VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: stage.name, detail: "Stage \(building.stage)/\(def.stages.count)") { ui.clearSelection() }
            Blurb(text: stage.blurb)
            Sells(items: stage.sells)

            if building.isRenovating {
                RenovationProgress(game: game, building: building)
            } else {
                HStack(spacing: 16) {
                    stat("Makes", "\(Format.compact(rate * 60))/min")
                    let decor = game.decorationBonus(building)
                    if decor > 0 {
                        stat("Decor", "+\(Int((decor * 100).rounded()))%")
                    }
                    if auto {
                        stat("Keeper", "Collecting")
                    } else {
                        stat("Holds", Format.compact(capacity))
                        stat("Waiting", Format.compact(waiting), highlight: game.isFull(building))
                    }
                }
                if !auto {
                    ProgressView(value: min(1, waiting / max(1, capacity)))
                        .tint(game.isFull(building) ? Theme.ember : Theme.lantern)
                }
            }

            WorkerSlots(game: game, shop: building, def: def)
            charterRow(def)

            if !building.isRenovating {
                NextStageCard(game: game, building: building, def: def)
            }

            Button("Move") { ui.startMoving(building.id, from: building.origin) }
                .buttonStyle(FenButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func charterRow(_ def: BuildingDef) -> some View {
        if building.autoCollect {
            Label(game.isAuto(building) ? "Keeper's Charter: your worker collects this shop for you."
                                        : "Keeper's Charter: assign a worker and they'll collect for you.",
                  systemImage: "lamp.table.fill")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.lantern)
        } else if game.hasBuilt(.guild), let cost = game.charterCost(building) {
            let hasWorker = !game.workers(at: building.id).isEmpty
            Button {
                if game.buyCharter(building.id) { Haptics.celebrate() }
            } label: {
                CostLabel(verb: "Keeper's Charter", cost: cost)
            }
            .buttonStyle(FenButtonStyle())
            .disabled(!hasWorker || game.state.glimmer < cost)
            if !hasWorker {
                Text("Assign a worker first. They'll collect this shop for you.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}

/// The worker slots on a shop, with a menu to choose who works there.
private struct WorkerSlots: View {
    let game: Game
    let shop: PlacedBuilding
    let def: BuildingDef

    var body: some View {
        let workers = game.workers(at: shop.id)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(workers) { worker in
                HStack(spacing: 10) {
                    Portrait(def: worker, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(worker.name).font(Theme.body(14, weight: .bold))
                        Text(bonusText(worker))
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(worker.favoriteShop == def.id ? Theme.lantern : Theme.moss)
                    }
                    Spacer()
                    Button("Remove") { game.unassignWorker(worker.id) }
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }
            }
            if workers.count < def.workerSlots {
                WorkerMenu(game: game, shop: shop, def: def)
            }
        }
    }

    private func bonusText(_ worker: ResidentDef) -> String {
        let favorite = worker.favoriteShop == def.id
        let pct = Int(Economy.workerBonus(isFavorite: favorite) * 100)
        return favorite ? "♥ Favourite shop · +\(pct)%" : "+\(pct)%"
    }
}

struct WorkerMenu: View {
    let game: Game
    let shop: PlacedBuilding
    let def: BuildingDef

    var body: some View {
        let candidates = game.residentDefs
            .filter { game.resident($0.id)?.workId != shop.id }
            .sorted { ($0.favoriteShop == def.id ? 0 : 1, $0.name) < ($1.favoriteShop == def.id ? 0 : 1, $1.name) }
        Menu {
            if candidates.isEmpty {
                Text("No one lives in town yet")
            }
            ForEach(candidates) { r in
                Button {
                    game.assignWorker(r.id, to: shop.id)
                } label: {
                    Text(label(for: r))
                }
            }
        } label: {
            Label("Choose a worker", systemImage: "person.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FenButtonStyle())
    }

    private func label(for r: ResidentDef) -> String {
        var text = r.name
        if r.favoriteShop == def.id { text += " ♥" }
        if let work = game.resident(r.id)?.workId, let b = game.building(id: work), let d = game.def(for: b) {
            text += " (at \(d.name))"
        }
        return text
    }
}

// MARK: - Houses, shrine, guild

struct HousePanel: View {
    let game: Game
    let ui: MapInteraction
    let building: PlacedBuilding

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollIfNeeded {
                content
            }
            .fenPanel()
        }
    }

    private var content: some View {
        let def = game.def(for: building)
        let stage = game.stageDef(building)
        let beds = Residents.beds(building, game.content)
        let occupants = Residents.occupants(of: building.id, in: game.state)
            .compactMap { game.content.resident($0.defId) }
        return VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: stage?.name ?? "House", detail: "\(occupants.count)/\(beds) beds") {
                ui.clearSelection()
            }
            if let stage { Blurb(text: stage.blurb) }
            if occupants.isEmpty {
                Blurb(text: "Empty for now. Someone will be along soon.")
            }
            ForEach(occupants) { r in
                HStack(spacing: 10) {
                    Portrait(def: r, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(Theme.body(14, weight: .bold))
                        Text(r.folk).font(Theme.body(12)).foregroundStyle(Theme.textDim)
                    }
                }
            }
            if building.isRenovating {
                RenovationProgress(game: game, building: building)
            } else if let def {
                NextStageCard(game: game, building: building, def: def)
            }
            Button("Move") { ui.startMoving(building.id, from: building.origin) }
                .buttonStyle(FenButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows its content as-is when it fits, or in a scroll view when it's taller than the space available.
struct ScrollIfNeeded<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollIndicators(.hidden)
        }
    }
}

/// "Sells: Mossbread · Honey cakes"
private struct Sells: View {
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            Text("Sells: " + items.joined(separator: " · "))
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.lantern)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the next stage is, what it needs, and the button to start renovating.
private struct NextStageCard: View {
    let game: Game
    let building: PlacedBuilding
    let def: BuildingDef

    var body: some View {
        if let next = game.nextStage(building) {
            let unmet = Set(game.unmetRequirements(building))
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT STAGE")
                    .font(Theme.body(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textDim)
                Text(next.name).font(Theme.title(17))
                Blurb(text: next.blurb)
                Sells(items: next.sells)
                if def.kind == .shop {
                    let now = game.rate(building)
                    let then = Economy.rate(def, stage: building.stage + 1, workers: game.workers(at: building.id))
                    Text("Makes \(Format.compact(now * 60))/min → \(Format.compact(then * 60))/min")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.moss)
                } else if next.beds > 0 {
                    Text("\(Residents.beds(building, game.content)) → \(next.beds) beds")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.moss)
                }
                ForEach(next.requirements, id: \.self) { r in
                    let met = !unmet.contains(r)
                    Label(Requirements.describe(r, game.content),
                          systemImage: met ? "checkmark.circle.fill" : "circle")
                        .font(Theme.body(13))
                        .foregroundStyle(met ? Theme.moss : Theme.textDim)
                }
                Button {
                    if game.startRenovation(building.id) { Haptics.build() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Renovate")
                        GlimmerIcon(size: 14)
                        Text(Format.compact(next.cost)).monospacedDigit()
                        Text("· \(Format.duration(next.buildSeconds))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FenButtonStyle(prominent: true))
                .disabled(!game.canRenovate(building))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.button.opacity(0.6)))
        } else if def.stages.count > 1 {
            Text("Fully built. This is as grand as it gets.")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.moss)
        }
    }
}

/// Countdown while a building is closed for renovation, with a wisp-powered "finish now".
private struct RenovationProgress: View {
    let game: Game
    let building: PlacedBuilding

    var body: some View {
        if let next = game.nextStage(building), let remaining = game.renovationRemaining(building),
           let cost = game.finishNowCost(building) {
            let total = max(1, next.buildSeconds)
            VStack(alignment: .leading, spacing: 8) {
                Text("Closed for renovation into the \(next.name)")
                    .font(Theme.body(14, weight: .bold))
                ProgressView(value: min(1, max(0, 1 - remaining / total)))
                    .tint(Theme.lantern)
                Text("\(Format.duration(remaining)) left. It earns nothing until it reopens.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
                Button {
                    if game.finishRenovationNow(building.id) { Haptics.celebrate() }
                } label: {
                    CostLabel(verb: "Finish now", cost: cost, icon: AnyView(WispIcon(size: 14)))
                }
                .buttonStyle(FenButtonStyle())
                .disabled(game.state.wisps < cost)
            }
        }
    }
}

struct ShrinePanel: View {
    let game: Game
    let ui: MapInteraction
    let building: PlacedBuilding
    var onSummon: (SummonResult) -> Void

    var body: some View {
        let odds = Residents.summonOdds(game.content)
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Wisp Shrine", detail: nil) { ui.clearSelection() }
            Blurb(text: "Offer wisps to call someone rare out of the deep fen. Wisps come from cleansing murk and levelling up.")
            HStack(spacing: 12) {
                ForEach(odds, id: \.0) { rarity, chance in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rarity.rawValue.capitalized)
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Theme.rarity(rarity))
                        Text("\(Int((chance * 100).rounded()))%")
                            .font(Theme.body(14, weight: .bold))
                            .monospacedDigit()
                    }
                }
            }
            if game.freeBeds <= 0 {
                Text("Every bed is taken. Build a house to make room first.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.ember)
            }
            Button {
                if let result = game.summon() {
                    Haptics.celebrate()
                    onSummon(result)
                }
            } label: {
                CostLabel(verb: "Summon", cost: game.summonCost, icon: AnyView(WispIcon(size: 14)))
            }
            .buttonStyle(FenButtonStyle(prominent: true))
            .disabled(!game.canSummon)
            Button("Move") { ui.startMoving(building.id, from: building.origin) }
                .buttonStyle(FenButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }
}

/// A placed decoration: what it boosts, move it, or put it away.
struct DecorationPanel: View {
    let game: Game
    let ui: MapInteraction
    let building: PlacedBuilding
    @State private var confirmRemove = false

    var body: some View {
        let def = game.def(for: building)
        let reached = game.shopsReached(by: building)
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: def?.name ?? "Decoration", detail: nil) { ui.clearSelection() }
            if let def { Blurb(text: def.blurb) }
            if let aura = def?.aura {
                Text("+\(Int((aura.bonus * 100).rounded()))% to shops within \(aura.radius) tile\(aura.radius == 1 ? "" : "s")")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.wisp)
                Text(reached.isEmpty ? "No shops nearby yet. Move it closer to some."
                                     : "Boosting: " + reached.map(game.name).joined(separator: ", "))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Move") { ui.startMoving(building.id, from: building.origin) }
                    .buttonStyle(FenButtonStyle())
                if let def {
                    Button {
                        if confirmRemove {
                            if game.removeDecoration(building.id) { ui.clearSelection() }
                        } else {
                            confirmRemove = true
                        }
                    } label: {
                        if confirmRemove {
                            Text("Tap again to put away").frame(maxWidth: .infinity)
                        } else {
                            CostLabel(verb: "Put away · get back", cost: Economy.removalRefund(def))
                        }
                    }
                    .buttonStyle(FenButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }
}

struct GuildPanel: View {
    let game: Game
    let ui: MapInteraction
    let building: PlacedBuilding

    var body: some View {
        let chartered = game.state.buildings.filter(\.autoCollect).count
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Lamplighters' Guild", detail: nil) { ui.clearSelection() }
            Blurb(text: "Open a shop's panel and buy a Keeper's Charter. From then on, that shop's worker collects it for you, even while you're away (up to \(Format.duration(Economy.offlineCap))).")
            Text("\(chartered) shop\(chartered == 1 ? "" : "s") chartered")
                .font(Theme.body(14, weight: .bold))
                .foregroundStyle(Theme.lantern)
            Button("Move") { ui.startMoving(building.id, from: building.origin) }
                .buttonStyle(FenButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }
}

// MARK: - Land

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
            PanelHeader(title: "Murk-choked bog", detail: nil) { ui.clearSelection() }
            Blurb(text: reachable
                  ? "The Lantern Thief's gloom still clings here. Cleanse it to reclaim \(tiles) tiles of land and earn \(Int(Economy.wispsPerCleanse)) wisps."
                  : "This murk is too deep to reach. Cleanse the land next to your town first.")
            Button {
                if game.cleanse(chunk) {
                    Haptics.build()
                    ui.clearSelection()
                }
            } label: {
                CostLabel(verb: "Cleanse for", cost: cost)
            }
            .buttonStyle(FenButtonStyle(prominent: true))
            .disabled(!reachable || game.state.glimmer < cost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }
}

// MARK: - Build menu

/// Everything you can build, grouped by kind, with locked ones greyed out.
struct BuildMenu: View {
    let game: Game
    var onChoose: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Build")
                    .font(Theme.title(24))
                    .padding(.top, 20)
                section("Shops", kinds: [.shop])
                section("Homes", kinds: [.house])
                section("Decorations", kinds: [.decoration])
                section("Special", kinds: [.shrine, .guild])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.text)
    }

    @ViewBuilder
    private func section(_ title: String, kinds: Set<BuildingKind>) -> some View {
        Text(title.uppercased())
            .font(Theme.body(12, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.textDim)
            .padding(.top, 8)
        ForEach(game.content.buildings.filter { kinds.contains($0.kind) }) { def in
            row(def)
        }
    }

    private func detail(_ def: BuildingDef) -> String {
        switch def.kind {
        case .shop: return "Sells \(def.stage(1).sells.joined(separator: ", ").lowercased()) · \(Format.compact(Economy.rate(def, stage: 1) * 60))/min"
        case .house: return "\(def.stage(1).beds) bed\(def.stage(1).beds == 1 ? "" : "s")"
        case .shrine: return "Summon rare residents"
        case .guild: return "Unlocks auto-collect"
        case .decoration:
            guard let aura = def.aura else { return "Just for looks" }
            return "+\(Int((aura.bonus * 100).rounded()))% to shops within \(aura.radius) tile\(aura.radius == 1 ? "" : "s")"
        }
    }

    private func row(_ def: BuildingDef) -> some View {
        let unlocked = game.isUnlocked(def)
        let canMore = game.canBuildMore(def)
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
                Text(detail(def))
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.moss)
            }
            Spacer(minLength: 8)
            if !unlocked {
                Text("Level \(def.unlockLevel)")
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 12)
            } else if !canMore {
                Text("Built")
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(Theme.moss)
                    .padding(.top, 12)
            } else {
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
            }
        }
        .opacity(unlocked ? 1 : 0.55)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.button.opacity(0.6)))
    }
}

// MARK: - Popups

/// "While you were away" summary shown on return.
struct WelcomeBackView: View {
    let summary: AwaySummary
    var onCollect: () -> Void
    var onLater: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Welcome back")
                    .font(Theme.title(26))
                Text("You were gone \(Format.duration(summary.duration)).")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textDim)
                if summary.keepers >= 1 {
                    line("Your keepers collected", summary.keepers)
                }
                if summary.waiting >= 1 {
                    line("Waiting in your shops", summary.waiting)
                }
                if !summary.arrivals.isEmpty {
                    VStack(spacing: 8) {
                        Text("New in town")
                            .font(Theme.body(12, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                        ForEach(summary.arrivals) { r in
                            HStack(spacing: 10) {
                                Portrait(def: r, size: 30)
                                Text("\(r.name), \(r.folk.lowercased())").font(Theme.body(14, weight: .semibold))
                            }
                        }
                    }
                }
                if summary.waiting >= 1 {
                    Button {
                        onCollect()
                    } label: {
                        Text("Collect all").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FenButtonStyle(prominent: true))
                }
                Button(summary.waiting >= 1 ? "Later" : "Back to town", action: onLater)
                    .buttonStyle(FenButtonStyle())
            }
            .padding(24)
        }
        .foregroundStyle(Theme.text)
    }

    private func line(_ label: String, _ amount: Double) -> some View {
        VStack(spacing: 4) {
            Text(label).font(Theme.body(13)).foregroundStyle(Theme.textDim)
            HStack(spacing: 8) {
                GlimmerIcon(size: 24)
                Text(Format.compact(amount)).font(Theme.title(30)).monospacedDigit()
            }
        }
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
                Button("+20 wisps") { game.debugAdd(wisps: 20) }
                Button("Wanderer now") { game.debugWandererNow() }
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
