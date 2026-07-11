// SPDX-License-Identifier: Apache-2.0
// Debug CLI exposing Core capabilities for development-time verification.
// Output is intentionally English-only and not localized (SPEC §8.5).
import Core
import Foundation

let version = "0.1.0"

func printUsage() {
    print("""
    mothball \(version) — debug CLI for the Mothball Core engine

    USAGE: mothball <command>

    COMMANDS:
      rules            List loaded rules (built-in + user overrides)
      scan             Scan global targets and print sizes
      doctor           Report per-target existence/readability/size
      detect           Show which tools are present on this machine
      size <path>      Measure allocated size of a path (perf debugging)
      version          Print version
      help             Show this help
    """)
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func loadRules() -> [Rule] {
    do {
        let result = try RuleLoader().loadAll()
        for warning in result.warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        return result.rules
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

func runRules() {
    let rules = loadRules()
    for rule in rules {
        print("\(rule.id) (\(rule.name), \(rule.vendor)) — \(rule.status.rawValue), \(rule.targets.count) targets")
        for t in rule.targets {
            let where_ = t.scope == .global ? (t.paths ?? []).joined(separator: ", ") : (t.projectGlobs ?? []).joined(separator: ", ")
            print("  - \(t.id) [\(t.scope.rawValue)/\(t.kind.rawValue)/\(t.safety.rawValue)] \(where_)")
        }
    }
}

func runScan() async {
    let rules = loadRules()
    let scanner = DiskScanner()
    var total: Int64 = 0
    var count = 0
    for await event in scanner.scanGlobal(rules: rules) {
        switch event {
        case .discovered(let item):
            print("found  \(item.ruleID)/\(item.targetID)  \(item.path)")
            count += 1
        case .sized(let path, let bytes):
            total += bytes
            print("sized  \(formatBytes(bytes))\t\(path)")
        case .finished:
            print("---\n\(count) items, \(formatBytes(total)) allocated")
        }
    }
}

func runDoctor() async {
    let rules = loadRules()
    let reports = await Doctor().examine(rules: rules, includeSizes: true)
    for report in reports {
        let flag = report.ruleStatus == .draft ? " [draft]" : ""
        print("\(report.ruleID)/\(report.targetID)\(flag)  (\(report.scope.rawValue), \(report.safety.rawValue))")
        if report.scope == .project {
            print("  project glob: \(report.pattern) — evaluated per project (M3)")
            continue
        }
        for p in report.expandedPaths {
            let status = p.exists ? (p.readable ? "ok" : "UNREADABLE") : "missing"
            let size = p.allocatedBytes.map { formatBytes($0) } ?? "-"
            print("  [\(status)] \(size)\t\(p.path)")
        }
    }
}

func runDetect() {
    let rules = loadRules()
    let detection = ToolDetection()
    for rule in rules {
        print("\(detection.isPresent(rule) ? "present" : "absent ")  \(rule.id)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "rules":
    runRules()
case "scan":
    await runScan()
case "doctor":
    await runDoctor()
case "detect":
    runDetect()
case "size":
    guard arguments.count == 2 else { printUsage(); exit(2) }
    let start = Date()
    let bytes = await DirectorySizer.allocatedSizeConcurrent(atPath: arguments[1])
    let elapsed = Date().timeIntervalSince(start)
    print("\(formatBytes(bytes)) (\(bytes) bytes) in \(String(format: "%.2f", elapsed))s")
case "version":
    print(version)
case "help", nil:
    printUsage()
default:
    printUsage()
    exit(2)
}
