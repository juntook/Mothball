// SPDX-License-Identifier: Apache-2.0
import Foundation

/// One user-defined protection rule (SPEC §5.12). Protected objects never
/// join batch operations, start unchecked, and carry a lock badge.
public struct ProtectionRule: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case path
        case pathPrefix
        case processName
        case port
        case volumeName
    }

    public var kind: Kind
    public var value: String

    public var id: String { "\(kind.rawValue):\(value)" }

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}

/// Versioned JSON store under Application Support (SPEC §5.12).
public struct ProtectionRuleStore: Sendable {
    public static let defaultStorePath = "~/Library/Application Support/Mothball/protection.json"

    private struct FileShape: Codable {
        var schemaVersion: Int
        var rules: [ProtectionRule]
    }

    private let storeURL: URL

    public init(storePath: String = ProtectionRuleStore.defaultStorePath, fs: any FileSystem = RealFileSystem()) {
        let expanded = storePath.hasPrefix("~")
            ? fs.homeDirectoryPath + storePath.dropFirst()
            : storePath
        storeURL = URL(fileURLWithPath: expanded)
    }

    public func load() -> [ProtectionRule] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(FileShape.self, from: data)
        else { return [] }
        return decoded.rules
    }

    public func save(_ rules: [ProtectionRule]) {
        let shape = FileShape(schemaVersion: 1, rules: rules)
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(shape).write(to: storeURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("protection store write failed: \(error)\n".utf8))
        }
    }

    public func add(_ rule: ProtectionRule) {
        var rules = load()
        guard !rules.contains(rule) else { return }
        rules.append(rule)
        save(rules)
    }

    public func remove(_ rule: ProtectionRule) {
        save(load().filter { $0 != rule })
    }
}

/// Fast membership checks over a rule set (SPEC §5.12). Path matching is
/// case-insensitive (APFS default) on exact paths and prefixes.
public struct ProtectionEvaluator: Sendable {
    private let exactPaths: Set<String>
    private let pathPrefixes: [String]
    private let processNames: Set<String>
    private let ports: Set<UInt16>
    private let volumeNames: Set<String>

    public init(rules: [ProtectionRule]) {
        var exact = Set<String>()
        var prefixes = [String]()
        var processes = Set<String>()
        var portSet = Set<UInt16>()
        var volumes = Set<String>()
        for rule in rules {
            switch rule.kind {
            case .path:
                exact.insert(Self.normalize(rule.value))
            case .pathPrefix:
                prefixes.append(Self.normalize(rule.value))
            case .processName:
                processes.insert(rule.value.lowercased())
            case .port:
                if let port = UInt16(rule.value.trimmingCharacters(in: .whitespaces)) {
                    portSet.insert(port)
                }
            case .volumeName:
                volumes.insert(rule.value)
            }
        }
        exactPaths = exact
        pathPrefixes = prefixes
        processNames = processes
        ports = portSet
        volumeNames = volumes
    }

    public var isEmpty: Bool {
        exactPaths.isEmpty && pathPrefixes.isEmpty && processNames.isEmpty
            && ports.isEmpty && volumeNames.isEmpty
    }

    public func isProtected(path: String) -> Bool {
        let normalized = Self.normalize(path)
        if exactPaths.contains(normalized) { return true }
        return pathPrefixes.contains { prefix in
            normalized == prefix || normalized.hasPrefix(prefix + "/")
        }
    }

    public func isProtected(processName: String) -> Bool {
        processNames.contains(processName.lowercased())
    }

    public func isProtected(port: UInt16) -> Bool {
        ports.contains(port)
    }

    /// A running service is protected when its name or any listening port is.
    public func isProtected(service: RunningService) -> Bool {
        isProtected(processName: service.name) || service.listeningPorts.contains(where: isProtected(port:))
    }

    public func isProtected(volumeName: String) -> Bool {
        volumeNames.contains(volumeName)
    }

    private static func normalize(_ path: String) -> String {
        var value = path.lowercased()
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
