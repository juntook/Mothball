// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

struct SettingsView: View {
    @Environment(CleanupModel.self) private var cleanup
    @Environment(ScanModel.self) private var scan
    @State private var directDelete = false
    @State private var codeRoots: [String] = []

    var body: some View {
        Form {
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
                    addCodeRoot()
                } label: {
                    Label {
                        Text("settings.codeRoots.add", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            } header: {
                Text("settings.section.codeRoots", bundle: .module)
            } footer: {
                Text("settings.codeRoots.detail", bundle: .module)
                    .font(.caption)
            }

            Section {
                Toggle(isOn: $directDelete) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.directDelete", bundle: .module)
                        Text("settings.directDelete.detail", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: directDelete) { _, newValue in
                    cleanup.directDeleteEnabled = newValue
                }
            } header: {
                Text("settings.section.cleanup", bundle: .module)
            } footer: {
                Text("settings.directDelete.userDataNote", bundle: .module)
                    .font(.caption)
            }

            Section {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([AuditLog().logURL])
                } label: {
                    Text("settings.openAuditLog", bundle: .module)
                }
            } header: {
                Text("settings.section.audit", bundle: .module)
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
                                Text("row.unignore", bundle: .module)
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("settings.section.ignored", bundle: .module)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("sidebar.settings", bundle: .module))
        .onAppear {
            directDelete = cleanup.directDeleteEnabled
            codeRoots = scan.codeRoots
        }
    }

    private func addCodeRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK {
            for url in panel.urls where !codeRoots.contains(url.path) {
                codeRoots.append(url.path)
            }
            scan.codeRoots = codeRoots
        }
    }
}
