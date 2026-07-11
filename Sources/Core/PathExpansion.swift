// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Expands rule path patterns to concrete filesystem paths.
///
/// Supported syntax (SPEC §5.1): leading `~` for the home directory, and `*`
/// wildcards within a single path segment. `**` and `..` are rejected outright.
public enum PathExpansion {
    public enum ExpansionError: Error, Equatable {
        case unsupportedPattern(String)
    }

    /// Expands `~` without touching wildcards. Throws on `..` or `**`.
    public static func expandTilde(_ pattern: String, fs: any FileSystem) throws -> String {
        guard !pattern.contains("..") else {
            throw ExpansionError.unsupportedPattern(pattern)
        }
        guard !pattern.contains("**") else {
            throw ExpansionError.unsupportedPattern(pattern)
        }
        if pattern == "~" { return fs.homeDirectoryPath }
        if pattern.hasPrefix("~/") {
            return fs.homeDirectoryPath + pattern.dropFirst(1)
        }
        return pattern
    }

    /// Expands a pattern to the list of existing paths that match it.
    /// Patterns without `*` return `[path]` only if the path exists.
    public static func expand(_ pattern: String, fs: any FileSystem) throws -> [String] {
        let absolute = try expandTilde(pattern, fs: fs)
        guard absolute.contains("*") else {
            return fs.exists(absolute) ? [absolute] : []
        }

        let segments = absolute.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = ["/"]
        for segment in segments {
            var next: [String] = []
            if segment.contains("*") {
                for dir in current where fs.isDirectory(dir) {
                    for name in fs.contentsOfDirectory(dir) where matchesSegment(name, pattern: segment) {
                        next.append(join(dir, name))
                    }
                }
            } else {
                for dir in current {
                    let candidate = join(dir, segment)
                    if fs.exists(candidate) { next.append(candidate) }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.sorted()
    }

    /// Single-segment wildcard match; `*` never crosses `/`. Hidden files are
    /// matched only when the pattern itself starts with a dot (fnmatch semantics
    /// with FNM_PERIOD).
    static func matchesSegment(_ name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, FNM_PERIOD) == 0
    }

    private static func join(_ dir: String, _ name: String) -> String {
        dir == "/" ? "/" + name : dir + "/" + name
    }
}
