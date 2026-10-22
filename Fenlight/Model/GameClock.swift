import Foundation

/// The one source of "now" for the game. Tests pass a fixed date; the debug menu
/// adds an offset to fast-forward time.
final class GameClock {
    var offset: TimeInterval = 0
    private let base: () -> Date

    init(base: @escaping () -> Date = Date.init) {
        self.base = base
    }

    var now: Date { base().addingTimeInterval(offset) }
}
