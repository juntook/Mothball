// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Container resources for the Runtime view (SPEC §5.5 matrix).
struct ContainerSection: View {
    @Environment(ScanModel.self) private var scan
    @Environment(ContainerModel.self) private var containers

    var body: some View {
        @Bindable var containers = containers
        return Group {
            if let diag = containers.diagnostics, diag.binaryPath == nil {
                emptyCard(
                    title: "docker.noBinary.title",
                    message: "docker.noBinary.message",
                    icon: "shippingbox"
                )
            } else if let diag = containers.diagnostics, !diag.daemonReachable {
                emptyCard(
                    title: "docker.daemonDown.title",
                    message: "docker.daemonDown.message",
                    icon: "shippingbox"
                )
            } else {
                resourceList
            }
        }
        .confirmationDialog(
            Text("docker.volume.confirm.title", bundle: .module),
            isPresented: Binding(
                get: { containers.volumePendingRemoval != nil },
                set: { if !$0 { containers.volumePendingRemoval = nil } }
            ),
            presenting: containers.volumePendingRemoval
        ) { volume in
            Button(role: .destructive) {
                containers.removeVolumeConfirmed(projects: scan.projects)
            } label: {
                Text("docker.volume.confirm.button \(volume.name)", bundle: .module)
            }
        } message: { volume in
            Text("docker.volume.confirm.message \(volume.name)", bundle: .module)
        }
        .confirmationDialog(
            Text("docker.image.confirm.title", bundle: .module),
            isPresented: Binding(
                get: { containers.imagePendingRemoval != nil },
                set: { if !$0 { containers.imagePendingRemoval = nil } }
            ),
            presenting: containers.imagePendingRemoval
        ) { image in
            Button(role: .destructive) {
                containers.removeTaggedImageConfirmed(projects: scan.projects)
            } label: {
                Text("docker.image.confirm.button", bundle: .module)
            }
        } message: { image in
            Text("docker.image.confirm.message \(image.name)", bundle: .module)
        }
        .alert(
            Text("docker.error.title", bundle: .module),
            isPresented: Binding(
                get: { containers.actionError != nil },
                set: { if !$0 { containers.actionError = nil } }
            )
        ) {
            Button {
                containers.actionError = nil
            } label: {
                Text("cleanup.done", bundle: .module)
            }
        } message: {
            Text(verbatim: containers.actionError ?? "")
        }
    }

    private var resourceList: some View {
        List {
            if let podman = containers.diagnostics?.podmanDetected, podman {
                Section {
                    Label {
                        Text("docker.podman.notice", bundle: .module)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            let running = containers.resources.filter { $0.kind == .runningContainer }
            let stopped = containers.resources.filter { $0.kind == .stoppedContainer }
            let dangling = containers.resources.filter { $0.kind == .danglingImage }
            let tagged = containers.resources.filter { $0.kind == .taggedImage }
            let volumes = containers.resources.filter { $0.kind == .volume }
            let cache = containers.resources.first { $0.kind == .buildCache }

            if !running.isEmpty {
                Section {
                    ForEach(running) { resource in
                        row(resource) {
                            actionButton("docker.action.stop", resource: resource) {
                                containers.stopContainer(resource, projects: scan.projects)
                            }
                        }
                    }
                } header: {
                    Text("docker.section.running", bundle: .module)
                }
            }

            if !stopped.isEmpty {
                Section {
                    ForEach(stopped) { resource in
                        row(resource) {
                            actionButton("docker.action.remove", resource: resource) {
                                containers.removeContainer(resource, projects: scan.projects)
                            }
                        }
                    }
                } header: {
                    Text("docker.section.stopped", bundle: .module)
                }
            }

            if !dangling.isEmpty {
                Section {
                    ForEach(dangling) { resource in
                        row(resource) {
                            actionButton("docker.action.remove", resource: resource) {
                                containers.removeDanglingImage(resource, projects: scan.projects)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("docker.section.dangling", bundle: .module)
                        Spacer()
                        Button {
                            containers.removeAllDanglingImages(projects: scan.projects)
                        } label: {
                            Text("docker.action.removeAllDangling \(dangling.count)", bundle: .module)
                        }
                        .controlSize(.small)
                    }
                }
            }

            if !tagged.isEmpty {
                Section {
                    ForEach(tagged) { resource in
                        row(resource) {
                            actionButton("docker.action.remove", resource: resource) {
                                containers.imagePendingRemoval = resource
                            }
                        }
                    }
                } header: {
                    Text("docker.section.taggedUnused", bundle: .module)
                } footer: {
                    Text("docker.taggedUnused.footer", bundle: .module).font(.caption)
                }
            }

            if !volumes.isEmpty {
                Section {
                    ForEach(volumes) { resource in
                        row(resource) {
                            actionButton("docker.action.removeVolume", resource: resource) {
                                containers.volumePendingRemoval = resource
                            }
                        }
                    }
                } header: {
                    Text("docker.section.volumes", bundle: .module)
                } footer: {
                    Text("docker.volumes.footer", bundle: .module).font(.caption)
                }
            }

            if let cache {
                Section {
                    row(cache) {
                        actionButton("docker.action.prune", resource: cache) {
                            containers.pruneBuildCache(projects: scan.projects)
                        }
                    }
                } header: {
                    Text("docker.section.buildCache", bundle: .module)
                }
            }
        }
    }

    private func row(_ resource: ContainerResource, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: resource.name)
                    SafetyBadge(safety: resource.safety)
                }
                HStack(spacing: 8) {
                    if !resource.detail.isEmpty {
                        Text(verbatim: resource.detail)
                    }
                    if let project = resource.attribution {
                        Label {
                            Text(verbatim: (project.projectPath as NSString).lastPathComponent)
                        } icon: {
                            Image(systemName: "folder")
                        }
                        .help(Text("evidence.composeLabel", bundle: .module))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let bytes = resource.sizeBytes {
                SizeText(bytes: bytes).font(.callout)
            }
            action()
        }
    }

    private func actionButton(_ key: LocalizedStringKey, resource: ContainerResource, perform: @escaping () -> Void) -> some View {
        Group {
            if containers.busyIDs.contains(resource.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(action: perform) {
                    Text(key, bundle: .module)
                }
                .controlSize(.small)
            }
        }
    }

    private func emptyCard(title: LocalizedStringKey, message: LocalizedStringKey, icon: String) -> some View {
        ContentUnavailableView {
            Label {
                Text(title, bundle: .module)
            } icon: {
                Image(systemName: icon)
            }
        } description: {
            Text(message, bundle: .module)
        }
    }
}
