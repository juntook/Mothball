// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Detects whether a tool has ever been present on this machine, per the rule's
/// `detection` block. Binary lookup uses a fixed candidate list — GUI apps do not
/// inherit the shell PATH (SPEC §9.1), so PATH is never consulted.
public struct ToolDetection: Sendable {
    /// Directories searched for `anyBinaries`, in order.
    public static let binarySearchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "~/.local/bin",
        "~/bin",
        "~/.orbstack/bin",
    ]

    private let fs: any FileSystem

    public init(fs: any FileSystem = RealFileSystem()) {
        self.fs = fs
    }

    public func isPresent(_ rule: Rule) -> Bool {
        let d = rule.detection
        for pattern in d.anyPaths ?? [] {
            if let matches = try? PathExpansion.expand(pattern, fs: fs), !matches.isEmpty {
                return true
            }
        }
        for binary in d.anyBinaries ?? [] {
            if resolveBinary(binary) != nil { return true }
        }
        for app in d.anyApps ?? [] where fs.exists(app) {
            return true
        }
        return false
    }

    /// Resolves a binary name against the fixed candidate directories.
    public func resolveBinary(_ name: String) -> String? {
        for dir in Self.binarySearchDirectories {
            guard let expanded = try? PathExpansion.expandTilde(dir, fs: fs) else { continue }
            let candidate = expanded + "/" + name
            if fs.exists(candidate) { return candidate }
        }
        return nil
    }
}
