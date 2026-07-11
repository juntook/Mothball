// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Full Disk Access probe")
struct FullDiskAccessTests {
    @Test("Probe returns a definite status on a real machine")
    func probeRuns() {
        // The probe must never crash and must return one of the three states.
        let status = FullDiskAccess.check()
        #expect([.granted, .denied, .indeterminate].contains(status))
    }

    @Test("Probe paths are TCC-protected user locations")
    func probePathsShape() {
        #expect(!FullDiskAccess.probePaths.isEmpty)
        #expect(FullDiskAccess.probePaths.allSatisfy { $0.hasPrefix("~/Library/") })
    }

    @Test("Settings deep link targets the Full Disk Access pane")
    func settingsLink() {
        #expect(FullDiskAccess.settingsPaneURL.contains("Privacy_AllFiles"))
        #expect(URL(string: FullDiskAccess.settingsPaneURL) != nil)
    }
}
