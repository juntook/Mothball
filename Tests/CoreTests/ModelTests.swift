// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Model basics")
struct ModelTests {
    @Test("Safety tiers order by destructiveness")
    func safetyOrdering() {
        #expect(Safety.regenerable < .userData)
        #expect(Safety.userData < .protected)
    }

    @Test("Safety raw values match the rule schema")
    func safetyRawValues() {
        #expect(Safety.regenerable.rawValue == "regenerable")
        #expect(Safety.userData.rawValue == "user_data")
        #expect(Safety.protected.rawValue == "protected")
    }

    @Test("Rule JSON from the seed library decodes")
    func decodeSeedShapedRule() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "example",
          "name": "Example",
          "vendor": "Example Corp",
          "category": "ai-cli",
          "platforms": ["macos"],
          "status": "draft",
          "detection": { "anyPaths": ["~/.example"] },
          "targets": [
            {
              "id": "cache",
              "scope": "global",
              "paths": ["~/.example/cache"],
              "kind": "cache",
              "safety": "regenerable",
              "description": "Cache",
              "attribution": { "encoding": "dashed-absolute" }
            },
            {
              "id": "deps",
              "scope": "project",
              "projectGlobs": ["node_modules"],
              "guardFiles": ["package.json"],
              "kind": "artifact",
              "safety": "regenerable",
              "description": "Deps"
            }
          ]
        }
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        #expect(rule.id == "example")
        #expect(rule.targets.count == 2)
        #expect(rule.targets[0].attribution?.encoding == .dashedAbsolute)
        #expect(rule.targets[1].scope == .project)
        #expect(rule.targets[1].guardFiles == ["package.json"])
    }

    @Test("Localized safety names resolve from the Core catalog")
    func localizedSafetyNames() {
        // Under the en test host these resolve to English strings, not raw keys.
        #expect(!Safety.regenerable.localizedName.isEmpty)
        #expect(Safety.regenerable.localizedName != "safety.regenerable.name")
        #expect(Safety.userData.localizedName != "safety.user_data.name")
        #expect(Safety.protected.localizedExplanation != "safety.protected.explanation")
    }

    @Test("Rule copy falls back to embedded English when no catalog key exists")
    func ruleLocalizationFallback() {
        let target = Target(
            id: "no-such-target", scope: .global, paths: ["~/x/y"],
            kind: .cache, safety: .regenerable,
            description: "English fallback", regenerateHint: "Comes back"
        )
        #expect(RuleLocalization.description(ruleID: "no-such-rule", target: target) == "English fallback")
        #expect(RuleLocalization.regenerateHint(ruleID: "no-such-rule", target: target) == "Comes back")
    }
}
