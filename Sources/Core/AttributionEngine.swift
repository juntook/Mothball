// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Maps resources to projects using the SPEC §5.3 evidence chain.
/// Matching normalizes paths (realpath where possible) and is
/// case-insensitive, matching APFS's default behavior.
public struct AttributionEngine: Sendable {
    private struct IndexedProject {
        let project: Project
        let normalizedPath: String
        let encodedName: String
    }

    private let indexed: [IndexedProject]

    public init(projects: [Project], fs: any FileSystem = RealFileSystem()) {
        indexed = projects.map { project in
            let normalized = fs.realpath(project.path) ?? project.path
            return IndexedProject(
                project: project,
                normalizedPath: normalized.lowercased(),
                encodedName: DashedPathCodec.encode(normalized).lowercased()
            )
        }
        // Longest path first so the nearest (deepest) project root wins.
        .sorted { $0.normalizedPath.count > $1.normalizedPath.count }
    }

    /// Evidence 1: the resource path lives inside a project root.
    public func attributeContainedPath(_ path: String) -> ResourceAttribution? {
        nearestProject(containing: path).map {
            ResourceAttribution(projectPath: $0.path, evidence: .pathInsideProject)
        }
    }

    /// Evidence 2: a process working directory inside a project root
    /// (nearest project root wins for nested paths).
    public func attributeCwd(_ cwd: String) -> ResourceAttribution? {
        nearestProject(containing: cwd).map {
            ResourceAttribution(projectPath: $0.path, evidence: .processCwd)
        }
    }

    /// Evidence 3: docker compose labels carry the compose working dir.
    public func attributeComposeWorkingDir(_ workingDir: String) -> ResourceAttribution? {
        nearestProject(containing: workingDir).map {
            ResourceAttribution(projectPath: $0.path, evidence: .composeLabel)
        }
    }

    /// Evidence 4: a bucket directory whose name is a dashed-absolute encoding
    /// of the project path (e.g. `-Users-me-dev-shop`), used by Claude Code's
    /// per-project data dirs. The encoding is lossy (dashes in real path
    /// components are indistinguishable from separators), so decoding works by
    /// comparing against the encodings of known project roots.
    public func attributeEncodedDirectoryName(_ dirName: String) -> ResourceAttribution? {
        let lowered = dirName.lowercased()
        for entry in indexed {
            if lowered == entry.encodedName || lowered.hasPrefix(entry.encodedName + "-") {
                return ResourceAttribution(projectPath: entry.project.path, evidence: .encodedPath)
            }
        }
        return nil
    }

    /// Evidence 5: a container bind-mount source inside a project root.
    public func attributeBindMountSource(_ source: String) -> ResourceAttribution? {
        nearestProject(containing: source).map {
            ResourceAttribution(projectPath: $0.path, evidence: .bindMount)
        }
    }

    private func nearestProject(containing path: String) -> Project? {
        let lowered = path.lowercased()
        for entry in indexed {
            if lowered == entry.normalizedPath || lowered.hasPrefix(entry.normalizedPath + "/") {
                return entry.project
            }
        }
        return nil
    }
}

/// Claude Code-style dashed-absolute path encoding: `/` (and `.`, which the
/// encoder also flattens) become `-`, so `/Users/me/dev/shop` is
/// `-Users-me-dev-shop`.
public enum DashedPathCodec {
    public static func encode(_ absolutePath: String) -> String {
        absolutePath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
