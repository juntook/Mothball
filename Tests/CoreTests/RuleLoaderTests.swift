// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Rule loading")
struct RuleLoaderTests {
    @Test("All bundled seed rules load and validate")
    func bundledRulesLoad() throws {
        let result = try RuleLoader().loadAll()
        let ids = Set(result.rules.map(\.id))
        #expect(ids.isSuperset(of: ["claude-code", "codex", "codebuddy-cli", "workbuddy", "npm", "node-modules"]))
    }

    @Test("Claude Code session history is user_data with dashed-absolute attribution")
    func claudeCodeSafetyInvariants() throws {
        let result = try RuleLoader().loadAll()
        let claude = try #require(result.rules.first { $0.id == "claude-code" })
        let history = try #require(claude.targets.first { $0.id == "session-history" })
        #expect(history.safety == .userData)
        #expect(history.attribution?.encoding == .dashedAbsolute)
        let config = try #require(claude.targets.first { $0.id == "config" })
        #expect(config.safety == .protected)
    }

    @Test("A user rule overrides the built-in rule with the same id")
    func userOverride() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mothball-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let override = """
        {
          "schemaVersion": 1, "id": "npm", "name": "npm (user override)",
          "vendor": "npm / Node.js", "category": "package-manager",
          "platforms": ["macos"], "status": "draft",
          "detection": { "anyPaths": ["~/.npm"] },
          "targets": [{
            "id": "cacache", "scope": "global", "paths": ["~/.npm/_cacache"],
            "kind": "cache", "safety": "regenerable", "description": "Override"
          }]
        }
        """
        try override.write(to: tmp.appendingPathComponent("npm.json"), atomically: true, encoding: .utf8)

        let loader = RuleLoader(userRulesDirectory: tmp.path)
        let result = try loader.loadAll()
        let npm = try #require(result.rules.first { $0.id == "npm" })
        #expect(npm.name == "npm (user override)")
        #expect(result.warnings.contains { $0.contains("overrides") })
    }

    @Test("A broken user rule is skipped with a warning, not fatal")
    func brokenUserRule() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mothball-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "not json".write(to: tmp.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)

        let result = try RuleLoader(userRulesDirectory: tmp.path).loadAll()
        #expect(result.warnings.contains { $0.contains("bad.json") })
        #expect(!result.rules.isEmpty)
    }

    @Test("Validation rejects credential targets that are not protected")
    func credentialMustBeProtected() {
        let rule = Rule(
            id: "x", name: "X", vendor: "V", category: .aiCli,
            detection: .init(anyPaths: ["~/.x"]),
            targets: [Target(id: "auth", scope: .global, paths: ["~/.x/auth.json"], kind: .credential, safety: .regenerable, description: "d")]
        )
        #expect(throws: RuleLoader.LoadError.self) { try RuleLoader.validate(rule) }
    }

    @Test("Validation rejects regenerable history")
    func historyNeverRegenerable() {
        let rule = Rule(
            id: "x", name: "X", vendor: "V", category: .aiCli,
            detection: .init(anyPaths: ["~/.x"]),
            targets: [Target(id: "h", scope: .global, paths: ["~/.x/h"], kind: .history, safety: .regenerable, description: "d")]
        )
        #expect(throws: RuleLoader.LoadError.self) { try RuleLoader.validate(rule) }
    }

    @Test("Validation rejects traversal and double-star in paths")
    func pathHygiene() {
        for bad in ["~/.x/../escape", "~/.x/**/all"] {
            let rule = Rule(
                id: "x", name: "X", vendor: "V", category: .aiCli,
                detection: .init(anyPaths: ["~/.x"]),
                targets: [Target(id: "t", scope: .global, paths: [bad], kind: .cache, safety: .regenerable, description: "d")]
            )
            #expect(throws: RuleLoader.LoadError.self) { try RuleLoader.validate(rule) }
        }
    }

    @Test("Validation requires guardFiles on project targets")
    func projectTargetNeedsGuards() {
        let rule = Rule(
            id: "x", name: "X", vendor: "V", category: .runtime,
            detection: .init(anyBinaries: ["node"]),
            targets: [Target(id: "t", scope: .project, projectGlobs: ["node_modules"], kind: .artifact, safety: .regenerable, description: "d")]
        )
        #expect(throws: RuleLoader.LoadError.self) { try RuleLoader.validate(rule) }
    }

    @Test("Verified rules must carry verifiedOn")
    func verifiedNeedsDate() {
        let rule = Rule(
            id: "x", name: "X", vendor: "V", category: .aiCli, status: .verified,
            detection: .init(anyPaths: ["~/.x"]),
            targets: [Target(id: "t", scope: .global, paths: ["~/.x/c"], kind: .cache, safety: .regenerable, description: "d")]
        )
        #expect(throws: RuleLoader.LoadError.self) { try RuleLoader.validate(rule) }
    }
}
