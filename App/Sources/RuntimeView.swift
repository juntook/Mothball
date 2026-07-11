// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Running services table (SPEC §5.4/§5.7). Refreshes on appear; manual
/// refresh in the toolbar. Container resources join this view in M5.
struct RuntimeView: View {
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime

    var body: some View {
        @Bindable var runtime = runtime
        return Group {
            if runtime.services.isEmpty && !runtime.isRefreshing {
                ContentUnavailableView {
                    Label {
                        Text("runtime.empty.title", bundle: .module)
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                    }
                } description: {
                    Text("runtime.empty.description", bundle: .module)
                }
            } else {
                serviceTable
            }
        }
        .navigationTitle(Text("sidebar.runtime", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    runtime.refresh(projects: scan.projects)
                } label: {
                    if runtime.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label {
                            Text("runtime.refresh", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(runtime.isRefreshing)
            }
        }
        .task {
            runtime.refresh(projects: scan.projects)
        }
        .confirmationDialog(
            Text("runtime.forceKill.title", bundle: .module),
            isPresented: Binding(
                get: { runtime.pendingForceKill != nil },
                set: { if !$0 { runtime.pendingForceKill = nil } }
            ),
            presenting: runtime.pendingForceKill
        ) { service in
            Button(role: .destructive) {
                runtime.forceKill(service, projects: scan.projects)
            } label: {
                Text("runtime.forceKill.button", bundle: .module)
            }
        } message: { service in
            Text("runtime.forceKill.message \(service.name) \(Int(service.pid))", bundle: .module)
        }
        .alert(
            Text("runtime.stale.title", bundle: .module),
            isPresented: $runtime.staleServiceNotice
        ) {
            Button {
                runtime.staleServiceNotice = false
            } label: {
                Text("cleanup.done", bundle: .module)
            }
        } message: {
            Text("runtime.stale.message", bundle: .module)
        }
    }

    private var serviceTable: some View {
        Table(runtime.services) {
            TableColumn(Text("runtime.column.port", bundle: .module)) { service in
                Text(verbatim: service.listeningPorts.isEmpty
                    ? "—"
                    : service.listeningPorts.map(String.init).joined(separator: ", "))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 90)

            TableColumn(Text("runtime.column.name", bundle: .module)) { service in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: service.name)
                    Text(verbatim: "PID \(service.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn(Text("runtime.column.project", bundle: .module)) { service in
                if let attribution = service.attribution {
                    Text(verbatim: (attribution.projectPath as NSString).lastPathComponent)
                        .help(Text("evidence.processCwd", bundle: .module))
                } else {
                    Text(verbatim: service.workingDirectory ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TableColumn(Text("runtime.column.memory", bundle: .module)) { service in
                SizeText(bytes: Int64(service.residentMemoryBytes)).font(.callout)
            }
            .width(min: 70, ideal: 90)

            TableColumn(Text("runtime.column.uptime", bundle: .module)) { service in
                Text(service.startDate, format: .relative(presentation: .numeric))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn(Text("runtime.column.actions", bundle: .module)) { service in
                if runtime.stoppingPIDs.contains(service.pid) {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        runtime.stop(service, projects: scan.projects)
                    } label: {
                        Text("runtime.stop", bundle: .module)
                    }
                    .controlSize(.small)
                }
            }
            .width(min: 70, ideal: 80)
        }
    }
}
