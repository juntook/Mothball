// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Lists and manipulates engine-side resources by shelling out to the docker
/// CLI with `--format json` (SPEC §5.5; a UDS HTTP client is a V2 item).
public struct DockerClient: Sendable {
    public struct ComposeInfo: Sendable, Hashable {
        public var project: String
        public var workingDir: String?
    }

    private let binary: String
    private let runner: any CommandRunner

    public init(binary: String, runner: any CommandRunner = RealCommandRunner()) {
        self.binary = binary
        self.runner = runner
    }

    // MARK: Listing

    public struct ContainerRow: Sendable {
        public var id: String
        public var name: String
        public var image: String
        public var state: String
        public var status: String
        public var ports: String
        public var runningFor: String
        public var compose: ComposeInfo?
        public var mountNames: [String]
    }

    public func listContainers() throws -> [ContainerRow] {
        let lines = try runJSONLines(["ps", "-a", "--no-trunc", "--format", "json"])
        return lines.compactMap { obj in
            guard let id = obj["ID"] as? String else { return nil }
            let labels = parseLabels(obj["Labels"] as? String ?? "")
            var compose: ComposeInfo?
            if let project = labels["com.docker.compose.project"] {
                compose = ComposeInfo(project: project, workingDir: labels["com.docker.compose.project.working_dir"])
            }
            return ContainerRow(
                id: id,
                name: obj["Names"] as? String ?? "",
                image: obj["Image"] as? String ?? "",
                state: obj["State"] as? String ?? "",
                status: obj["Status"] as? String ?? "",
                ports: obj["Ports"] as? String ?? "",
                runningFor: obj["RunningFor"] as? String ?? "",
                compose: compose,
                mountNames: (obj["Mounts"] as? String ?? "").split(separator: ",").map(String.init)
            )
        }
    }

    public struct ImageRow: Sendable {
        public var id: String
        public var repository: String
        public var tag: String
        public var sizeBytes: Int64
        public var createdSince: String
        public var isDangling: Bool { repository == "<none>" || tag == "<none>" }
        public var reference: String { isDangling ? id : "\(repository):\(tag)" }
    }

    public func listImages() throws -> [ImageRow] {
        let lines = try runJSONLines(["images", "-a", "--format", "json"])
        return lines.compactMap { obj in
            guard let id = obj["ID"] as? String else { return nil }
            return ImageRow(
                id: id,
                repository: obj["Repository"] as? String ?? "<none>",
                tag: obj["Tag"] as? String ?? "<none>",
                sizeBytes: Self.parseHumanSize(obj["Size"] as? String ?? "0B"),
                createdSince: obj["CreatedSince"] as? String ?? ""
            )
        }
    }

    public struct VolumeRow: Sendable {
        public var name: String
        public var composeProject: String?
        public var isDangling: Bool
    }

    public func listVolumes() throws -> [VolumeRow] {
        let all = try runJSONLines(["volume", "ls", "--format", "json"])
        let dangling = try runJSONLines(["volume", "ls", "--filter", "dangling=true", "--format", "json"])
        let danglingNames = Set(dangling.compactMap { $0["Name"] as? String })
        return all.compactMap { obj in
            guard let name = obj["Name"] as? String else { return nil }
            let labels = parseLabels(obj["Labels"] as? String ?? "")
            return VolumeRow(
                name: name,
                composeProject: labels["com.docker.compose.project"],
                isDangling: danglingNames.contains(name)
            )
        }
    }

    public struct DiskUsage: Sendable {
        public var imagesBytes: Int64 = 0
        public var containersBytes: Int64 = 0
        public var volumesBytes: Int64 = 0
        public var buildCacheBytes: Int64 = 0
        public var buildCacheReclaimableBytes: Int64 = 0
    }

    public func diskUsage() throws -> DiskUsage {
        let lines = try runJSONLines(["system", "df", "--format", "json"])
        var usage = DiskUsage()
        for obj in lines {
            let size = Self.parseHumanSize(obj["Size"] as? String ?? "0B")
            let reclaimable = Self.parseHumanSize(
                (obj["Reclaimable"] as? String ?? "0B").components(separatedBy: " ").first ?? "0B"
            )
            switch obj["Type"] as? String {
            case "Images": usage.imagesBytes = size
            case "Containers": usage.containersBytes = size
            case "Local Volumes": usage.volumesBytes = size
            case "Build Cache":
                usage.buildCacheBytes = size
                usage.buildCacheReclaimableBytes = reclaimable
            default: break
            }
        }
        return usage
    }

    /// Bind-mount sources per container (SPEC §5.3 evidence 5), via inspect.
    public func bindMountSources(containerIDs: [String]) throws -> [String: [String]] {
        guard !containerIDs.isEmpty else { return [:] }
        let data = try runner.run(
            executable: binary,
            arguments: ["container", "inspect", "--format", "json"] + containerIDs
        )
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var result: [String: [String]] = [:]
        for obj in array {
            guard let id = obj["Id"] as? String else { continue }
            let mounts = obj["Mounts"] as? [[String: Any]] ?? []
            result[id] = mounts.compactMap { mount in
                (mount["Type"] as? String) == "bind" ? mount["Source"] as? String : nil
            }
        }
        return result
    }

    // MARK: Actions (each maps to one row of the SPEC §5.5 operation matrix)

    public func stopContainer(id: String) throws {
        _ = try runner.run(executable: binary, arguments: ["stop", id])
    }

    public func removeContainer(id: String) throws {
        // No -f: running containers must be stopped first, by design.
        _ = try runner.run(executable: binary, arguments: ["rm", id])
    }

    public func removeImage(reference: String) throws {
        // No -f: images still referenced by containers must not disappear.
        _ = try runner.run(executable: binary, arguments: ["rmi", reference])
    }

    public func removeVolume(name: String) throws {
        // No -f, single volume only — volumes never join batch operations.
        _ = try runner.run(executable: binary, arguments: ["volume", "rm", name])
    }

    public func pruneBuildCache() throws {
        _ = try runner.run(executable: binary, arguments: ["builder", "prune", "--force"])
    }

    // MARK: Parsing helpers

    private func runJSONLines(_ arguments: [String]) throws -> [[String: Any]] {
        let data = try runner.run(executable: binary, arguments: arguments)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
        }
    }

    func parseLabels(_ raw: String) -> [String: String] {
        var labels: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            labels[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        return labels
    }

    /// Parses docker's human sizes ("479MB", "13.44GB", "2.481kB", "0B").
    /// Docker uses decimal (SI) units.
    static func parseHumanSize(_ raw: String) -> Int64 {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let scanner = Scanner(string: trimmed)
        guard let value = scanner.scanDouble() else { return 0 }
        let unit = trimmed[scanner.currentIndex...].trimmingCharacters(in: .whitespaces).lowercased()
        let multiplier: Double
        switch unit {
        case "b", "": multiplier = 1
        case "kb": multiplier = 1e3
        case "mb": multiplier = 1e6
        case "gb": multiplier = 1e9
        case "tb": multiplier = 1e12
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }
}

/// Builds the UI-facing container resource list with safety tiers and compose
/// attribution (SPEC §5.5 matrix + §5.3 evidence 3/5).
public struct ContainerResourceScanner: Sendable {
    private let client: DockerClient

    public init(client: DockerClient) {
        self.client = client
    }

    public struct Result: Sendable {
        public var resources: [ContainerResource]
        /// Tagged image references still used by at least one container.
        public var referencedImages: Set<String>
    }

    public func scan(projects: [Project], fs: any FileSystem = RealFileSystem()) throws -> Result {
        let attribution = AttributionEngine(projects: projects, fs: fs)
        var resources: [ContainerResource] = []

        let containers = try client.listContainers()
        let bindMounts = (try? client.bindMountSources(containerIDs: containers.map(\.id))) ?? [:]

        for container in containers {
            var attributed: ResourceAttribution?
            if let workingDir = container.compose?.workingDir {
                attributed = attribution.attributeComposeWorkingDir(workingDir)
            }
            if attributed == nil {
                for source in bindMounts[container.id] ?? [] {
                    if let hit = attribution.attributeBindMountSource(source) {
                        attributed = hit
                        break
                    }
                }
            }
            let running = container.state == "running"
            resources.append(ContainerResource(
                id: "container:\(container.id)",
                kind: running ? .runningContainer : .stoppedContainer,
                name: container.name,
                detail: "\(container.image)  \(running ? container.ports : container.status)",
                sizeBytes: nil,
                safety: .regenerable,
                composeProject: container.compose?.project,
                attribution: attributed
            ))
        }

        let referencedImageNames = Set(containers.map(\.image))
        for image in try client.listImages() {
            if image.isDangling {
                resources.append(ContainerResource(
                    id: "image:\(image.id)",
                    kind: .danglingImage,
                    name: image.id.replacingOccurrences(of: "sha256:", with: "").prefix(12).description,
                    detail: image.createdSince,
                    sizeBytes: image.sizeBytes,
                    safety: .regenerable
                ))
            } else if !referencedImageNames.contains(image.reference)
                && !referencedImageNames.contains(image.repository) {
                // Tagged but unreferenced: re-pull/rebuild costs — user_data tier.
                resources.append(ContainerResource(
                    id: "image:\(image.id):\(image.reference)",
                    kind: .taggedImage,
                    name: image.reference,
                    detail: image.createdSince,
                    sizeBytes: image.sizeBytes,
                    safety: .userData
                ))
            }
        }

        for volume in try client.listVolumes() {
            var attributed: ResourceAttribution?
            if volume.composeProject != nil {
                // Compose volume names carry no working dir; correlate through
                // a container of the same compose project when one exists.
                if let sibling = containers.first(where: { $0.compose?.project == volume.composeProject }),
                   let workingDir = sibling.compose?.workingDir {
                    attributed = attribution.attributeComposeWorkingDir(workingDir)
                }
            }
            resources.append(ContainerResource(
                id: "volume:\(volume.name)",
                kind: .volume,
                name: volume.name,
                detail: volume.isDangling ? "dangling" : "in use",
                sizeBytes: nil,
                safety: .protected,
                composeProject: volume.composeProject,
                attribution: attributed
            ))
        }

        if let usage = try? client.diskUsage(), usage.buildCacheBytes > 0 {
            resources.append(ContainerResource(
                id: "build-cache",
                kind: .buildCache,
                name: "build cache",
                detail: "",
                sizeBytes: usage.buildCacheBytes,
                safety: .regenerable
            ))
        }

        return Result(resources: resources, referencedImages: referencedImageNames)
    }
}
