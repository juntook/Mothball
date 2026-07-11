// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation

// MARK: - Cleanup plan types

/// One confirmed entry from the preview sheet. The executor receives only
/// these concrete paths — never rules (SPEC §5.6 gate rule 1).
public struct CleanupItem: Sendable, Hashable, Codable {
    public var path: String
    public var safety: Safety
    public var ruleID: String
    public var targetID: String
    public var sizeBytes: Int64?

    public init(path: String, safety: Safety, ruleID: String, targetID: String, sizeBytes: Int64? = nil) {
        self.path = path
        self.safety = safety
        self.ruleID = ruleID
        self.targetID = targetID
        self.sizeBytes = sizeBytes
    }
}

public enum CleanupMethod: String, Sendable, Codable {
    case trash
    case delete
}

// MARK: - Gate

/// The last hard check before anything is removed. Lives entirely below the UI:
/// even a buggy view layer cannot push an item past these rules (SPEC §5.6).
public struct DeletionGate: Sendable {
    public enum Rejection: Error, Equatable, Sendable {
        /// Root, home itself, `..`, too short, /System, system /Library.
        case forbiddenPath
        /// Normalized path is not under any enabled rule's expanded prefix.
        case outsideAllowedPrefixes
        /// Protected items have no deletion path, period.
        case protectedSafety
        /// user_data may only be trashed, never directly deleted.
        case userDataRequiresTrash
        /// Direct delete requested but the global setting is off.
        case directDeleteDisabled
        /// The path does not exist (lstat, so dangling symlinks still count).
        case notFound
    }

    public enum Decision: Equatable, Sendable {
        case allowed
        case rejected(Rejection)
    }

    /// realpath-normalized prefixes expanded from enabled rules.
    private let allowedPrefixes: [String]
    private let homeDirectoryPath: String
    private let directDeleteEnabled: Bool

    public init(allowedPrefixes: [String], homeDirectoryPath: String, directDeleteEnabled: Bool) {
        self.allowedPrefixes = allowedPrefixes.compactMap(Self.normalizeExisting)
        self.homeDirectoryPath = Self.normalizeExisting(homeDirectoryPath) ?? homeDirectoryPath
        self.directDeleteEnabled = directDeleteEnabled
    }

    public func check(_ item: CleanupItem, method: CleanupMethod) -> Decision {
        // Gate 3 first on the raw path: `..` never survives, normalized or not.
        if item.path.components(separatedBy: "/").contains("..") {
            return .rejected(.forbiddenPath)
        }

        // Gate 3 lexical screen on the raw path, before any resolution.
        if let rejection = forbiddenScreen(item.path) { return .rejected(rejection) }

        // Gate 4: never follow the leaf symlink. The parent chain is realpath'd
        // so a symlinked directory cannot smuggle the operation outside the
        // allowed prefix, but the leaf itself stays un-dereferenced. When the
        // parent chain does not resolve, the raw path still goes through the
        // prefix screen so escape attempts report as out-of-bounds.
        let resolved = Self.normalizeParentRealLeaf(item.path)
        let normalized = resolved ?? item.path

        // Gate 3 again on the normalized form (a symlink could point at a
        // forbidden location).
        if let rejection = forbiddenScreen(normalized) { return .rejected(rejection) }

        // Gate 2: must sit under an enabled rule's expanded prefix.
        let inside = allowedPrefixes.contains { prefix in
            normalized == prefix || normalized.hasPrefix(prefix + "/")
        }
        guard inside else { return .rejected(.outsideAllowedPrefixes) }

        var st = stat()
        guard resolved != nil, lstat(normalized, &st) == 0 else {
            return .rejected(.notFound)
        }

        // Safety tiers (SPEC §4.3): protected has no deletion path at all;
        // user_data is trash-only; regenerable needs the setting for direct delete.
        switch item.safety {
        case .protected:
            return .rejected(.protectedSafety)
        case .userData:
            return method == .trash ? .allowed : .rejected(.userDataRequiresTrash)
        case .regenerable:
            if method == .delete && !directDeleteEnabled {
                return .rejected(.directDeleteDisabled)
            }
            return .allowed
        }
    }

    /// Absolute forbidden set (gate rule 3).
    private func forbiddenScreen(_ path: String) -> Rejection? {
        if path.isEmpty || path == "/" { return .forbiddenPath }
        if path == homeDirectoryPath || path + "/" == homeDirectoryPath { return .forbiddenPath }
        if path.count < 8 { return .forbiddenPath }
        if path == "/System" || path.hasPrefix("/System/") { return .forbiddenPath }
        if path == "/Library" || path.hasPrefix("/Library/") { return .forbiddenPath }
        return nil
    }

    /// realpath() of the parent directory + the untouched leaf name.
    /// Returns nil when the parent chain does not resolve.
    static func normalizeParentRealLeaf(_ path: String) -> String? {
        let ns = path as NSString
        let leaf = ns.lastPathComponent
        if leaf == "/" || leaf.isEmpty { return normalizeExisting(path) }
        let parent = ns.deletingLastPathComponent
        guard let realParent = normalizeExisting(parent) else { return nil }
        return realParent == "/" ? "/" + leaf : realParent + "/" + leaf
    }

    static func normalizeExisting(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.realpath(path, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}
