import SwiftUI

/// A resident's portrait (their art if it exists, otherwise initials on their colour).
struct Portrait: View {
    let def: ResidentDef
    var size: CGFloat = 44

    var body: some View {
        Image(uiImage: ArtCatalog.shared.portrait(def))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Everyone in town, where they live and work, and who's coming next.
struct ResidentsView: View {
    let game: Game

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Townsfolk").font(Theme.title(24))
                        Spacer()
                        Text("\(game.state.residents.count)/\(game.totalBeds) beds")
                            .font(Theme.body(13, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }
                    .padding(.top, 20)

                    arrivals

                    ForEach(game.residentDefs) { r in
                        row(r)
                    }
                    if game.state.residents.isEmpty {
                        Text("No one lives here yet. Build a house and they'll come.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.text)
    }

    @ViewBuilder
    private var arrivals: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ON THE WAY")
                .font(Theme.body(12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.textDim)
            ForEach(game.waitingForBed) { r in
                note("\(r.name) wants to move in. Build a house to give them a bed.", color: Theme.lantern)
            }
            if let next = game.state.nextWandererAt {
                let wait = max(0, next.timeIntervalSince(game.now))
                note("Someone is on the road. They'll arrive in about \(Format.duration(wait)).", color: Theme.text)
            } else if game.freeBeds <= 0 {
                note("Every bed is taken. Build a house so wanderers can stay.", color: Theme.textDim)
            }
            if let story = game.upcomingStory.first {
                note("\(story.name) will come when the town reaches level \(story.unlockLevel).", color: Theme.textDim)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.button.opacity(0.6)))
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ r: ResidentDef) -> some View {
        let resident = game.resident(r.id)
        let workplace = resident?.workId.flatMap { game.building(id: $0) }
        let workDef = workplace.flatMap { game.def(for: $0) }
        let favorite = game.content.building(r.favoriteShop)

        return HStack(alignment: .top, spacing: 12) {
            Portrait(def: r, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.name).font(Theme.body(16, weight: .bold))
                    Text(r.rarity.rawValue.capitalized)
                        .font(Theme.body(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.rarity(r.rarity).opacity(0.2)))
                        .foregroundStyle(Theme.rarity(r.rarity))
                }
                Text(r.folk).font(Theme.body(12, weight: .semibold)).foregroundStyle(Theme.textDim)
                Text(r.blurb)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text(workDef.map { "Works at \($0.name)" } ?? "Not working")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(workDef == nil ? Theme.textDim : Theme.moss)
                if let favorite {
                    Text("♥ Loves the \(favorite.name)")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.lantern)
                }
                if workDef != nil {
                    Button("Stop working") { game.unassignWorker(r.id) }
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.button.opacity(0.6)))
    }
}

/// "Someone moved in!" card, shown over the map when a resident arrives.
struct ArrivalCard: View {
    let def: ResidentDef
    var title = "moved in!"
    var subtitle: String?
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Portrait(def: def, size: 84)
            Text("\(def.name) \(title)")
                .font(Theme.title(20))
                .multilineTextAlignment(.center)
            Text(def.folk)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.rarity(def.rarity))
            Text(subtitle ?? def.blurb)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Text("Welcome to Fenlight").frame(maxWidth: .infinity)
            }
            .buttonStyle(FenButtonStyle(prominent: true))
        }
        .padding(6)
        .fenPanel()
        .padding(.horizontal, 32)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
