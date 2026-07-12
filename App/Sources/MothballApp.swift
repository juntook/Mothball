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
    @State private var brewModel = BrewModel()
    @State private var protectionModel = ProtectionModel()
    @State private var sessionModel = SessionModel()
    @State private var notificationModel = NotificationModel()
    @AppStorage("menuBarEnabled") private var menuBarEnabled = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Mothball", id: "main") {
            AppShell()
                .environment(loc)
                .environment(shell)
                .environment(scanModel)
                .environment(cleanupModel)
                .environment(runtimeModel)
                .environment(containerModel)
                .environment(updaterModel)
                .environment(riskModel)
                .environment(brewModel)
                .environment(protectionModel)
                .environment(sessionModel)
                .environment(notificationModel)
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
                Button {
                    shell.open(.sessions)
                } label: {
                    Text("sidebar.sessions", bundle: loc.appBundle)
                }
                .keyboardShortcut("4", modifiers: .command)
                Button {
                    shell.open(.history)
                } label: {
                    Text("sidebar.history", bundle: loc.appBundle)
                }
                .keyboardShortcut("5", modifiers: .command)
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

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent()
                .environment(loc)
                .environment(shell)
                .environment(scanModel)
                .environment(runtimeModel)
                .environment(containerModel)
                .environment(sessionModel)
                .environment(\.locale, loc.locale)
        } label: {
            MenuBarIcon()
        }
    }
}
