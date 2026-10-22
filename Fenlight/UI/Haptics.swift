import UIKit

/// Small taps of vibration for key moments.
@MainActor
enum Haptics {
    static func collect() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func build() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func celebrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
