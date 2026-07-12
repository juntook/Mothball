// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Background services tab (SPEC §5.11): Homebrew services with the three
/// stop semantics. Data directories are never touched from here.
struct BrewServicesSection: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(BrewModel.self) private var brew
    @Environment(ProtectionModel.self) private var protection

    var body: some View {
        @Bindable var brew = brew
        return Group {
            if !brew.brewInstalled {
                ContentUnavailableView {
                    Label {
                        Text("brew.notInstalled.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "mug")
                    }
                } description: {
                    Text("brew.notInstalled.message", bundle: loc.appBundle)
                }
            } else if brew.services.isEmpty && !brew.isRefreshing {
                ContentUnavailableView {
                    Label {
                        Text("brew.empty.title", bundle: loc.appBundle)
                    } icon: {
                        Image(systemName: "mug")
                    }
                } description: {
                    Text("brew.empty.message", bundle: loc.appBundle)
                }
            } else {
                serviceList
            }
        }
        .alert(
            Text("brew.error.title", bundle: loc.appBundle),
            isPresented: Binding(
                get: { brew.actionError != nil },
                set: { if !$0 { brew.actionError = nil } }
            )
        ) {
            Button {
                brew.actionError = nil
            } label: {
                Text("cleanup.done", bundle: loc.appBundle)
            }
        } message: {
            Text(verbatim: brew.actionError ?? "")
        }
    }

    private var serviceList: some View {
        List {
            Section {
                ForEach(brew.services) { service in
                    row(service)
                }
            } footer: {
                Text("brew.footer", bundle: loc.appBundle)
                    .font(.caption)
            }
        }
    }

    private func row(_ service: BrewService) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: service.name)
                        .fontWeight(.medium)
                    statusBadge(service)
                    if protection.evaluator.isProtected(processName: service.name) {
                        Image(systemName: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(Text("brew.protected.help", bundle: loc.appBundle))
                    }
                }
                HStack(spacing: 8) {
                    if service.startsAtLogin {
                        Text("brew.startsAtLogin", bundle: loc.appBundle)
                    }
                    if let user = service.user {
                        Text(verbatim: user)
                    }
                    if let exit = service.exitCode, exit != 0 {
                        Text("brew.exitCode \(exit)", bundle: loc.appBundle)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            actions(service)
        }
        .contextMenu {
            if let plist = service.plistPath {
                Button {
                    NSWorkspace.shared.selectFile(plist, inFileViewerRootedAtPath: "")
                } label: {
                    Text("row.revealInFinder", bundle: loc.appBundle)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ service: BrewService) -> some View {
        let (key, color): (LocalizedStringKey, Color) = if service.status == "error" {
            ("brew.status.error", .red)
        } else if service.isRunning {
            ("brew.status.running", .green)
        } else {
            ("brew.status.stopped", .secondary)
        }
        Text(key, bundle: loc.appBundle)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func actions(_ service: BrewService) -> some View {
        if brew.busyNames.contains(service.name) {
            ProgressView().controlSize(.small)
        } else if service.isRunning {
            Menu {
                Button {
                    brew.stopOnce(service)
                } label: {
                    Text("brew.action.stopOnce", bundle: loc.appBundle)
                }
                Button {
                    brew.stopAndDisable(service)
                } label: {
                    Text("brew.action.stopDisable", bundle: loc.appBundle)
                }
            } label: {
                Text("runtime.stop", bundle: loc.appBundle)
            } primaryAction: {
                brew.stopOnce(service)
            }
            .fixedSize()
            .controlSize(.small)
        } else {
            Button {
                brew.startOnce(service)
            } label: {
                Text("brew.action.start", bundle: loc.appBundle)
            }
            .controlSize(.small)
        }
    }
}
