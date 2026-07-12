// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// V2 shell (SPEC §5.7): sidebar navigation, toolbar scan + search, status
/// footer, and the app-wide sheets (onboarding, cleanup).
struct AppShell: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ShellModel.self) private var shell
    @Environment(ScanModel.self) private var scan
    @Environment(CleanupModel.self) private var cleanup
    @Environment(RuntimeModel.self) private var runtime
    @Environment(ContainerModel.self) private var containers
    @Environment(RiskModel.self) private var risk
    @Environment(ProtectionModel.self) private var protection
    @Environment(SessionModel.self) private var sessionModel

    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingComplete")
    @State private var fdaStatus = FullDiskAccess.check()

    var body: some View {
        @Bindable var shell = shell
        return NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                FDABanner(status: fdaStatus)
                detailView
            }
        }
        .frame(minWidth: 920, minHeight: 560)
        .searchable(
            text: $shell.searchText,
            placement: .toolbar,
            prompt: Text("search.prompt", bundle: loc.appBundle)
        )
        .modifier(SearchFocusBridge(request: shell.searchFocusRequest))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                scanButton
            }
        }
        .task {
            scan.loadRulesIfNeeded()
        }
        .onAppear {
            // Bare `swift run` executables have no bundle, so AppKit will not
            // bring the window forward on its own.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let protection = protection
            cleanup.protectedPathCheck = { path in
                protection.evaluator.isProtected(path: path)
            }
        }
        .onChange(of: scan.isScanning) { _, _ in
            fdaStatus = FullDiskAccess.check()
        }
        .onChange(of: scan.hasScanned) { _, scanned in
            if scanned {
                rebuildRisk()
                cleanup.defaultSelect(items: scan.items, assessments: risk.itemAssessments)
                risk.probeGitStatus(projects: scan.projects) {
                    rebuildRisk()
                    cleanup.defaultSelect(items: scan.items, assessments: risk.itemAssessments)
                }
            }
        }
        .onChange(of: runtime.services) { _, _ in
            rebuildRisk()
        }
        .onChange(of: containers.resources) { _, _ in
            rebuildRisk()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .sheet(isPresented: Binding(
            get: { cleanup.phase != .idle },
            set: { if !$0 { cleanup.dismiss() } }
        )) {
            CleanupSheet()
        }
        .sheet(item: Binding(
            get: { sessionModel.pendingEnd },
            set: { if $0 == nil { sessionModel.dismiss() } }
        )) { session in
            SessionEndSheet(session: session)
        }
        .onChange(of: runtime.services) { _, _ in
            sessionModel.rebuild(
                projects: scan.projects,
                services: runtime.services,
                containers: containers.resources
            )
        }
        .onChange(of: containers.resources) { _, _ in
            sessionModel.rebuild(
                projects: scan.projects,
                services: runtime.services,
                containers: containers.resources
            )
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var shell = shell
        return VStack(spacing: 0) {
            List(selection: $shell.section) {
                Label {
                    Text("sidebar.overview", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                }
                .tag(SidebarSection.overview)

                Label {
                    Text("sidebar.activeResources", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "bolt")
                }
                .tag(SidebarSection.activeResources)
                .badge(runningResourceCount)

                Label {
                    Text("sidebar.storage", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "internaldrive")
                }
                .tag(SidebarSection.storage)

                Label {
                    Text("sidebar.sessions", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "rectangle.stack.badge.play")
                }
                .tag(SidebarSection.sessions)
                .badge(sessionModel.sessions.count)

                Label {
                    Text("sidebar.settings", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "gearshape")
                }
                .tag(SidebarSection.settings)
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)
            sidebarFooter
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
    }

    private var runningResourceCount: Int {
        runtime.services.count
            + containers.resources.filter { $0.kind == .runningContainer }.count
    }

    private func rebuildRisk() {
        risk.rebuild(
            items: scan.items,
            containers: containers.resources,
            projects: scan.projects,
            services: runtime.services
        )
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if let last = scan.lastScanDate {
                Label {
                    Text("footer.lastScan \(Text(last, format: .relative(presentation: .named)))", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "clock")
                }
            } else {
                Label {
                    Text("footer.notScanned", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "clock")
                }
            }
            if cleanup.totalReclaimedBytes > 0 {
                Label {
                    Text("footer.totalReclaimed \(Text(cleanup.totalReclaimedBytes, format: .byteCount(style: .file)))", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "trash")
                }
            }
            HStack {
                Text(verbatim: versionString)
                Spacer()
                Link(destination: URL(string: "https://mothball.dev")!) {
                    Text("footer.helpFeedback", bundle: loc.appBundle)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?): return "v\(s) (\(b))"
        case let (s?, nil): return "v\(s)"
        default: return "dev"
        }
    }

    // MARK: Toolbar

    private var scanButton: some View {
        Button {
            scan.scan()
        } label: {
            if scan.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("toolbar.scanning", bundle: loc.appBundle)
                }
            } else {
                Label {
                    Text("toolbar.scan", bundle: loc.appBundle)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .disabled(scan.isScanning)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        switch shell.section ?? .overview {
        case .overview:
            DashboardView()
        case .activeResources:
            ActiveResourcesView()
        case .storage:
            StorageView()
        case .sessions:
            SessionsView()
        case .settings:
            SettingsView()
        }
    }
}

/// Focuses the search field on ⌘K where the API exists (macOS 15+); the menu
/// item is hidden on macOS 14 (SPEC §5.7).
private struct SearchFocusBridge: ViewModifier {
    let request: Int

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.modifier(SearchFocusModifier(request: request))
        } else {
            content
        }
    }
}

@available(macOS 15.0, *)
private struct SearchFocusModifier: ViewModifier {
    @FocusState private var focused: Bool
    let request: Int

    func body(content: Content) -> some View {
        content
            .searchFocused($focused)
            .onChange(of: request) { _, _ in
                focused = true
            }
    }
}
