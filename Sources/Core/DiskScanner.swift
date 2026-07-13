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

    /// Expands `scope == .project` targets against discovered project roots:
    /// a projectGlob matches inside the project root only when at least one
    /// guardFile exists next to it (SPEC §5.2 — a stray `node_modules` without
    /// `package.json` is not counted).
    public func discoverProjectItems(rules: [Rule], projects: [Project]) -> [ResourceItem] {
        var items: [ResourceItem] = []
        for rule in rules {
            for target in rule.targets where target.scope == .project {
                guard let globs = target.projectGlobs, let guards = target.guardFiles else { continue }
                for project in projects {
                    for glob in globs {
                        let matches: [String]
                        if glob.contains("*") {
                            matches = (try? PathExpansion.expand(project.path + "/" + glob, fs: fs)) ?? []
                        } else {
                            let literal = project.path + "/" + glob
                            matches = fs.exists(literal) ? [literal] : []
                        }
                        for match in matches {
                            let parent = (match as NSString).deletingLastPathComponent
                            let guarded = guards.contains { fs.exists(parent + "/" + $0) }
                            guard guarded else { continue }
                            items.append(ResourceItem(
                                ruleID: rule.id,
                                targetID: target.id,
                                path: match,
                                kind: target.kind,
                                safety: target.safety,
                                ruleStatus: rule.status,
                                attribution: ResourceAttribution(
                                    projectPath: project.path,
                                    evidence: .pathInsideProject
                                )
                            ))
                        }
                    }
                }
            }
        }
        return items
    }

    /// Replaces items of dashed-absolute-encoded targets with one item per
    /// bucket subdirectory, attributed via the encoding (SPEC §5.3 evidence 4).
    /// Unmatched buckets stay as items with no attribution (the
    /// "unattributed/global" group). Parents with no children pass through.
    public func explodeEncodedTargets(
        items: [ResourceItem],
        rules: [Rule],
        attribution: AttributionEngine
    ) -> [ResourceItem] {
        var result: [ResourceItem] = []
        for item in items {
            let target = rules.first { $0.id == item.ruleID }?
                .targets.first { $0.id == item.targetID }
            guard target?.attribution?.encoding == .dashedAbsolute, fs.isDirectory(item.path) else {
                result.append(item)
                continue
            }
            let children = fs.contentsOfDirectory(item.path).sorted()
            if children.isEmpty {
                result.append(item)
                continue
            }
            for child in children {
                var childItem = item
                childItem.path = item.path + "/" + child
                childItem.sizeBytes = nil
                childItem.attribution = attribution.attributeEncodedDirectoryName(child)
                result.append(childItem)
            }
        }
        return result
    }

    /// Prefix whitelist for the deletion gate (SPEC §5.6 rule 2): every path
    /// the enabled rules currently expand to, global targets and per-project
    /// artifacts alike. Recomputed from the rules at execution time so the
    /// executor's containment check never depends on scan or UI state.
    public func allowedDeletionPrefixes(rules: [Rule], projects: [Project]) -> [String] {
        discoverGlobalItems(rules: rules).map(\.path)
            + discoverProjectItems(rules: rules, projects: projects).map(\.path)
    }

    /// Full progressive scan: global targets (encoded buckets exploded and
    /// attributed) plus per-project artifacts.
    public func scanAll(rules: [Rule], projects: [Project]) -> AsyncStream<Event> {
        let attribution = AttributionEngine(projects: projects, fs: fs)
        var items = explodeEncodedTargets(
            items: discoverGlobalItems(rules: rules),
            rules: rules,
            attribution: attribution
        )
        // Global paths that happen to live inside a project root pick up
        // evidence-1 attribution (e.g. a project-local venv listed globally).
        for index in items.indices where items[index].attribution == nil {
            items[index].attribution = attribution.attributeContainedPath(items[index].path)
        }
        items += discoverProjectItems(rules: rules, projects: projects)
        return stream(for: items)
    }

    /// Full progressive scan of global targets.
    public func scanGlobal(rules: [Rule]) -> AsyncStream<Event> {
        stream(for: discoverGlobalItems(rules: rules))
    }

    private func stream(for items: [ResourceItem]) -> AsyncStream<Event> {
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
