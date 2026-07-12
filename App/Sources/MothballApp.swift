// SPDX-License-Identifier: Apache-2.0
import SwiftUI

@main
struct MothballApp: App {
    @State private var loc = LocalizationModel()
    @State private var shell = ShellModel()
    @State private var scanModel = ScanModel()
    @State private var cleanupModel = CleanupModel()
    @State private var runtimeModel = RuntimeModel()
    @State private var containerModel = ContainerModel()
    @State private var updaterModel = UpdaterModel()
    @State private var riskModel = RiskModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Mothball") {
            AppShell()
                .environment(loc)
                .environment(shell)
                .environment(scanModel)
                .environment(cleanupModel)
                .environment(runtimeModel)
                .environment(containerModel)
                .environment(updaterModel)
                .environment(riskModel)
                .environment(\.locale, loc.locale)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button {
                    updaterModel.checkForUpdates()
                } label: {
                    Text("menu.checkForUpdates", bundle: loc.appBundle)
                }
                .disabled(!updaterModel.canCheckForUpdates)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button {
                    shell.open(.overview)
                } label: {
                    Text("sidebar.overview", bundle: loc.appBundle)
                }
                .keyboardShortcut("1", modifiers: .command)
                Button {
                    shell.open(.activeResources)
                } label: {
                    Text("sidebar.activeResources", bundle: loc.appBundle)
                }
                .keyboardShortcut("2", modifiers: .command)
                Button {
                    shell.open(.storage)
                } label: {
                    Text("sidebar.storage", bundle: loc.appBundle)
                }
                .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button {
                    scanModel.scan()
                } label: {
                    Text("toolbar.scan", bundle: loc.appBundle)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(scanModel.isScanning)
                if #available(macOS 15.0, *) {
                    Button {
                        shell.searchFocusRequest += 1
                    } label: {
                        Text("menu.search", bundle: loc.appBundle)
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
            CommandMenu(Text("menu.developer", bundle: loc.appBundle)) {
                Button {
                    openWindow(id: "doctor")
                } label: {
                    Text("doctor.title", bundle: loc.appBundle)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Window(Text("doctor.title", bundle: loc.appBundle), id: "doctor") {
            NavigationStack {
                DoctorView()
            }
            .environment(loc)
            .environment(scanModel)
            .environment(cleanupModel)
            .environment(riskModel)
            .environment(\.locale, loc.locale)
            .frame(minWidth: 600, minHeight: 400)
        }
    }
}
