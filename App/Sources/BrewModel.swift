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
    private(set) var isRefreshing = false
    private(set) var busyNames: Set<String> = []
    var actionError: String?

    private let auditLog = AuditLog()

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [BrewService]? in
                guard let binary = BrewServicesClient.resolveBinary() else { return nil }
                return (try? BrewServicesClient(binary: binary).list()) ?? []
            }.value
            if let result {
                brewInstalled = true
                services = result.sorted {
                    ($0.isRunning ? 0 : 1, $0.name) < ($1.isRunning ? 0 : 1, $1.name)
                }
            } else {
                brewInstalled = false
                services = []
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
