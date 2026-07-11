// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation

/// Full Disk Access detection (SPEC §5.8). The probe reads a TCC-protected
/// directory: readable → granted; permission error → denied. No entitlements,
/// no private API — just observing what TCC lets us do.
public enum FullDiskAccess {
    public enum Status: Sendable, Equatable {
        case granted
        case denied
        /// No probe path exists on this machine (fresh account) — treated as
        /// granted for UI purposes but reported distinctly.
        case indeterminate
    }

    /// TCC-protected paths that exist on virtually every macOS install.
    static let probePaths = [
        "~/Library/Safari",
        "~/Library/Mail",
        "~/Library/Messages",
    ]

    public static func check(fs: any FileSystem = RealFileSystem()) -> Status {
        for probe in probePaths {
            guard let expanded = try? PathExpansion.expandTilde(probe, fs: fs) else { continue }
            var st = stat()
            guard lstat(expanded, &st) == 0 else { continue }

            guard let dir = opendir(expanded) else {
                if errno == EPERM || errno == EACCES {
                    return .denied
                }
                continue
            }
            closedir(dir)
            return .granted
        }
        return .indeterminate
    }

    /// Deep link to the Full Disk Access pane in System Settings.
    public static let settingsPaneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
}
