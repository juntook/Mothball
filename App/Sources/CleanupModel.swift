// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Cleanup flow state: selection → preview → execution → results (SPEC §5.6).
@MainActor
@Observable
final class CleanupModel {
    enum Phase: Equatable {
        case idle
        case previewing
        case running
        case finished
    }

    private(set) var phase: Phase = .idle
    /// Paths selected in the list. Only selectable safeties ever enter.
    var selectedPaths: Set<String> = []
    /// user_data items individually confirmed inside the preview sheet.
    var confirmedUserDataPaths: Set<String> = []
    private(set) var previewItems: [CleanupItem] = []
    private(set) var runResult: CleanupExecutor.RunResult?
    private(set) var ignoredPaths: Set<String> = []

    /// Global setting (SPEC §5.6 gate rule 6). The first direct delete per
    /// session re-confirms.
    var directDeleteEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "directDeleteEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "directDeleteEnabled") }
    }
    var hasConfirmedDirectDeleteThisSession = false

    /// Lifetime bytes reclaimed by file cleanups, shown in the sidebar footer.
    private(set) var totalReclaimedBytes: Int64 = UserDefaults.standard.object(forKey: "totalReclaimedBytes") as? Int64 ?? 0

    private let ignoreList = IgnoreList()

    init() {
        ignoredPaths = ignoreList.load()
    }

    // MARK: Selection

    func defaultSelect(items: [ResourceItem], assessments: [String: RiskAssessment] = [:]) {
        // regenerable is checked by default; user_data never is (SPEC §4.3).
        // The risk layer only tightens: S2+ (in use / dirty) starts unchecked
        // (SPEC §4.4).
        selectedPaths = Set(
            items.filter { item in
                guard item.safety == .regenerable, !ignoredPaths.contains(item.path) else { return false }
                if let assessment = assessments[item.path], assessment.tier >= .s2 { return false }
                return true
            }.map(\.path)
        )
    }

    func isSelectable(_ item: ResourceItem) -> Bool {
        item.safety != .protected && !ignoredPaths.contains(item.path)
    }

    func toggle(_ item: ResourceItem) {
        guard isSelectable(item) else { return }
        if selectedPaths.contains(item.path) {
            selectedPaths.remove(item.path)
        } else {
            selectedPaths.insert(item.path)
        }
    }

    func ignore(_ item: ResourceItem) {
        ignoreList.add(item.path)
        ignoredPaths.insert(item.path)
        selectedPaths.remove(item.path)
    }

    func unignore(_ path: String) {
        ignoreList.remove(path)
        ignoredPaths.remove(path)
    }

    // MARK: Preview

    func beginPreview(items: [ResourceItem]) {
        previewItems = items
            .filter { selectedPaths.contains($0.path) && $0.safety != .protected }
            .map { CleanupItem(path: $0.path, safety: $0.safety, ruleID: $0.ruleID, targetID: $0.targetID, sizeBytes: $0.sizeBytes) }
            .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        confirmedUserDataPaths = []
        runResult = nil
        phase = .previewing
    }

    var previewUserDataItems: [CleanupItem] { previewItems.filter { $0.safety == .userData } }
    var previewRegenerableItems: [CleanupItem] { previewItems.filter { $0.safety == .regenerable } }

    /// Every user_data item must be individually confirmed before execution.
    var canExecute: Bool {
        Set(previewUserDataItems.map(\.path)).isSubset(of: confirmedUserDataPaths)
            && !previewItems.isEmpty
    }

    var previewTotalBytes: Int64 {
        previewItems.compactMap(\.sizeBytes).reduce(0, +)
    }

    // MARK: Execution

    func execute(allowedPrefixes: [String]) {
        guard phase == .previewing, canExecute else { return }
        phase = .running

        let items = previewItems
        let method: CleanupMethod = directDeleteEnabled ? .delete : .trash
        let gate = DeletionGate(
            allowedPrefixes: allowedPrefixes,
            homeDirectoryPath: RealFileSystem().homeDirectoryPath,
            directDeleteEnabled: directDeleteEnabled
        )
        let executor = CleanupExecutor(gate: gate, auditLog: AuditLog())

        Task {
            let result = await executor.execute(items: items, method: method)
            self.runResult = result
            self.phase = .finished
            self.selectedPaths.subtract(Set(result.results.filter {
                $0.outcome == .trashed || $0.outcome == .deleted
            }.map(\.item.path)))
            self.totalReclaimedBytes += result.reclaimedBytes
            UserDefaults.standard.set(self.totalReclaimedBytes, forKey: "totalReclaimedBytes")
        }
    }

    func dismiss() {
        phase = .idle
        previewItems = []
        confirmedUserDataPaths = []
    }
}
