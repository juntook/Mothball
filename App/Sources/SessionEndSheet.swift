// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// End-session flow (SPEC §5.13): impact preview with per-resource
/// checkboxes → sequential execution → per-step results. Protected
/// resources are shown locked and never enter the batch.
struct SessionEndSheet: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers
    @Environment(SessionModel.self) private var sessionModel
    @Environment(ProtectionModel.self) private var protection
    @Environment(CleanupModel.self) private var cleanup

    let session: DevSession

    @State private var selectedPIDs: Set<Int32> = []
    @State private var selectedContainerIDs: Set<String> = []
    @State private var cleanArtifactsAfter = false
    @State private var initialized = false

    private var protectedServices: [RunningService] {
        session.services.filter { protection.evaluator.isProtected(service: $0) }
    }

    private var stoppableServices: [RunningService] {
        session.services.filter { !protection.evaluator.isProtected(service: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 520, height: 480)
        .interactiveDismissDisabled(sessionModel.phase == .running)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            selectedPIDs = Set(stoppableServices.map(\.pid))
            selectedContainerIDs = Set(session.containers.map(\.id))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("sessionEnd.title \(session.projectName)", bundle: loc.appBundle)
                .font(.headline)
            Text("sessionEnd.subtitle", bundle: loc.appBundle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch sessionModel.phase {
        case .confirming, .idle:
            previewList
        case .running:
            VStack(spacing: 10) {
                ProgressView()
                if let name = sessionModel.runningStepName {
                    Text("sessionEnd.stopping \(name)", bundle: loc.appBundle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished:
            resultList
        }
    }

    // MARK: Preview

    private var previewList: some View {
        List {
            if !stoppableServices.isEmpty {
                Section {
                    ForEach(stoppableServices) { service in
                        Toggle(isOn: Binding(
                            get: { selectedPIDs.contains(service.pid) },
                            set: { on in
                                if on { selectedPIDs.insert(service.pid) } else { selectedPIDs.remove(service.pid) }
                            }
                        )) {
                            resourceLabel(
                                name: service.name,
                                detail: service.listeningPorts.map { ":\($0)" }.joined(separator: " ")
                                    + "  ·  " + Int64(service.residentMemoryBytes).formatted(.byteCount(style: .memory))
                            )
                        }
                    }
                } header: {
                    Text("sessionEnd.section.processes \(stoppableServices.count)", bundle: loc.appBundle)
                }
            }

            if !session.containers.isEmpty {
                Section {
                    ForEach(session.containers) { container in
                        Toggle(isOn: Binding(
                            get: { selectedContainerIDs.contains(container.id) },
                            set: { on in
                                if on { selectedContainerIDs.insert(container.id) } else { selectedContainerIDs.remove(container.id) }
                            }
                        )) {
                            resourceLabel(name: container.name, detail: container.detail)
                        }
                    }
                } header: {
                    Text("sessionEnd.section.containers \(session.containers.count)", bundle: loc.appBundle)
                }
            }

            if !protectedServices.isEmpty {
                Section {
                    ForEach(protectedServices) { service in
                        HStack {
                            Image(systemName: "lock")
                                .foregroundStyle(.secondary)
                            resourceLabel(
                                name: service.name,
                                detail: service.listeningPorts.map { ":\($0)" }.joined(separator: " ")
                            )
                            Spacer()
                            Text("sessionEnd.protected", bundle: loc.appBundle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("sessionEnd.section.protected", bundle: loc.appBundle)
                }
            }

            Section {
                Toggle(isOn: $cleanArtifactsAfter) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sessionEnd.cleanAfter", bundle: loc.appBundle)
                        Text("sessionEnd.cleanAfter.detail", bundle: loc.appBundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func resourceLabel(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: name)
            if !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Results

    private var resultList: some View {
        List {
            Section {
                ForEach(sessionModel.stepResults) { step in
                    HStack {
                        outcomeIcon(step.outcome)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: step.name)
                            if !step.detail.isEmpty {
                                Text(verbatim: step.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        outcomeText(step.outcome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                let failed = sessionModel.stepResults.filter {
                    if case .failed = $0.outcome { return true }
                    if case .stillRunning = $0.outcome { return true }
                    return false
                }.count
                if failed > 0 {
                    Text("sessionEnd.result.partial \(failed)", bundle: loc.appBundle)
                        .foregroundStyle(.orange)
                } else {
                    Text("sessionEnd.result.ok", bundle: loc.appBundle)
                }
            }
        }
    }

    @ViewBuilder
    private func outcomeIcon(_ outcome: SessionModel.StepResult.Outcome) -> some View {
        switch outcome {
        case .stopped:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .stillRunning:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .skippedProtected:
            Image(systemName: "lock").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func outcomeText(_ outcome: SessionModel.StepResult.Outcome) -> Text {
        switch outcome {
        case .stopped: Text("sessionEnd.outcome.stopped", bundle: loc.appBundle)
        case .stillRunning: Text("sessionEnd.outcome.stillRunning", bundle: loc.appBundle)
        case .skippedProtected: Text("sessionEnd.protected", bundle: loc.appBundle)
        case .failed(let message): Text(verbatim: message)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if sessionModel.phase == .confirming {
                let memory = stoppableServices
                    .filter { selectedPIDs.contains($0.pid) }
                    .reduce(Int64(0)) { $0 + Int64($1.residentMemoryBytes) }
                Text("sessionEnd.estimate \(Text(memory, format: .byteCount(style: .memory)))", bundle: loc.appBundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch sessionModel.phase {
            case .confirming, .idle:
                Button {
                    sessionModel.dismiss()
                } label: {
                    Text("cleanup.cancel", bundle: loc.appBundle)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    execute()
                } label: {
                    Text("sessions.end", bundle: loc.appBundle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPIDs.isEmpty && selectedContainerIDs.isEmpty)
            case .running:
                EmptyView()
            case .finished:
                Button {
                    finish()
                } label: {
                    Text("cleanup.done", bundle: loc.appBundle)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private func execute() {
        for service in protectedServices {
            sessionModel.recordSkippedProtected(
                service.name,
                detail: service.listeningPorts.map { ":\($0)" }.joined(separator: " ")
            )
        }
        sessionModel.endSession(
            services: stoppableServices.filter { selectedPIDs.contains($0.pid) },
            containers: session.containers.filter { selectedContainerIDs.contains($0.id) },
            dockerBinary: containers.diagnostics?.binaryPath
        )
    }

    private func finish() {
        let wantsCleanup = cleanArtifactsAfter
        let projectPath = session.projectPath
        sessionModel.dismiss()
        runtime.refresh(projects: scan.projects)
        containers.refresh(projects: scan.projects)
        if wantsCleanup {
            // Select the project's regenerable artifacts and route through the
            // mandatory cleanup preview (SPEC §5.6) — never delete directly.
            let projectItems = scan.items.filter {
                $0.attribution?.projectPath == projectPath && $0.safety == .regenerable
            }
            var selectedAny = false
            for item in projectItems where cleanup.isSelectable(item) {
                cleanup.selectedPaths.insert(item.path)
                selectedAny = true
            }
            shell.openStorage(tab: .projects)
            if selectedAny {
                cleanup.beginPreview(items: scan.items)
            }
        }
    }
}
