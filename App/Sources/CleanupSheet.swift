// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Preview → progress → results, in one sheet (SPEC §5.6 flow).
struct CleanupSheet: View {
    @Environment(CleanupModel.self) private var cleanup
    @Environment(ScanModel.self) private var scan
    @Environment(LocalizationModel.self) private var loc
    @State private var showDirectDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            switch cleanup.phase {
            case .previewing:
                previewContent
            case .running:
                ProgressView {
                    Text("cleanup.running", bundle: loc.appBundle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished:
                resultContent
            case .idle:
                EmptyView()
            }
        }
        .frame(width: 560, height: 480)
    }

    // MARK: Preview

    private var previewContent: some View {
        @Bindable var cleanup = cleanup
        return VStack(spacing: 0) {
            List {
                if !cleanup.previewUserDataItems.isEmpty {
                    Section {
                        ForEach(cleanup.previewUserDataItems, id: \.path) { item in
                            userDataRow(item)
                        }
                    } header: {
                        Text("cleanup.section.userData", bundle: loc.appBundle)
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("cleanup.userData.footer", bundle: loc.appBundle)
                            .font(.caption)
                    }
                }
                if !cleanup.previewRegenerableItems.isEmpty {
                    Section {
                        ForEach(cleanup.previewRegenerableItems, id: \.path) { item in
                            previewRow(item)
                        }
                    } header: {
                        Text("cleanup.section.regenerable", bundle: loc.appBundle)
                    }
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("cleanup.preview.total \(cleanup.previewItems.count) \(Int64(cleanup.previewTotalBytes).formatted(.byteCount(style: .file)))", bundle: loc.appBundle)
                        .font(.callout)
                    Text(cleanup.directDeleteEnabled ? "cleanup.method.delete" : "cleanup.method.trash", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    cleanup.dismiss()
                } label: {
                    Text("cleanup.cancel", bundle: loc.appBundle)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    confirmAndExecute()
                } label: {
                    Text("cleanup.confirm", bundle: loc.appBundle)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!cleanup.canExecute)
            }
            .padding(12)
        }
        .confirmationDialog(
            Text("cleanup.directDelete.confirm.title", bundle: loc.appBundle),
            isPresented: $showDirectDeleteConfirm
        ) {
            Button(role: .destructive) {
                cleanup.hasConfirmedDirectDeleteThisSession = true
                runExecution()
            } label: {
                Text("cleanup.directDelete.confirm.button", bundle: loc.appBundle)
            }
        } message: {
            Text("cleanup.directDelete.confirm.message", bundle: loc.appBundle)
        }
    }

    private func userDataRow(_ item: CleanupItem) -> some View {
        @Bindable var cleanup = cleanup
        return HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: Binding(
                get: { cleanup.confirmedUserDataPaths.contains(item.path) },
                set: { on in
                    if on { cleanup.confirmedUserDataPaths.insert(item.path) }
                    else { cleanup.confirmedUserDataPaths.remove(item.path) }
                }
            )) {
                itemDetails(item)
            }
            Spacer()
            SizeText(bytes: item.sizeBytes ?? 0)
        }
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.06))
    }

    private func previewRow(_ item: CleanupItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            itemDetails(item)
            Spacer()
            SizeText(bytes: item.sizeBytes ?? 0)
        }
        .padding(.vertical, 2)
    }

    private func itemDetails(_ item: CleanupItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: displayName(item))
                SafetyBadge(safety: item.safety)
            }
            Text(verbatim: item.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let hint = regenerateHint(item) {
                Text(verbatim: hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func confirmAndExecute() {
        if cleanup.directDeleteEnabled && !cleanup.hasConfirmedDirectDeleteThisSession {
            showDirectDeleteConfirm = true
        } else {
            runExecution()
        }
    }

    private func runExecution() {
        cleanup.execute(rules: scan.rules, projects: scan.projects)
    }

    // MARK: Results

    private var resultContent: some View {
        VStack(spacing: 0) {
            if let result = cleanup.runResult {
                List {
                    Section {
                        ForEach(Array(result.results.enumerated()), id: \.offset) { _, r in
                            HStack {
                                outcomeIcon(r.outcome)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: r.item.path)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    outcomeText(r.outcome)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                SizeText(bytes: r.item.sizeBytes ?? 0).font(.caption)
                            }
                        }
                    } header: {
                        Text("cleanup.result.reclaimed \(Int64(result.reclaimedBytes).formatted(.byteCount(style: .file)))", bundle: loc.appBundle)
                            .font(.headline)
                    }
                }

                if result.abortedOnTrashFailure {
                    banner("cleanup.result.trashFailure", color: .orange)
                }
                banner("cleanup.result.apfsNote", color: .secondary)
            }

            Divider()
            HStack {
                Spacer()
                Button {
                    cleanup.dismiss()
                } label: {
                    Text("cleanup.done", bundle: loc.appBundle)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }

    private func banner(_ key: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
            Text(key, bundle: loc.appBundle)
        }
        .font(.caption)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func outcomeIcon(_ outcome: CleanupExecutor.ItemResult.Outcome) -> some View {
        switch outcome {
        case .trashed, .deleted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .rejected:
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
        case .failed, .abortedTrashFailure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skippedAfterAbort:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private func outcomeText(_ outcome: CleanupExecutor.ItemResult.Outcome) -> Text {
        switch outcome {
        case .trashed: Text("cleanup.outcome.trashed", bundle: loc.appBundle)
        case .deleted: Text("cleanup.outcome.deleted", bundle: loc.appBundle)
        case .rejected: Text("cleanup.outcome.rejected", bundle: loc.appBundle)
        case .failed(let m): Text(verbatim: m)
        case .abortedTrashFailure(let m): Text(verbatim: m)
        case .skippedAfterAbort: Text("cleanup.outcome.skipped", bundle: loc.appBundle)
        }
    }

    private func displayName(_ item: CleanupItem) -> String {
        guard let target = scan.target(ruleID: item.ruleID, targetID: item.targetID) else { return item.targetID }
        return loc.ruleDescription(ruleID: item.ruleID, target: target)
    }

    private func regenerateHint(_ item: CleanupItem) -> String? {
        guard let target = scan.target(ruleID: item.ruleID, targetID: item.targetID) else { return nil }
        return loc.regenerateHint(ruleID: item.ruleID, target: target)
    }
}
