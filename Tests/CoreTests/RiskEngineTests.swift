// SPDX-License-Identifier: Apache-2.0
// Mapping invariants for the presentation-layer risk scores (SPEC §4.4):
// user_data/protected are always S3, and scores only ever tighten defaults.
import Foundation
import Testing
@testable import Core

@Suite("Risk engine")
struct RiskEngineTests {
    private func item(
        safety: Safety,
        project: String? = nil
    ) -> ResourceItem {
        ResourceItem(
            ruleID: "npm", targetID: "cacache", path: "/Users/test/.npm/_cacache",
            sizeBytes: 1000, kind: .cache, safety: safety,
            attribution: project.map { ResourceAttribution(projectPath: $0, evidence: .pathInsideProject) }
        )
    }

    @Test("user_data is always S3, regardless of activity signals")
    func userDataAlwaysS3() {
        let engine = RiskEngine(
            inUseProjectPaths: [], dirtyProjectPaths: [],
            lastActiveByProject: [:],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let assessment = engine.assess(item(safety: .userData, project: "/Users/test/dev/idle"))
        #expect(assessment.tier == .s3)
        #expect(assessment.reasons == [.userData])
    }

    @Test("protected is always S3")
    func protectedAlwaysS3() {
        let engine = RiskEngine()
        #expect(engine.assess(item(safety: .protected)).tier == .s3)
    }

    @Test("regenerable in an in-use project is S2 (tightened, never loosened)")
    func inUseProjectTightensToS2() {
        let engine = RiskEngine(inUseProjectPaths: ["/Users/test/dev/app"])
        let assessment = engine.assess(item(safety: .regenerable, project: "/Users/test/dev/app"))
        #expect(assessment.tier == .s2)
        #expect(assessment.reasons == [.projectInUse])
    }

    @Test("regenerable in a git-dirty project is S1 — active, but not in use")
    func gitDirtyIsS1() {
        let engine = RiskEngine(dirtyProjectPaths: ["/Users/test/dev/app"])
        let assessment = engine.assess(item(safety: .regenerable, project: "/Users/test/dev/app"))
        #expect(assessment.tier == .s1)
        #expect(assessment.reasons == [.gitDirty])
    }

    @Test("in-use beats git-dirty in the reported reason")
    func inUseWinsOverDirty() {
        let engine = RiskEngine(
            inUseProjectPaths: ["/Users/test/dev/app"],
            dirtyProjectPaths: ["/Users/test/dev/app"]
        )
        #expect(engine.assess(item(safety: .regenerable, project: "/Users/test/dev/app")).reasons == [.projectInUse])
    }

    @Test("recently active project lands on S1")
    func recentActivityIsS1() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = RiskEngine(
            lastActiveByProject: ["/Users/test/dev/app": now.addingTimeInterval(-5 * 24 * 3600)],
            now: now
        )
        let assessment = engine.assess(item(safety: .regenerable, project: "/Users/test/dev/app"))
        #expect(assessment.tier == .s1)
        #expect(assessment.reasons == [.recentlyActive])
    }

    @Test("idle clean project lands on S0")
    func idleCleanProjectIsS0() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = RiskEngine(
            lastActiveByProject: ["/Users/test/dev/app": now.addingTimeInterval(-182 * 24 * 3600)],
            now: now
        )
        let assessment = engine.assess(item(safety: .regenerable, project: "/Users/test/dev/app"))
        #expect(assessment.tier == .s0)
        #expect(assessment.reasons == [.noActivitySignals])
    }

    @Test("global tool caches stay at S1, never S0")
    func globalCachesAreS1() {
        let engine = RiskEngine()
        let assessment = engine.assess(item(safety: .regenerable, project: nil))
        #expect(assessment.tier == .s1)
        #expect(assessment.reasons == [.toolCache])
    }

    @Test("container resources map through the same tiers")
    func containerMapping() {
        let engine = RiskEngine(inUseProjectPaths: ["/Users/test/dev/app"])
        let volume = ContainerResource(id: "v:pg", kind: .volume, name: "pg-data", safety: .protected)
        #expect(engine.assess(volume).tier == .s3)
        let container = ContainerResource(
            id: "c:web", kind: .runningContainer, name: "web", safety: .regenerable,
            attribution: ResourceAttribution(projectPath: "/Users/test/dev/app", evidence: .composeLabel)
        )
        #expect(engine.assess(container).tier == .s2)
    }

    @Test("tiers are ordered so consumers can compare against thresholds")
    func tierOrdering() {
        #expect(RiskTier.s0 < .s1)
        #expect(RiskTier.s1 < .s2)
        #expect(RiskTier.s2 < .s3)
    }
}
