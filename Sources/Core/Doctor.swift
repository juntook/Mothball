// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Doctor reports the on-machine reality of every rule target: does the path
/// exist, is it readable, how big is it. This is the workbench for promoting a
/// rule from `draft` to `verified` (SPEC §5.1) and the community's verification
/// tool.
public struct Doctor: Sendable {
    public struct TargetReport: Sendable, Identifiable {
        public var id: String { "\(ruleID)/\(targetID)/\(pattern)" }
        public var ruleID: String
        public var targetID: String
        public var pattern: String
        public var expandedPaths: [PathReport]
        public var scope: Target.Scope
        public var safety: Safety
        public var ruleStatus: Rule.Status
    }

    public struct PathReport: Sendable, Identifiable {
        public var id: String { path }
        public var path: String
        public var exists: Bool
        public var readable: Bool
        public var isDirectory: Bool
        public var allocatedBytes: Int64?
    }

    private let fs: any FileSystem

    public init(fs: any FileSystem = RealFileSystem()) {
        self.fs = fs
    }

    /// Examines every target of every rule. Sizing is optional because it can be
    /// slow for big trees; the UI sizes on demand.
    public func examine(rules: [Rule], includeSizes: Bool = false) async -> [TargetReport] {
        var reports: [TargetReport] = []
        for rule in rules {
            for target in rule.targets {
                switch target.scope {
                case .global:
                    for pattern in target.paths ?? [] {
                        let matches = (try? PathExpansion.expand(pattern, fs: fs)) ?? []
                        var paths: [PathReport] = []
                        for path in matches {
                            var bytes: Int64?
                            if includeSizes {
                                bytes = await DirectorySizer.allocatedSizeConcurrent(atPath: path)
                            }
                            paths.append(PathReport(
                                path: path,
                                exists: true,
                                readable: fs.isReadable(path),
                                isDirectory: fs.isDirectory(path),
                                allocatedBytes: bytes
                            ))
                        }
                        if paths.isEmpty {
                            let literal = (try? PathExpansion.expandTilde(pattern, fs: fs)) ?? pattern
                            paths = [PathReport(path: literal, exists: false, readable: false, isDirectory: false, allocatedBytes: nil)]
                        }
                        reports.append(TargetReport(
                            ruleID: rule.id, targetID: target.id, pattern: pattern,
                            expandedPaths: paths, scope: target.scope,
                            safety: target.safety, ruleStatus: rule.status
                        ))
                    }
                case .project:
                    // Project targets are matched per discovered project (M3);
                    // Doctor lists them so contributors see the full rule surface.
                    reports.append(TargetReport(
                        ruleID: rule.id, targetID: target.id,
                        pattern: (target.projectGlobs ?? []).joined(separator: ", "),
                        expandedPaths: [], scope: target.scope,
                        safety: target.safety, ruleStatus: rule.status
                    ))
                }
            }
        }
        return reports
    }
}
