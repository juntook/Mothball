// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Overview (SPEC §5.7): metric cards + prioritized attention list. The
/// current-session card joins with M10.
struct DashboardView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers
    @Environment(SessionModel.self) private var sessionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricGrid
                attentionSection
                currentSessionSection
            }
            .padding(20)
        }
        .navigationTitle(Text("sidebar.overview", bundle: loc.appBundle))
        .task {
            if !scan.hasScanned && !scan.isScanning {
                scan.scan()
            }
            runtime.refresh(projects: scan.projects)
            containers.refresh(projects: scan.projects)
        }
    }

    // MARK: Derived numbers

    private var runningContainers: [ContainerResource] {
        containers.resources.filter { $0.kind == .runningContainer }
    }

    private var runningCount: Int { runtime.services.count + runningContainers.count }

    private var activePortCount: Int {
        Set(runtime.services.flatMap(\.listeningPorts)).count
    }

    private var devMemoryBytes: Int64 {
        Int64(runtime.services.reduce(0) { $0 + $1.residentMemoryBytes })
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("dashboard.greeting \(runningCount)", bundle: loc.appBundle)
                .font(.title.weight(.semibold))
            HStack(spacing: 4) {
                if let last = scan.lastScanDate {
                    Text("dashboard.lastScan \(Text(last, format: .relative(presentation: .named)))", bundle: loc.appBundle)
                } else if scan.isScanning {
                    Text("toolbar.scanning", bundle: loc.appBundle)
                }
                Text("dashboard.privacyNote", bundle: loc.appBundle)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Metric cards

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            MetricCard(
                titleKey: "dashboard.card.running",
                value: Text("dashboard.card.running.value \(runningCount)", bundle: loc.appBundle),
                systemImage: "bolt"
            ) {
                shell.openActiveResources(tab: .processes)
            }
            MetricCard(
                titleKey: "dashboard.card.ports",
                value: Text("dashboard.card.ports.value \(activePortCount)", bundle: loc.appBundle),
                systemImage: "network"
            ) {
                shell.openActiveResources(tab: .processes)
            }
            MetricCard(
                titleKey: "dashboard.card.memory",
                value: Text(devMemoryBytes, format: .byteCount(style: .memory)),
                systemImage: "memorychip"
            ) {
                shell.openActiveResources(tab: .processes)
            }
            MetricCard(
                titleKey: "dashboard.card.reclaimable",
                value: Text(scan.totalBytes, format: .byteCount(style: .file)),
                systemImage: "internaldrive"
            ) {
                shell.openStorage(tab: .projects)
            }
        }
    }

    // MARK: Attention list

    private struct AttentionItem: Identifiable {
        let id: String
        let icon: String
        let iconColor: Color
        let title: Text
        let subtitle: Text
        let action: () -> Void
    }

    private var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []

        // Scan-side problems first (SPEC §5.7 priority order).
        if let diag = containers.diagnostics, diag.binaryPath != nil, !diag.daemonReachable {
            items.append(AttentionItem(
                id: "docker-down",
                icon: "shippingbox",
                iconColor: .secondary,
                title: Text("dashboard.attention.dockerDown", bundle: loc.appBundle),
                subtitle: Text("dashboard.attention.dockerDown.detail", bundle: loc.appBundle),
                action: { shell.openActiveResources(tab: .containers) }
            ))
        }

        // Sustained high CPU (SPEC §5.7 attention order, M8 signal).
        for service in runtime.services {
            if let percent = runtime.cpuPercents[service.pid], percent > 50 {
                items.append(AttentionItem(
                    id: "cpu-\(service.pid)",
                    icon: "flame",
                    iconColor: .red,
                    title: Text(verbatim: service.name),
                    subtitle: Text("dashboard.attention.highCPU \(Text(verbatim: String(format: "%.0f%%", percent)))", bundle: loc.appBundle),
                    action: { shell.openActiveResources(tab: .processes) }
                ))
            }
        }

        // Long-running listeners (> 8 hours).
        let longRunningCutoff = Date().addingTimeInterval(-8 * 3600)
        for service in runtime.services
        where !service.listeningPorts.isEmpty && service.startDate < longRunningCutoff && service.startDate > .distantPast {
            items.append(AttentionItem(
                id: "long-\(service.pid)",
                icon: "clock.badge.exclamationmark",
                iconColor: .orange,
                title: Text(verbatim: service.name),
                subtitle: Text("dashboard.attention.longRunning \(Text(service.startDate, format: .relative(presentation: .named))) \(Text(verbatim: service.listeningPorts.map(String.init).joined(separator: ", ")))", bundle: loc.appBundle),
                action: { shell.openActiveResources(tab: .ports) }
            ))
        }

        // Largest reclaimable regenerable items (top 3, ≥ 1 GB).
        let big = scan.items
            .filter { $0.safety == .regenerable && ($0.sizeBytes ?? 0) >= 1_000_000_000 }
            .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
            .prefix(3)
        for item in big {
            let name = (item.path as NSString).abbreviatingWithTildeInPath
            items.append(AttentionItem(
                id: "big-\(item.path)",
                icon: "internaldrive",
                iconColor: .blue,
                title: Text(verbatim: name),
                subtitle: Text("dashboard.attention.reclaimable \(Text(item.sizeBytes ?? 0, format: .byteCount(style: .file)))", bundle: loc.appBundle),
                action: { [isAttributed = item.attribution != nil] in
                    shell.openStorage(tab: isAttributed ? .projects : .toolCaches)
                }
            ))
        }

        // Long-idle projects still holding reclaimable artifacts.
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let stale = scan.itemsByProject
            .filter { group in
                guard let project = group.project, let lastActive = project.lastActive else { return false }
                return lastActive < cutoff && group.totalBytes >= 500_000_000
            }
            .sorted { $0.totalBytes > $1.totalBytes }
            .prefix(2)
        for group in stale {
            guard let project = group.project else { continue }
            items.append(AttentionItem(
                id: "stale-\(project.path)",
                icon: "folder.badge.questionmark",
                iconColor: .green,
                title: Text(verbatim: project.name),
                subtitle: Text("dashboard.attention.staleProject \(Text(project.lastActive ?? Date(), format: .relative(presentation: .named))) \(Text(group.totalBytes, format: .byteCount(style: .file)))", bundle: loc.appBundle),
                action: { shell.openStorage(tab: .projects) }
            ))
        }

        return items
    }

    @ViewBuilder
    private var attentionSection: some View {
        let items = Array(attentionItems.prefix(8))
        VStack(alignment: .leading, spacing: 8) {
            Text("dashboard.attention.title", bundle: loc.appBundle)
                .font(.headline)
            if items.isEmpty {
                emptyAttention
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        attentionRow(item)
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func attentionRow(_ item: AttentionItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .foregroundStyle(item.iconColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    item.title
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    item.subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("dashboard.attention.review", bundle: loc.appBundle)
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Current session (SPEC §5.13)

    @ViewBuilder
    private var currentSessionSection: some View {
        if let session = sessionModel.sessions.first {
            VStack(alignment: .leading, spacing: 8) {
                Text("dashboard.session.title", bundle: loc.appBundle)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verbatim: session.projectName)
                            .fontWeight(.semibold)
                        Text(verbatim: (session.projectPath as NSString).abbreviatingWithTildeInPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    Text("dashboard.session.summary \(session.services.count) \(session.containers.count) \(Text(session.totalMemoryBytes, format: .byteCount(style: .memory)))", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button {
                            shell.open(.sessions)
                        } label: {
                            Text("dashboard.session.view", bundle: loc.appBundle)
                        }
                        Button {
                            sessionModel.beginConfirmation(session)
                        } label: {
                            Text("sessions.end", bundle: loc.appBundle)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var emptyAttention: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(scan.hasScanned ? "dashboard.attention.empty" : "dashboard.attention.notScanned", bundle: loc.appBundle)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
