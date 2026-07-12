// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Storage (SPEC §5.7): project artifacts / tool caches / docker storage,
/// with the selection bottom bar driving the cleanup flow (§5.6).
struct StorageView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(CleanupModel.self) private var cleanup
    @Environment(ContainerModel.self) private var containers

    /// Project presented in the cleanup-detail sheet; an empty path is the
    /// unattributed bucket.
    private struct SheetTarget: Identifiable {
        let path: String
        var id: String { path }
    }

    @State private var presentedProject: SheetTarget?
    @State private var previewAfterSheetDismiss = false

    var body: some View {
        @Bindable var shell = shell
        return VStack(spacing: 0) {
            Picker(selection: $shell.storageTab) {
                Text("storage.tab.projects", bundle: loc.appBundle).tag(StorageTab.projects)
                Text("storage.tab.toolCaches", bundle: loc.appBundle).tag(StorageTab.toolCaches)
                Text("storage.tab.docker", bundle: loc.appBundle).tag(StorageTab.docker)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            tabContent
        }
        .navigationTitle(Text("sidebar.storage", bundle: loc.appBundle))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            selectionBar
        }
        .sheet(item: $presentedProject, onDismiss: {
            if previewAfterSheetDismiss {
                previewAfterSheetDismiss = false
                cleanup.beginPreview(items: scan.items)
            }
        }) { target in
            ProjectCleanupSheet(
                projectPath: target.path,
                requestPreview: {
                    previewAfterSheetDismiss = true
                    presentedProject = nil
                }
            )
        }
        .task(id: shell.storageTab) {
            if shell.storageTab == .docker {
                containers.refresh(projects: scan.projects)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch shell.storageTab {
        case .projects:
            projectsTab
        case .toolCaches:
            toolCachesTab
        case .docker:
            ContainerListView(kinds: [.stoppedContainer, .danglingImage, .taggedImage, .volume, .buildCache])
        }
    }

    // MARK: Projects tab

    private var projectsTab: some View {
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
            } else if scan.codeRoots.isEmpty && scan.projects.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("projects.noRoots.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "folder.badge.questionmark")
                    }
                } description: {
                    Text("projects.noRoots.description", bundle: loc.appBundle)
                } actions: {
                    Button {
                        shell.open(.settings)
                    } label: {
                        Text("projects.noRoots.action", bundle: loc.appBundle)
                    }
                }
            } else if scan.items.isEmpty && !scan.isScanning {
                scanEmptyState
            } else {
                List {
                    summaryHeader
                    ForEach(filteredProjectGroups, id: \.key) { group in
                        Button {
                            presentedProject = SheetTarget(path: group.project?.path ?? "")
                        } label: {
                            ProjectCard(
                                project: group.project,
                                itemCount: group.items.count,
                                totalBytes: group.totalBytes,
                                selectedCount: group.items.filter { cleanup.selectedPaths.contains($0.path) }.count
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filteredProjectGroups: [(key: String, project: Project?, items: [ResourceItem], totalBytes: Int64)] {
        scan.itemsByProject
            .filter { !$0.items.isEmpty || $0.project != nil }
            .map { (key: $0.project?.path ?? "", project: $0.project, items: $0.items, totalBytes: $0.totalBytes) }
            .filter { group in
                guard !shell.searchText.isEmpty else { return true }
                let needle = shell.searchText
                if let project = group.project {
                    return project.name.localizedCaseInsensitiveContains(needle)
                        || project.path.localizedCaseInsensitiveContains(needle)
                }
                return group.items.contains { $0.path.localizedCaseInsensitiveContains(needle) }
            }
    }

    private var summaryHeader: some View {
        HStack(spacing: 4) {
            Text("storage.summary \(Text(scan.totalBytes, format: .byteCount(style: .file))) \(scan.projects.count)", bundle: loc.appBundle)
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }

    // MARK: Tool caches tab

    private var toolCachesTab: some View {
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
            } else if scan.items.isEmpty && !scan.isScanning {
                scanEmptyState
            } else {
                List {
                    ForEach(filteredRuleGroups, id: \.rule.id) { group in
                        Section {
                            ForEach(group.items) { item in
                                SelectableResourceRow(item: item)
                            }
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
                    Section {
                        HStack {
                            Text("tools.total", bundle: loc.appBundle)
                            Spacer()
                            SizeText(bytes: scan.totalBytes).bold()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filteredRuleGroups: [(rule: Rule, items: [ResourceItem], totalBytes: Int64)] {
        guard !shell.searchText.isEmpty else { return scan.itemsByRule }
        let needle = shell.searchText
        return scan.itemsByRule.compactMap { group in
            if group.rule.name.localizedCaseInsensitiveContains(needle) { return group }
            let items = group.items.filter { $0.path.localizedCaseInsensitiveContains(needle) }
            guard !items.isEmpty else { return nil }
            return (group.rule, items, items.compactMap(\.sizeBytes).reduce(0, +))
        }
    }

    private var scanEmptyState: some View {
        ContentUnavailableView {
            Label {
                Text("tools.empty.title", bundle: loc.appBundle)
            } icon: {
                Image(systemName: "internaldrive")
            }
        } description: {
            Text("tools.empty.description", bundle: loc.appBundle)
        }
    }

    // MARK: Selection bar (SPEC §5.7)

    private var selectedItems: [ResourceItem] {
        scan.items.filter { cleanup.selectedPaths.contains($0.path) }
    }

    @ViewBuilder
    private var selectionBar: some View {
        let items = selectedItems
        if !items.isEmpty && shell.storageTab != .docker {
            let bytes = items.compactMap(\.sizeBytes).reduce(0, +)
            HStack(spacing: 12) {
                Text("storage.selection \(items.count) \(Text(bytes, format: .byteCount(style: .file)))", bundle: loc.appBundle)
                    .font(.callout)
                Spacer()
                Button {
                    cleanup.selectedPaths = []
                } label: {
                    Text("storage.selection.clear", bundle: loc.appBundle)
                }
                Button {
                    cleanup.beginPreview(items: scan.items)
                } label: {
                    Text("storage.selection.review", bundle: loc.appBundle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(scan.isScanning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .prototypeCard(cornerRadius: 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

struct ProjectCard: View {
    @Environment(LocalizationModel.self) private var loc
    let project: Project?
    let itemCount: Int
    let totalBytes: Int64
    let selectedCount: Int

    var body: some View {
        HStack {
            Image(systemName: project == nil ? "tray" : "folder")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let project {
                    Text(verbatim: project.name).fontWeight(.medium)
                    Text(verbatim: project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("projects.unattributed", bundle: loc.appBundle).fontWeight(.medium)
                    Text("projects.unattributed.detail", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                SizeText(bytes: totalBytes)
                HStack(spacing: 6) {
                    if let lastActive = project?.lastActive {
                        Text(lastActive, format: .relative(presentation: .named))
                    }
                    if selectedCount > 0 {
                        Text("projects.selectedCount \(selectedCount)", bundle: loc.appBundle)
                            .foregroundStyle(.tint)
                    }
                    Text("projects.itemCount \(itemCount)", bundle: loc.appBundle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Project cleanup detail (SPEC §5.7 — sheet): everything attributed to one
/// project (or the unattributed bucket), grouped by kind, selectable.
struct ProjectCleanupSheet: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ScanModel.self) private var scan
    @Environment(CleanupModel.self) private var cleanup
    @Environment(\.dismiss) private var dismiss

    let projectPath: String
    let requestPreview: () -> Void

    private var project: Project? {
        scan.projects.first { $0.path == projectPath }
    }

    private var groupItems: [ResourceItem] {
        if projectPath.isEmpty {
            scan.items.filter { $0.attribution == nil }
        } else {
            scan.items.filter { $0.attribution?.projectPath == projectPath }
        }
    }

    private var selectedInProject: [ResourceItem] {
        groupItems.filter { cleanup.selectedPaths.contains($0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(kindGroups, id: \.kind) { group in
                    Section {
                        ForEach(group.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                SelectableResourceRow(item: item)
                                if let evidence = item.attribution?.evidence {
                                    EvidenceLabel(evidence: evidence)
                                }
                            }
                        }
                    } header: {
                        KindLabel(kind: group.kind)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: project?.name ?? loc.string("projects.unattributed"))
                    .font(.headline)
                if let project {
                    Text(verbatim: project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let lastActive = project?.lastActive {
                Text("projectDetail.lastActive \(Text(lastActive, format: .relative(presentation: .named)))", bundle: loc.appBundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            if let project {
                Button {
                    NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: "")
                } label: {
                    Text("row.revealInFinder", bundle: loc.appBundle)
                }
            }
            Text(cleanup.directDeleteEnabled ? "cleanup.method.delete" : "cleanup.method.trash", bundle: loc.appBundle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("cleanup.done", bundle: loc.appBundle)
            }
            Button {
                requestPreview()
            } label: {
                let bytes = selectedInProject.compactMap(\.sizeBytes).reduce(0, +)
                Text("projectDetail.clean \(Text(bytes, format: .byteCount(style: .file)))", bundle: loc.appBundle)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedInProject.isEmpty)
        }
        .padding(12)
    }

    private var kindGroups: [(kind: Target.Kind, items: [ResourceItem])] {
        Dictionary(grouping: groupItems, by: \.kind)
            .map { (kind: $0.key, items: $0.value.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }) }
            .sorted { lhs, rhs in
                let l = lhs.items.compactMap(\.sizeBytes).reduce(0, +)
                let r = rhs.items.compactMap(\.sizeBytes).reduce(0, +)
                return l > r
            }
    }
}
