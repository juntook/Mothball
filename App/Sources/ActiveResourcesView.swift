// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Active resources (SPEC §5.7): ports, processes, containers. Background
/// services join in M9. Row selection opens an inspector. CPU sampling runs
/// only while a runtime tab is visible (SPEC §5.10, §9.11).
struct ActiveResourcesView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers
    @Environment(BrewModel.self) private var brew
    @Environment(ProtectionModel.self) private var protection

    @State private var selectedPID: RunningService.ID?
    /// "Development ports only" filter (SPEC §5.9): hides the ephemeral range.
    @AppStorage("devPortsOnly") private var devPortsOnly = true

    private static let ephemeralPortFloor: UInt16 = 49152

    var body: some View {
        @Bindable var shell = shell
        @Bindable var runtime = runtime
        return VStack(spacing: 0) {
            HStack {
                Picker(selection: $shell.activeResourceTab) {
                    Text("active.tab.ports \(portRows.count)", bundle: loc.appBundle)
                        .tag(ActiveResourceTab.ports)
                    Text("active.tab.processes \(runtime.services.count)", bundle: loc.appBundle)
                        .tag(ActiveResourceTab.processes)
                    Text("active.tab.containers \(containerCount)", bundle: loc.appBundle)
                        .tag(ActiveResourceTab.containers)
                    Text("active.tab.services \(brew.services.filter(\.isRunning).count)", bundle: loc.appBundle)
                        .tag(ActiveResourceTab.services)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if shell.activeResourceTab == .ports {
                    Toggle(isOn: $devPortsOnly) {
                        Text("active.devPortsOnly", bundle: loc.appBundle)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            tabContent
        }
        .navigationTitle(Text("sidebar.activeResources", bundle: loc.appBundle))
        .toolbar {
            ToolbarItem {
                Button {
                    runtime.refresh(projects: scan.projects)
                    containers.refresh(projects: scan.projects)
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
        .task(id: shell.activeResourceTab) {
            containers.refresh(projects: scan.projects)
            brew.refresh()
            guard shell.activeResourceTab == .ports || shell.activeResourceTab == .processes else { return }
            // Visible-only sampling loop: cancelled the moment this view or
            // tab goes away, so idle means zero polling (SPEC §5.10).
            while !Task.isCancelled {
                runtime.refresh(projects: scan.projects)
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
            }
        }
        .sheet(item: Binding(
            get: { (shell.activeResourceTab == .ports || shell.activeResourceTab == .processes) ? selectedService : nil },
            set: { if $0 == nil { selectedPID = nil } }
        )) { service in
            ServiceInspector(service: service)
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

    private var containerCount: Int {
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
        case .ports:
            if portRows.isEmpty && !runtime.isRefreshing {
                ContentUnavailableView {
                    Label {
                        Text("ports.empty.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "network")
                    }
                } description: {
                    Text("ports.empty.description", bundle: loc.appBundle)
                }
            } else {
                portTable.cardContainer()
            }
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
                processTable.cardContainer()
            }
        case .containers:
            ContainerListView(kinds: [.runningContainer, .stoppedContainer])
        case .services:
            BrewServicesSection()
        }
    }

    // MARK: Ports tab (SPEC §5.9)

    private struct PortRow: Identifiable {
        let port: UInt16
        let service: RunningService
        var id: String { "\(port):\(service.pid)" }
    }

    private var portRows: [PortRow] {
        filteredServices
            .flatMap { service in
                service.listeningPorts.map { PortRow(port: $0, service: service) }
            }
            .filter { !devPortsOnly || $0.port < Self.ephemeralPortFloor }
            .sorted { $0.port < $1.port }
    }

    private var portTable: some View {
        Table(portRows, selection: Binding(
            get: { selectedPID.map { pid in portRows.first { $0.service.pid == pid }?.id } ?? nil },
            set: { rowID in
                selectedPID = rowID.flatMap { id in portRows.first { $0.id == id }?.service.pid }
            }
        )) {
            TableColumn(Text("runtime.column.port", bundle: loc.appBundle)) { row in
                Text(verbatim: "\(row.port)").monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn(Text("ports.column.protocol", bundle: loc.appBundle)) { _ in
                Text(verbatim: "TCP").foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)

            TableColumn(Text("runtime.column.name", bundle: loc.appBundle)) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.service.name)
                    Text(verbatim: "PID \(row.service.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn(Text("runtime.column.project", bundle: loc.appBundle)) { row in
                projectCell(row.service)
            }

            TableColumn(Text("runtime.column.uptime", bundle: loc.appBundle)) { row in
                Text(row.service.startDate, format: .relative(presentation: .numeric))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn(Text("runtime.column.memory", bundle: loc.appBundle)) { row in
                SizeText(bytes: Int64(row.service.residentMemoryBytes)).font(.callout)
            }
            .width(min: 70, ideal: 90)

            TableColumn(Text("runtime.column.actions", bundle: loc.appBundle)) { row in
                stopButton(row.service)
            }
            .width(min: 70, ideal: 80)
        }
    }

    // MARK: Processes tab (tree per SPEC §5.10)

    private struct ProcessNode: Identifiable {
        let service: RunningService
        var children: [ProcessNode]?
        var id: Int32 { service.pid }
    }

    /// Parent/child outline when not searching; flat rows while filtering.
    private var processNodes: [ProcessNode] {
        let services = filteredServices
        guard shell.searchText.isEmpty else {
            return services.map { ProcessNode(service: $0, children: nil) }
        }
        let pids = Set(services.map(\.pid))
        var childrenByParent = [Int32: [RunningService]]()
        for service in services where pids.contains(service.parentPID) && service.parentPID != service.pid {
            childrenByParent[service.parentPID, default: []].append(service)
        }
        func node(_ service: RunningService) -> ProcessNode {
            let children = (childrenByParent[service.pid] ?? []).map(node)
            return ProcessNode(service: service, children: children.isEmpty ? nil : children)
        }
        return services
            .filter { !pids.contains($0.parentPID) || $0.parentPID == $0.pid }
            .map(node)
    }

    private var processTable: some View {
        Table(processNodes, children: \.children, selection: $selectedPID) {
            TableColumn(Text("runtime.column.port", bundle: loc.appBundle)) { node in
                Text(verbatim: node.service.listeningPorts.isEmpty
                    ? "—"
                    : node.service.listeningPorts.map(String.init).joined(separator: ", "))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 90)

            TableColumn(Text("runtime.column.name", bundle: loc.appBundle)) { node in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: node.service.name)
                    Text(verbatim: "PID \(node.service.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 130, ideal: 180)

            TableColumn(Text("runtime.column.project", bundle: loc.appBundle)) { node in
                projectCell(node.service)
            }

            TableColumn(Text("runtime.column.cpu", bundle: loc.appBundle)) { node in
                if let percent = runtime.cpuPercents[node.service.pid] {
                    Text(verbatim: String(format: "%.1f%%", percent))
                        .monospacedDigit()
                        .foregroundStyle(percent > 50 ? .orange : .primary)
                } else {
                    Text(verbatim: "—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 55, ideal: 70)

            TableColumn(Text("runtime.column.memory", bundle: loc.appBundle)) { node in
                SizeText(bytes: Int64(node.service.residentMemoryBytes)).font(.callout)
            }
            .width(min: 70, ideal: 90)

            TableColumn(Text("runtime.column.uptime", bundle: loc.appBundle)) { node in
                Text(node.service.startDate, format: .relative(presentation: .numeric))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn(Text("runtime.column.actions", bundle: loc.appBundle)) { node in
                stopButton(node.service)
            }
            .width(min: 70, ideal: 80)
        }
        .contextMenu(forSelectionType: RunningService.ID.self) { pids in
            if let pid = pids.first,
               let service = runtime.services.first(where: { $0.pid == pid }) {
                Button {
                    runtime.stop(service, projects: scan.projects)
                } label: {
                    Text("runtime.stop", bundle: loc.appBundle)
                }
                if !runtime.children(of: service).isEmpty {
                    Button {
                        runtime.stopTree(service, projects: scan.projects)
                    } label: {
                        Text("runtime.stopTree", bundle: loc.appBundle)
                    }
                }
            }
        }
    }

    // MARK: Shared cells

    @ViewBuilder
    private func projectCell(_ service: RunningService) -> some View {
        HStack(spacing: 4) {
            if protection.evaluator.isProtected(service: service) {
                Image(systemName: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(Text("protection.service.help", bundle: loc.appBundle))
            }
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
    }

    @ViewBuilder
    private func stopButton(_ service: RunningService) -> some View {
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
}

/// Process detail inspector (SPEC §5.7/§5.9).
struct ServiceInspector: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(\.dismiss) private var dismiss
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
                    if let percent = runtime.cpuPercents[service.pid] {
                        detailRow("runtime.column.cpu") {
                            Text(verbatim: String(format: "%.1f%%", percent)).monospacedDigit()
                        }
                    }
                    detailRow("inspector.memory") {
                        SizeText(bytes: Int64(service.residentMemoryBytes))
                    }
                    detailRow("inspector.uptime") {
                        Text(service.startDate, format: .relative(presentation: .named))
                    }
                    if !runtime.children(of: service).isEmpty {
                        detailRow("inspector.children") {
                            Text(verbatim: "\(runtime.children(of: service).count)")
                        }
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
                    Button {
                        dismiss()
                    } label: {
                        Text("cleanup.done", bundle: loc.appBundle)
                    }
                    .keyboardShortcut(.cancelAction)
                    if runtime.stoppingPIDs.contains(service.pid) {
                        ProgressView().controlSize(.small)
                    } else {
                        Menu {
                            if !runtime.children(of: service).isEmpty {
                                Button {
                                    runtime.stopTree(service, projects: scan.projects)
                                } label: {
                                    Text("runtime.stopTree", bundle: loc.appBundle)
                                }
                            }
                        } label: {
                            Text("runtime.stop", bundle: loc.appBundle)
                        } primaryAction: {
                            runtime.stop(service, projects: scan.projects)
                        }
                        .fixedSize()
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 380, height: 500)
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
