// SPDX-License-Identifier: Apache-2.0
// Session grouping follows the attribution evidence chain (SPEC §5.13).
import Foundation
import Testing
@testable import Core

@Suite("Dev sessions")
struct DevSessionsTests {
    private let projects = [
        Project(name: "admin", path: "/Users/test/dev/admin"),
        Project(name: "idle", path: "/Users/test/dev/idle"),
    ]

    private func service(pid: Int32, project: String?, ports: [UInt16] = [], memory: UInt64 = 0) -> RunningService {
        RunningService(
            pid: pid, name: "node", listeningPorts: ports,
            residentMemoryBytes: memory, startDate: .distantPast,
            attribution: project.map { ResourceAttribution(projectPath: $0, evidence: .processCwd) }
        )
    }

    @Test("resources group into sessions by project attribution")
    func grouping() {
        let services = [
            service(pid: 1, project: "/Users/test/dev/admin", ports: [3000], memory: 100),
            service(pid: 2, project: "/Users/test/dev/admin", ports: [8080], memory: 50),
            service(pid: 3, project: nil, ports: [9999]),
        ]
        let containers = [
            ContainerResource(
                id: "c:redis", kind: .runningContainer, name: "redis-dev", safety: .regenerable,
                attribution: ResourceAttribution(projectPath: "/Users/test/dev/admin", evidence: .composeLabel)
            ),
            ContainerResource(
                id: "c:old", kind: .stoppedContainer, name: "old", safety: .regenerable,
                attribution: ResourceAttribution(projectPath: "/Users/test/dev/admin", evidence: .composeLabel)
            ),
        ]
        let sessions = SessionResolver().resolve(projects: projects, services: services, containers: containers)

        #expect(sessions.count == 1)
        let session = sessions[0]
        #expect(session.projectName == "admin")
        #expect(session.services.count == 2)
        // Stopped containers never join a session.
        #expect(session.containers.map(\.name) == ["redis-dev"])
        #expect(session.ports == [3000, 8080])
        #expect(session.totalMemoryBytes == 150)
        #expect(session.resourceCount == 3)
    }

    @Test("no running resources means no sessions")
    func emptyWhenIdle() {
        let sessions = SessionResolver().resolve(projects: projects, services: [], containers: [])
        #expect(sessions.isEmpty)
    }

    @Test("unattributed resources never form a session")
    func unattributedExcluded() {
        let sessions = SessionResolver().resolve(
            projects: projects,
            services: [service(pid: 9, project: nil, ports: [5000])],
            containers: []
        )
        #expect(sessions.isEmpty)
    }

    @Test("sessions sort by resource count")
    func sorting() {
        let services = [
            service(pid: 1, project: "/Users/test/dev/idle"),
            service(pid: 2, project: "/Users/test/dev/admin"),
            service(pid: 3, project: "/Users/test/dev/admin"),
        ]
        let sessions = SessionResolver().resolve(projects: projects, services: services, containers: [])
        #expect(sessions.map(\.projectName) == ["admin", "idle"])
    }

    @Test("template store round-trips and replaces by name")
    func templateStore() {
        let dir = NSTemporaryDirectory() + "mothball-templates-\(UUID().uuidString)"
        let store = SessionTemplateStore(storePath: dir + "/templates.json")
        #expect(store.load().isEmpty)

        store.add(SessionTemplate(name: "Frontend", projectPath: "/Users/test/dev/admin"))
        store.add(SessionTemplate(name: "Frontend", projectPath: "/Users/test/dev/admin", stopContainers: false))
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].stopContainers == false)

        store.remove(named: "Frontend")
        #expect(store.load().isEmpty)
        try? FileManager.default.removeItem(atPath: dir)
    }
}
