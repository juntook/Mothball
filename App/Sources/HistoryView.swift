// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI
import UniformTypeIdentifiers

/// Operation history (SPEC §5.16): the audit log grouped by day, with
/// recovery pointers (Trash, restart) and diagnostics export.
struct HistoryView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ContainerModel.self) private var containers
    @Environment(ScanModel.self) private var scan

    @State private var records: [AuditLog.Record] = []
    @State private var exportError: String?

    private static let displayCap = 500

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("history.empty.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                } description: {
                    Text("history.empty.description", bundle: loc.appBundle)
                }
            } else {
                recordList
            }
        }
        .navigationTitle(Text("sidebar.history", bundle: loc.appBundle))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([AuditLog().logURL])
                } label: {
                    Text("history.openLog", bundle: loc.appBundle)
                }
                Button {
                    exportDiagnostics()
                } label: {
                    Text("history.exportDiagnostics", bundle: loc.appBundle)
                }
            }
        }
        .task {
            reload()
        }
        .alert(
            Text("history.export.errorTitle", bundle: loc.appBundle),
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button {
                exportError = nil
            } label: {
                Text("cleanup.done", bundle: loc.appBundle)
            }
        } message: {
            Text(verbatim: exportError ?? "")
        }
    }

    private func reload() {
        let all = AuditLog().readAll()
        records = Array(all.suffix(Self.displayCap).reversed())
    }

    // MARK: List

    private struct DayGroup: Identifiable {
        let day: Date
        let records: [AuditLog.Record]
        var id: Date { day }
    }

    private var dayGroups: [DayGroup] {
        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        var groups = [Date: [AuditLog.Record]]()
        for record in records {
            let date = formatter.date(from: record.timestamp) ?? .distantPast
            let day = calendar.startOfDay(for: date)
            groups[day, default: []].append(record)
        }
        return groups
            .map { DayGroup(day: $0.key, records: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private var recordList: some View {
        baseRecordList.scrollContentBackground(.hidden).cardContainer()
    }

    private var baseRecordList: some View {
        List {
            ForEach(dayGroups) { group in
                Section {
                    ForEach(Array(group.records.enumerated()), id: \.offset) { _, record in
                        recordRow(record)
                    }
                } header: {
                    Text(group.day, format: .dateTime.year().month().day().weekday())
                }
            }
        }
    }

    private func recordRow(_ record: AuditLog.Record) -> some View {
        let succeeded = isSuccess(record.result)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: methodIcon(record.method))
                .foregroundStyle(succeeded ? Color.secondary : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    methodLabel(record.method)
                        .fontWeight(.medium)
                    if let time = ISO8601DateFormatter().date(from: record.timestamp) {
                        Text(time, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(verbatim: (record.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !succeeded {
                    Text(verbatim: record.result)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let bytes = record.bytes {
                SizeText(bytes: bytes).font(.callout)
            }
            if record.method == "trash" && succeeded {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                } label: {
                    Text("history.openTrash", bundle: loc.appBundle)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func isSuccess(_ result: String) -> Bool {
        result == "ok" || result == "trashed" || result == "deleted"
            || result == "terminated" || result == "alreadyGone"
    }

    private func methodIcon(_ method: String) -> String {
        switch method {
        case "trash": "trash"
        case "delete": "trash.slash"
        case "stop": "stop.circle"
        case "session-end": "rectangle.stack.badge.play"
        case let m where m.hasPrefix("docker"): "shippingbox"
        case let m where m.hasPrefix("brew"): "mug"
        default: "circle"
        }
    }

    private func methodLabel(_ method: String) -> Text {
        switch method {
        case "trash": Text("history.method.trash", bundle: loc.appBundle)
        case "delete": Text("history.method.delete", bundle: loc.appBundle)
        case "stop": Text("history.method.stop", bundle: loc.appBundle)
        case "session-end": Text("history.method.sessionEnd", bundle: loc.appBundle)
        case let m where m.hasPrefix("docker"): Text(verbatim: m)
        case let m where m.hasPrefix("brew"): Text(verbatim: m)
        default: Text(verbatim: method)
        }
    }

    // MARK: Diagnostics export (SPEC §5.16)

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = "mothball-diagnostics.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let staging = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mothball-diagnostics-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            let logURL = AuditLog().logURL
            if FileManager.default.fileExists(atPath: logURL.path) {
                try FileManager.default.copyItem(at: logURL, to: staging.appendingPathComponent("operations.jsonl"))
            }
            try environmentReport().write(
                to: staging.appendingPathComponent("environment.txt"),
                atomically: true,
                encoding: .utf8
            )

            // ditto ships with macOS; keeps the export dependency-free.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", staging.path, destination.path]
            try process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: staging)
            if process.terminationStatus != 0 {
                exportError = "ditto exited with status \(process.terminationStatus)"
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Environment summary. Audit-log records are machine-readable English;
    /// no additional user paths are collected here.
    private func environmentReport() -> String {
        var lines = [String]()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        lines.append("mothball version: \(version)")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("macos: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        lines.append("fda: \(FullDiskAccess.check())")
        lines.append("rules: \(scan.rules.count) loaded, \(scan.rules.filter { $0.status == .verified }.count) verified")
        if let diag = containers.diagnostics {
            lines.append("docker binary: \(diag.binaryPath == nil ? "absent" : "present")")
            lines.append("docker daemon reachable: \(diag.daemonReachable)")
            lines.append("podman detected: \(diag.podmanDetected)")
        }
        lines.append("brew installed: \(BrewServicesClient.resolveBinary() != nil)")
        return lines.joined(separator: "\n") + "\n"
    }
}
