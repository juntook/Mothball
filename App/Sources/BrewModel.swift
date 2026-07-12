// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Homebrew services state (SPEC §5.11). Nil client means brew isn't
/// installed — the tab shows an empty state, never an error.
@MainActor
@Observable
final class BrewModel {
    private(set) var services: [BrewService] = []
    private(set) var brewInstalled = true
    /// Non-nil when brew exists but listing failed — shown as an error
    /// state, never silently as "no services".
    private(set) var loadError: String?
    private(set) var isRefreshing = false
    private(set) var busyNames: Set<String> = []
    var actionError: String?

    private let auditLog = AuditLog()

    private enum ListOutcome: Sendable {
        case notInstalled
        case listed([BrewService])
        case failed(String)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ListOutcome in
                guard let binary = BrewServicesClient.resolveBinary() else { return .notInstalled }
                do {
                    return .listed(try BrewServicesClient(binary: binary).list())
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
            switch outcome {
            case .notInstalled:
                brewInstalled = false
                services = []
                loadError = nil
            case .listed(let result):
                brewInstalled = true
                loadError = nil
                services = result.sorted {
                    ($0.isRunning ? 0 : 1, $0.name) < ($1.isRunning ? 0 : 1, $1.name)
                }
            case .failed(let message):
                brewInstalled = true
                services = []
                loadError = message
            }
            isRefreshing = false
        }
    }

    /// Stop this instance only; login registration is kept (SPEC §5.11).
    func stopOnce(_ service: BrewService) {
        perform(service, method: "brew-kill") { try $0.stopOnce($1) }
    }

    /// Stop and unregister from login.
    func stopAndDisable(_ service: BrewService) {
        perform(service, method: "brew-stop") { try $0.stopAndDisable($1) }
    }

    /// Start once without registering at login.
    func startOnce(_ service: BrewService) {
        perform(service, method: "brew-run") { try $0.runOnce($1) }
    }

    private func perform(
        _ service: BrewService,
        method: String,
        _ operation: @escaping @Sendable (BrewServicesClient, String) throws -> Void
    ) {
        guard !busyNames.contains(service.name) else { return }
        busyNames.insert(service.name)
        let name = service.name
        Task {
            let failure: String? = await Task.detached { () -> String? in
                guard let binary = BrewServicesClient.resolveBinary() else { return "brew not found" }
                do {
                    try operation(BrewServicesClient(binary: binary), name)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            busyNames.remove(name)
            auditLog.append(.init(
                ruleID: "homebrew-services",
                targetID: method,
                path: name,
                bytes: nil,
                method: method,
                result: failure ?? "ok"
            ))
            if let failure {
                actionError = failure
            } else {
                refresh()
            }
        }
    }
}
