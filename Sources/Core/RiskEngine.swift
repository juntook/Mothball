// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Presentation-layer risk tier (SPEC §4.4). Computed on top of the safety
/// tiers and only ever tightens defaults; enforcement stays with `Safety`
/// and the deletion gate.
public enum RiskTier: Int, Sendable, Comparable, Hashable {
    case s0 = 0
    case s1 = 1
    case s2 = 2
    case s3 = 3

    public static func < (lhs: RiskTier, rhs: RiskTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Why an item landed on its tier — every score must be explainable in the UI
/// (SPEC §4.4: signals are local and explainable).
public enum RiskReason: String, Sendable, Hashable, CaseIterable {
    case userData
    case protectedSafety
    case projectInUse
    case gitDirty
    case recentlyActive
    case toolCache
    case noActivitySignals
}

public struct RiskAssessment: Sendable, Hashable {
    public var tier: RiskTier
    public var reasons: [RiskReason]

    public init(tier: RiskTier, reasons: [RiskReason]) {
        self.tier = tier
        self.reasons = reasons
    }
}

/// Maps resources to S0–S3 from local signals (SPEC §4.4):
/// `user_data`/`protected` are always S3; `regenerable` falls on S0–S2
/// depending on whether its project is in use, has uncommitted changes,
/// or was recently active.
public struct RiskEngine: Sendable {
    /// Project roots that currently have an attributed running process.
    private let inUseProjectPaths: Set<String>
    /// Project roots with uncommitted git changes.
    private let dirtyProjectPaths: Set<String>
    /// Last-activity dates per project root.
    private let lastActiveByProject: [String: Date]
    private let now: Date
    private let recentActivityWindow: TimeInterval

    public init(
        inUseProjectPaths: Set<String> = [],
        dirtyProjectPaths: Set<String> = [],
        lastActiveByProject: [String: Date] = [:],
        now: Date = Date(),
        recentActivityWindow: TimeInterval = 30 * 24 * 3600
    ) {
        self.inUseProjectPaths = inUseProjectPaths
        self.dirtyProjectPaths = dirtyProjectPaths
        self.lastActiveByProject = lastActiveByProject
        self.now = now
        self.recentActivityWindow = recentActivityWindow
    }

    public func assess(_ item: ResourceItem) -> RiskAssessment {
        switch item.safety {
        case .protected:
            return RiskAssessment(tier: .s3, reasons: [.protectedSafety])
        case .userData:
            return RiskAssessment(tier: .s3, reasons: [.userData])
        case .regenerable:
            return assessRegenerable(projectPath: item.attribution?.projectPath)
        }
    }

    public func assess(_ resource: ContainerResource) -> RiskAssessment {
        switch resource.safety {
        case .protected:
            return RiskAssessment(tier: .s3, reasons: [.protectedSafety])
        case .userData:
            return RiskAssessment(tier: .s3, reasons: [.userData])
        case .regenerable:
            return assessRegenerable(projectPath: resource.attribution?.projectPath)
        }
    }

    private func assessRegenerable(projectPath: String?) -> RiskAssessment {
        guard let projectPath else {
            // Global tool caches carry no per-project activity signal; stay
            // at low risk rather than claiming they are fully idle.
            return RiskAssessment(tier: .s1, reasons: [.toolCache])
        }
        if inUseProjectPaths.contains(projectPath) {
            return RiskAssessment(tier: .s2, reasons: [.projectInUse])
        }
        // Uncommitted changes are the steady state of active development and
        // build artifacts are not part of git state, so dirty alone flags the
        // project as active (S1) rather than in use (S2, SPEC §4.4).
        if dirtyProjectPaths.contains(projectPath) {
            return RiskAssessment(tier: .s1, reasons: [.gitDirty])
        }
        if let lastActive = lastActiveByProject[projectPath],
           now.timeIntervalSince(lastActive) < recentActivityWindow {
            return RiskAssessment(tier: .s1, reasons: [.recentlyActive])
        }
        return RiskAssessment(tier: .s0, reasons: [.noActivitySignals])
    }
}

/// Uncommitted-change probe for the risk engine (SPEC §4.4). Uses the fixed
/// git candidates — GUI apps have no Homebrew PATH (SPEC §9.1).
public struct GitStatusProbe: Sendable {
    private let runner: any CommandRunner
    private let fs: any FileSystem

    public init(runner: any CommandRunner = RealCommandRunner(), fs: any FileSystem = RealFileSystem()) {
        self.runner = runner
        self.fs = fs
    }

    /// true = uncommitted changes, false = clean, nil = not a git repo or
    /// git unavailable (treated as "no signal", never as dirty).
    public func isDirty(projectPath: String) -> Bool? {
        guard fs.isDirectory(projectPath + "/.git") else { return nil }
        guard let git = ProjectActivity.gitCandidates.first(where: { fs.exists($0) }) else { return nil }
        guard let output = try? runner.run(
            executable: git,
            arguments: ["-C", projectPath, "status", "--porcelain", "--no-renames"]
        ) else { return nil }
        return !output.isEmpty
    }
}
