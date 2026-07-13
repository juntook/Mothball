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
    private(set) var projects: [Project] = []
    private(set) var presentRuleIDs: Set<String> = []
    private(set) var isScanning = false
    private(set) var loadError: String?
    private(set) var hasScanned = false
    private(set) var lastScanDate: Date?
    /// Increments once per completed scan. Reactions to scan results must key
    /// on this, not `hasScanned`, which never flips back and so only ever
    /// changes on the first scan.
    private(set) var scanGeneration = 0

    private var scanTask: Task<Void, Never>?

    // MARK: Code roots (SPEC §5.3; full onboarding arrives with M6)

    var codeRoots: [String] {
        get { UserDefaults.standard.stringArray(forKey: "codeRoots") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "codeRoots") }
    }

    var codeRootExclusions: [String] {
        get { UserDefaults.standard.stringArray(forKey: "codeRootExclusions") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "codeRootExclusions") }
    }

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
        let roots = codeRoots
        let exclusions = codeRootExclusions
        scanTask = Task {
            let detection = ToolDetection()
            presentRuleIDs = Set(rules.filter { detection.isPresent($0) }.map(\.id))

            // Discovery and git-based activity run off the main actor.
            let discovered = await Task.detached(priority: .userInitiated) {
                let projects = ProjectDiscovery().discover(codeRoots: roots, exclusions: exclusions)
                let activity = ProjectActivity()
                return projects.map { project in
                    var p = project
                    p.lastActive = activity.lastActive(projectPath: project.path)
                    return p
                }
            }.value
            projects = discovered

            let scanner = DiskScanner()
            for await event in scanner.scanAll(rules: rules, projects: discovered) {
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
            lastScanDate = Date()
            scanGeneration += 1
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

    /// Projects with their attributed items, footprint-descending, plus the
    /// unattributed/global bucket at the end (SPEC §5.7).
    var itemsByProject: [(project: Project?, items: [ResourceItem], totalBytes: Int64)] {
        var groups: [(project: Project?, items: [ResourceItem], totalBytes: Int64)] = projects.map { project in
            let projectItems = items
                .filter { $0.attribution?.projectPath == project.path }
                .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
            let total = projectItems.compactMap(\.sizeBytes).reduce(0, +)
            return (project, projectItems, total)
        }
        groups.sort { $0.totalBytes > $1.totalBytes }

        let orphans = items
            .filter { $0.attribution == nil }
            .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        let orphanTotal = orphans.compactMap(\.sizeBytes).reduce(0, +)
        groups.append((nil, orphans, orphanTotal))
        return groups
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
