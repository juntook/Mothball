// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// The default home view: one card per project with its aggregated footprint,
/// ending with the unattributed/global bucket (SPEC §5.7).
struct ProjectsView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        Group {
            if model.codeRoots.isEmpty && model.projects.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("projects.noRoots.title", bundle: .module)
                    } icon: {
                        Image(systemName: "folder.badge.questionmark")
                    }
                } description: {
                    Text("projects.noRoots.description", bundle: .module)
                }
            } else if model.items.isEmpty && !model.isScanning {
                ContentUnavailableView {
                    Label {
                        Text("tools.empty.title", bundle: .module)
                    } icon: {
                        Image(systemName: "internaldrive")
                    }
                } description: {
                    Text("tools.empty.description", bundle: .module)
                }
            } else {
                projectList
            }
        }
        .navigationTitle(Text("sidebar.projects", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                CleanButton()
            }
        }
    }

    private var projectList: some View {
        List {
            ForEach(model.itemsByProject, id: \.project?.path) { group in
                if group.project != nil || !group.items.isEmpty {
                    NavigationLink {
                        ProjectDetailView(project: group.project)
                    } label: {
                        ProjectCard(project: group.project, itemCount: group.items.count, totalBytes: group.totalBytes)
                    }
                }
            }
        }
    }
}

struct ProjectCard: View {
    let project: Project?
    let itemCount: Int
    let totalBytes: Int64

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
                    Text("projects.unattributed", bundle: .module).fontWeight(.medium)
                    Text("projects.unattributed.detail", bundle: .module)
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
                    Text("projects.itemCount \(itemCount)", bundle: .module)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// All resources attributed to one project (or the unattributed bucket),
/// grouped by kind, selectable for cleanup.
struct ProjectDetailView: View {
    @Environment(ScanModel.self) private var model
    let project: Project?

    private var groupItems: [ResourceItem] {
        if let project {
            model.items.filter { $0.attribution?.projectPath == project.path }
        } else {
            model.items.filter { $0.attribution == nil }
        }
    }

    var body: some View {
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
        .navigationTitle(project.map { Text(verbatim: $0.name) } ?? Text("projects.unattributed", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                CleanButton()
            }
        }
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

struct KindLabel: View {
    let kind: Target.Kind

    var body: some View {
        switch kind {
        case .cache: Text("kind.cache", bundle: .module)
        case .log: Text("kind.log", bundle: .module)
        case .history: Text("kind.history", bundle: .module)
        case .config: Text("kind.config", bundle: .module)
        case .credential: Text("kind.credential", bundle: .module)
        case .artifact: Text("kind.artifact", bundle: .module)
        case .state: Text("kind.state", bundle: .module)
        }
    }
}

/// Hover-visible attribution evidence (SPEC §5.3 — "attributed via …").
struct EvidenceLabel: View {
    let evidence: AttributionEvidence

    var body: some View {
        label
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var label: Text {
        switch evidence {
        case .pathInsideProject: Text("evidence.pathInsideProject", bundle: .module)
        case .processCwd: Text("evidence.processCwd", bundle: .module)
        case .composeLabel: Text("evidence.composeLabel", bundle: .module)
        case .encodedPath: Text("evidence.encodedPath", bundle: .module)
        case .bindMount: Text("evidence.bindMount", bundle: .module)
        }
    }
}
