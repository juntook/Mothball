// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

/// Records operations without touching the filesystem; can simulate failures.
final class SpyRemover: FileRemover, @unchecked Sendable {
    var trashed: [String] = []
    var deleted: [String] = []
    var failTrashPaths: Set<String> = []

    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "simulated cross-volume failure" }
    }

    func trash(_ path: String) throws {
        if failTrashPaths.contains(path) { throw Failure() }
        trashed.append(path)
    }

    func delete(_ path: String) throws {
        deleted.append(path)
    }
}

@Suite("Cleanup executor")
struct CleanupExecutorTests {
    struct Fixture {
        let root: URL
        let home: String
        let allowed: URL
        let remover = SpyRemover()
        let logURL: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("mothball-exec-\(UUID().uuidString)")
            home = root.appendingPathComponent("home").path
            allowed = root.appendingPathComponent("home/.tool/cache")
            try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
            logURL = root.appendingPathComponent("ops.jsonl")
            for name in ["a", "b", "c"] {
                try Data("x".utf8).write(to: allowed.appendingPathComponent(name))
            }
        }

        func executor(directDelete: Bool = false) -> CleanupExecutor {
            CleanupExecutor(
                gate: DeletionGate(
                    allowedPrefixes: [allowed.path],
                    homeDirectoryPath: home,
                    directDeleteEnabled: directDelete
                ),
                remover: remover,
                auditLog: AuditLog(logPath: logURL.path)
            )
        }

        func item(_ name: String, safety: Safety = .regenerable, bytes: Int64 = 100) -> CleanupItem {
            CleanupItem(path: allowed.appendingPathComponent(name).path, safety: safety, ruleID: "tool", targetID: "cache", sizeBytes: bytes)
        }
    }

    @Test("Trashes allowed items and reports reclaimed bytes")
    func happyPath() async throws {
        let f = try Fixture()
        let run = await f.executor().execute(items: [f.item("a"), f.item("b")], method: .trash)
        #expect(f.remover.trashed.count == 2)
        #expect(run.reclaimedBytes == 200)
        #expect(!run.abortedOnTrashFailure)
    }

    @Test("Rejected items are recorded and skipped, not fatal")
    func rejectionRecorded() async throws {
        let f = try Fixture()
        let outside = CleanupItem(path: f.home + "/Documents/keep.txt", safety: .regenerable, ruleID: "tool", targetID: "cache")
        let run = await f.executor().execute(items: [outside, f.item("a")], method: .trash)
        #expect(f.remover.trashed.count == 1)
        #expect(run.results[0].outcome == .rejected(.outsideAllowedPrefixes))
        #expect(run.results[1].outcome == .trashed)
    }

    @Test("user_data trash failure aborts the run — remaining items skipped, no direct-delete fallback")
    func userDataTrashFailureAborts() async throws {
        let f = try Fixture()
        f.remover.failTrashPaths = [f.item("a").path]
        let items = [f.item("a", safety: .userData), f.item("b"), f.item("c")]
        let run = await f.executor().execute(items: items, method: .trash)

        #expect(run.abortedOnTrashFailure)
        #expect(f.remover.deleted.isEmpty)
        #expect(f.remover.trashed.isEmpty)
        if case .abortedTrashFailure = run.results[0].outcome {} else {
            Issue.record("expected abortedTrashFailure, got \(run.results[0].outcome)")
        }
        #expect(run.results[1].outcome == .skippedAfterAbort)
        #expect(run.results[2].outcome == .skippedAfterAbort)
    }

    @Test("regenerable trash failure does not abort the run")
    func regenerableFailureContinues() async throws {
        let f = try Fixture()
        f.remover.failTrashPaths = [f.item("a").path]
        let run = await f.executor().execute(items: [f.item("a"), f.item("b")], method: .trash)
        #expect(!run.abortedOnTrashFailure)
        if case .failed = run.results[0].outcome {} else {
            Issue.record("expected failed, got \(run.results[0].outcome)")
        }
        #expect(run.results[1].outcome == .trashed)
    }

    @Test("user_data in a direct-delete run is still trashed")
    func userDataForcedToTrash() async throws {
        let f = try Fixture()
        let run = await f.executor(directDelete: true).execute(
            items: [f.item("a", safety: .userData), f.item("b")],
            method: .delete
        )
        #expect(f.remover.trashed == [f.item("a").path])
        #expect(f.remover.deleted == [f.item("b").path])
        #expect(run.results[0].outcome == .trashed)
        #expect(run.results[1].outcome == .deleted)
    }

    @Test("Protected items can never be executed")
    func protectedNeverExecuted() async throws {
        let f = try Fixture()
        let run = await f.executor(directDelete: true).execute(
            items: [f.item("a", safety: .protected)],
            method: .trash
        )
        #expect(run.results[0].outcome == .rejected(.protectedSafety))
        #expect(f.remover.trashed.isEmpty)
        #expect(f.remover.deleted.isEmpty)
    }

    @Test("Every operation lands in the audit log as JSONL")
    func auditTrail() async throws {
        let f = try Fixture()
        let items = [f.item("a"), f.item("a", safety: .protected)]
        _ = await f.executor().execute(items: items, method: .trash)

        let records = AuditLog(logPath: f.logURL.path).readAll()
        #expect(records.count == 2)
        #expect(records[0].result == "ok")
        #expect(records[0].method == "trash")
        #expect(records[0].ruleID == "tool")
        #expect(records[1].result.hasPrefix("rejected:"))
    }
}

@Suite("Audit log")
struct AuditLogTests {
    @Test("Append is strictly append-only — an unopenable existing log stays byte-intact")
    func appendNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mothball-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let logPath = dir.appendingPathComponent("ops.jsonl").path

        let log = AuditLog(logPath: logPath)
        log.append(AuditLog.Record(ruleID: "r", targetID: "t", path: "/tmp/mothball/a", bytes: 1, method: "trash", result: "ok"))
        log.append(AuditLog.Record(ruleID: "r", targetID: "t", path: "/tmp/mothball/b", bytes: 2, method: "trash", result: "ok"))
        #expect(log.readAll().count == 2)
        let before = try Data(contentsOf: URL(fileURLWithPath: logPath))

        // An existing log that cannot be opened for appending must never be
        // replaced by a fresh single-line file (append-only guarantee).
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: logPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logPath) }
        log.append(AuditLog.Record(ruleID: "r", targetID: "t", path: "/tmp/mothball/c", bytes: 3, method: "trash", result: "ok"))

        let after = try Data(contentsOf: URL(fileURLWithPath: logPath))
        #expect(after == before)
    }
}

@Suite("Ignore list")
struct IgnoreListTests {
    @Test("Round-trips paths through the store")
    func roundTrip() throws {
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent("mothball-ignore-\(UUID().uuidString)/ignored.json")
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let list = IgnoreList(storePath: store.path)
        #expect(list.load().isEmpty)
        list.add("/Users/test/.npm/_cacache")
        list.add("/Users/test/.claude/statsig")
        #expect(list.load().count == 2)
        list.remove("/Users/test/.npm/_cacache")
        #expect(list.load() == ["/Users/test/.claude/statsig"])
    }
}
