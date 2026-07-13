// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Append-only JSONL audit trail of every operation (SPEC §5.6).
/// Records are machine-readable and always English — safe to paste into a
/// GitHub issue regardless of UI language.
public final class AuditLog: @unchecked Sendable {
    public struct Record: Codable, Sendable {
        public var timestamp: String
        public var ruleID: String
        public var targetID: String
        public var path: String
        public var bytes: Int64?
        public var method: String
        public var result: String

        public init(item: CleanupItem, method: CleanupMethod, result: String, timestamp: Date = Date()) {
            self.timestamp = ISO8601DateFormatter().string(from: timestamp)
            self.ruleID = item.ruleID
            self.targetID = item.targetID
            self.path = item.path
            self.bytes = item.sizeBytes
            self.method = method.rawValue
            self.result = result
        }

        public init(timestamp: Date = Date(), ruleID: String, targetID: String, path: String, bytes: Int64?, method: String, result: String) {
            self.timestamp = ISO8601DateFormatter().string(from: timestamp)
            self.ruleID = ruleID
            self.targetID = targetID
            self.path = path
            self.bytes = bytes
            self.method = method
            self.result = result
        }
    }

    public static let defaultLogPath = "~/Library/Logs/Mothball/operations.jsonl"

    public let logURL: URL
    private let queue = DispatchQueue(label: "mothball.auditlog")

    public init(logPath: String = AuditLog.defaultLogPath, fs: any FileSystem = RealFileSystem()) {
        let expanded = (try? PathExpansion.expandTilde(logPath, fs: fs)) ?? logPath
        self.logURL = URL(fileURLWithPath: expanded)
    }

    public func append(_ record: Record) {
        queue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                var line = try encoder.encode(record)
                line.append(0x0A)
                let fm = FileManager.default
                try fm.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                // Strictly append-only: create the file if missing, then open
                // for appending. An existing log that cannot be opened is an
                // error — never fall back to a whole-file write, which would
                // replace the history with a single line.
                if !fm.fileExists(atPath: logURL.path) {
                    fm.createFile(atPath: logURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                // The audit log must never take the app down; last resort is stderr.
                FileHandle.standardError.write(Data("audit-log write failed: \(error)\n".utf8))
            }
        }
    }

    /// Reads all records (newest last). Used by tests and the log viewer.
    public func readAll() -> [Record] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(Record.self, from: Data($0.utf8))
        }
    }
}
