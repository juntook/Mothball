// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// UI-facing scan state. Items appear as soon as they are discovered; sizes
/// fill in asynchronously (SPEC §5.2 progressive rendering).
@MainActor
@Observable
final class ScanModel {
    private(set) var rules: [Rule] = []
    private(set) var ruleWarnings: [String] = []
    private(set) var items: [ResourceItem] = []
    private(set) var presentRuleIDs: Set<String> = []
    private(set) var isScanning = false
    private(set) var loadError: String?
    private(set) var hasScanned = false

    private var scanTask: Task<Void, Never>?

    func loadRulesIfNeeded() {
        guard rules.isEmpty, loadError == nil else { return }
        do {
            let result = try RuleLoader().loadAll()
            rules = result.rules
            ruleWarnings = result.warnings
        } catch {
            loadError = String(describing: error)
        }
    }

    func scan() {
        loadRulesIfNeeded()
        guard !isScanning else { return }
        isScanning = true
        items = []

        let rules = rules
        scanTask = Task {
            let detection = ToolDetection()
            let present = Set(rules.filter { detection.isPresent($0) }.map(\.id))
            self.presentRuleIDs = present

            let scanner = DiskScanner()
            for await event in scanner.scanGlobal(rules: rules) {
                switch event {
                case .discovered(let item):
                    items.append(item)
                case .sized(let path, let bytes):
                    if let index = items.firstIndex(where: { $0.path == path }) {
                        items[index].sizeBytes = bytes
                    }
                case .finished:
                    break
                }
            }
            isScanning = false
            hasScanned = true
        }
    }

    // MARK: Derived views

    var itemsByRule: [(rule: Rule, items: [ResourceItem], totalBytes: Int64)] {
        rules.compactMap { rule in
            let ruleItems = items.filter { $0.ruleID == rule.id }
            guard !ruleItems.isEmpty else { return nil }
            let total = ruleItems.compactMap(\.sizeBytes).reduce(0, +)
            return (rule, ruleItems.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }, total)
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    var totalBytes: Int64 {
        items.compactMap(\.sizeBytes).reduce(0, +)
    }

    func rule(withID id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    func target(ruleID: String, targetID: String) -> Target? {
        rule(withID: ruleID)?.targets.first { $0.id == targetID }
    }
}
