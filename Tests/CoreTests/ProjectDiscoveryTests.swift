// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Project discovery")
struct ProjectDiscoveryTests {
    /// SPEC M3 acceptance tree: nested git, fake node_modules, distractor
    /// directories without guard files.
    let fs = FakeFileSystem(home: "/Users/test", entries: [
        // Regular git project with a nested git repo inside (outermost wins).
        "/Users/test/dev/shop/.git": true,
        "/Users/test/dev/shop/package.json": false,
        "/Users/test/dev/shop/vendor/inner/.git": true,
        // Node project without git.
        "/Users/test/dev/webapp/package.json": false,
        "/Users/test/dev/webapp/node_modules/lodash/package.json": false,
        // Rust project deeper down.
        "/Users/test/dev/org/tools/rustify/Cargo.toml": false,
        // Distractor: directory named node_modules with no guard file anywhere.
        "/Users/test/dev/junk/node_modules/stuff.txt": false,
        // Distractor: hidden directory containing a project marker.
        "/Users/test/dev/.hidden/project/.git": true,
        // Distractor: project under Library (skipped).
        "/Users/test/dev/Library/proj/.git": true,
        // Compose-only project.
        "/Users/test/dev/infra/docker-compose.yml": false,
        // Too deep (depth 7 > max 6).
        "/Users/test/dev/a/b/c/d/e/f/g/.git": true,
        // Chinese name + spaces.
        "/Users/test/dev/我的 项目/go.mod": false,
    ])

    var discovered: [Project] {
        ProjectDiscovery(fs: fs).discover(codeRoots: ["/Users/test/dev"])
    }

    @Test("Finds exactly the expected project roots")
    func exactRoots() {
        #expect(Set(discovered.map(\.path)) == [
            "/Users/test/dev/shop",
            "/Users/test/dev/webapp",
            "/Users/test/dev/org/tools/rustify",
            "/Users/test/dev/infra",
            "/Users/test/dev/我的 项目",
        ])
    }

    @Test("Never descends into a project (nested git ignored)")
    func nestedGitIgnored() {
        #expect(!discovered.contains { $0.path.contains("vendor/inner") })
    }

    @Test("Skips hidden, Library and node_modules subtrees")
    func skipRules() {
        let paths = discovered.map(\.path)
        #expect(!paths.contains { $0.contains(".hidden") })
        #expect(!paths.contains { $0.contains("Library") })
        #expect(!paths.contains { $0.contains("node_modules") })
    }

    @Test("Respects the depth limit")
    func depthLimit() {
        #expect(!discovered.contains { $0.path.hasSuffix("/g") })
    }

    @Test("Exclusions prune whole subtrees")
    func exclusions() {
        let projects = ProjectDiscovery(fs: fs).discover(
            codeRoots: ["/Users/test/dev"],
            exclusions: ["/Users/test/dev/org"]
        )
        #expect(!projects.contains { $0.path.contains("rustify") })
    }

    @Test("Project name is the directory name")
    func names() {
        #expect(discovered.first { $0.path.hasSuffix("shop") }?.name == "shop")
        #expect(discovered.contains { $0.name == "我的 项目" })
    }
}

@Suite("Dashed-absolute attribution")
struct DashedPathTests {
    let projects = [
        Project(name: "shop", path: "/Users/me/dev/shop"),
        Project(name: "my-app", path: "/Users/me/dev/my-app"),
        Project(name: "中文项目", path: "/Users/me/dev/中文项目"),
        Project(name: "with space", path: "/Users/me/dev/with space"),
        Project(name: "shop-admin", path: "/Users/me/dev/shop-admin"),
    ]

    var engine: AttributionEngine {
        AttributionEngine(projects: projects, fs: FakeFileSystem(home: "/Users/me"))
    }

    @Test("Encodes slashes and dots to dashes")
    func encoding() {
        #expect(DashedPathCodec.encode("/Users/me/dev/shop") == "-Users-me-dev-shop")
        #expect(DashedPathCodec.encode("/Users/me/dev/app.web") == "-Users-me-dev-app-web")
    }

    @Test("Decodes bucket names to the right project, including dashed project names")
    func decode() {
        #expect(engine.attributeEncodedDirectoryName("-Users-me-dev-shop")?.projectPath == "/Users/me/dev/shop")
        #expect(engine.attributeEncodedDirectoryName("-Users-me-dev-my-app")?.projectPath == "/Users/me/dev/my-app")
        #expect(engine.attributeEncodedDirectoryName("-Users-me-dev-shop-admin")?.projectPath == "/Users/me/dev/shop-admin")
    }

    @Test("Chinese and space-containing paths decode")
    func unicodeDecode() {
        #expect(engine.attributeEncodedDirectoryName("-Users-me-dev-中文项目")?.projectPath == "/Users/me/dev/中文项目")
        #expect(engine.attributeEncodedDirectoryName("-Users-me-dev-with space")?.projectPath == "/Users/me/dev/with space")
    }

    @Test("Case-insensitive matching (APFS default)")
    func caseInsensitive() {
        #expect(engine.attributeEncodedDirectoryName("-users-ME-dev-SHOP")?.projectPath == "/Users/me/dev/shop")
    }

    @Test("Unknown buckets stay unattributed")
    func unknownBucket() {
        #expect(engine.attributeEncodedDirectoryName("-Users-someone-else-proj") == nil)
    }

    @Test("Evidence type is encodedPath")
    func evidenceType() {
        #expect(engine.attributeEncodedDirectoryName("-Users-me-dev-shop")?.evidence == .encodedPath)
    }

    @Test("Contained-path attribution picks the nearest project root")
    func containment() {
        let nested = [
            Project(name: "outer", path: "/Users/me/dev/outer"),
            Project(name: "inner", path: "/Users/me/dev/outer/packages/inner"),
        ]
        let engine = AttributionEngine(projects: nested, fs: FakeFileSystem(home: "/Users/me"))
        let hit = engine.attributeContainedPath("/Users/me/dev/outer/packages/inner/node_modules")
        #expect(hit?.projectPath == "/Users/me/dev/outer/packages/inner")
        #expect(hit?.evidence == .pathInsideProject)
        #expect(engine.attributeContainedPath("/Users/me/dev/outer/src/x.ts")?.projectPath == "/Users/me/dev/outer")
        #expect(engine.attributeContainedPath("/Users/me/elsewhere") == nil)
    }
}

@Suite("Project-scope scanning")
struct ProjectScanTests {
    let fs = FakeFileSystem(home: "/Users/test", entries: [
        "/Users/test/dev/webapp/package.json": false,
        "/Users/test/dev/webapp/node_modules/lodash/index.js": false,
        // node_modules WITHOUT package.json next to it — guard fails.
        "/Users/test/dev/junk/node_modules/stuff.txt": false,
        "/Users/test/dev/junk/docker-compose.yml": false,
        // Claude Code bucket dirs.
        "/Users/test/.claude/projects/-Users-test-dev-webapp/session.jsonl": false,
        "/Users/test/.claude/projects/-Users-nobody-mystery/session.jsonl": false,
    ])

    let nodeRule = Rule(
        id: "node-modules", name: "Node deps", vendor: "generic", category: .runtime,
        detection: .init(anyBinaries: ["node"]),
        targets: [Target(id: "node-modules", scope: .project, projectGlobs: ["node_modules"], guardFiles: ["package.json"], kind: .artifact, safety: .regenerable, description: "d")]
    )

    let claudeRule = Rule(
        id: "claude-code", name: "Claude Code", vendor: "Anthropic", category: .aiCli,
        detection: .init(anyPaths: ["~/.claude"]),
        targets: [Target(id: "session-history", scope: .global, paths: ["~/.claude/projects"], kind: .history, safety: .userData, description: "d", attribution: .init(encoding: .dashedAbsolute))]
    )

    let projects = [
        Project(name: "webapp", path: "/Users/test/dev/webapp"),
        Project(name: "junk", path: "/Users/test/dev/junk"),
    ]

    @Test("Guard files gate project glob matches")
    func guardFiles() {
        let items = DiskScanner(fs: fs).discoverProjectItems(rules: [nodeRule], projects: projects)
        #expect(items.map(\.path) == ["/Users/test/dev/webapp/node_modules"])
        #expect(items[0].attribution?.projectPath == "/Users/test/dev/webapp")
    }

    @Test("Encoded targets explode into per-bucket items with attribution")
    func encodedExplosion() {
        let scanner = DiskScanner(fs: fs)
        let engine = AttributionEngine(projects: projects, fs: fs)
        let global = scanner.discoverGlobalItems(rules: [claudeRule])
        let exploded = scanner.explodeEncodedTargets(items: global, rules: [claudeRule], attribution: engine)

        #expect(exploded.count == 2)
        let attributed = exploded.first { $0.path.hasSuffix("-Users-test-dev-webapp") }
        let orphan = exploded.first { $0.path.hasSuffix("-Users-nobody-mystery") }
        #expect(attributed?.attribution?.projectPath == "/Users/test/dev/webapp")
        #expect(attributed?.attribution?.evidence == .encodedPath)
        #expect(orphan?.attribution == nil)
        // Safety must survive the explosion — buckets are still user_data.
        #expect(exploded.allSatisfy { $0.safety == .userData })
    }

    @Test("scanAll emits both exploded buckets and project artifacts")
    func scanAllCombined() async {
        var paths: Set<String> = []
        for await event in DiskScanner(fs: fs).scanAll(rules: [nodeRule, claudeRule], projects: projects) {
            if case .discovered(let item) = event { paths.insert(item.path) }
        }
        #expect(paths == [
            "/Users/test/dev/webapp/node_modules",
            "/Users/test/.claude/projects/-Users-test-dev-webapp",
            "/Users/test/.claude/projects/-Users-nobody-mystery",
        ])
    }
}
