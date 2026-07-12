// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Loads and validates the rule library.
///
/// Rules ship inside the Core bundle (`rules/tools/*.json`). Users may add or
/// override rules by dropping files into
/// `~/Library/Application Support/Mothball/rules/` — a local rule with the same
/// id replaces the built-in one (SPEC §5.1).
public struct RuleLoader: Sendable {
    public enum LoadError: Error, Equatable {
        case invalidRule(file: String, reason: String)
        case duplicateID(String)
    }

    public struct LoadResult: Sendable {
        public var rules: [Rule]
        /// Non-fatal problems (e.g. one bad user rule) — surfaced, not thrown.
        public var warnings: [String]
    }

    private let fs: any FileSystem
    private let userRulesDirectory: String

    public static let defaultUserRulesDirectory = "~/Library/Application Support/Mothball/rules"

    public init(
        fs: any FileSystem = RealFileSystem(),
        userRulesDirectory: String = RuleLoader.defaultUserRulesDirectory
    ) {
        self.fs = fs
        self.userRulesDirectory = userRulesDirectory
    }

    /// Loads built-in rules, then applies user overrides. Built-in rules must all
    /// be valid (they are CI-validated); a broken user rule becomes a warning.
    public func loadAll() throws -> LoadResult {
        var byID: [String: Rule] = [:]
        var warnings: [String] = []

        for url in builtinRuleURLs() {
            let rule = try loadRule(at: url)
            guard byID[rule.id] == nil else { throw LoadError.duplicateID(rule.id) }
            byID[rule.id] = rule
        }

        let userDir = (try? PathExpansion.expandTilde(userRulesDirectory, fs: fs)) ?? ""
        if !userDir.isEmpty, fs.isDirectory(userDir) {
            for name in fs.contentsOfDirectory(userDir).sorted() where name.hasSuffix(".json") {
                let path = userDir + "/" + name
                do {
                    let rule = try loadRule(at: URL(fileURLWithPath: path))
                    if byID[rule.id] != nil {
                        warnings.append("User rule '\(rule.id)' overrides the built-in rule")
                    }
                    byID[rule.id] = rule
                } catch {
                    warnings.append("Skipped invalid user rule \(name): \(error)")
                }
            }
        }

        let rules = byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return LoadResult(rules: rules, warnings: warnings)
    }

    func builtinRuleURLs() -> [URL] {
        guard let dir = CoreResources.bundle.url(forResource: "rules/tools", withExtension: nil)
            ?? CoreResources.bundle.url(forResource: "tools", withExtension: nil, subdirectory: "rules")
        else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    func loadRule(at url: URL) throws -> Rule {
        let data = try Data(contentsOf: url)
        let rule: Rule
        do {
            rule = try JSONDecoder().decode(Rule.self, from: data)
        } catch {
            throw LoadError.invalidRule(file: url.lastPathComponent, reason: "\(error)")
        }
        try Self.validate(rule, file: url.lastPathComponent)
        return rule
    }

    /// Semantic validation mirroring scripts/validate-rules.sh, enforced at load
    /// time as defense in depth (user rules never go through CI).
    public static func validate(_ rule: Rule, file: String = "") throws {
        func reject(_ reason: String) throws -> Never {
            throw LoadError.invalidRule(file: file, reason: reason)
        }
        if rule.schemaVersion != 1 { try reject("unsupported schemaVersion \(rule.schemaVersion)") }
        if !isKebab(rule.id) { try reject("rule id '\(rule.id)' is not kebab-case") }
        if rule.targets.isEmpty { try reject("rule has no targets") }

        var seen = Set<String>()
        for target in rule.targets {
            if !isKebab(target.id) { try reject("target id '\(target.id)' is not kebab-case") }
            if !seen.insert(target.id).inserted { try reject("duplicate target id '\(target.id)'") }

            switch target.scope {
            case .global:
                guard let paths = target.paths, !paths.isEmpty else {
                    try reject("global target '\(target.id)' has no paths")
                }
                for p in paths {
                    if p.contains("..") || p.contains("**") { try reject("illegal path pattern '\(p)'") }
                    if !(p.hasPrefix("~/") || p.hasPrefix("/")) { try reject("path '\(p)' must start with ~/ or /") }
                }
            case .project:
                guard let globs = target.projectGlobs, !globs.isEmpty else {
                    try reject("project target '\(target.id)' has no projectGlobs")
                }
                guard let guards = target.guardFiles, !guards.isEmpty else {
                    try reject("project target '\(target.id)' has no guardFiles")
                }
                for g in globs where g.contains("..") || g.contains("**") || g.hasPrefix("/") {
                    try reject("illegal project glob '\(g)'")
                }
            }

            if target.kind == .credential, target.safety != .protected {
                try reject("credential target '\(target.id)' must be protected")
            }
            if target.kind == .history, target.safety == .regenerable {
                try reject("history target '\(target.id)' must not be regenerable")
            }
        }
        if rule.status == .verified, rule.verifiedOn == nil {
            try reject("verified rule must set verifiedOn")
        }
    }

    private static func isKebab(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}
