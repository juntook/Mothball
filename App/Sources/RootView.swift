// SPDX-License-Identifier: Apache-2.0
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case projects
    case tools
    case runtime
    case settings

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .projects: "sidebar.projects"
        case .tools: "sidebar.tools"
        case .runtime: "sidebar.runtime"
        case .settings: "sidebar.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "folder"
        case .tools: "wrench.and.screwdriver"
        case .runtime: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(ScanModel.self) private var model
    @Environment(CleanupModel.self) private var cleanup
    @State private var selection: SidebarSection? = .projects

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.titleKey, bundle: .module)
                } icon: {
                    Image(systemName: section.systemImage)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.scan()
                } label: {
                    if model.isScanning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("toolbar.scanning", bundle: .module)
                        }
                    } else {
                        Label {
                            Text("toolbar.scan", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(model.isScanning)
            }
        }
        .task {
            model.loadRulesIfNeeded()
        }
        .onChange(of: model.hasScanned) { _, scanned in
            if scanned { cleanup.defaultSelect(items: model.items) }
        }
        .sheet(isPresented: Binding(
            get: { cleanup.phase != .idle },
            set: { if !$0 { cleanup.dismiss() } }
        )) {
            CleanupSheet()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .projects {
        case .tools:
            ToolsView()
        case .projects:
            NavigationStack {
                ProjectsView()
            }
        case .settings:
            SettingsView()
        case .runtime:
            RuntimeView()
        }
    }
}

struct PlaceholderView: View {
    let section: SidebarSection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(section.titleKey, bundle: .module)
                .font(.title2)
            Text("placeholder.tagline", bundle: .module)
                .foregroundStyle(.secondary)
            Text("placeholder.section.pending", bundle: .module)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
