import SwiftUI

/// Everyone there is to find. Folk you haven't met yet are silhouettes with a hint about how to meet them.
struct RegistryGrid: View {
    let game: Game

    var body: some View {
        let order: [ArrivalKind] = [.story, .wanderer, .summon]
        let sorted = game.content.residents.sorted {
            (order.firstIndex(of: $0.arrival)!, $0.unlockLevel, $0.rarity) < (order.firstIndex(of: $1.arrival)!, $1.unlockLevel, $1.rarity)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(sorted) { r in
                card(r, found: game.resident(r.id) != nil)
            }
        }
    }

    private func card(_ r: ResidentDef, found: Bool) -> some View {
        VStack(spacing: 6) {
            if found {
                Portrait(def: r, size: 56)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .overlay(Text("?").font(Theme.title(24)).foregroundStyle(Theme.textDim))
                    .frame(width: 56, height: 56)
            }
            Text(found ? r.name : "???")
                .font(Theme.body(12, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(r.rarity.rawValue.capitalized)
                .font(Theme.body(10, weight: .bold))
                .foregroundStyle(Theme.rarity(r.rarity))
            Text(found ? r.folk : hint(r))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.button.opacity(found ? 0.8 : 0.4)))
    }

    private func hint(_ r: ResidentDef) -> String {
        switch r.arrival {
        case .story:
            return r.unlockLevel > game.level ? "Arrives at level \(r.unlockLevel)" : "Waiting for a free bed"
        case .wanderer:
            return r.unlockLevel > game.level ? "May wander in from level \(r.unlockLevel)" : "Might wander in when a bed is free"
        case .summon:
            return "Summon at the Wisp Shrine"
        }
    }
}

/// Shown when you tap a resident on the map: who they are, where they live and work, and a job picker.
struct ResidentPanel: View {
    let game: Game
    let ui: MapInteraction
    let def: ResidentDef

    var body: some View {
        let resident = game.resident(def.id)
        let home = resident.flatMap { game.building(id: $0.homeId) }
        let work = resident?.workId.flatMap { game.building(id: $0) }
        let favorite = game.content.building(def.favoriteShop)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Portrait(def: def, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(def.name).font(Theme.title(19))
                        Text(def.rarity.rawValue.capitalized)
                            .font(Theme.body(10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.rarity(def.rarity).opacity(0.2)))
                            .foregroundStyle(Theme.rarity(def.rarity))
                    }
                    Text(def.folk).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
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
            VStack(alignment: .leading, spacing: 3) {
                if let home { Text("Lives in the \(game.name(home))").font(Theme.body(13)) }
                Text(work.map { "Works at the \(game.name($0))" } ?? "Not working")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(work == nil ? Theme.textDim : Theme.moss)
                if let favorite {
                    Text("♥ Loves the \(favorite.name) (+\(Int(Economy.workerBonus(isFavorite: true) * 100))% there)")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.lantern)
                }
            }
            HStack(spacing: 10) {
                JobMenu(game: game, def: def, currentShop: work?.id)
                if work != nil {
                    Button("Stop working") { game.unassignWorker(def.id) }
                        .buttonStyle(FenButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fenPanel()
    }
}

/// A menu of shops to put this resident to work at. Their favourite kind of shop is listed first and marked ♥.
private struct JobMenu: View {
    let game: Game
    let def: ResidentDef
    let currentShop: Int?

    var body: some View {
        let shops = game.state.buildings
            .filter { game.def(for: $0)?.kind == .shop && $0.id != currentShop }
            .sorted { ($0.defId == def.favoriteShop ? 0 : 1) < ($1.defId == def.favoriteShop ? 0 : 1) }
        Menu {
            if shops.isEmpty { Text("No shops to work at yet") }
            ForEach(shops) { shop in
                let slots = game.def(for: shop)?.workerSlots ?? 0
                let full = game.workers(at: shop.id).count >= slots
                Button {
                    game.assignWorker(def.id, to: shop.id)
                } label: {
                    Text(game.name(shop) + (shop.defId == def.favoriteShop ? " ♥" : "") + (full ? " (full)" : ""))
                }
                .disabled(full)
            }
        } label: {
            Label(currentShop == nil ? "Give a job" : "Change job", systemImage: "briefcase.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FenButtonStyle(prominent: currentShop == nil))
    }
}
