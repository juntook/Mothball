// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Menu-bar label: the moth glyph as a template image so the system tints
/// it for light/dark menu bars (SPEC §5.14 — static icon, no animation).
struct MenuBarIcon: View {
    static let templateImage: NSImage? = {
        guard let url = AppResources.bundle.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some View {
        if let image = Self.templateImage {
            Image(nsImage: image)
        } else {
            Image(systemName: "shippingbox")
        }
    }
}

/// Menu-bar extra content (SPEC §5.14): summary, current session, quick
/// actions. Ending a session routes through the main window's mandatory
/// preview — nothing destructive happens straight from the menu.
struct MenuBarContent: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers
    @Environment(SessionModel.self) private var sessionModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text("menubar.summary \(activePortCount) \(runningCount)", bundle: loc.appBundle)
            Text("menubar.reclaimable \(Text(scan.totalBytes, format: .byteCount(style: .file)))", bundle: loc.appBundle)

            Divider()

            if let session = sessionModel.sessions.first {
                Text("menubar.currentSession \(session.projectName)", bundle: loc.appBundle)
                Button {
                    openMainWindow()
                    shell.open(.sessions)
                    sessionModel.beginConfirmation(session)
                } label: {
                    Text("menubar.endSession", bundle: loc.appBundle)
                }
                Divider()
            }

            Button {
                openMainWindow()
                shell.openActiveResources(tab: .ports)
                shell.searchFocusRequest += 1
            } label: {
                Text("menubar.findPort", bundle: loc.appBundle)
            }
            Button {
                openMainWindow()
                shell.openStorage(tab: .projects)
                scan.scan()
            } label: {
                Text("menubar.scan", bundle: loc.appBundle)
            }
            Button {
                openMainWindow()
            } label: {
                Text("menubar.openMain", bundle: loc.appBundle)
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("menubar.quit", bundle: loc.appBundle)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var runningCount: Int {
        runtime.services.count
            + containers.resources.filter { $0.kind == .runningContainer }.count
    }

    private var activePortCount: Int {
        Set(runtime.services.flatMap(\.listeningPorts)).count
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
