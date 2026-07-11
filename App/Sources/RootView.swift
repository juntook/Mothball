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
    @State private var selection: SidebarSection? = .tools

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
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .tools {
        case .tools:
            ToolsView()
        case .projects, .runtime, .settings:
            PlaceholderView(section: selection ?? .projects)
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
