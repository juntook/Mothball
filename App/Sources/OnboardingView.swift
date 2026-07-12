// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// Two-page first-launch flow (SPEC §5.8): welcome → permissions & privacy.
/// Finishing auto-starts the first scan.
struct OnboardingView: View {
    @Environment(LocalizationModel.self) private var loc
    @Environment(ScanModel.self) private var scan
    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var codeRoots: [String] = []
    @State private var fdaStatus = FullDiskAccess.check()
    @State private var fdaTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if step == 0 {
                    welcome
                } else {
                    permissions
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if step == 1 {
                    Button {
                        step = 0
                    } label: {
                        Text("onboarding.back", bundle: loc.appBundle)
                    }
                    Spacer()
                    Button {
                        finish()
                    } label: {
                        Text("onboarding.later", bundle: loc.appBundle)
                    }
                    Button {
                        finish()
                    } label: {
                        Text("onboarding.continue", bundle: loc.appBundle)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(codeRoots.isEmpty)
                } else {
                    Spacer()
                    Button {
                        step = 1
                        startFDAPolling()
                    } label: {
                        Text("onboarding.start", bundle: loc.appBundle)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 540, height: 470)
        .onAppear { codeRoots = scan.codeRoots }
        .onDisappear { fdaTimer?.invalidate() }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        isPresented = false
        scan.scan()
    }

    // MARK: Page 0 — welcome

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(verbatim: "Mothball")
                .font(.largeTitle.bold())
            Text("onboarding.welcome.tagline", bundle: loc.appBundle)
                .font(.title3)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                bullet("onboarding.welcome.feature.ports")
                bullet("onboarding.welcome.feature.stop")
                bullet("onboarding.welcome.feature.caches")
                bullet("onboarding.welcome.feature.local")
            }
            .padding(.top, 4)

            Text("onboarding.welcome.privacy", bundle: loc.appBundle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }

    private func bullet(_ key: LocalizedStringKey) -> some View {
        Label {
            Text(key, bundle: loc.appBundle)
        } icon: {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
        }
        .font(.callout)
    }

    // MARK: Page 1 — permissions & privacy

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("onboarding.permissions.title", bundle: loc.appBundle)
                .font(.title2.bold())
            Text("onboarding.permissions.intro", bundle: loc.appBundle)
                .foregroundStyle(.secondary)

            permissionRow(
                icon: "waveform.path.ecg",
                titleKey: "onboarding.permissions.runtime",
                detailKey: "onboarding.permissions.runtime.detail"
            ) {
                Text("onboarding.permissions.granted", bundle: loc.appBundle)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            permissionRow(
                icon: "folder",
                titleKey: "onboarding.permissions.roots",
                detailKey: "onboarding.permissions.roots.detail"
            ) {
                HStack(spacing: 6) {
                    if !codeRoots.isEmpty {
                        Text("onboarding.permissions.roots.count \(codeRoots.count)", bundle: loc.appBundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        pickRoots()
                    } label: {
                        Text("onboarding.permissions.roots.choose", bundle: loc.appBundle)
                    }
                    .controlSize(.small)
                }
            }

            permissionRow(
                icon: "internaldrive",
                titleKey: "onboarding.permissions.fda",
                detailKey: "onboarding.permissions.fda.detail"
            ) {
                HStack(spacing: 6) {
                    fdaStatusIcon
                    Button {
                        if let url = URL(string: FullDiskAccess.settingsPaneURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("onboarding.fda.open", bundle: loc.appBundle)
                    }
                    .controlSize(.small)
                }
            }

            Text("onboarding.permissions.fdaNote", bundle: loc.appBundle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func permissionRow(
        icon: String,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey, bundle: loc.appBundle)
                    .fontWeight(.medium)
                Text(detailKey, bundle: loc.appBundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var fdaStatusIcon: some View {
        switch fdaStatus {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .help(Text("onboarding.fda.granted", bundle: loc.appBundle))
        case .denied:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                .help(Text("onboarding.fda.denied", bundle: loc.appBundle))
        case .indeterminate:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .help(Text("onboarding.fda.indeterminate", bundle: loc.appBundle))
        }
    }

    private func pickRoots() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK {
            for url in panel.urls where !codeRoots.contains(url.path) {
                codeRoots.append(url.path)
            }
            scan.codeRoots = codeRoots
        }
    }

    private func startFDAPolling() {
        fdaTimer?.invalidate()
        fdaTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            let status = FullDiskAccess.check()
            Task { @MainActor in
                fdaStatus = status
            }
        }
    }
}
