// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

/// Canned docker CLI runner; recorded shapes come from a real Colima engine.
final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    var responses: [String: String] = [:]
    var calls: [[String]] = []
    struct NoResponse: Error {}

    func run(executable: String, arguments: [String]) throws -> Data {
        calls.append([executable] + arguments)
        let key = arguments.joined(separator: " ")
        guard let response = responses[key] else { throw NoResponse() }
        return Data(response.utf8)
    }
}

private let psJSON = """
{"ID":"7ba876cdea44","Image":"db-db","Labels":"com.docker.compose.project=db,com.docker.compose.project.working_dir=/Users/me/dev/echo/db,com.docker.compose.service=db","Mounts":"db_echo-pg-data","Names":"echo-pg","Ports":"0.0.0.0:5432->5432/tcp","RunningFor":"11 hours ago","State":"running","Status":"Up 11 hours"}
{"ID":"fb97bb9f652a","Image":"aigw-server:dev","Labels":"com.docker.compose.project=ai-gateway,com.docker.compose.project.working_dir=/Users/me/dev/ai-gateway","Mounts":"","Names":"aigw-gateway","Ports":"0.0.0.0:8080->8080/tcp","RunningFor":"3 days ago","State":"running","Status":"Up 11 hours (healthy)"}
{"ID":"aaaa00000001","Image":"redis:7","Labels":"","Mounts":"","Names":"scratch-redis","Ports":"","RunningFor":"2 weeks ago","State":"exited","Status":"Exited (0) 2 weeks ago"}
"""

private let imagesJSON = """
{"ID":"sha256:7e52efb841f9","Repository":"db-db","Tag":"latest","Size":"479MB","CreatedSince":"11 hours ago"}
{"ID":"sha256:0e2074125708","Repository":"aigw-server","Tag":"dev","Size":"34.7MB","CreatedSince":"3 days ago"}
{"ID":"sha256:deadbeef0001","Repository":"<none>","Tag":"<none>","Size":"1.2GB","CreatedSince":"5 weeks ago"}
{"ID":"sha256:cafebabe0002","Repository":"old-experiment","Tag":"v1","Size":"850MB","CreatedSince":"3 months ago"}
{"ID":"sha256:feedface0003","Repository":"redis","Tag":"7","Size":"117MB","CreatedSince":"2 months ago"}
"""

private let volumesJSON = """
{"Name":"db_echo-pg-data","Labels":"com.docker.compose.project=db,com.docker.compose.volume=echo-pg-data"}
{"Name":"orphan-vol","Labels":""}
"""

private let volumesDanglingJSON = """
{"Name":"orphan-vol","Labels":""}
"""

private let dfJSON = """
{"Active":"12","Reclaimable":"3.06GB (54%)","Size":"5.64GB","TotalCount":"87","Type":"Images"}
{"Active":"5","Reclaimable":"2.481kB (7%)","Size":"33.67kB","TotalCount":"14","Type":"Containers"}
{"Active":"9","Reclaimable":"1.161GB (46%)","Size":"2.502GB","TotalCount":"17","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"13.44GB","Size":"13.44GB","TotalCount":"381","Type":"Build Cache"}
"""

private let inspectJSON = """
[{"Id":"7ba876cdea44","Mounts":[{"Type":"volume","Name":"db_echo-pg-data","Source":"/var/lib/docker/volumes/db_echo-pg-data/_data"}]},{"Id":"fb97bb9f652a","Mounts":[]},{"Id":"aaaa00000001","Mounts":[{"Type":"bind","Source":"/Users/me/dev/echo/scripts"}]}]
"""

@Suite("Docker CLI parsing")
struct DockerParsingTests {
    func makeClient() -> (DockerClient, FakeCommandRunner) {
        let runner = FakeCommandRunner()
        runner.responses["ps -a --no-trunc --format json"] = psJSON
        runner.responses["images -a --format json"] = imagesJSON
        runner.responses["volume ls --format json"] = volumesJSON
        runner.responses["volume ls --filter dangling=true --format json"] = volumesDanglingJSON
        runner.responses["system df --format json"] = dfJSON
        runner.responses["container inspect --format json 7ba876cdea44 fb97bb9f652a aaaa00000001"] = inspectJSON
        return (DockerClient(binary: "/opt/homebrew/bin/docker", runner: runner), runner)
    }

    @Test("Containers parse with compose labels")
    func containers() throws {
        let (client, _) = makeClient()
        let rows = try client.listContainers()
        #expect(rows.count == 3)
        #expect(rows[0].compose?.project == "db")
        #expect(rows[0].compose?.workingDir == "/Users/me/dev/echo/db")
        #expect(rows[2].compose == nil)
        #expect(rows[2].state == "exited")
    }

    @Test("Human sizes parse with SI units")
    func humanSizes() {
        #expect(DockerClient.parseHumanSize("479MB") == 479_000_000)
        #expect(DockerClient.parseHumanSize("13.44GB") == 13_440_000_000)
        #expect(DockerClient.parseHumanSize("2.481kB") == 2_481)
        #expect(DockerClient.parseHumanSize("0B") == 0)
        #expect(DockerClient.parseHumanSize("117MB") == 117_000_000)
    }

    @Test("Dangling detection via <none> repo/tag")
    func dangling() throws {
        let (client, _) = makeClient()
        let images = try client.listImages()
        #expect(images.filter(\.isDangling).map(\.id) == ["sha256:deadbeef0001"])
    }

    @Test("Volume dangling filter cross-references")
    func volumes() throws {
        let (client, _) = makeClient()
        let volumes = try client.listVolumes()
        #expect(volumes.first { $0.name == "orphan-vol" }?.isDangling == true)
        #expect(volumes.first { $0.name == "db_echo-pg-data" }?.isDangling == false)
        #expect(volumes.first { $0.name == "db_echo-pg-data" }?.composeProject == "db")
    }

    @Test("system df totals")
    func diskUsage() throws {
        let (client, _) = makeClient()
        let usage = try client.diskUsage()
        #expect(usage.buildCacheBytes == 13_440_000_000)
        #expect(usage.imagesBytes == 5_640_000_000)
    }
}

@Suite("Container resource scanner")
struct ContainerScannerTests {
    let projects = [
        Project(name: "echo", path: "/Users/me/dev/echo"),
        Project(name: "ai-gateway", path: "/Users/me/dev/ai-gateway"),
    ]
    let fs = FakeFileSystem(home: "/Users/me", entries: [
        "/Users/me/dev/echo/README.md": false,
        "/Users/me/dev/ai-gateway/README.md": false,
    ])

    func makeScanner() -> (ContainerResourceScanner, FakeCommandRunner) {
        let runner = FakeCommandRunner()
        runner.responses["ps -a --no-trunc --format json"] = psJSON
        runner.responses["images -a --format json"] = imagesJSON
        runner.responses["volume ls --format json"] = volumesJSON
        runner.responses["volume ls --filter dangling=true --format json"] = volumesDanglingJSON
        runner.responses["system df --format json"] = dfJSON
        runner.responses["container inspect --format json 7ba876cdea44 fb97bb9f652a aaaa00000001"] = inspectJSON
        let client = DockerClient(binary: "/opt/homebrew/bin/docker", runner: runner)
        return (ContainerResourceScanner(client: client), runner)
    }

    func scan() throws -> [ContainerResource] {
        try makeScanner().0.scan(projects: projects, fs: fs).resources
    }

    @Test("Compose working dir attributes containers (evidence 3)")
    func composeAttribution() throws {
        let resources = try scan()
        let db = resources.first { $0.name == "echo-pg" }
        #expect(db?.attribution?.projectPath == "/Users/me/dev/echo")
        #expect(db?.attribution?.evidence == .composeLabel)
        #expect(db?.composeProject == "db")
    }

    @Test("Bind mount source attributes label-less containers (evidence 5)")
    func bindMountAttribution() throws {
        let resources = try scan()
        let scratch = resources.first { $0.name == "scratch-redis" }
        #expect(scratch?.kind == .stoppedContainer)
        #expect(scratch?.attribution?.projectPath == "/Users/me/dev/echo")
        #expect(scratch?.attribution?.evidence == .bindMount)
    }

    @Test("Safety matrix: dangling regenerable, tagged-unused user_data, volumes protected")
    func safetyMatrix() throws {
        let resources = try scan()
        let dangling = resources.first { $0.kind == .danglingImage }
        #expect(dangling?.safety == .regenerable)

        let taggedUnused = resources.filter { $0.kind == .taggedImage }
        #expect(Set(taggedUnused.map(\.name)) == ["old-experiment:v1"])
        #expect(taggedUnused.allSatisfy { $0.safety == .userData })

        // redis:7 backs the exited scratch container — must NOT be listed as unused.
        #expect(!resources.contains { $0.name == "redis:7" })
        // In-use tagged images (db-db, aigw-server) aren't offered either.
        #expect(!resources.contains { $0.name.hasPrefix("db-db") && $0.kind == .taggedImage })

        let volumes = resources.filter { $0.kind == .volume }
        #expect(volumes.count == 2)
        #expect(volumes.allSatisfy { $0.safety == .protected })
    }

    @Test("Volumes correlate to projects through compose siblings")
    func volumeAttribution() throws {
        let resources = try scan()
        let dbVolume = resources.first { $0.id == "volume:db_echo-pg-data" }
        #expect(dbVolume?.attribution?.projectPath == "/Users/me/dev/echo")
    }

    @Test("Build cache appears with df size")
    func buildCache() throws {
        let resources = try scan()
        let cache = resources.first { $0.kind == .buildCache }
        #expect(cache?.sizeBytes == 13_440_000_000)
        #expect(cache?.safety == .regenerable)
    }

    @Test("Actions never pass force flags and volumes are removed singly")
    func actionSafety() throws {
        let (scanner, runner) = makeScanner()
        _ = try scanner.scan(projects: projects, fs: fs)
        let client = DockerClient(binary: "/opt/homebrew/bin/docker", runner: runner)
        runner.responses["rm aaaa00000001"] = ""
        runner.responses["rmi old-experiment:v1"] = ""
        runner.responses["volume rm orphan-vol"] = ""
        try client.removeContainer(id: "aaaa00000001")
        try client.removeImage(reference: "old-experiment:v1")
        try client.removeVolume(name: "orphan-vol")
        let flat = runner.calls.map { $0.joined(separator: " ") }
        #expect(!flat.contains { $0.contains(" -f") || $0.contains("--force") })
    }
}

@Suite("Docker environment discovery")
struct DockerEnvironmentTests {
    @Test("Binary resolution walks fixed candidates only")
    func binaryResolution() {
        let fs = FakeFileSystem(home: "/Users/me", entries: [
            "/usr/local/bin/docker": false,
        ])
        let env = DockerEnvironment(fs: fs, runner: FakeCommandRunner())
        #expect(env.resolveBinary() == "/usr/local/bin/docker")

        let none = DockerEnvironment(fs: FakeFileSystem(home: "/Users/me"), runner: FakeCommandRunner())
        #expect(none.resolveBinary() == nil)
    }

    @Test("Diagnostics record sockets and unreachable daemon")
    func diagnostics() {
        let fs = FakeFileSystem(home: "/Users/me", entries: [
            "/opt/homebrew/bin/docker": false,
            "/Users/me/.colima/default/docker.sock": false,
        ])
        let runner = FakeCommandRunner() // no responses → probes fail
        let diag = DockerEnvironment(fs: fs, runner: runner).diagnose()
        #expect(diag.binaryPath == "/opt/homebrew/bin/docker")
        #expect(diag.socketCandidatesFound == ["/Users/me/.colima/default/docker.sock"])
        #expect(!diag.daemonReachable)
    }
}
