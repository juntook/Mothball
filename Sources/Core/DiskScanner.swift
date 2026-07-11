// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Scans global rule targets and reports results progressively: items appear as
/// soon as their path is confirmed to exist; sizes stream in afterwards
/// (SPEC §5.2 — no blank-screen waits).
public struct DiskScanner: Sendable {
    public enum Event: Sendable {
        /// A target path exists; size not yet known.
        case discovered(ResourceItem)
        /// Sizing finished for a previously discovered path.
        case sized(path: String, bytes: Int64)
        /// All discovery and sizing completed.
        case finished
    }

    private let fs: any FileSystem

    public init(fs: any FileSystem = RealFileSystem()) {
        self.fs = fs
    }

    /// Expands every `scope == .global` target of the given rules to existing
    /// paths, without sizing. Pure and fast; also used by the Doctor panel.
    public func discoverGlobalItems(rules: [Rule]) -> [ResourceItem] {
        var items: [ResourceItem] = []
        for rule in rules {
            for target in rule.targets where target.scope == .global {
                for pattern in target.paths ?? [] {
                    let matches = (try? PathExpansion.expand(pattern, fs: fs)) ?? []
                    for path in matches {
                        items.append(ResourceItem(
                            ruleID: rule.id,
                            targetID: target.id,
                            path: path,
                            kind: target.kind,
                            safety: target.safety,
                            ruleStatus: rule.status
                        ))
                    }
                }
            }
        }
        return items
    }

    /// Full progressive scan of global targets.
    public func scanGlobal(rules: [Rule]) -> AsyncStream<Event> {
        let items = discoverGlobalItems(rules: rules)
        return AsyncStream { continuation in
            let task = Task {
                for item in items {
                    continuation.yield(.discovered(item))
                }
                await withTaskGroup(of: Void.self) { group in
                    for item in items {
                        group.addTask {
                            let bytes = await DirectorySizer.allocatedSizeConcurrent(atPath: item.path)
                            continuation.yield(.sized(path: item.path, bytes: bytes))
                        }
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
