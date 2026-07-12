// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Dev sessions (SPEC §5.13): auto-resolved per-project resource groups,
/// templates, and the end-session flow.
struct SessionsView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers
    @Environment(SessionModel.self) private var sessionModel
    @Environment(ProtectionModel.self) private var protection

    @State private var templateNamePrompt: DevSession?
    @State private var templateName = ""
    @State private var templateMissingSession = false

    var body: some View {
        Group {
            if sessionModel.sessions.isEmpty && sessionModel.templates.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("sessions.empty.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "rectangle.stack.badge.play")
                    }
                } description: {
                    Text("sessions.empty.description", bundle: loc.appBundle)
                }
            } else {
                sessionList
            }
        }
        .navigationTitle(Text("sidebar.sessions", bundle: loc.appBundle))
        .toolbar {
            ToolbarItem {
                Button {
                    refresh()
                } label: {
                    if runtime.isRefreshing || containers.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label {
                            Text("runtime.refresh", bundle: loc.appBundle)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task {
            refresh()
        }
        .onChange(of: runtime.services) { _, _ in rebuild() }
        .onChange(of: containers.resources) { _, _ in rebuild() }
        .alert(
            Text("sessions.template.name.title", bundle: loc.appBundle),
            isPresented: Binding(
                get: { templateNamePrompt != nil },
                set: { if !$0 { templateNamePrompt = nil } }
            ),
            presenting: templateNamePrompt
        ) { session in
            TextField(text: $templateName) {
                Text("sessions.template.name.placeholder", bundle: loc.appBundle)
            }
            Button {
                let name = templateName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    sessionModel.saveTemplate(named: name, for: session)
                }
                templateNamePrompt = nil
            } label: {
                Text("sessions.template.save", bundle: loc.appBundle)
            }
            Button(role: .cancel) {
                templateNamePrompt = nil
            } label: {
                Text("cleanup.cancel", bundle: loc.appBundle)
            }
        }
        .alert(
            Text("sessions.template.noSession.title", bundle: loc.appBundle),
            isPresented: $templateMissingSession
        ) {
            Button {
                templateMissingSession = false
            } label: {
                Text("cleanup.done", bundle: loc.appBundle)
            }
        } message: {
            Text("sessions.template.noSession.message", bundle: loc.appBundle)
        }
    }

    private func refresh() {
        runtime.refresh(projects: scan.projects)
        containers.refresh(projects: scan.projects)
        rebuild()
    }

    private func rebuild() {
        sessionModel.rebuild(
            projects: scan.projects,
            services: runtime.services,
            containers: containers.resources
        )
    }

    private var sessionList: some View {
        baseSessionList.scrollContentBackground(.hidden)
    }

    private var baseSessionList: some View {
        List {
            if !sessionModel.sessions.isEmpty {
                Section {
                    ForEach(sessionModel.sessions) { session in
                        sessionCard(session)
                    }
                } header: {
                    Text("sessions.section.current", bundle: loc.appBundle)
                }
            }

            if !sessionModel.templates.isEmpty {
                Section {
                    ForEach(sessionModel.templates) { template in
                        templateRow(template)
                    }
                } header: {
                    Text("sessions.section.templates", bundle: loc.appBundle)
                }
            }
        }
    }

    private func sessionCard(_ session: DevSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: session.projectName)
                    .font(.headline)
                Text("sessions.running", bundle: loc.appBundle)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
                Spacer()
                Text(verbatim: (session.projectPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Resource chips, protected ones locked.
            FlowChips(session: session)

            HStack {
                Text("sessions.impact \(Text(session.totalMemoryBytes, format: .byteCount(style: .memory))) \(session.ports.count)", bundle: loc.appBundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    templateName = session.projectName
                    templateNamePrompt = session
                } label: {
                    Text("sessions.saveTemplate", bundle: loc.appBundle)
                }
                Button {
                    sessionModel.beginConfirmation(session)
                } label: {
                    Text("sessions.end", bundle: loc.appBundle)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }

    private func templateRow(_ template: SessionTemplate) -> some View {
        HStack {
            Image(systemName: "square.on.square.dashed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: template.name)
                    .fontWeight(.medium)
                Text(verbatim: (template.projectPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                if let session = sessionModel.session(forProjectPath: template.projectPath) {
                    sessionModel.beginConfirmation(session)
                } else {
                    templateMissingSession = true
                }
            } label: {
                Text("sessions.template.apply", bundle: loc.appBundle)
            }
            .controlSize(.small)
            Button {
                sessionModel.removeTemplate(template)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
        }
    }
}

/// Wrapping chip row for a session's resources.
private struct FlowChips: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ProtectionModel.self) private var protection
    let session: DevSession

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 6, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(session.services) { service in
                chip(
                    text: service.listeningPorts.isEmpty
                        ? service.name
                        : "\(service.name) · :\(service.listeningPorts.map(String.init).joined(separator: ", :"))",
                    locked: protection.evaluator.isProtected(service: service)
                )
            }
            ForEach(session.containers) { container in
                chip(text: container.name, locked: false, icon: "shippingbox")
            }
        }
    }

    private func chip(text: String, locked: Bool, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if locked {
                Image(systemName: "lock").font(.caption2)
            } else if let icon {
                Image(systemName: icon).font(.caption2)
            }
            Text(verbatim: text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}
