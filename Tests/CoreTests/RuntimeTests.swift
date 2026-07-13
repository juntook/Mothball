// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

/// Scriptable process world for filter and stop-flow tests.
final class FakeProcessProvider: ProcessProvider, @unchecked Sendable {
    var processes: [Int32: ProcessSnapshot] = [:]
    var signals: [(signal: Int32, pid: Int32)] = []
    /// Signal → pids that should die when receiving it.
    var diesOn: [Int32: Set<Int32>] = [:]
    var failSignals = false

    func currentUserProcesses() -> [ProcessSnapshot] { Array(processes.values) }
    func snapshot(pid: Int32) -> ProcessSnapshot? { processes[pid] }

    func sendSignal(_ signal: Int32, to pid: Int32) -> Bool {
        if failSignals { return false }
        signals.append((signal, pid))
        if diesOn[signal, default: []].contains(pid) {
            processes[pid] = nil
        }
        return true
    }
}

@Suite("Runtime scanner filtering")
struct RuntimeScannerTests {
    let projects = [Project(name: "webapp", path: "/Users/test/dev/webapp")]
    let fs = FakeFileSystem(home: "/Users/test", entries: ["/Users/test/dev/webapp/package.json": false])

    func makeProvider() -> FakeProcessProvider {
        let provider = FakeProcessProvider()
        provider.processes = [
            100: ProcessSnapshot(pid: 100, name: "node", listeningTCPPorts: [5173], workingDirectory: "/Users/test/dev/webapp", residentMemoryBytes: 50_000_000, startDate: Date(timeIntervalSince1970: 1_000_000)),
            101: ProcessSnapshot(pid: 101, name: "python3", listeningTCPPorts: [], workingDirectory: "/Users/test/dev/webapp/scripts", startDate: Date(timeIntervalSince1970: 1_000_100)),
            102: ProcessSnapshot(pid: 102, name: "rapportd", listeningTCPPorts: [49152], startDate: Date(timeIntervalSince1970: 900_000)),
            103: ProcessSnapshot(pid: 103, name: "zsh", listeningTCPPorts: [], workingDirectory: "/Users/test", startDate: Date(timeIntervalSince1970: 950_000)),
            104: ProcessSnapshot(pid: 104, name: "postgres", listeningTCPPorts: [5432], workingDirectory: "/", startDate: Date(timeIntervalSince1970: 940_000)),
        ]
        return provider
    }

    var scanner: RuntimeScanner {
        RuntimeScanner(
            provider: makeProvider(),
            exclusions: SystemExclusions(excludedProcessNames: ["rapportd"])
        )
    }

    @Test("Keeps listeners and project-cwd processes; drops excluded and idle ones")
    func filtering() {
        let services = scanner.discover(projects: projects, fs: fs)
        let pids = Set(services.map(\.pid))
        // 100: listens + project cwd; 101: project cwd only; 104: listens.
        // 102: excluded name; 103: no port, cwd not in a project.
        #expect(pids == [100, 101, 104])
    }

    @Test("Attributes cwd inside a project, including subdirectories")
    func cwdAttribution() {
        let services = scanner.discover(projects: projects, fs: fs)
        let node = services.first { $0.pid == 100 }
        let script = services.first { $0.pid == 101 }
        let db = services.first { $0.pid == 104 }
        #expect(node?.attribution?.projectPath == "/Users/test/dev/webapp")
        #expect(node?.attribution?.evidence == .processCwd)
        #expect(script?.attribution?.projectPath == "/Users/test/dev/webapp")
        #expect(db?.attribution == nil)
    }

    @Test("Bundled system exclusion list loads and includes rapportd")
    func bundledExclusions() {
        let exclusions = SystemExclusions.loadBundled()
        #expect(exclusions.excludedProcessNames.contains("rapportd"))
    }
}

@Suite("Service stop flow")
struct ServiceStopperTests {
    func service(pid: Int32 = 100, start: TimeInterval = 1_000_000) -> RunningService {
        RunningService(pid: pid, name: "node", startDate: Date(timeIntervalSince1970: start))
    }

    func stopper(_ provider: FakeProcessProvider, grace: Duration = .milliseconds(300)) -> ServiceStopper {
        ServiceStopper(provider: provider, pollInterval: .milliseconds(20), gracePeriod: grace)
    }

    @Test("SIGTERM terminates a cooperative process")
    func gracefulStop() async {
        let provider = FakeProcessProvider()
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "node", startDate: Date(timeIntervalSince1970: 1_000_000))
        provider.diesOn[SIGTERM] = [100]

        let result = await stopper(provider).stop(service())
        #expect(result == .terminated)
        #expect(provider.signals.map(\.signal) == [SIGTERM])
    }

    @Test("Uncooperative process reports stillRunning after the grace period, no auto-SIGKILL")
    func uncooperative() async {
        let provider = FakeProcessProvider()
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "node", startDate: Date(timeIntervalSince1970: 1_000_000))

        let result = await stopper(provider).stop(service())
        #expect(result == .stillRunning)
        // SIGKILL must never be sent implicitly — it requires separate confirmation.
        #expect(!provider.signals.contains { $0.signal == SIGKILL })
    }

    @Test("PID reuse is detected before any signal is sent")
    func pidReuseGuard() async {
        let provider = FakeProcessProvider()
        // Same pid, different start time — a recycled pid.
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "other", startDate: Date(timeIntervalSince1970: 2_000_000))

        let result = await stopper(provider).stop(service())
        #expect(result == .pidReused)
        #expect(provider.signals.isEmpty)
    }

    @Test("Already-exited process is reported without signaling")
    func alreadyGone() async {
        let provider = FakeProcessProvider()
        let result = await stopper(provider).stop(service())
        #expect(result == .alreadyGone)
        #expect(provider.signals.isEmpty)
    }

    @Test("Force kill re-verifies identity and sends SIGKILL")
    func forceKill() async {
        let provider = FakeProcessProvider()
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "node", startDate: Date(timeIntervalSince1970: 1_000_000))
        provider.diesOn[SIGKILL] = [100]

        let result = await stopper(provider).forceKill(service())
        #expect(result == .terminated)
        #expect(provider.signals.map(\.signal) == [SIGKILL])
    }

    @Test("Force kill aborts on PID reuse")
    func forceKillReuse() async {
        let provider = FakeProcessProvider()
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "other", startDate: Date(timeIntervalSince1970: 3_000_000))
        let result = await stopper(provider).forceKill(service())
        #expect(result == .pidReused)
        #expect(provider.signals.isEmpty)
    }

    @Test("Signal failure surfaces as signalFailed")
    func signalFailure() async {
        let provider = FakeProcessProvider()
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "node", startDate: Date(timeIntervalSince1970: 1_000_000))
        provider.failSignals = true
        let result = await stopper(provider).stop(service())
        #expect(result == .signalFailed)
    }

    @Test("Cancellation exits the grace loop promptly instead of spinning until the deadline")
    func cancellationExitsGraceLoop() async {
        let provider = FakeProcessProvider()
        provider.processes[100] = ProcessSnapshot(pid: 100, name: "node", startDate: Date(timeIntervalSince1970: 1_000_000))

        let sut = stopper(provider, grace: .seconds(3))
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { await sut.stop(service()) }
        task.cancel()
        let result = await task.value
        #expect(result == .stillRunning)
        #expect(clock.now - start < .seconds(1))
    }
}
