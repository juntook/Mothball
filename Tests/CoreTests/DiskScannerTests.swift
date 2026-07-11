// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Disk scanner")
struct DiskScannerTests {
    let fs = FakeFileSystem(home: "/Users/test", entries: [
        "/Users/test/.npm": true,
        "/Users/test/.npm/_cacache": true,
        "/Users/test/.claude": true,
        "/Users/test/.claude/projects": true,
    ])

    var rules: [Rule] {
        [
            Rule(
                id: "npm", name: "npm", vendor: "npm", category: .packageManager,
                detection: .init(anyPaths: ["~/.npm"]),
                targets: [
                    Target(id: "cacache", scope: .global, paths: ["~/.npm/_cacache"], kind: .cache, safety: .regenerable, description: "d"),
                    Target(id: "npx", scope: .global, paths: ["~/.npm/_npx"], kind: .cache, safety: .regenerable, description: "d"),
                ]
            ),
            Rule(
                id: "claude-code", name: "Claude Code", vendor: "Anthropic", category: .aiCli,
                detection: .init(anyPaths: ["~/.claude"]),
                targets: [
                    Target(id: "session-history", scope: .global, paths: ["~/.claude/projects"], kind: .history, safety: .userData, description: "d"),
                    Target(id: "deps", scope: .project, projectGlobs: ["node_modules"], guardFiles: ["package.json"], kind: .artifact, safety: .regenerable, description: "d"),
                ]
            ),
        ]
    }

    @Test("Discovers only existing global targets")
    func discovery() {
        let items = DiskScanner(fs: fs).discoverGlobalItems(rules: rules)
        let paths = Set(items.map(\.path))
        #expect(paths == ["/Users/test/.npm/_cacache", "/Users/test/.claude/projects"])
    }

    @Test("Project-scope targets are excluded from the global scan")
    func projectTargetsExcluded() {
        let items = DiskScanner(fs: fs).discoverGlobalItems(rules: rules)
        #expect(!items.contains { $0.targetID == "deps" })
    }

    @Test("Items carry safety and rule status through")
    func metadataCarried() {
        let items = DiskScanner(fs: fs).discoverGlobalItems(rules: rules)
        let history = items.first { $0.targetID == "session-history" }
        #expect(history?.safety == .userData)
        #expect(history?.ruleStatus == .draft)
    }

    @Test("Scan stream emits discovered before sized, then finishes")
    func streamOrdering() async {
        var discovered: Set<String> = []
        var sizedBeforeDiscovered = false
        var finished = false
        for await event in DiskScanner(fs: fs).scanGlobal(rules: rules) {
            switch event {
            case .discovered(let item):
                discovered.insert(item.path)
            case .sized(let path, _):
                if !discovered.contains(path) { sizedBeforeDiscovered = true }
            case .finished:
                finished = true
            }
        }
        #expect(!sizedBeforeDiscovered)
        #expect(finished)
        #expect(discovered.count == 2)
    }
}
