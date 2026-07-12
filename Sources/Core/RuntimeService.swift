// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Loads the community-maintained process exclusion list
/// (`rules/system-exclusions.json`) from the Core bundle.
public struct SystemExclusions: Sendable {
    public let excludedProcessNames: Set<String>

    public init(excludedProcessNames: Set<String>) {
        self.excludedProcessNames = excludedProcessNames
    }

    public static func loadBundled() -> SystemExclusions {
        struct FileShape: Decodable {
            var excludedProcessNames: [String]
        }
        guard
            let url = CoreResources.bundle.url(forResource: "system-exclusions", withExtension: "json", subdirectory: "rules")
                ?? CoreResources.bundle.url(forResource: "system-exclusions", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(FileShape.self, from: data)
        else {
            return SystemExclusions(excludedProcessNames: [])
        }
        return SystemExclusions(excludedProcessNames: Set(decoded.excludedProcessNames))
    }
}

/// Turns raw process snapshots into the Runtime view's service list (SPEC §5.4):
/// current-user processes that either listen on a TCP port or have a cwd
/// attributed to a discovered project, minus the system exclusion list and
/// Mothball itself.
public struct RuntimeScanner: Sendable {
    private let provider: any ProcessProvider
    private let exclusions: SystemExclusions

    public init(
        provider: any ProcessProvider = LibprocProcessProvider(),
        exclusions: SystemExclusions = .loadBundled()
    ) {
        self.provider = provider
        self.exclusions = exclusions
    }

    public func discover(projects: [Project], fs: any FileSystem = RealFileSystem()) -> [RunningService] {
        let attribution = AttributionEngine(projects: projects, fs: fs)
        let selfPID = getpid()
        return provider.currentUserProcesses().compactMap { snapshot in
            guard snapshot.pid != selfPID else { return nil }
            guard !exclusions.excludedProcessNames.contains(snapshot.name) else { return nil }

            let cwdAttribution = snapshot.workingDirectory.flatMap { attribution.attributeCwd($0) }
            guard !snapshot.listeningTCPPorts.isEmpty || cwdAttribution != nil else { return nil }

            return RunningService(
                pid: snapshot.pid,
                name: snapshot.name,
                executablePath: snapshot.executablePath,
                listeningPorts: snapshot.listeningTCPPorts,
                workingDirectory: snapshot.workingDirectory,
                residentMemoryBytes: snapshot.residentMemoryBytes,
                startDate: snapshot.startDate,
                attribution: cwdAttribution,
                parentPID: snapshot.parentPID,
                cpuTimeNanos: snapshot.cpuTimeNanos
            )
        }
        .sorted { ($0.listeningPorts.first ?? .max) < ($1.listeningPorts.first ?? .max) }
    }
}

/// Graceful stop flow with PID-reuse protection (SPEC §5.4):
/// verify (pid, startDate) → SIGTERM → poll up to 5 s → report.
/// SIGKILL is a separate, explicitly confirmed call that re-verifies again.
public struct ServiceStopper: Sendable {
    public enum StopResult: Sendable, Equatable {
        case terminated
        /// Process survived SIGTERM through the grace window; UI may offer force kill.
        case stillRunning
        /// The pid now belongs to a different process (reuse) — aborted, refresh.
        case pidReused
        case alreadyGone
        case signalFailed
    }

    private let provider: any ProcessProvider
    private let pollInterval: Duration
    private let gracePeriod: Duration

    public init(
        provider: any ProcessProvider = LibprocProcessProvider(),
        pollInterval: Duration = .milliseconds(200),
        gracePeriod: Duration = .seconds(5)
    ) {
        self.provider = provider
        self.pollInterval = pollInterval
        self.gracePeriod = gracePeriod
    }

    public func stop(_ service: RunningService) async -> StopResult {
        switch verify(service) {
        case .gone: return .alreadyGone
        case .reused: return .pidReused
        case .match: break
        }

        guard provider.sendSignal(SIGTERM, to: service.pid) else { return .signalFailed }

        let deadline = ContinuousClock.now + gracePeriod
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            switch verify(service) {
            case .gone: return .terminated
            case .reused: return .terminated // original died; pid recycled
            case .match: continue
            }
        }
        return .stillRunning
    }

    /// Explicit force kill after user confirmation (SPEC §5.4).
    public func forceKill(_ service: RunningService) async -> StopResult {
        switch verify(service) {
        case .gone: return .alreadyGone
        case .reused: return .pidReused
        case .match: break
        }
        guard provider.sendSignal(SIGKILL, to: service.pid) else { return .signalFailed }
        try? await Task.sleep(for: pollInterval)
        switch verify(service) {
        case .gone, .reused: return .terminated
        case .match: return .stillRunning
        }
    }

    private enum Verification { case match, gone, reused }

    /// (pid, startDate) must both match — the guard against PID reuse.
    private func verify(_ service: RunningService) -> Verification {
        guard let current = provider.snapshot(pid: service.pid) else { return .gone }
        // Same-second tolerance: start time is reported in whole seconds.
        let delta = abs(current.startDate.timeIntervalSince(service.startDate))
        return delta < 1.0 ? .match : .reused
    }
}
