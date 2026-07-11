// SPDX-License-Identifier: Apache-2.0
import SwiftUI

@main
struct MothballApp: App {
    @State private var scanModel = ScanModel()
    @State private var cleanupModel = CleanupModel()
    @State private var runtimeModel = RuntimeModel()
    @State private var containerModel = ContainerModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Mothball") {
            RootView()
                .environment(scanModel)
                .environment(cleanupModel)
                .environment(runtimeModel)
                .environment(containerModel)
        }
        .commands {
            CommandMenu(Text("menu.developer", bundle: .module)) {
                Button {
                    openWindow(id: "doctor")
                } label: {
                    Text("doctor.title", bundle: .module)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Window(Text("doctor.title", bundle: .module), id: "doctor") {
            NavigationStack {
                DoctorView()
            }
            .environment(scanModel)
            .environment(cleanupModel)
            .frame(minWidth: 600, minHeight: 400)
        }
    }
}
