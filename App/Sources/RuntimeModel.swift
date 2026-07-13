// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Runtime view state: process discovery + the graceful stop flow (SPEC §5.4),
/// plus CPU sampling by snapshot differencing (SPEC §5.10). Sampling only
/// happens while a runtime page drives `refresh()`; there is no background
/// polling loop in this model.
@MainActor
@Observable
final class RuntimeModel {
    private(set) var services: [RunningService] = []
    private(set) var isRefreshing = false
    /// pid → instantaneous CPU usage in percent (one core = 100).
    private(set) var cpuPercents: [Int32: Double] = [:]
    /// pids with a stop in flight.
    private(set) var stoppingPIDs: Set<Int32> = []
    /// A stop that outlived the grace period; the UI offers force kill.
    var pendingForceKill: RunningService?
    /// A stop aborted because the pid was recycled.
    var staleServiceNotice = false

    private let auditLog = AuditLog()
    /// pid → (cumulative CPU nanos, sample time) from the previous refresh.
    private var cpuSamples: [Int32: (nanos: UInt64, at: Date)] = [:]
    /// Refresh requested while one was in flight — replayed on completion so
    /// an action finishing mid-refresh never loses its trailing refresh.
    private var queuedRefreshProjects: [Project]?

    func refresh(projects: [Project]) {
        guard !isRefreshing else {
            queuedRefreshProjects = projects
            return
        }
        isRefreshing = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                RuntimeScanner().discover(projects: projects)
            }.value
            updateCPUSamples(found)
            services = found
            isRefreshing = false
            if let queued = queuedRefreshProjects {
                queuedRefreshProjects = nil
                refresh(projects: queued)
            }
        }
    }

    private func updateCPUSamples(_ found: [RunningService]) {
        let now = Date()
        var next: [Int32: (nanos: UInt64, at: Date)] = [:]
        var percents: [Int32: Double] = [:]
        for service in found {
            guard let nanos = service.cpuTimeNanos else { continue }
            next[service.pid] = (nanos, now)
            if let previous = cpuSamples[service.pid], nanos >= previous.nanos {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.5 {
                    let used = Double(nanos - previous.nanos) / 1_000_000_000
                    percents[service.pid] = min(used / elapsed * 100, 999)
                }
            }
        }
        cpuSamples = next
        cpuPercents = percents
    }

    /// Direct children in the current snapshot (SPEC §5.10 process tree).
    func children(of service: RunningService) -> [RunningService] {
        services.filter { $0.parentPID == service.pid }
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

    /// Stops a whole subtree, children before parents (SPEC §5.10). Any
    /// member that survives its grace period surfaces the force-kill dialog.
    func stopTree(_ root: RunningService, projects: [Project]) {
        let targets = subtree(of: root)
        guard stoppingPIDs.isDisjoint(with: targets.map(\.pid)) else { return }
        for target in targets { stoppingPIDs.insert(target.pid) }
        Task {
            let stopper = ServiceStopper()
            var survivor: RunningService?
            for target in targets {
                let result = await stopper.stop(target)
                audit(target, action: "stop-tree", result: result)
                if result == .stillRunning && survivor == nil { survivor = target }
                if result == .pidReused { staleServiceNotice = true }
            }
            for target in targets { stoppingPIDs.remove(target.pid) }
            if let survivor { pendingForceKill = survivor }
            refresh(projects: projects)
        }
    }

    /// Depth-first subtree, deepest descendants first so children stop
    /// before their parents.
    private func subtree(of root: RunningService) -> [RunningService] {
        var ordered: [RunningService] = []
        func visit(_ node: RunningService) {
            for child in children(of: node) { visit(child) }
            ordered.append(node)
        }
        visit(root)
        return ordered
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
