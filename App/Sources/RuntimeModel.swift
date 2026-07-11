// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Runtime view state: process discovery + the graceful stop flow (SPEC §5.4).
@MainActor
@Observable
final class RuntimeModel {
    private(set) var services: [RunningService] = []
    private(set) var isRefreshing = false
    /// pids with a stop in flight.
    private(set) var stoppingPIDs: Set<Int32> = []
    /// A stop that outlived the grace period; the UI offers force kill.
    var pendingForceKill: RunningService?
    /// A stop aborted because the pid was recycled.
    var staleServiceNotice = false

    private let auditLog = AuditLog()

    func refresh(projects: [Project]) {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                RuntimeScanner().discover(projects: projects)
            }.value
            services = found
            isRefreshing = false
        }
    }

    func stop(_ service: RunningService, projects: [Project]) {
        guard !stoppingPIDs.contains(service.pid) else { return }
        stoppingPIDs.insert(service.pid)
        Task {
            let result = await ServiceStopper().stop(service)
            stoppingPIDs.remove(service.pid)
            audit(service, action: "stop", result: result)
            switch result {
            case .stillRunning:
                pendingForceKill = service
            case .pidReused:
                staleServiceNotice = true
                refresh(projects: projects)
            case .terminated, .alreadyGone, .signalFailed:
                refresh(projects: projects)
            }
        }
    }

    func forceKill(_ service: RunningService, projects: [Project]) {
        stoppingPIDs.insert(service.pid)
        pendingForceKill = nil
        Task {
            let result = await ServiceStopper().forceKill(service)
            stoppingPIDs.remove(service.pid)
            audit(service, action: "force-kill", result: result)
            if result == .pidReused { staleServiceNotice = true }
            refresh(projects: projects)
        }
    }

    private func audit(_ service: RunningService, action: String, result: ServiceStopper.StopResult) {
        auditLog.append(.init(
            ruleID: "runtime",
            targetID: action,
            path: "pid:\(service.pid) \(service.name)",
            bytes: nil,
            method: "stop",
            result: "\(result)"
        ))
    }
}
