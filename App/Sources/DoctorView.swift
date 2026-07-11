// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Developer workbench: shows every target's on-machine reality so draft rules
/// can be verified and promoted (SPEC §5.1).
struct DoctorView: View {
    @Environment(ScanModel.self) private var model
    @State private var reports: [Doctor.TargetReport] = []
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            if isRunning && reports.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                reportTable
            }
        }
        .navigationTitle(Text("doctor.title", bundle: .module))
        .toolbar {
            Button {
                run()
            } label: {
                Label {
                    Text("doctor.run", bundle: .module)
                } icon: {
                    Image(systemName: "stethoscope")
                }
            }
            .disabled(isRunning)
        }
        .task { run() }
    }

    private var reportTable: some View {
        List {
            ForEach(groupedByRule, id: \.0) { ruleID, ruleReports in
                Section {
                    ForEach(ruleReports) { report in
                        DoctorTargetRow(report: report)
                    }
                } header: {
                    HStack {
                        Text(verbatim: ruleID)
                        if ruleReports.first?.ruleStatus == .draft { DraftBadge() }
                    }
                }
            }
        }
    }

    private var groupedByRule: [(String, [Doctor.TargetReport])] {
        Dictionary(grouping: reports, by: \.ruleID)
            .sorted { $0.key < $1.key }
    }

    private func run() {
        guard !isRunning else { return }
        isRunning = true
        model.loadRulesIfNeeded()
        let rules = model.rules
        Task {
            reports = await Doctor().examine(rules: rules, includeSizes: true)
            isRunning = false
        }
    }
}

struct DoctorTargetRow: View {
    let report: Doctor.TargetReport

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: report.targetID)
                    .fontWeight(.medium)
                SafetyBadge(safety: report.safety)
                Spacer()
            }
            if report.scope == .project {
                Text("doctor.projectScope \(report.pattern)", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.expandedPaths) { path in
                    HStack(spacing: 6) {
                        statusIcon(path)
                        Text(verbatim: path.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if let bytes = path.allocatedBytes {
                            SizeText(bytes: bytes).font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIcon(_ path: Doctor.PathReport) -> some View {
        if !path.exists {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .help(Text("doctor.status.missing", bundle: .module))
        } else if !path.readable {
            Image(systemName: "lock.circle")
                .foregroundStyle(.orange)
                .help(Text("doctor.status.unreadable", bundle: .module))
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .help(Text("doctor.status.ok", bundle: .module))
        }
    }
}
