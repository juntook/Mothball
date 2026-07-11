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
    @State private var selection: SidebarSection? = .projects

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.titleKey, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            PlaceholderView(section: selection ?? .projects)
        }
        .frame(minWidth: 800, minHeight: 500)
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
