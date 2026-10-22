import SwiftUI
import UIKit

/// UI colours, fonts and panel art in one place. When real UI art exists, add images named
/// `ui.panel` and `ui.button` to Assets.xcassets and they replace the drawn shapes (see docs/ART_SPEC.md).
enum Theme {
    static let panel = Color(hex: "#18211E").opacity(0.94)
    static let panelStroke = Color(hex: "#3E4D44")
    static let text = Color(hex: "#F3EEDC")
    static let textDim = Color(hex: "#A9B3A3")
    static let lantern = Color(hex: "#F2B544")
    static let lanternInk = Color(hex: "#2A1B00")
    static let moss = Color(hex: "#8CCB72")
    static let ember = Color(hex: "#E0654A")
    static let button = Color(hex: "#2C3833")
    static let wisp = Color(hex: "#7FE3D6")

    static func rarity(_ r: Rarity) -> Color {
        switch r {
        case .common: return Color(hex: "#C9CFC2")
        case .uncommon: return Color(hex: "#8CCB72")
        case .rare: return Color(hex: "#7FB8F0")
        case .legendary: return Color(hex: "#F2B544")
        }
    }

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let hasPanelArt = UIImage(named: "ui.panel") != nil
    static let hasButtonArt = UIImage(named: "ui.button") != nil
    /// How much of the edges of the panel/button art stays unstretched.
    static let artCapInsets = EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

/// The dark, mossy panel used for every HUD card.
struct FenPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background {
                if Theme.hasPanelArt {
                    Image("ui.panel").resizable(capInsets: Theme.artCapInsets)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.panelStroke, lineWidth: 1))
                }
            }
            .foregroundStyle(Theme.text)
    }
}

extension View {
    func fenPanel() -> some View { modifier(FenPanel()) }
}

struct FenButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        FenButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct FenButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.body(15, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .foregroundStyle(prominent ? Theme.lanternInk : Theme.text)
                .background {
                    if Theme.hasButtonArt {
                        Image("ui.button").resizable(capInsets: Theme.artCapInsets)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(prominent ? Theme.lantern : Theme.button)
                    }
                }
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// A small glowing wisp used next to wisp amounts.
struct WispIcon: View {
    var size: CGFloat = 16
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white, Theme.wisp, Theme.wisp.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size * 0.55))
            .frame(width: size, height: size)
    }
}

/// A small drawn coin used next to glimmer amounts.
struct GlimmerIcon: View {
    var size: CGFloat = 16
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: "#FFF1C2"), Theme.lantern], center: .init(x: 0.35, y: 0.3),
                                 startRadius: 0, endRadius: size * 0.6))
            .overlay(Circle().stroke(Color(hex: "#8A5B00"), lineWidth: 1))
            .frame(width: size, height: size)
    }
}
