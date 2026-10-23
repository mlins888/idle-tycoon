import SwiftUI

/// Who's speaking a line: their name, colour and portrait (nil for the narrator).
struct Speaker {
    let name: String
    let color: Color
    let portrait: UIImage?

    @MainActor
    static func resolve(_ id: String, _ game: Game) -> Speaker {
        switch id {
        case "narrator":
            return Speaker(name: "", color: Theme.textDim, portrait: nil)
        case "player":
            let p = game.state.player
            return Speaker(name: p.name, color: Color(hex: p.color),
                           portrait: ArtCatalog.shared.portrait(id: "player", name: p.name, color: p.color))
        default:
            if let r = game.content.resident(id) {
                return Speaker(name: r.name, color: Color(hex: r.color), portrait: ArtCatalog.shared.portrait(r))
            }
            if let c = game.content.character(id) {
                return Speaker(name: c.name, color: Color(hex: c.color),
                               portrait: ArtCatalog.shared.portrait(id: "character.\(c.id)", name: c.name, color: c.color))
            }
            return Speaker(name: id, color: Theme.ember, portrait: nil)
        }
    }
}

/// Plays a dialogue scene over the map: portraits on the left and right, the speaker's name and line
/// in a box at the bottom. Tap to go on; choices appear after the last line.
struct SceneView: View {
    let game: Game
    let scene: SceneDef

    @State private var index = 0
    @State private var left: String?
    @State private var right: String?
    @State private var skipArmed = false

    private var line: SceneLine { scene.lines[min(index, scene.lines.count - 1)] }
    private var isLast: Bool { index >= scene.lines.count - 1 }

    var body: some View {
        let speaker = Speaker.resolve(line.speaker, game)
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    portrait(left)
                    Spacer(minLength: 0)
                    portrait(right)
                }
                .padding(.horizontal, 12)
                HStack {
                    Spacer()
                    Button(skipArmed ? "Tap again to skip" : "Skip") { skip() }
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(skipArmed ? Theme.lantern : Theme.textDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .accessibilityHint("Skips to the end of this scene")
                }
                dialogBox(speaker)
                if isLast && !scene.choices.isEmpty {
                    choices
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear { place(line.speaker) }
        .onChange(of: index) { _, _ in place(line.speaker) }
        .animation(.easeInOut(duration: 0.25), value: index)
        .animation(.easeInOut(duration: 0.25), value: left)
        .animation(.easeInOut(duration: 0.25), value: right)
    }

    // MARK: Pieces

    @ViewBuilder
    private func portrait(_ id: String?) -> some View {
        if let id, let image = Speaker.resolve(id, game).portrait {
            let active = id == line.speaker
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .opacity(active ? 1 : 0.4)
                .scaleEffect(active ? 1 : 0.92, anchor: .bottom)
                .transition(.move(edge: id == left ? .leading : .trailing).combined(with: .opacity))
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 150, height: 150)
        }
    }

    private func dialogBox(_ speaker: Speaker) -> some View {
        let text = Story.render(line.text, player: game.state.player)
        let narrator = line.speaker == "narrator"
        return Button(action: advance) {
            VStack(alignment: .leading, spacing: 8) {
                if !speaker.name.isEmpty {
                    Text(speaker.name)
                        .font(Theme.title(17))
                        .foregroundStyle(speaker.color)
                }
                Text(text)
                    // Narration in the serif face (the rounded face has no italic).
                    .font(narrator ? .system(size: 17, design: .serif).italic() : Theme.body(17))
                    .foregroundStyle(narrator ? Theme.textDim : Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                    .transition(.opacity)
                if !(isLast && !scene.choices.isEmpty) {
                    HStack {
                        Spacer()
                        Image(systemName: isLast ? "checkmark" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(16)
            .background {
                // Solid, so nothing on the map shows through the text.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#18211E"))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(speaker.name.isEmpty ? Theme.panelStroke : speaker.color.opacity(0.6), lineWidth: 1.5))
            }
            .foregroundStyle(Theme.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speaker.name.isEmpty ? text : "\(speaker.name): \(text)")
        .accessibilityHint(isLast && !scene.choices.isEmpty ? "Choose below" : "Continue")
        .accessibilityIdentifier("sceneLine")
    }

    private var choices: some View {
        VStack(spacing: 8) {
            ForEach(Array(scene.choices.enumerated()), id: \.offset) { i, choice in
                Button {
                    game.finishScene(scene.id, choice: i)
                } label: {
                    Text(Story.render(choice.text, player: game.state.player))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FenButtonStyle(prominent: i == 0))
            }
        }
        .padding(.top, 10)
        .transition(.opacity)
    }

    // MARK: Actions

    private func advance() {
        skipArmed = false
        if isLast {
            if scene.choices.isEmpty { game.finishScene(scene.id) }
        } else {
            index += 1
        }
    }

    private func skip() {
        guard skipArmed else {
            skipArmed = true
            return
        }
        skipArmed = false
        if scene.choices.isEmpty {
            game.finishScene(scene.id)
        } else {
            index = scene.lines.count - 1
        }
    }

    /// Puts a new speaker on the left or right. The narrator doesn't take a side.
    private func place(_ id: String) {
        guard id != "narrator", id != left, id != right else { return }
        if left == nil { left = id }
        else if right == nil { right = id }
        // Replace whoever didn't speak last.
        else if let previous = previousSpeaker(), previous == left { right = id }
        else { left = id }
    }

    private func previousSpeaker() -> String? {
        scene.lines[..<min(index, scene.lines.count)].last { $0.speaker != "narrator" && $0.speaker != line.speaker }?.speaker
    }
}
