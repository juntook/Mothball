// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Prototype-style content backdrop: a faint cool gradient in light mode,
/// a deep neutral one in dark mode.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.11, blue: 0.13), Color(red: 0.08, green: 0.08, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(red: 0.965, green: 0.965, blue: 0.985), Color(red: 0.93, green: 0.935, blue: 0.97)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

/// Prototype card surface: translucent material, continuous corners,
/// hairline border, soft shadow.
struct PrototypeCard: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
    }
}

extension View {
    func prototypeCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(PrototypeCard(cornerRadius: cornerRadius))
    }

    /// Wraps a full-bleed list or table into a prototype card floating on
    /// the tinted backdrop.
    func cardContainer() -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }
}

/// Colored rounded-square sidebar icon, matching the prototype's visual
/// language (SPEC §5.7).
struct SidebarChip: View {
    let color: Color
    let systemImage: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Tinted icon chip used in list rows (attention list, search results).
struct IconChip: View {
    let color: Color
    let systemImage: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.15))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color)
            }
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

struct SafetyBadge: View {
    @Environment(LocalizationModel.self) private var loc
    let safety: Safety

    var body: some View {
        Text(verbatim: loc.safetyName(safety))
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

/// S0–S3 presentation-layer risk badge (SPEC §4.4). Hover explains why.
struct RiskBadge: View {
    @Environment(LocalizationModel.self) private var loc
    let assessment: RiskAssessment

    var body: some View {
        Text(tierKey, bundle: loc.appBundle)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .help(reasonText)
    }

    private var tierKey: LocalizedStringKey {
        switch assessment.tier {
        case .s0: "risk.s0"
        case .s1: "risk.s1"
        case .s2: "risk.s2"
        case .s3: "risk.s3"
        }
    }

    private var color: Color {
        switch assessment.tier {
        case .s0: .green
        case .s1: .yellow
        case .s2: .orange
        case .s3: .red
        }
    }

    private var reasonText: String {
        assessment.reasons
            .map { loc.string("risk.reason.\($0.rawValue)") }
            .joined(separator: "\n")
    }
}

struct DraftBadge: View {
    @Environment(LocalizationModel.self) private var loc

    var body: some View {
        Text("badge.unverified", bundle: loc.appBundle)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.yellow.opacity(0.25), in: Capsule())
            .foregroundStyle(.orange)
            .help(Text("badge.unverified.help", bundle: loc.appBundle))
    }
}

struct KindLabel: View {
    @Environment(LocalizationModel.self) private var loc
    let kind: Target.Kind

    var body: some View {
        Text(key, bundle: loc.appBundle)
    }

    private var key: LocalizedStringKey {
        switch kind {
        case .cache: "kind.cache"
        case .log: "kind.log"
        case .history: "kind.history"
        case .config: "kind.config"
        case .credential: "kind.credential"
        case .artifact: "kind.artifact"
        case .state: "kind.state"
        }
    }
}

/// Hover-visible attribution evidence (SPEC §5.3 — "attributed via …").
struct EvidenceLabel: View {
    @Environment(LocalizationModel.self) private var loc
    let evidence: AttributionEvidence

    var body: some View {
        Text(key, bundle: loc.appBundle)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var key: LocalizedStringKey {
        switch evidence {
        case .pathInsideProject: "evidence.pathInsideProject"
        case .processCwd: "evidence.processCwd"
        case .composeLabel: "evidence.composeLabel"
        case .encodedPath: "evidence.encodedPath"
        case .bindMount: "evidence.bindMount"
        }
    }
}

/// Persistent banner shown above content while FDA is missing — results must
/// never look silently incomplete (SPEC §5.8 degraded mode). TCC grants only
/// apply to a freshly launched process, so the banner offers a relaunch.
struct FDABanner: View {
    @Environment(LocalizationModel.self) private var loc
    let status: FullDiskAccess.Status

    var body: some View {
        if status == .denied {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("fda.banner", bundle: loc.appBundle)
                        .font(.callout)
                    Text("fda.banner.restartHint", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: FullDiskAccess.settingsPaneURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("fda.banner.action", bundle: loc.appBundle)
                }
                .controlSize(.small)
                if Bundle.main.bundleIdentifier != nil {
                    Button {
                        relaunch()
                    } label: {
                        Text("fda.banner.relaunch", bundle: loc.appBundle)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
        }
    }

    /// Quit and reopen so a fresh process picks up the new TCC verdict.
    private func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }
}

/// Overview metric card (SPEC §5.7), prototype-styled: muted title, colored
/// glyph top-right, large figure. The whole card is a click target.
struct MetricCard: View {
    @Environment(LocalizationModel.self) private var loc
    let titleKey: LocalizedStringKey
    let value: Text
    let systemImage: String
    var iconColor: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(titleKey, bundle: loc.appBundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: systemImage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(iconColor)
                }
                value
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .prototypeCard()
        }
        .buttonStyle(.plain)
    }
}

/// A resource row with tier-appropriate selection affordance:
/// regenerable — checkbox, checked by default; user_data — checkbox, unchecked;
/// protected — no checkbox at all (SPEC §4.3).
struct SelectableResourceRow: View {
    @Environment(ScanModel.self) private var scan
    @Environment(CleanupModel.self) private var cleanup
    @Environment(LocalizationModel.self) private var loc
    @Environment(RiskModel.self) private var risk
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
                    .help(Text("row.protected.help", bundle: loc.appBundle))
            } else if !isIgnored {
                // Selectable tier blocked by a user protection rule (SPEC §5.12).
                Image(systemName: "lock")
                    .foregroundStyle(.tint)
                    .help(Text("protection.path.help", bundle: loc.appBundle))
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
                    Text("row.unignore", bundle: loc.appBundle)
                }
            } else if item.safety != .protected {
                Button {
                    cleanup.ignore(item)
                } label: {
                    Text("row.ignore", bundle: loc.appBundle)
                }
            }
            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Text("row.revealInFinder", bundle: loc.appBundle)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: displayName)
                SafetyBadge(safety: item.safety)
                if let assessment = risk.assessment(for: item) {
                    RiskBadge(assessment: assessment)
                }
                if isIgnored {
                    Text("row.ignored", bundle: loc.appBundle)
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
        return loc.ruleDescription(ruleID: item.ruleID, target: target)
    }

    private var helpText: String {
        var lines = [loc.safetyExplanation(item.safety)]
        if let target = scan.target(ruleID: item.ruleID, targetID: item.targetID),
           let hint = loc.regenerateHint(ruleID: item.ruleID, target: target) {
            lines.append(hint)
        }
        return lines.joined(separator: "\n")
    }
}
