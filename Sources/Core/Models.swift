// SPDX-License-Identifier: Apache-2.0
import Foundation

// MARK: - Rule model (mirrors rules/schema/rule.schema.json)

public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public enum Category: String, Codable, Sendable {
        case aiCli = "ai-cli"
        case aiApp = "ai-app"
        case packageManager = "package-manager"
        case buildTool = "build-tool"
        case ide
        case runtime
    }

    public enum Status: String, Codable, Sendable {
        case draft
        case verified
    }

    public struct Detection: Codable, Sendable, Hashable {
        public var anyPaths: [String]?
        public var anyBinaries: [String]?
        public var anyApps: [String]?

        public init(anyPaths: [String]? = nil, anyBinaries: [String]? = nil, anyApps: [String]? = nil) {
            self.anyPaths = anyPaths
            self.anyBinaries = anyBinaries
            self.anyApps = anyApps
        }
    }

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var vendor: String
    public var category: Category
    public var homepage: String?
    public var platforms: [String]
    public var status: Status
    public var verifiedOn: String?
    public var notes: String?
    public var detection: Detection
    public var targets: [Target]

    public init(
        schemaVersion: Int = 1, id: String, name: String, vendor: String,
        category: Category, homepage: String? = nil, platforms: [String] = ["macos"],
        status: Status = .draft, verifiedOn: String? = nil, notes: String? = nil,
        detection: Detection, targets: [Target]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.vendor = vendor
        self.category = category
        self.homepage = homepage
        self.platforms = platforms
        self.status = status
        self.verifiedOn = verifiedOn
        self.notes = notes
        self.detection = detection
        self.targets = targets
    }
}

public struct Target: Codable, Sendable, Identifiable, Hashable {
    public enum Scope: String, Codable, Sendable {
        case global
        case project
    }

    public enum Kind: String, Codable, Sendable {
        case cache, log, history, config, credential, artifact, state
    }

    public struct Attribution: Codable, Sendable, Hashable {
        public enum Encoding: String, Codable, Sendable {
            case dashedAbsolute = "dashed-absolute"
        }
        public var encoding: Encoding
        public init(encoding: Encoding) { self.encoding = encoding }
    }

    public var id: String
    public var scope: Scope
    public var paths: [String]?
    public var projectGlobs: [String]?
    public var guardFiles: [String]?
    public var kind: Kind
    public var safety: Safety
    public var description: String
    public var regenerateHint: String?
    public var attribution: Attribution?

    public init(
        id: String, scope: Scope, paths: [String]? = nil,
        projectGlobs: [String]? = nil, guardFiles: [String]? = nil,
        kind: Kind, safety: Safety, description: String,
        regenerateHint: String? = nil, attribution: Attribution? = nil
    ) {
        self.id = id
        self.scope = scope
        self.paths = paths
        self.projectGlobs = projectGlobs
        self.guardFiles = guardFiles
        self.kind = kind
        self.safety = safety
        self.description = description
        self.regenerateHint = regenerateHint
        self.attribution = attribution
    }
}

// MARK: - Safety tiers (SPEC §4.3 — hard constraint)

public enum Safety: String, Codable, Sendable, Comparable {
    /// Deleting is harmless; the tool recreates it. Trash by default, direct delete behind a setting.
    case regenerable
    /// User asset; not recoverable once gone. Unchecked by default, per-item confirmation, trash only.
    case userData = "user_data"
    /// Credentials/config/volume data. Display only — no delete affordance exists for these.
    case protected

    private var rank: Int {
        switch self {
        case .regenerable: 0
        case .userData: 1
        case .protected: 2
        }
    }

    public static func < (lhs: Safety, rhs: Safety) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Discovered entities

/// A project root found under a user-selected code root directory.
public struct Project: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var lastActive: Date?

    public init(name: String, path: String, lastActive: Date? = nil) {
        self.name = name
        self.path = path
        self.lastActive = lastActive
    }
}

/// How a resource was attributed to a project (SPEC §5.3 evidence table).
public enum AttributionEvidence: Sendable, Hashable {
    /// The resource path lives inside the project root.
    case pathInsideProject
    /// A process's cwd is inside the project root.
    case processCwd
    /// Docker compose labels name the project working dir.
    case composeLabel
    /// A rule-declared path encoding (dashed-absolute) decoded to the project root.
    case encodedPath
    /// A container bind mount's host source is inside the project root.
    case bindMount
}

public struct ResourceAttribution: Sendable, Hashable {
    public var projectPath: String
    public var evidence: AttributionEvidence

    public init(projectPath: String, evidence: AttributionEvidence) {
        self.projectPath = projectPath
        self.evidence = evidence
    }
}

/// One discovered disk resource: a target hit at a concrete path.
public struct ResourceItem: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public var ruleID: String
    public var targetID: String
    public var path: String
    /// Allocated (physical) size in bytes; nil while sizing is still in flight.
    public var sizeBytes: Int64?
    public var kind: Target.Kind
    public var safety: Safety
    public var ruleStatus: Rule.Status
    public var attribution: ResourceAttribution?

    public init(
        ruleID: String, targetID: String, path: String, sizeBytes: Int64? = nil,
        kind: Target.Kind, safety: Safety, ruleStatus: Rule.Status = .draft,
        attribution: ResourceAttribution? = nil
    ) {
        self.ruleID = ruleID
        self.targetID = targetID
        self.path = path
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.safety = safety
        self.ruleStatus = ruleStatus
        self.attribution = attribution
    }
}

/// A discovered runtime service: a user process, usually listening on a TCP port.
public struct RunningService: Sendable, Identifiable, Hashable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var executablePath: String?
    public var listeningPorts: [UInt16]
    public var workingDirectory: String?
    public var residentMemoryBytes: UInt64
    public var startDate: Date
    public var attribution: ResourceAttribution?

    public init(
        pid: Int32, name: String, executablePath: String? = nil,
        listeningPorts: [UInt16] = [], workingDirectory: String? = nil,
        residentMemoryBytes: UInt64 = 0, startDate: Date,
        attribution: ResourceAttribution? = nil
    ) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.listeningPorts = listeningPorts
        self.workingDirectory = workingDirectory
        self.residentMemoryBytes = residentMemoryBytes
        self.startDate = startDate
        self.attribution = attribution
    }
}

/// A container-side resource (container/image/volume/build cache).
public struct ContainerResource: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        case runningContainer
        case stoppedContainer
        case danglingImage
        case taggedImage
        case volume
        case buildCache
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var detail: String
    public var sizeBytes: Int64?
    public var safety: Safety
    public var composeProject: String?
    public var attribution: ResourceAttribution?

    public init(
        id: String, kind: Kind, name: String, detail: String = "",
        sizeBytes: Int64? = nil, safety: Safety,
        composeProject: String? = nil, attribution: ResourceAttribution? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.safety = safety
        self.composeProject = composeProject
        self.attribution = attribution
    }
}
