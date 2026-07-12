// SPDX-License-Identifier: Apache-2.0
import Foundation
import Observation
import Sparkle

/// Sparkle wiring. The updater only functions inside a signed .app bundle with
/// SUFeedURL/SUPublicEDKey set (scripts/release.sh); in a bare SwiftPM dev run
/// the menu item stays disabled instead of erroring.
@MainActor
@Observable
final class UpdaterModel {
    private let controller: SPUStandardUpdaterController

    /// True when running from a real bundle where updating can work.
    let updatingSupported: Bool

    init() {
        updatingSupported = Bundle.main.bundleIdentifier != nil
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(
            startingUpdater: updatingSupported,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        updatingSupported && controller.updater.canCheckForUpdates
    }

    /// Sparkle's scheduled background check (user still confirms installs).
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Fully automatic download + install on quit.
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
