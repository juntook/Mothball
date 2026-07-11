// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Finds project roots under user-selected code root directories (SPEC §5.3).
///
/// BFS, depth ≤ 6; skips hidden directories, `node_modules`, `Library`,
/// `.Trash`. A directory containing any marker file is a project root and is
/// not descended into (outermost root wins; nested monorepo granularity is V2).
public struct ProjectDiscovery: Sendable {
    public static let markerFiles: [String] = [
        ".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod",
        "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts",
        "CMakeLists.txt", "Package.swift", "docker-compose.yml",
    ]

    public static let skippedDirectoryNames: Set<String> = [
        "node_modules", "Library", ".Trash",
    ]

    public static let maxDepth = 6

    private let fs: any FileSystem

    public init(fs: any FileSystem = RealFileSystem()) {
        self.fs = fs
    }

    /// Discovers project roots under the given code roots, honoring exclusions.
    /// `lastActive` is left nil; fill it via `ProjectActivity` (separate pass so
    /// discovery stays pure and fast).
    public func discover(codeRoots: [String], exclusions: [String] = []) -> [Project] {
        var projects: [Project] = []
        var seenRoots = Set<String>()
        let excluded = Set(exclusions.map { ($0 as NSString).standardizingPath })

        for root in codeRoots {
            let rootPath = ((try? PathExpansion.expandTilde(root, fs: fs)) ?? root)
            guard fs.isDirectory(rootPath) else { continue }

            var queue: [(path: String, depth: Int)] = [(rootPath, 0)]
            while !queue.isEmpty {
                let (dir, depth) = queue.removeFirst()
                if excluded.contains(dir) { continue }

                if isProjectRoot(dir) {
                    if seenRoots.insert(dir).inserted {
                        projects.append(Project(
                            name: (dir as NSString).lastPathComponent,
                            path: dir
                        ))
                    }
                    continue // never descend into a project
                }

                guard depth < Self.maxDepth else { continue }
                for name in fs.contentsOfDirectory(dir) {
                    if name.hasPrefix(".") { continue }
                    if Self.skippedDirectoryNames.contains(name) { continue }
                    let child = dir + "/" + name
                    if fs.isDirectory(child) {
                        queue.append((child, depth + 1))
                    }
                }
            }
        }
        return projects.sorted { $0.path < $1.path }
    }

    public func isProjectRoot(_ dir: String) -> Bool {
        Self.markerFiles.contains { fs.exists(dir + "/" + $0) }
    }
}

/// Resolves a project's last-active date: last git commit when the project has
/// git history, else the root directory's mtime (SPEC §5.3).
public struct ProjectActivity: Sendable {
    /// git lives at a fixed path — GUI apps have no Homebrew PATH (SPEC §9.1).
    public static let gitCandidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]

    public init() {}

    public func lastActive(projectPath: String) -> Date? {
        if let date = gitLastCommitDate(projectPath: projectPath) {
            return date
        }
        var st = stat()
        guard lstat(projectPath, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    private func gitLastCommitDate(projectPath: String) -> Date? {
        guard FileManager.default.fileExists(atPath: projectPath + "/.git") else { return nil }
        guard let git = Self.gitCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-C", projectPath, "log", "-1", "--format=%ct"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let epoch = TimeInterval(text) else { return nil }
            return Date(timeIntervalSince1970: epoch)
        } catch {
            return nil
        }
    }
}
