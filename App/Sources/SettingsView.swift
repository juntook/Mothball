// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Settings (SPEC §5.7): general / scan scope / language / privacy / advanced.
struct SettingsView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(CleanupModel.self) private var cleanup
    @Environment(ScanModel.self) private var scan
    @Environment(UpdaterModel.self) private var updater
    @Environment(ProtectionModel.self) private var protection
    @Environment(\.openWindow) private var openWindow

    @State private var directDelete = false
    @State private var codeRoots: [String] = []
    @State private var exclusions: [String] = []
    @State private var newRuleKind: ProtectionRule.Kind = .pathPrefix
    @State private var newRuleValue = ""
    @AppStorage("menuBarEnabled") private var menuBarEnabled = false

    var body: some View {
        @Bindable var loc = loc
        return Form {
            // MARK: General
            Section {
                Toggle(isOn: $menuBarEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.menuBar", bundle: loc.appBundle)
                        Text("settings.menuBar.detail", bundle: loc.appBundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $directDelete) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.directDelete", bundle: loc.appBundle)
                        Text("settings.directDelete.detail", bundle: loc.appBundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: directDelete) { _, newValue in
                    cleanup.directDeleteEnabled = newValue
                }
            } header: {
                Text("settings.section.general", bundle: loc.appBundle)
            } footer: {
                Text("settings.directDelete.userDataNote", bundle: loc.appBundle)
                    .font(.caption)
            }

            // MARK: Scan scope
            Section {
                ForEach(codeRoots, id: \.self) { root in
                    HStack {
                        Text(verbatim: root)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            codeRoots.removeAll { $0 == root }
                            scan.codeRoots = codeRoots
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    addDirectories(to: \.codeRoots, local: $codeRoots)
                } label: {
                    Label {
                        Text("settings.codeRoots.add", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            } header: {
                Text("settings.section.codeRoots", bundle: loc.appBundle)
            } footer: {
                Text("settings.codeRoots.detail", bundle: loc.appBundle)
                    .font(.caption)
            }

            Section {
                ForEach(exclusions, id: \.self) { path in
                    HStack {
                        Text(verbatim: path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            exclusions.removeAll { $0 == path }
                            scan.codeRootExclusions = exclusions
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    addDirectories(to: \.codeRootExclusions, local: $exclusions)
                } label: {
                    Label {
                        Text("settings.exclusions.add", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            } header: {
                Text("settings.section.exclusions", bundle: loc.appBundle)
            } footer: {
                Text("settings.exclusions.detail", bundle: loc.appBundle)
                    .font(.caption)
            }

            // MARK: Language
            Section {
                Picker(selection: $loc.language) {
                    Text("settings.language.system", bundle: loc.appBundle)
                        .tag(AppLanguage.system)
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                    Text(verbatim: "English").tag(AppLanguage.english)
                } label: {
                    Text("settings.language", bundle: loc.appBundle)
                }
            } header: {
                Text("settings.section.language", bundle: loc.appBundle)
            } footer: {
                Text("settings.language.detail", bundle: loc.appBundle)
                    .font(.caption)
            }

            // MARK: Privacy
            Section {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Text("menu.checkForUpdates", bundle: loc.appBundle)
                }
                .disabled(!updater.canCheckForUpdates)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([AuditLog().logURL])
                } label: {
                    Text("settings.openAuditLog", bundle: loc.appBundle)
                }
            } header: {
                Text("settings.section.privacy", bundle: loc.appBundle)
            } footer: {
                Text("settings.privacy.note", bundle: loc.appBundle)
                    .font(.caption)
            }

            // MARK: Protection rules (SPEC §5.12)
            Section {
                ForEach(protection.rules) { rule in
                    HStack {
                        Text(kindKey(rule.kind), bundle: loc.appBundle)
                            .font(.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                        Text(verbatim: rule.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            protection.remove(rule)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Picker(selection: $newRuleKind) {
                        ForEach(ProtectionRule.Kind.allCases, id: \.self) { kind in
                            Text(kindKey(kind), bundle: loc.appBundle).tag(kind)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField(text: $newRuleValue) {
                        Text("protection.value.placeholder", bundle: loc.appBundle)
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addProtectionRule)
                    Button(action: addProtectionRule) {
                        Text("protection.add", bundle: loc.appBundle)
                    }
                    .disabled(newRuleValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("settings.section.protection", bundle: loc.appBundle)
            } footer: {
                Text("settings.protection.detail", bundle: loc.appBundle)
                    .font(.caption)
            }

            // MARK: Advanced
            Section {
                Button {
                    openWindow(id: "doctor")
                } label: {
                    Label {
                        Text("doctor.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "stethoscope")
                    }
                }
            } header: {
                Text("settings.section.advanced", bundle: loc.appBundle)
            } footer: {
                Text("settings.doctor.detail", bundle: loc.appBundle)
                    .font(.caption)
            }

            if !cleanup.ignoredPaths.isEmpty {
                Section {
                    ForEach(cleanup.ignoredPaths.sorted(), id: \.self) { path in
                        HStack {
                            Text(verbatim: path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                cleanup.unignore(path)
                            } label: {
                                Text("row.unignore", bundle: loc.appBundle)
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("settings.section.ignored", bundle: loc.appBundle)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("sidebar.settings", bundle: loc.appBundle))
        .onAppear {
            directDelete = cleanup.directDeleteEnabled
            codeRoots = scan.codeRoots
            exclusions = scan.codeRootExclusions
        }
    }

    private func addProtectionRule() {
        let value = newRuleValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        protection.add(kind: newRuleKind, value: value)
        newRuleValue = ""
    }

    private func kindKey(_ kind: ProtectionRule.Kind) -> LocalizedStringKey {
        switch kind {
        case .path: "protection.kind.path"
        case .pathPrefix: "protection.kind.pathPrefix"
        case .processName: "protection.kind.processName"
        case .port: "protection.kind.port"
        case .volumeName: "protection.kind.volumeName"
        }
    }

    private func addDirectories(
        to keyPath: ReferenceWritableKeyPath<ScanModel, [String]>,
        local: Binding<[String]>
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK {
            for url in panel.urls where !local.wrappedValue.contains(url.path) {
                local.wrappedValue.append(url.path)
            }
            scan[keyPath: keyPath] = local.wrappedValue
        }
    }
}
