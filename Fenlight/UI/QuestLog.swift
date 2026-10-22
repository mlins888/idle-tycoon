import SwiftUI

/// The quests in progress: who asked, what they want, how far along you are, and the reward.
struct QuestLog: View {
    let game: Game

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Quests").font(Theme.title(24))
                        Spacer()
                        Text("\(game.state.completedQuests.count) done")
                            .font(Theme.body(13, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }
                    .padding(.top, 20)

                    ForEach(game.activeQuests) { q in
                        QuestCard(game: game, quest: q)
                    }
                    if game.activeQuests.isEmpty {
                        Text("No one needs anything right now. As the town grows and more folk move in, they'll come to you.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.text)
    }
}

private struct QuestCard: View {
    let game: Game
    let quest: QuestDef

    var body: some View {
        let giver = game.content.resident(quest.giver)
        let progress = game.progress(quest)
        let ready = game.isReady(quest)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let giver { Portrait(def: giver, size: 40) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(quest.title).font(Theme.body(16, weight: .bold))
                    if let giver {
                        Text(giver.name).font(Theme.body(12)).foregroundStyle(Theme.textDim)
                    }
                }
            }
            Text(ready ? quest.doneText : quest.text)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textDim)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
            if !ready {
                ProgressView(value: progress.current / max(1, progress.target))
                    .tint(Theme.lantern)
                Text(progressText(progress))
                    .font(Theme.body(12, weight: .semibold))
                    .monospacedDigit()
            }
            RewardRow(reward: quest.reward)
            if ready {
                Button {
                    if game.claimQuest(quest.id) { Haptics.celebrate() }
                } label: {
                    Text("Claim reward").frame(maxWidth: .infinity)
                }
                .buttonStyle(FenButtonStyle(prominent: true))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.button.opacity(ready ? 1 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ready ? Theme.lantern : .clear, lineWidth: 1.5))
    }

    private func progressText(_ p: (current: Double, target: Double)) -> String {
        switch quest.objective {
        case .collect: return "\(Format.compact(p.current)) / \(Format.compact(p.target)) glimmer"
        case .stage: return "Not yet"
        default: return "\(Int(p.current)) / \(Int(p.target))"
        }
    }
}

struct RewardRow: View {
    let reward: Reward

    var body: some View {
        HStack(spacing: 12) {
            Text("REWARD")
                .font(Theme.body(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)
            if reward.glimmer > 0 {
                HStack(spacing: 4) { GlimmerIcon(size: 13); Text(Format.compact(reward.glimmer)) }
            }
            if reward.wisps > 0 {
                HStack(spacing: 4) { WispIcon(size: 13); Text("\(Int(reward.wisps))") }
            }
            if reward.xp > 0 {
                Text("\(Int(reward.xp)) XP")
            }
        }
        .font(Theme.body(13, weight: .bold))
        .monospacedDigit()
    }
}

/// A generic popup card for announcements that aren't about a resident.
struct NoticeCard: View {
    let eyebrow: String
    let title: String
    let message: String
    var detail: String?
    var button: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(eyebrow.uppercased())
                .font(Theme.body(11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.lantern)
            Text(title)
                .font(Theme.title(21))
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.moss)
                    .multilineTextAlignment(.center)
            }
            Button(action: onDismiss) {
                Text(button).frame(maxWidth: .infinity)
            }
            .buttonStyle(FenButtonStyle(prominent: true))
        }
        .padding(6)
        .fenPanel()
        .padding(.horizontal, 32)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
