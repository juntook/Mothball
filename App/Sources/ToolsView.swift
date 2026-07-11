// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Per-tool global targets, grouped by rule, sorted by footprint (SPEC §5.7).
struct ToolsView: View {
    @Environment(ScanModel.self) private var model

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
    }

    private var toolList: some View {
        List {
            ForEach(model.itemsByRule, id: \.rule.id) { group in
                Section {
                    ForEach(group.items) { item in
                        ResourceItemRow(item: item, target: model.target(ruleID: item.ruleID, targetID: item.targetID))
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

struct ResourceItemRow: View {
    let item: ResourceItem
    let target: Target?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: displayName)
                    SafetyBadge(safety: item.safety)
                }
                Text(verbatim: item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let bytes = item.sizeBytes {
                SizeText(bytes: bytes)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .help(helpText)
    }

    private var displayName: String {
        guard let target else { return item.targetID }
        return RuleLocalization.description(ruleID: item.ruleID, target: target)
    }

    private var helpText: String {
        var lines = [item.safety.localizedExplanation]
        if let target, let hint = RuleLocalization.regenerateHint(ruleID: item.ruleID, target: target) {
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
