// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Dev-session state and the end-session orchestration (SPEC §5.13):
/// preview → graceful process stops → container stops → summary. Protected
/// resources never enter the batch; SIGKILL is never sent from here.
@MainActor
@Observable
final class SessionModel {
    enum Phase: Equatable {
        case idle
        case confirming
        case running
        case finished
    }

    struct StepResult: Identifiable, Equatable {
        enum Outcome: Equatable {
            case stopped
            case stillRunning
            case skippedProtected
            case failed(String)
        }

        let id: String
        let name: String
        let detail: String
        let outcome: Outcome
    }

    private(set) var sessions: [DevSession] = []
    private(set) var templates: [SessionTemplate] = []

    /// Session in the end-confirmation sheet.
    var pendingEnd: DevSession?
    private(set) var phase: Phase = .idle
    private(set) var stepResults: [StepResult] = []
    /// Step currently executing, for the progress UI.
    private(set) var runningStepName: String?
    /// Set when the user asked to clean the project's artifacts afterwards.
    var cleanupProjectPathAfterEnd: String?

    private let templateStore = SessionTemplateStore()
    private let auditLog = AuditLog()

    init() {
        templates = templateStore.load()
    }

    func rebuild(projects: [Project], services: [RunningService], containers: [ContainerResource]) {
        sessions = SessionResolver().resolve(projects: projects, services: services, containers: containers)
    }

    // MARK: Templates

    func saveTemplate(named name: String, for session: DevSession) {
        templateStore.add(SessionTemplate(name: name, projectPath: session.projectPath))
        templates = templateStore.load()
    }

    func removeTemplate(_ template: SessionTemplate) {
        templateStore.remove(named: template.name)
        templates = templateStore.load()
    }

    func session(forProjectPath path: String) -> DevSession? {
        sessions.first { $0.projectPath == path }
    }

    // MARK: End flow

    func beginConfirmation(_ session: DevSession) {
        pendingEnd = session
        stepResults = []
        phase = .confirming
    }

    func dismiss() {
        pendingEnd = nil
        phase = .idle
        stepResults = []
        runningStepName = nil
    }

    /// Executes the confirmed plan. Stops processes first (SIGTERM + grace),
    /// then containers; every step is audited and reported individually so
    /// partial failure stays actionable (SPEC §5.13).
    func endSession(
        services: [RunningService],
        containers: [ContainerResource],
        dockerBinary: String?
    ) {
        guard phase == .confirming else { return }
        phase = .running
        stepResults = []

        Task {
            var results: [StepResult] = []
            let stopper = ServiceStopper()

            for service in services {
                runningStepName = service.name
                let result = await stopper.stop(service)
                audit(kind: "process", name: "pid:\(service.pid) \(service.name)", result: "\(result)")
                let outcome: StepResult.Outcome = switch result {
                case .terminated, .alreadyGone: .stopped
                case .stillRunning: .stillRunning
                case .pidReused: .failed("pid reused")
                case .signalFailed: .failed("signal failed")
                }
                results.append(StepResult(
                    id: "p\(service.pid)",
                    name: service.name,
                    detail: service.listeningPorts.map { ":\($0)" }.joined(separator: " "),
                    outcome: outcome
                ))
            }

            for container in containers {
                runningStepName = container.name
                let containerID = container.id.components(separatedBy: ":").dropFirst().joined(separator: ":")
                let failure: String? = await Task.detached { () -> String? in
                    guard let dockerBinary else { return "docker not found" }
                    do {
                        try DockerClient(binary: dockerBinary).stopContainer(id: containerID)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                audit(kind: "container", name: container.name, result: failure ?? "ok")
                results.append(StepResult(
                    id: "c\(container.id)",
                    name: container.name,
                    detail: container.detail,
                    outcome: failure.map { .failed($0) } ?? .stopped
                ))
            }

            runningStepName = nil
            stepResults = results
            phase = .finished
        }
    }

    func recordSkippedProtected(_ name: String, detail: String) {
        stepResults.append(StepResult(id: "s\(name)", name: name, detail: detail, outcome: .skippedProtected))
    }

    private func audit(kind: String, name: String, result: String) {
        auditLog.append(.init(
            ruleID: "session",
            targetID: kind,
            path: name,
            bytes: nil,
            method: "session-end",
            result: result
        ))
    }
}
