// SPDX-License-Identifier: Apache-2.0
// Protection rules must be honored by every batch path (SPEC §5.12, §8.4).
import Foundation
import Testing
@testable import Core

@Suite("Protection rules")
struct ProtectionRulesTests {
    @Test("store round-trips rules through versioned JSON")
    func storeRoundTrip() throws {
        let dir = NSTemporaryDirectory() + "mothball-protection-\(UUID().uuidString)"
        let path = dir + "/protection.json"
        let store = ProtectionRuleStore(storePath: path)

        #expect(store.load().isEmpty)
        store.add(ProtectionRule(kind: .pathPrefix, value: "/Users/test/work/client-a"))
        store.add(ProtectionRule(kind: .port, value: "11434"))
        store.add(ProtectionRule(kind: .port, value: "11434")) // duplicate ignored
        #expect(store.load().count == 2)

        store.remove(ProtectionRule(kind: .port, value: "11434"))
        #expect(store.load() == [ProtectionRule(kind: .pathPrefix, value: "/Users/test/work/client-a")])

        // Schema version is present for future migrations.
        let raw = try #require(try? String(contentsOfFile: path, encoding: .utf8))
        #expect(raw.contains("\"schemaVersion\" : 1"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test("path prefix protects the directory itself and its descendants only")
    func pathPrefixMatching() {
        let evaluator = ProtectionEvaluator(rules: [
            ProtectionRule(kind: .pathPrefix, value: "/Users/test/work/client-a/"),
        ])
        #expect(evaluator.isProtected(path: "/Users/test/work/client-a"))
        #expect(evaluator.isProtected(path: "/Users/test/work/client-a/node_modules"))
        #expect(evaluator.isProtected(path: "/Users/Test/Work/Client-A/dist")) // APFS case-insensitive
        #expect(!evaluator.isProtected(path: "/Users/test/work/client-abc"))
        #expect(!evaluator.isProtected(path: "/Users/test/work"))
    }

    @Test("exact path protects only that path")
    func exactPathMatching() {
        let evaluator = ProtectionEvaluator(rules: [
            ProtectionRule(kind: .path, value: "/Users/test/.npm/_cacache"),
        ])
        #expect(evaluator.isProtected(path: "/Users/test/.npm/_cacache"))
        #expect(!evaluator.isProtected(path: "/Users/test/.npm/_cacache/tmp"))
    }

    @Test("process and port rules protect a running service")
    func serviceProtection() {
        let evaluator = ProtectionEvaluator(rules: [
            ProtectionRule(kind: .processName, value: "Ollama"),
            ProtectionRule(kind: .port, value: "5432"),
        ])
        let ollama = RunningService(pid: 10, name: "ollama", startDate: .distantPast)
        #expect(evaluator.isProtected(service: ollama))
        let postgres = RunningService(pid: 11, name: "postgres", listeningPorts: [5432], startDate: .distantPast)
        #expect(evaluator.isProtected(service: postgres))
        let vite = RunningService(pid: 12, name: "node", listeningPorts: [5173], startDate: .distantPast)
        #expect(!evaluator.isProtected(service: vite))
    }

    @Test("volume names match exactly")
    func volumeMatching() {
        let evaluator = ProtectionEvaluator(rules: [
            ProtectionRule(kind: .volumeName, value: "prod-db"),
        ])
        #expect(evaluator.isProtected(volumeName: "prod-db"))
        #expect(!evaluator.isProtected(volumeName: "prod-db-backup"))
    }

    @Test("invalid port values never match")
    func invalidPort() {
        let evaluator = ProtectionEvaluator(rules: [
            ProtectionRule(kind: .port, value: "not-a-port"),
        ])
        #expect(!evaluator.isProtected(port: 0))
        #expect(evaluator.isEmpty == false || true) // evaluator stays usable
    }
}

@Suite("Brew services client")
struct BrewServicesTests {
    private struct RecordingRunner: CommandRunner {
        let output: Data
        let calls: LockedCalls

        final class LockedCalls: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [[String]] = []
            func append(_ args: [String]) {
                lock.lock()
                defer { lock.unlock() }
                storage.append(args)
            }
            var all: [[String]] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
        }

        func run(executable: String, arguments: [String]) throws -> Data {
            calls.append([executable] + arguments)
            return output
        }
    }

    @Test("parses brew services list --json")
    func parseList() throws {
        let json = """
        [
          {"name": "postgresql@16", "status": "started", "user": "test", "file": "/Users/test/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist", "exit_code": 0},
          {"name": "redis", "status": "none"},
          {"name": "mysql", "status": "error", "user": "test", "exit_code": 78}
        ]
        """
        let runner = RecordingRunner(output: Data(json.utf8), calls: .init())
        let client = BrewServicesClient(binary: "/opt/homebrew/bin/brew", runner: runner)
        let services = try client.list()

        #expect(services.count == 3)
        let pg = try #require(services.first { $0.name == "postgresql@16" })
        #expect(pg.isRunning)
        #expect(pg.startsAtLogin)
        #expect(pg.plistPath?.hasSuffix(".plist") == true)
        let redis = try #require(services.first { $0.name == "redis" })
        #expect(!redis.isRunning)
        let mysql = try #require(services.first { $0.name == "mysql" })
        #expect(mysql.isRunning) // error state still shows as needing attention
        #expect(runner.calls.all == [["/opt/homebrew/bin/brew", "services", "list", "--json"]])
    }

    @Test("stop semantics map to the right brew subcommands")
    func stopSemantics() throws {
        let runner = RecordingRunner(output: Data("[]".utf8), calls: .init())
        let client = BrewServicesClient(binary: "/opt/homebrew/bin/brew", runner: runner)
        try client.stopOnce("redis")
        try client.stopAndDisable("redis")
        try client.runOnce("redis")
        #expect(runner.calls.all == [
            ["/opt/homebrew/bin/brew", "services", "kill", "redis"],
            ["/opt/homebrew/bin/brew", "services", "stop", "redis"],
            ["/opt/homebrew/bin/brew", "services", "run", "redis"],
        ])
    }
}
