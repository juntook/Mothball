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
    @Environment(NotificationModel.self) private var notifications

    @AppStorage("scanFrequency") private var scanFrequency = "manual"

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
            .background(AppBackground())
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
            if let session = sessionModel.sessions.first {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shell.open(.sessions)
                        sessionModel.beginConfirmation(session)
                    } label: {
                        Label {
                            Text("toolbar.endSession", bundle: loc.appBundle)
                        } icon: {
                            Image(systemName: "power")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task {
            scan.loadRulesIfNeeded()
        }
        .task {
            // Scheduled scans only ever produce a report — the deletion path
            // stays behind the interactive preview, always (SPEC §5.15).
            while !Task.isCancelled {
                autoScanIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
        .onAppear {
            // Bare `swift run` executables have no bundle, so AppKit will not
            // bring the window forward or pick up the app icon on its own.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if Bundle.main.bundleIdentifier == nil,
               let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = icon
            }
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
                notifications.maybeNotifyReclaimable(totalBytes: scan.totalBytes, loc: loc)
            }
        }
        .onChange(of: runtime.services) { _, _ in
            rebuildRisk()
            notifications.maybeNotifyLongRunning(services: runtime.services, loc: loc)
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
                    SidebarChip(color: .blue, systemImage: "gauge.with.dots.needle.33percent")
                }
                .tag(SidebarSection.overview)

                Label {
                    Text("sidebar.activeResources", bundle: loc.appBundle)
                } icon: {
                    SidebarChip(color: .green, systemImage: "bolt.fill")
                }
                .tag(SidebarSection.activeResources)
                .badge(runningResourceCount)

                Label {
                    Text("sidebar.storage", bundle: loc.appBundle)
                } icon: {
                    SidebarChip(color: .orange, systemImage: "internaldrive.fill")
                }
                .tag(SidebarSection.storage)

                Label {
                    Text("sidebar.sessions", bundle: loc.appBundle)
                } icon: {
                    SidebarChip(color: .purple, systemImage: "rectangle.stack.badge.play.fill")
                }
                .tag(SidebarSection.sessions)
                .badge(sessionModel.sessions.count)

                Label {
                    Text("sidebar.history", bundle: loc.appBundle)
                } icon: {
                    SidebarChip(color: .teal, systemImage: "clock.arrow.circlepath")
                }
                .tag(SidebarSection.history)

                Label {
                    Text("sidebar.settings", bundle: loc.appBundle)
                } icon: {
                    SidebarChip(color: .gray, systemImage: "gearshape.fill")
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

    private func autoScanIfDue() {
        let interval: TimeInterval? = switch scanFrequency {
        case "daily": 24 * 3600
        case "weekly": 7 * 24 * 3600
        default: nil
        }
        guard let interval, !scan.isScanning else { return }
        let last = UserDefaults.standard.object(forKey: "lastAutoScanDate") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval else { return }
        UserDefaults.standard.set(Date(), forKey: "lastAutoScanDate")
        scan.scan()
    }

    private func rebuildRisk() {
        risk.rebuild(
            items: scan.items,
            containers: containers.resources,
            projects: scan.projects,
            services: runtime.services
        )
    }

    /// Prototype-style status block: scan-state dot, lifetime reclaimed with
    /// an emphasized figure, then version + feedback on one muted line.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(scan.isScanning ? Color.orange : .green)
                    .frame(width: 7, height: 7)
                if scan.isScanning {
                    Text("toolbar.scanning", bundle: loc.appBundle)
                } else if let last = scan.lastScanDate {
                    Text("footer.lastScan \(Text(last, format: .relative(presentation: .named)))", bundle: loc.appBundle)
                } else {
                    Text("footer.notScanned", bundle: loc.appBundle)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if cleanup.totalReclaimedBytes > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("footer.totalReclaimed.label", bundle: loc.appBundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cleanup.totalReclaimedBytes, format: .byteCount(style: .file))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }

            HStack {
                Text(verbatim: versionString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Link(destination: URL(string: "https://mothball.dev/")!) {
                    Text("footer.helpFeedback", bundle: loc.appBundle)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
        case .history:
            HistoryView()
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
