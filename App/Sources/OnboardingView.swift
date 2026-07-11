// SPDX-License-Identifier: Apache-2.0
import Core
import SwiftUI

/// First-launch flow (SPEC §5.8): welcome → code roots → Full Disk Access →
/// finish (auto-starts the first scan).
struct OnboardingView: View {
    @Environment(ScanModel.self) private var scan
    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var codeRoots: [String] = []
    @State private var fdaStatus = FullDiskAccess.check()
    @State private var fdaTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: rootsPicker
                default: fdaGuide
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Text("onboarding.back", bundle: .module)
                    }
                }
                Spacer()
                if step == 1 && codeRoots.isEmpty {
                    Button {
                        step += 1
                    } label: {
                        Text("onboarding.skip", bundle: .module)
                    }
                }
                Button {
                    advance()
                } label: {
                    Text(step == 2 ? "onboarding.finish" : "onboarding.continue", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(step == 1 && codeRoots.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
        .onAppear { codeRoots = scan.codeRoots }
        .onDisappear { fdaTimer?.invalidate() }
    }

    private func advance() {
        if step < 2 {
            step += 1
            if step == 2 { startFDAPolling() }
        } else {
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            isPresented = false
            scan.scan()
        }
    }

    // MARK: Step 0 — welcome

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(verbatim: "Mothball")
                .font(.largeTitle.bold())
            Text("onboarding.welcome.tagline", bundle: .module)
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("onboarding.welcome.privacy", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }

    // MARK: Step 1 — code roots

    private var rootsPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("onboarding.roots.title", bundle: .module)
                .font(.title2.bold())
            Text("onboarding.roots.detail", bundle: .module)
                .foregroundStyle(.secondary)

            List {
                ForEach(codeRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder")
                        Text(verbatim: root).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            codeRoots.removeAll { $0 == root }
                            scan.codeRoots = codeRoots
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 120)

            Button {
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
            } label: {
                Label {
                    Text("settings.codeRoots.add", bundle: .module)
                } icon: {
                    Image(systemName: "plus")
                }
            }
        }
        .padding()
    }

    // MARK: Step 2 — Full Disk Access

    private var fdaGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("onboarding.fda.title", bundle: .module)
                .font(.title2.bold())
            Text("onboarding.fda.why", bundle: .module)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                statusIcon
                statusText
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Button {
                if let url = URL(string: FullDiskAccess.settingsPaneURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label {
                    Text("onboarding.fda.open", bundle: .module)
                } icon: {
                    Image(systemName: "gear")
                }
            }

            Text("onboarding.fda.optional", bundle: .module)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch fdaStatus {
        case .granted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied: Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
        case .indeterminate: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private var statusText: Text {
        switch fdaStatus {
        case .granted: Text("onboarding.fda.granted", bundle: .module)
        case .denied: Text("onboarding.fda.denied", bundle: .module)
        case .indeterminate: Text("onboarding.fda.indeterminate", bundle: .module)
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

/// Persistent banner shown above scan results while FDA is missing —
/// results must never look silently incomplete (SPEC §5.8 degraded mode).
struct FDABanner: View {
    let status: FullDiskAccess.Status

    var body: some View {
        if status == .denied {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("fda.banner", bundle: .module)
                    .font(.callout)
                Spacer()
                Button {
                    if let url = URL(string: FullDiskAccess.settingsPaneURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("fda.banner.action", bundle: .module)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
        }
    }
}
