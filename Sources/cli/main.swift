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
      projects <root>  Discover projects under a root and attribute resources
      runtime [root]   List running services (listeners + project processes)
      stop <pid>       Gracefully stop a service (SIGTERM, 5s grace, no auto-kill)
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
case "projects":
    guard arguments.count == 2 else { printUsage(); exit(2) }
    let rules = loadRules()
    let projects = ProjectDiscovery().discover(codeRoots: [arguments[1]]).map { project in
        var p = project
        p.lastActive = ProjectActivity().lastActive(projectPath: project.path)
        return p
    }
    print("\(projects.count) projects discovered:")
    for p in projects {
        let active = p.lastActive.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        print("  \(p.name)  \(p.path)  last-active=\(active)")
    }
    print("\nattributed resources:")
    let scanner = DiskScanner()
    var attributed: [String: [String]] = [:]
    var orphans: [String] = []
    for await event in scanner.scanAll(rules: rules, projects: projects) {
        if case .discovered(let item) = event {
            if let a = item.attribution {
                attributed[a.projectPath, default: []].append("\(item.path)  [\(a.evidence)]")
            } else {
                orphans.append(item.path)
            }
        }
    }
    for (project, paths) in attributed.sorted(by: { $0.key < $1.key }) {
        print("  \(project)")
        for path in paths { print("    - \(path)") }
    }
    print("  (unattributed)")
    for path in orphans { print("    - \(path)") }
case "runtime":
    var projects: [Project] = []
    if arguments.count == 2 {
        projects = ProjectDiscovery().discover(codeRoots: [arguments[1]])
    }
    let services = RuntimeScanner().discover(projects: projects)
    print("PORT(S)      PID     MEM        UPTIME    NAME             PROJECT / CWD")
    for s in services {
        let ports = s.listeningPorts.isEmpty ? "-" : s.listeningPorts.map(String.init).joined(separator: ",")
        let mem = formatBytes(Int64(s.residentMemoryBytes))
        let uptime = Duration.seconds(Date().timeIntervalSince(s.startDate)).formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2))
        let place = s.attribution?.projectPath ?? s.workingDirectory ?? "-"
        print("\(ports.padding(toLength: 12, withPad: " ", startingAt: 0)) \(String(s.pid).padding(toLength: 7, withPad: " ", startingAt: 0)) \(mem.padding(toLength: 10, withPad: " ", startingAt: 0)) \(uptime.padding(toLength: 9, withPad: " ", startingAt: 0)) \(s.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(place)")
    }
case "stop":
    guard arguments.count == 2, let pid = Int32(arguments[1]) else { printUsage(); exit(2) }
    let provider = LibprocProcessProvider()
    guard let snap = provider.snapshot(pid: pid) else {
        print("no such process: \(pid)")
        exit(1)
    }
    let service = RunningService(pid: pid, name: snap.name, startDate: snap.startDate)
    print("sending SIGTERM to \(snap.name) (\(pid))…")
    let result = await ServiceStopper().stop(service)
    print("result: \(result)")
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
