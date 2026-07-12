// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation
import UserNotifications

/// Threshold notifications (SPEC §5.15). Only functional inside a real app
/// bundle — UserNotifications requires a bundle identifier, so bare
/// `swift run` sessions silently no-op. Every alert type is independently
/// switchable and rate-limited; notifications never trigger any action by
/// themselves.
@MainActor
@Observable
final class NotificationModel {
    /// UserNotifications needs a bundle; dev runs have none.
    let available = Bundle.main.bundleIdentifier != nil

    var spaceAlertEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifySpace") }
        set { UserDefaults.standard.set(newValue, forKey: "notifySpace"); if newValue { requestAuthorization() } }
    }

    var longRunningAlertEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notifyLongRunning") }
        set { UserDefaults.standard.set(newValue, forKey: "notifyLongRunning"); if newValue { requestAuthorization() } }
    }

    /// GB of reclaimable space that triggers the storage alert.
    var spaceThresholdGB: Int {
        get { max(1, UserDefaults.standard.object(forKey: "notifySpaceThresholdGB") as? Int ?? 10) }
        set { UserDefaults.standard.set(newValue, forKey: "notifySpaceThresholdGB") }
    }

    private var authorizationRequested = false

    private func requestAuthorization() {
        guard available, !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    /// Storage alert: at most once per week (SPEC §5.15 default cadence).
    func maybeNotifyReclaimable(totalBytes: Int64, loc: LocalizationModel) {
        guard available, spaceAlertEnabled else { return }
        guard totalBytes >= Int64(spaceThresholdGB) * 1_000_000_000 else { return }
        let key = "lastSpaceNotification"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 24 * 3600 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        post(
            title: loc.string("notify.space.title"),
            body: loc.string("notify.space.body %@", totalBytes.formatted(.byteCount(style: .file)))
        )
    }

    /// Long-running listener alert: at most once per day, one summary.
    func maybeNotifyLongRunning(services: [RunningService], loc: LocalizationModel) {
        guard available, longRunningAlertEnabled else { return }
        let cutoff = Date().addingTimeInterval(-8 * 3600)
        let longRunners = services.filter {
            !$0.listeningPorts.isEmpty && $0.startDate < cutoff && $0.startDate > .distantPast
        }
        guard !longRunners.isEmpty else { return }
        let key = "lastLongRunningNotification"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        post(
            title: loc.string("notify.longRunning.title"),
            body: loc.string("notify.longRunning.body %lld", longRunners.count)
        )
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
