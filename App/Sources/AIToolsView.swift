// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

extension Rule {
    /// AI development tools get their own top-level section (SPEC §5.17):
    /// the AI categories, plus the model runtimes whose weights dominate
    /// AI-related disk use.
    var isAITool: Bool {
        category == .aiCli || category == .aiApp
            || id == "ollama" || id == "huggingface"
    }
}

extension ScanModel {
    var aiRuleIDs: Set<String> {
        Set(rules.filter(\.isAITool).map(\.id))
    }
}

/// AI Tools (SPEC §5.17): one card per AI tool, its resources split by safety
/// tier — regenerable caches (bulk-selectable), sessions & data grouped by
/// attributed project (per-item opt-in), protected entries display-only.
struct AIToolsView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(CleanupModel.self) private var cleanup
    @Environment(RiskModel.self) private var risk
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let error = scan.loadError {
                ContentUnavailableView {
                    Label {
                        Text("tools.error.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(verbatim: error)
                }
            } else if toolGroups.isEmpty && !scan.isScanning {
                ContentUnavailableView {
                    Label {
                        Text("ai.empty.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                } description: {
                    Text("ai.empty.description", bundle: loc.appBundle)
                }
            } else {
                List {
                    summaryHeader
                    ForEach(toolGroups, id: \.rule.id) { group in
                        Section {
                            toolCard(group)
                        } header: {
                            HStack {
                                Text(verbatim: group.rule.name)
                                if group.rule.status == .draft {
                                    DraftBadge()
                                }
                                Spacer()
                                SizeText(bytes: group.totalBytes)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .cardContainer()
            }
        }
        .navigationTitle(Text("sidebar.aiTools", bundle: loc.appBundle))
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: "doctor")
                } label: {
                    Label {
                        Text("ai.doctor", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "stethoscope")
                    }
                }
                .help(Text("ai.doctor.help", bundle: loc.appBundle))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupSelectionBar()
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            Text("ai.summary \(Text(totalBytes, format: .byteCount(style: .file))) \(toolGroups.count)", bundle: loc.appBundle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                cleanup.selectLowRisk(items: aiItems, assessments: risk.itemAssessments)
            } label: {
                Text("storage.selectLowRisk", bundle: loc.appBundle)
            }
            .help(Text("storage.selectLowRisk.help", bundle: loc.appBundle))
        }
        .listRowSeparator(.hidden)
    }

    // MARK: Per-tool card

    @ViewBuilder
    private func toolCard(_ group: (rule: Rule, items: [ResourceItem], totalBytes: Int64)) -> some View {
        let caches = group.items.filter { $0.safety == .regenerable }
        let data = group.items.filter { $0.safety == .userData }
        let locked = group.items.filter { $0.safety == .protected }

        if !caches.isEmpty {
            tierHeader(titleKey: "ai.section.caches", items: caches, selectable: true)
            ForEach(caches) { item in
                SelectableResourceRow(item: item)
            }
        }
        if !data.isEmpty {
            tierHeader(titleKey: "ai.section.data", items: data, selectable: false)
            ForEach(projectGroups(data), id: \.key) { projectGroup in
                if let name = projectGroup.name {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SizeText(bytes: projectGroup.items.compactMap(\.sizeBytes).reduce(0, +))
                            .font(.caption)
                    }
                    .padding(.top, 2)
                }
                ForEach(projectGroup.items) { item in
                    SelectableResourceRow(item: item)
                }
            }
        }
        if !locked.isEmpty {
            tierHeader(titleKey: "ai.section.protected", items: locked, selectable: false)
            ForEach(locked) { item in
                SelectableResourceRow(item: item)
            }
        }
    }

    private func tierHeader(titleKey: LocalizedStringKey, items: [ResourceItem], selectable: Bool) -> some View {
        HStack(spacing: 6) {
            if selectable {
                GroupSelectToggle(items: items)
            }
            Text(titleKey, bundle: loc.appBundle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .listRowSeparator(.hidden)
        .padding(.top, 4)
    }

    // MARK: Grouping

    private var aiItems: [ResourceItem] {
        let ids = scan.aiRuleIDs
        return scan.items.filter { ids.contains($0.ruleID) }
    }

    private var toolGroups: [(rule: Rule, items: [ResourceItem], totalBytes: Int64)] {
        let groups = scan.itemsByRule.filter { $0.rule.isAITool }
        guard !shell.searchText.isEmpty else { return groups }
        let needle = shell.searchText
        return groups.compactMap { group in
            if group.rule.name.localizedCaseInsensitiveContains(needle) { return group }
            let items = group.items.filter { $0.path.localizedCaseInsensitiveContains(needle) }
            guard !items.isEmpty else { return nil }
            return (group.rule, items, items.compactMap(\.sizeBytes).reduce(0, +))
        }
    }

    private var totalBytes: Int64 {
        toolGroups.flatMap(\.items).compactMap(\.sizeBytes).reduce(0, +)
    }

    /// user_data grouped by attributed project, largest first; unattributed
    /// entries close the list under a nil name.
    private func projectGroups(_ items: [ResourceItem]) -> [(key: String, name: String?, items: [ResourceItem])] {
        let grouped = Dictionary(grouping: items) { $0.attribution?.projectPath ?? "" }
        return grouped
            .map { path, groupItems in
                let name = path.isEmpty
                    ? nil
                    : scan.projects.first { $0.path == path }?.name ?? (path as NSString).lastPathComponent
                return (
                    key: path,
                    name: name,
                    items: groupItems.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
                )
            }
            .sorted { lhs, rhs in
                if (lhs.name == nil) != (rhs.name == nil) { return rhs.name == nil }
                let l = lhs.items.compactMap(\.sizeBytes).reduce(0, +)
                let r = rhs.items.compactMap(\.sizeBytes).reduce(0, +)
                return l > r
            }
    }
}
