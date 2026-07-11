// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Performs the actual removal operations. Injectable so tests observe exactly
/// what would be touched.
public protocol FileRemover: Sendable {
    /// Move to Trash. Returns the trashed item's new URL when available.
    func trash(_ path: String) throws
    /// Direct removal. Must not follow symlinks (removing a link removes the link).
    func delete(_ path: String) throws
}

public struct RealFileRemover: FileRemover {
    public init() {}

    public func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }

    public func delete(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}

/// Executes a confirmed cleanup plan behind the deletion gate (SPEC §5.6).
public struct CleanupExecutor: Sendable {
    public struct ItemResult: Sendable, Equatable {
        public enum Outcome: Sendable, Equatable {
            case trashed
            case deleted
            case rejected(DeletionGate.Rejection)
            case failed(String)
            /// user_data trash failed: the run stops and asks — never a
            /// silent fallback to direct deletion (gate rule 5).
            case abortedTrashFailure(String)
            /// Skipped because an earlier user_data trash failure aborted the run.
            case skippedAfterAbort
        }
        public var item: CleanupItem
        public var method: CleanupMethod
        public var outcome: Outcome
    }

    public struct RunResult: Sendable {
        public var results: [ItemResult]
        public var reclaimedBytes: Int64
        /// True when a user_data trash failure stopped the run early.
        public var abortedOnTrashFailure: Bool
    }

    private let gate: DeletionGate
    private let remover: any FileRemover
    private let auditLog: AuditLog?

    public init(gate: DeletionGate, remover: any FileRemover = RealFileRemover(), auditLog: AuditLog? = nil) {
        self.gate = gate
        self.remover = remover
        self.auditLog = auditLog
    }

    /// Runs the plan item by item. Rejections and per-item failures don't stop
    /// the run; a user_data trash failure does (abort-and-ask).
    public func execute(items: [CleanupItem], method: CleanupMethod) async -> RunResult {
        var results: [ItemResult] = []
        var reclaimed: Int64 = 0
        var aborted = false

        for item in items {
            if aborted {
                results.append(.init(item: item, method: method, outcome: .skippedAfterAbort))
                continue
            }
            // user_data is trash-only regardless of the requested method; the
            // gate would reject .delete, and the UI never offers it.
            let effectiveMethod: CleanupMethod = item.safety == .userData ? .trash : method

            switch gate.check(item, method: effectiveMethod) {
            case .rejected(let reason):
                results.append(.init(item: item, method: effectiveMethod, outcome: .rejected(reason)))
                auditLog?.append(.init(item: item, method: effectiveMethod, result: "rejected:\(reason)"))
            case .allowed:
                do {
                    switch effectiveMethod {
                    case .trash:
                        try remover.trash(item.path)
                        results.append(.init(item: item, method: .trash, outcome: .trashed))
                        auditLog?.append(.init(item: item, method: .trash, result: "ok"))
                    case .delete:
                        try remover.delete(item.path)
                        results.append(.init(item: item, method: .delete, outcome: .deleted))
                        auditLog?.append(.init(item: item, method: .delete, result: "ok"))
                    }
                    reclaimed += item.sizeBytes ?? 0
                } catch {
                    let message = error.localizedDescription
                    if effectiveMethod == .trash && item.safety == .userData {
                        results.append(.init(item: item, method: .trash, outcome: .abortedTrashFailure(message)))
                        auditLog?.append(.init(item: item, method: .trash, result: "aborted-trash-failure: \(message)"))
                        aborted = true
                    } else {
                        results.append(.init(item: item, method: effectiveMethod, outcome: .failed(message)))
                        auditLog?.append(.init(item: item, method: effectiveMethod, result: "failed: \(message)"))
                    }
                }
            }
        }
        return RunResult(results: results, reclaimedBytes: reclaimed, abortedOnTrashFailure: aborted)
    }
}
