// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// Protection-rule state (SPEC §5.12). The evaluator is rebuilt on every
/// change and consulted by every batch path.
@MainActor
@Observable
final class ProtectionModel {
    private(set) var rules: [ProtectionRule] = []
    private(set) var evaluator = ProtectionEvaluator(rules: [])

    private let store = ProtectionRuleStore()

    init() {
        reload()
    }

    func reload() {
        rules = store.load()
        evaluator = ProtectionEvaluator(rules: rules)
    }

    func add(kind: ProtectionRule.Kind, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(ProtectionRule(kind: kind, value: trimmed))
        reload()
    }

    func remove(_ rule: ProtectionRule) {
        store.remove(rule)
        reload()
    }

    func isProtected(_ item: ResourceItem) -> Bool {
        evaluator.isProtected(path: item.path)
    }
}
