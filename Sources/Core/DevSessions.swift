// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A development session: the running resources attributed to one project
/// (SPEC §5.13).
public struct DevSession: Sendable, Identifiable, Hashable {
    public var id: String { projectPath }
    public var projectPath: String
    public var projectName: String
    public var services: [RunningService]
    /// Running containers attributed to the project.
    public var containers: [ContainerResource]

    public var ports: [UInt16] {
        services.flatMap(\.listeningPorts).sorted()
    }

    public var totalMemoryBytes: Int64 {
        Int64(services.reduce(0) { $0 + $1.residentMemoryBytes })
    }

    public var resourceCount: Int { services.count + containers.count }

    public init(projectPath: String, projectName: String, services: [RunningService], containers: [ContainerResource]) {
        self.projectPath = projectPath
        self.projectName = projectName
        self.services = services
        self.containers = containers
    }
}

/// Groups running resources into sessions by project attribution
/// (SPEC §5.13): same evidence chain as everywhere else, no new heuristics.
public struct SessionResolver: Sendable {
    public init() {}

    public func resolve(
        projects: [Project],
        services: [RunningService],
        containers: [ContainerResource]
    ) -> [DevSession] {
        let namesByPath = Dictionary(
            projects.map { ($0.path, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        var servicesByProject = [String: [RunningService]]()
        for service in services {
            guard let path = service.attribution?.projectPath else { continue }
            servicesByProject[path, default: []].append(service)
        }

        var containersByProject = [String: [ContainerResource]]()
        for container in containers where container.kind == .runningContainer {
            guard let path = container.attribution?.projectPath else { continue }
            containersByProject[path, default: []].append(container)
        }

        let paths = Set(servicesByProject.keys).union(containersByProject.keys)
        return paths.map { path in
            DevSession(
                projectPath: path,
                projectName: namesByPath[path] ?? (path as NSString).lastPathComponent,
                services: servicesByProject[path] ?? [],
                containers: containersByProject[path] ?? []
            )
        }
        .filter { $0.resourceCount > 0 }
        .sorted {
            ($0.resourceCount, $0.projectName) > ($1.resourceCount, $1.projectName)
        }
    }
}

/// A saved way to end one project's session (SPEC §5.13 templates).
public struct SessionTemplate: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name }
    public var name: String
    public var projectPath: String
    public var stopProcesses: Bool
    public var stopContainers: Bool

    public init(name: String, projectPath: String, stopProcesses: Bool = true, stopContainers: Bool = true) {
        self.name = name
        self.projectPath = projectPath
        self.stopProcesses = stopProcesses
        self.stopContainers = stopContainers
    }
}

/// Versioned JSON store for session templates.
public struct SessionTemplateStore: Sendable {
    public static let defaultStorePath = "~/Library/Application Support/Mothball/session-templates.json"

    private struct FileShape: Codable {
        var schemaVersion: Int
        var templates: [SessionTemplate]
    }

    private let storeURL: URL

    public init(storePath: String = SessionTemplateStore.defaultStorePath, fs: any FileSystem = RealFileSystem()) {
        let expanded = storePath.hasPrefix("~")
            ? fs.homeDirectoryPath + storePath.dropFirst()
            : storePath
        storeURL = URL(fileURLWithPath: expanded)
    }

    public func load() -> [SessionTemplate] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(FileShape.self, from: data)
        else { return [] }
        return decoded.templates
    }

    public func save(_ templates: [SessionTemplate]) {
        let shape = FileShape(schemaVersion: 1, templates: templates)
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(shape).write(to: storeURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("session template store write failed: \(error)\n".utf8))
        }
    }

    public func add(_ template: SessionTemplate) {
        var templates = load().filter { $0.name != template.name }
        templates.append(template)
        save(templates)
    }

    public func remove(named name: String) {
        save(load().filter { $0.name != name })
    }
}
