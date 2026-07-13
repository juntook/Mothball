// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Container-resource state for the Runtime view (SPEC §5.5).
@MainActor
@Observable
final class ContainerModel {
    private(set) var diagnostics: DockerEnvironment.Diagnostics?
    private(set) var resources: [ContainerResource] = []
    private(set) var isRefreshing = false
    private(set) var busyIDs: Set<String> = []
    var actionError: String?
    /// Volume pending the strong single-delete confirmation.
    var volumePendingRemoval: ContainerResource?
    /// Tagged image pending its per-item confirmation.
    var imagePendingRemoval: ContainerResource?

    private let auditLog = AuditLog()
    /// Refresh requested while one was in flight — replayed on completion so
    /// concurrent actions (e.g. the dangling-image batch) never end on a
    /// snapshot taken mid-batch.
    private var queuedRefreshProjects: [Project]?

    private var client: DockerClient? {
        guard let binary = diagnostics?.binaryPath, diagnostics?.daemonReachable == true else { return nil }
        return DockerClient(binary: binary)
    }

    func refresh(projects: [Project]) {
        guard !isRefreshing else {
            queuedRefreshProjects = projects
            return
        }
        isRefreshing = true
        Task {
            let (diag, found) = await Task.detached(priority: .userInitiated) { () -> (DockerEnvironment.Diagnostics, [ContainerResource]) in
                let diag = DockerEnvironment().diagnose()
                guard let binary = diag.binaryPath, diag.daemonReachable else { return (diag, []) }
                let scanner = ContainerResourceScanner(client: DockerClient(binary: binary))
                let result = (try? scanner.scan(projects: projects))?.resources ?? []
                return (diag, result)
            }.value
            diagnostics = diag
            resources = found
            isRefreshing = false
            if let queued = queuedRefreshProjects {
                queuedRefreshProjects = nil
                refresh(projects: queued)
            }
        }
    }

    // MARK: Actions (SPEC §5.5 operation matrix)

    func stopContainer(_ resource: ContainerResource, projects: [Project]) {
        perform(resource, projects: projects, method: "docker-stop") { client, id in
            try client.stopContainer(id: id)
        }
    }

    func removeContainer(_ resource: ContainerResource, projects: [Project]) {
        perform(resource, projects: projects, method: "docker-rm") { client, id in
            try client.removeContainer(id: id)
        }
    }

    func removeDanglingImage(_ resource: ContainerResource, projects: [Project]) {
        guard resource.kind == .danglingImage else { return }
        perform(resource, projects: projects, method: "docker-rmi") { client, _ in
            try client.removeImage(reference: "sha256:" + resource.name)
        }
    }

    /// All dangling images in one click — the only batch container operation.
    func removeAllDanglingImages(projects: [Project]) {
        let dangling = resources.filter { $0.kind == .danglingImage }
        for image in dangling {
            removeDanglingImage(image, projects: projects)
        }
    }

    /// Tagged image removal arrives here only after per-item confirmation.
    func removeTaggedImageConfirmed(projects: [Project]) {
        guard let resource = imagePendingRemoval else { return }
        imagePendingRemoval = nil
        perform(resource, projects: projects, method: "docker-rmi") { client, _ in
            try client.removeImage(reference: resource.name)
        }
    }

    /// Volume removal arrives here only after the strong confirmation.
    /// Volumes never join batch operations (SPEC §5.5).
    func removeVolumeConfirmed(projects: [Project]) {
        guard let resource = volumePendingRemoval else { return }
        volumePendingRemoval = nil
        perform(resource, projects: projects, method: "docker-volume-rm") { client, _ in
            try client.removeVolume(name: resource.name)
        }
    }

    func pruneBuildCache(projects: [Project]) {
        guard let cache = resources.first(where: { $0.kind == .buildCache }) else { return }
        perform(cache, projects: projects, method: "docker-builder-prune") { client, _ in
            try client.pruneBuildCache()
        }
    }

    private func perform(
        _ resource: ContainerResource,
        projects: [Project],
        method: String,
        _ operation: @escaping @Sendable (DockerClient, String) throws -> Void
    ) {
        guard let client, !busyIDs.contains(resource.id) else { return }
        busyIDs.insert(resource.id)
        let rawID = resource.id.components(separatedBy: ":").dropFirst().joined(separator: ":")
        Task {
            let failure: String? = await Task.detached {
                do {
                    try operation(client, rawID)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            busyIDs.remove(resource.id)
            auditLog.append(.init(
                ruleID: "docker",
                targetID: method,
                path: resource.name,
                bytes: resource.sizeBytes,
                method: method,
                result: failure ?? "ok"
            ))
            if let failure {
                actionError = failure
            } else {
                refresh(projects: projects)
            }
        }
    }
}
