import SwiftUI

/// A short message under the top bar, e.g. "+3 wisps · cleansed the murk". Disappears on its own.
struct ToastView: View {
    let toast: Toast
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            WispIcon(size: 16)
            Text(toast.text)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.wisp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Theme.wisp.opacity(0.5), lineWidth: 1))
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(2.5))
            onDone()
        }
    }
}

/// What wisps are, where they come from and what they're for.
struct WispInfoView: View {
    let game: Game

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    WispIcon(size: 30)
                    Text("Wisps").font(Theme.title(24))
                    Spacer()
                    Text("You have \(Int(game.state.wisps))")
                        .font(Theme.body(14, weight: .bold))
                        .foregroundStyle(Theme.wisp)
                }
                .padding(.top, 20)
                Text("Wisps are the fen's lost lights, scattered when the Lantern Thief came. They're rare, so spend them carefully.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                section("Where they come from", [
                    ("sparkles", "Every so often a lost wisp drifts over town. Tap it before it fades to catch it."),
                    ("leaf", "Cleansing a patch of murk frees \(Int(Economy.wispsPerCleanse))."),
                    ("star", "Each new town level brings \(Int(Economy.wispsPerLevel))."),
                    ("scroll", "Some quests and festival rewards give wisps."),
                ])
                section("What they're for", [
                    ("sparkle.magnifyingglass", "Summoning rare residents at the Wisp Shrine (\(Int(Economy.summonCost)) each)."),
                    ("hammer", "Finishing a renovation early (1 per 10 minutes left)."),
                ])
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.text)
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.body(11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.textDim)
            ForEach(rows, id: \.1) { icon, text in
                Label {
                    Text(text).font(Theme.body(14)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: icon).foregroundStyle(Theme.wisp)
                }
            }
        }
    }
}
