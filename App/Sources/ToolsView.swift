// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Per-tool global targets, grouped by rule, sorted by footprint (SPEC §5.7).
struct ToolsView: View {
    @Environment(ScanModel.self) private var model
    @Environment(CleanupModel.self) private var cleanup

    var body: some View {
        Group {
            if let error = model.loadError {
                ContentUnavailableView {
                    Label {
                        Text("tools.error.title", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(verbatim: error)
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
                toolList
            }
        }
        .navigationTitle(Text("sidebar.tools", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                CleanButton()
            }
        }
    }

    private var toolList: some View {
        List {
            ForEach(model.itemsByRule, id: \.rule.id) { group in
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
                    Text("tools.total", bundle: .module)
                    Spacer()
                    SizeText(bytes: model.totalBytes).bold()
                }
            }
        }
    }
}

/// Toolbar button opening the cleanup preview for the current selection.
struct CleanButton: View {
    @Environment(ScanModel.self) private var model
    @Environment(CleanupModel.self) private var cleanup

    var body: some View {
        Button {
            cleanup.beginPreview(items: model.items)
        } label: {
            Label {
                Text("cleanup.button \(cleanup.selectedPaths.count)", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .disabled(cleanup.selectedPaths.isEmpty || model.isScanning)
    }
}

/// A resource row with tier-appropriate selection affordance:
/// regenerable — checkbox, checked by default; user_data — checkbox, unchecked;
/// protected — no checkbox at all (SPEC §4.3).
struct SelectableResourceRow: View {
    @Environment(ScanModel.self) private var scan
    @Environment(CleanupModel.self) private var cleanup
    let item: ResourceItem

    private var isIgnored: Bool { cleanup.ignoredPaths.contains(item.path) }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if cleanup.isSelectable(item) {
                Toggle(isOn: Binding(
                    get: { cleanup.selectedPaths.contains(item.path) },
                    set: { _ in cleanup.toggle(item) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
            } else if item.safety == .protected {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .help(Text("row.protected.help", bundle: .module))
            }

            details
            Spacer()
            if let bytes = item.sizeBytes {
                SizeText(bytes: bytes)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .opacity(isIgnored ? 0.45 : 1)
        .help(helpText)
        .contextMenu {
            if isIgnored {
                Button {
                    cleanup.unignore(item.path)
                } label: {
                    Text("row.unignore", bundle: .module)
                }
            } else if item.safety != .protected {
                Button {
                    cleanup.ignore(item)
                } label: {
                    Text("row.ignore", bundle: .module)
                }
            }
            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Text("row.revealInFinder", bundle: .module)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: displayName)
                SafetyBadge(safety: item.safety)
                if isIgnored {
                    Text("row.ignored", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(verbatim: item.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var displayName: String {
        guard let target = scan.target(ruleID: item.ruleID, targetID: item.targetID) else { return item.targetID }
        return RuleLocalization.description(ruleID: item.ruleID, target: target)
    }

    private var helpText: String {
        var lines = [item.safety.localizedExplanation]
        if let target = scan.target(ruleID: item.ruleID, targetID: item.targetID),
           let hint = RuleLocalization.regenerateHint(ruleID: item.ruleID, target: target) {
            lines.append(hint)
        }
        return lines.joined(separator: "\n")
    }
}

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Text(verbatim: safety.localizedName)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch safety {
        case .regenerable: .green
        case .userData: .orange
        case .protected: .gray
        }
    }
}

struct DraftBadge: View {
    var body: some View {
        Text("badge.unverified", bundle: .module)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.yellow.opacity(0.25), in: Capsule())
            .foregroundStyle(.orange)
            .help(Text("badge.unverified.help", bundle: .module))
    }
}

/// Monospaced-digit byte size, locale-aware (SPEC §8.5(4)).
struct SizeText: View {
    let bytes: Int64

    var body: some View {
        Text(bytes, format: .byteCount(style: .file))
            .monospacedDigit()
    }
}
