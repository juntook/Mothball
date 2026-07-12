// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Active resources (SPEC §5.7): processes and containers today; ports and
/// background services join in M8/M9. Row selection opens an inspector.
struct ActiveResourcesView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers

    @State private var selectedPID: RunningService.ID?

    var body: some View {
        @Bindable var shell = shell
        @Bindable var runtime = runtime
        return VStack(spacing: 0) {
            Picker(selection: $shell.activeResourceTab) {
                Text("active.tab.processes \(runtime.services.count)", bundle: loc.appBundle)
                    .tag(ActiveResourceTab.processes)
                Text("active.tab.containers \(runningContainerCount)", bundle: loc.appBundle)
                    .tag(ActiveResourceTab.containers)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            tabContent
        }
        .navigationTitle(Text("sidebar.activeResources", bundle: loc.appBundle))
        .toolbar {
            ToolbarItem {
                Button {
                    refresh()
                } label: {
                    if runtime.isRefreshing || containers.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label {
                            Text("runtime.refresh", bundle: loc.appBundle)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(runtime.isRefreshing)
            }
        }
        .task {
            refresh()
        }
        .inspector(isPresented: Binding(
            get: { shell.activeResourceTab == .processes && selectedService != nil },
            set: { if !$0 { selectedPID = nil } }
        )) {
            if let service = selectedService {
                ServiceInspector(service: service)
                    .inspectorColumnWidth(min: 260, ideal: 300)
            }
        }
        .confirmationDialog(
            Text("runtime.forceKill.title", bundle: loc.appBundle),
            isPresented: Binding(
                get: { runtime.pendingForceKill != nil },
                set: { if !$0 { runtime.pendingForceKill = nil } }
            ),
            presenting: runtime.pendingForceKill
        ) { service in
            Button(role: .destructive) {
                runtime.forceKill(service, projects: scan.projects)
            } label: {
                Text("runtime.forceKill.button", bundle: loc.appBundle)
            }
        } message: { service in
            Text("runtime.forceKill.message \(service.name) \(Int(service.pid))", bundle: loc.appBundle)
        }
        .alert(
            Text("runtime.stale.title", bundle: loc.appBundle),
            isPresented: $runtime.staleServiceNotice
        ) {
            Button {
                runtime.staleServiceNotice = false
            } label: {
                Text("cleanup.done", bundle: loc.appBundle)
            }
        } message: {
            Text("runtime.stale.message", bundle: loc.appBundle)
        }
    }

    private func refresh() {
        runtime.refresh(projects: scan.projects)
        containers.refresh(projects: scan.projects)
    }

    private var runningContainerCount: Int {
        containers.resources.filter { $0.kind == .runningContainer || $0.kind == .stoppedContainer }.count
    }

    private var selectedService: RunningService? {
        guard let pid = selectedPID else { return nil }
        return runtime.services.first { $0.pid == pid }
    }

    private var filteredServices: [RunningService] {
        guard !shell.searchText.isEmpty else { return runtime.services }
        let needle = shell.searchText
        return runtime.services.filter { service in
            service.name.localizedCaseInsensitiveContains(needle)
                || service.listeningPorts.contains { String($0).contains(needle) }
                || (service.workingDirectory?.localizedCaseInsensitiveContains(needle) ?? false)
                || (service.attribution?.projectPath.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch shell.activeResourceTab {
        case .processes:
            if runtime.services.isEmpty && !runtime.isRefreshing {
                ContentUnavailableView {
                    Label {
                        Text("runtime.empty.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                    }
                } description: {
                    Text("runtime.empty.description", bundle: loc.appBundle)
                }
            } else {
                serviceTable
            }
        case .containers:
            ContainerListView(kinds: [.runningContainer, .stoppedContainer])
        }
    }

    private var serviceTable: some View {
        Table(filteredServices, selection: $selectedPID) {
            TableColumn(Text("runtime.column.port", bundle: loc.appBundle)) { service in
                Text(verbatim: service.listeningPorts.isEmpty
                    ? "—"
                    : service.listeningPorts.map(String.init).joined(separator: ", "))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 90)

            TableColumn(Text("runtime.column.name", bundle: loc.appBundle)) { service in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: service.name)
                    Text(verbatim: "PID \(service.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn(Text("runtime.column.project", bundle: loc.appBundle)) { service in
                if let attribution = service.attribution {
                    Text(verbatim: (attribution.projectPath as NSString).lastPathComponent)
                        .help(Text("evidence.processCwd", bundle: loc.appBundle))
                } else {
                    Text(verbatim: service.workingDirectory ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TableColumn(Text("runtime.column.memory", bundle: loc.appBundle)) { service in
                SizeText(bytes: Int64(service.residentMemoryBytes)).font(.callout)
            }
            .width(min: 70, ideal: 90)

            TableColumn(Text("runtime.column.uptime", bundle: loc.appBundle)) { service in
                Text(service.startDate, format: .relative(presentation: .numeric))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn(Text("runtime.column.actions", bundle: loc.appBundle)) { service in
                if runtime.stoppingPIDs.contains(service.pid) {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        runtime.stop(service, projects: scan.projects)
                    } label: {
                        Text("runtime.stop", bundle: loc.appBundle)
                    }
                    .controlSize(.small)
                }
            }
            .width(min: 70, ideal: 80)
        }
    }
}

/// Process detail inspector (SPEC §5.7).
struct ServiceInspector: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    let service: RunningService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: service.name)
                        .font(.title3.weight(.semibold))
                    Text("inspector.running", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    detailRow("inspector.pid") {
                        Text(verbatim: "\(service.pid)").monospacedDigit()
                    }
                    if !service.listeningPorts.isEmpty {
                        detailRow("inspector.ports") {
                            Text(verbatim: service.listeningPorts.map(String.init).joined(separator: ", "))
                                .monospacedDigit()
                        }
                    }
                    if let attribution = service.attribution {
                        detailRow("inspector.project") {
                            Text(verbatim: (attribution.projectPath as NSString).lastPathComponent)
                        }
                    }
                    if let cwd = service.workingDirectory {
                        detailRow("inspector.cwd") {
                            Text(verbatim: (cwd as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    if let path = service.executablePath {
                        detailRow("inspector.executable") {
                            Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    detailRow("inspector.memory") {
                        SizeText(bytes: Int64(service.residentMemoryBytes))
                    }
                    detailRow("inspector.uptime") {
                        Text(service.startDate, format: .relative(presentation: .named))
                    }
                }
                .font(.callout)

                VStack(alignment: .leading, spacing: 4) {
                    Text("inspector.stopImpact.title", bundle: loc.appBundle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("inspector.stopImpact.body", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    if let cwd = service.workingDirectory {
                        Button {
                            NSWorkspace.shared.selectFile(cwd, inFileViewerRootedAtPath: "")
                        } label: {
                            Text("row.revealInFinder", bundle: loc.appBundle)
                        }
                    }
                    Spacer()
                    if runtime.stoppingPIDs.contains(service.pid) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(role: .destructive) {
                            runtime.stop(service, projects: scan.projects)
                        } label: {
                            Text("runtime.stop", bundle: loc.appBundle)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func detailRow(_ key: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(key, bundle: loc.appBundle)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            value()
        }
    }
}
