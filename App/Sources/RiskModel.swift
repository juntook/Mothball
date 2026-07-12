// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Presentation-layer risk state (SPEC §4.4). Rebuilt whenever scan or
/// runtime data changes; git-dirty probing runs off the main actor and
/// feeds back into the next rebuild.
@MainActor
@Observable
final class RiskModel {
    /// ResourceItem.path → assessment.
    private(set) var itemAssessments: [String: RiskAssessment] = [:]
    /// ContainerResource.id → assessment.
    private(set) var containerAssessments: [String: RiskAssessment] = [:]
    private(set) var dirtyProjectPaths: Set<String> = []

    private var probedProjects: Set<String> = []

    func rebuild(
        items: [ResourceItem],
        containers: [ContainerResource],
        projects: [Project],
        services: [RunningService]
    ) {
        let inUse = Set(services.compactMap(\.attribution?.projectPath))
        let lastActive = Dictionary(
            projects.compactMap { project in project.lastActive.map { (project.path, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let engine = RiskEngine(
            inUseProjectPaths: inUse,
            dirtyProjectPaths: dirtyProjectPaths,
            lastActiveByProject: lastActive
        )
        itemAssessments = Dictionary(
            items.map { ($0.path, engine.assess($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        containerAssessments = Dictionary(
            containers.map { ($0.id, engine.assess($0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func assessment(for item: ResourceItem) -> RiskAssessment? {
        itemAssessments[item.path]
    }

    func assessment(for resource: ContainerResource) -> RiskAssessment? {
        containerAssessments[resource.id]
    }

    /// Probes uncommitted changes for newly seen projects, then triggers the
    /// caller-supplied rebuild once results land.
    func probeGitStatus(projects: [Project], onCompletion: @escaping @MainActor () -> Void) {
        let pending = projects.map(\.path).filter { !probedProjects.contains($0) }
        guard !pending.isEmpty else { return }
        probedProjects.formUnion(pending)
        Task {
            let dirty = await Task.detached(priority: .utility) { () -> Set<String> in
                let probe = GitStatusProbe()
                var result = Set<String>()
                for path in pending where probe.isDirty(projectPath: path) == true {
                    result.insert(path)
                }
                return result
            }.value
            guard !dirty.isEmpty else { return }
            dirtyProjectPaths.formUnion(dirty)
            onCompletion()
        }
    }
}
