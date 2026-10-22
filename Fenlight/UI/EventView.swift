import SwiftUI

/// A strip under the top bar while a festival is running: name, days left, tokens. Tap for the reward track.
struct EventBanner: View {
    let game: Game
    let event: EventDef
    var onTap: () -> Void

    var body: some View {
        let progress = game.eventProgress(event)
        let next = event.milestones.indices.contains(progress.reached) ? event.milestones[progress.reached] : nil
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: event.color)).frame(width: 12, height: 12)
                    .shadow(color: Color(hex: event.color), radius: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.name).font(Theme.body(14, weight: .bold))
                    Text(game.eventTimeLeft.map { "\(Format.days($0)) left" } ?? "")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(progress.tokens)) \(progress.tokens == 1 ? event.token : event.tokens)")
                        .font(Theme.body(13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: event.color))
                    if let next {
                        Text("Next reward at \(Int(next.tokens))")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: event.color).opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .accessibilityLabel("\(event.name), \(Int(progress.tokens)) \(event.tokens). Show rewards")
    }
}

/// The festival's reward track.
struct EventView: View {
    let game: Game
    let event: EventDef

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let progress = game.eventProgress(event)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.name).font(Theme.title(26))
                        if let left = game.eventTimeLeft {
                            Text("\(Format.days(left)) left · back every year \(dateRange)")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(Color(hex: event.color))
                        }
                        Text(event.blurb)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 20)

                    Text("Collect from a shop that's at least a quarter full to earn 1 \(event.token). Keepers don't earn \(event.tokens), so check in by hand.")
                        .font(Theme.body(13))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.button.opacity(0.6)))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("You have").font(Theme.body(14))
                        Text("\(Int(progress.tokens)) \(event.tokens)")
                            .font(Theme.body(16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color(hex: event.color))
                    }

                    ForEach(Array(event.milestones.enumerated()), id: \.offset) { i, m in
                        milestoneRow(m, reached: i < progress.reached, tokens: progress.tokens)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var dateRange: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2001, month: event.start.month, day: event.start.day))!
        let end = cal.date(from: DateComponents(year: 2001, month: event.end.month, day: event.end.day))!
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private func milestoneRow(_ m: Milestone, reached: Bool, tokens: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(reached ? Color(hex: event.color) : Theme.button)
                if reached {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.lanternInk)
                } else {
                    Text("\(Int(m.tokens))").font(Theme.body(12, weight: .bold)).monospacedDigit()
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(EventRewards.describe(m.reward, game.content))
                    .font(Theme.body(14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !reached {
                    ProgressView(value: min(1, tokens / m.tokens))
                        .tint(Color(hex: event.color))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.button.opacity(reached ? 0.9 : 0.5)))
    }
}

enum EventRewards {
    /// e.g. "Gourd Lanterns (festival decoration) · 5 wisps"
    static func describe(_ r: EventReward, _ content: GameContent) -> String {
        var parts: [String] = []
        if let id = r.resident { parts.append("\(content.resident(id)?.name ?? id) moves in") }
        if let id = r.decoration { parts.append("\(content.building(id)?.name ?? id) (festival decoration)") }
        if r.glimmer > 0 { parts.append("\(Format.compact(r.glimmer)) glimmer") }
        if r.wisps > 0 { parts.append("\(Int(r.wisps)) wisps") }
        return parts.joined(separator: " · ")
    }
}
