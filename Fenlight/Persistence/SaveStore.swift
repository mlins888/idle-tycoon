import Foundation

/// Reads and writes the save file (JSON in Application Support).
final class SaveStore {
    let url: URL

    init(url: URL = SaveStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fenlight", isDirectory: true)
            .appendingPathComponent("save.json")
    }

    func load() -> GameState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let state = try JSONDecoder().decode(GameState.self, from: data)
            return migrate(state)
        } catch {
            print("Fenlight: save file could not be read, starting fresh: \(error)")
            return nil
        }
    }

    func save(_ state: GameState) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            print("Fenlight: save failed: \(error)")
        }
    }

    /// Upgrades older save formats. Add a step here whenever `GameState.currentVersion` goes up.
    private func migrate(_ state: GameState) -> GameState {
        var s = state
        s.version = GameState.currentVersion
        return s
    }
}
