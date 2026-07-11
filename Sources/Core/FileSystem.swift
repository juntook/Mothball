// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Minimal file-system facade so path expansion and rule loading are testable
/// against a fixture directory instead of the real home directory.
public protocol FileSystem: Sendable {
    var homeDirectoryPath: String { get }
    func exists(_ path: String) -> Bool
    func isDirectory(_ path: String) -> Bool
    func isReadable(_ path: String) -> Bool
    func contentsOfDirectory(_ path: String) -> [String]
    func realpath(_ path: String) -> String?
}

public struct RealFileSystem: FileSystem {
    public init() {}

    public var homeDirectoryPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public func exists(_ path: String) -> Bool {
        // lstat so dangling symlinks still count as existing entries.
        var st = stat()
        return lstat(path, &st) == 0
    }

    public func isDirectory(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    public func isReadable(_ path: String) -> Bool {
        access(path, R_OK) == 0
    }

    public func contentsOfDirectory(_ path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    public func realpath(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.realpath(path, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}

/// In-memory file system for unit tests. Paths are absolute strings; directories
/// are implied by their children plus explicit entries.
public struct FakeFileSystem: FileSystem {
    public var homeDirectoryPath: String
    /// path -> isDirectory
    public var entries: [String: Bool]

    public init(home: String = "/Users/test", entries: [String: Bool] = [:]) {
        self.homeDirectoryPath = home
        var all = entries
        // Ancestor directories are implied so fixtures only list leaves.
        for path in entries.keys {
            var parent = (path as NSString).deletingLastPathComponent
            while parent.count > 1 {
                all[parent] = true
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        all["/"] = true
        self.entries = all
    }

    public func exists(_ path: String) -> Bool { entries[path] != nil }
    public func isDirectory(_ path: String) -> Bool { entries[path] == true }
    public func isReadable(_ path: String) -> Bool { entries[path] != nil }

    public func contentsOfDirectory(_ path: String) -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        var names = Set<String>()
        for key in entries.keys where key.hasPrefix(prefix) {
            let rest = key.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                names.insert(String(rest[..<slash]))
            } else if !rest.isEmpty {
                names.insert(String(rest))
            }
        }
        return names.sorted()
    }

    public func realpath(_ path: String) -> String? {
        entries[path] != nil ? path : nil
    }
}
