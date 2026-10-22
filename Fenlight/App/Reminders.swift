import UserNotifications

/// Local notifications: "your shop is full" and "renovation finished". Scheduled when the app goes
/// to the background, cancelled when it comes back. No server involved.
@MainActor
enum Reminders {
    private static let id = "shop-full"
    private static let renovationId = "renovation-done"

    static func schedule(_ game: Game) {
        scheduleShopFull(game)
        scheduleRenovationDone(game)
    }

    static func scheduleRenovationDone(_ game: Game) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [renovationId])
        guard let next = game.nextRenovationDone() else { return }
        let content = UNMutableNotificationContent()
        content.title = "The \(next.name) is open"
        content.body = "The scaffolding's down. Come and see what's new."
        content.sound = .default
        let delay = max(1, next.date.timeIntervalSince(game.now))
        center.add(UNNotificationRequest(identifier: renovationId, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
    }

    /// Asks once. iOS remembers the answer, so calling again does nothing.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func scheduleShopFull(_ game: Game) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let next = game.nextShopFull() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your \(next.name) is full"
        content.body = "Its glimmer has stopped piling up. Come collect it before the gloom creeps back."
        content.sound = .default
        let delay = max(60, next.date.timeIntervalSince(game.now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id, renovationId])
    }
}
