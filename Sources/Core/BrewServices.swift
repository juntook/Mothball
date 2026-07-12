// SPDX-License-Identifier: Apache-2.0
import Foundation

/// One Homebrew-managed background service (SPEC §5.11).
public struct BrewService: Sendable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    /// Raw brew status: "started", "scheduled", "stopped", "error", "none", …
    public var status: String
    public var user: String?
    /// launchd plist path when registered.
    public var plistPath: String?
    public var exitCode: Int?

    public var isRunning: Bool { status == "started" || status == "scheduled" || status == "error" }
    /// Registered to relaunch at login (brew "started" semantics).
    public var startsAtLogin: Bool { status == "started" || status == "scheduled" }

    public init(name: String, status: String, user: String? = nil, plistPath: String? = nil, exitCode: Int? = nil) {
        self.name = name
        self.status = status
        self.user = user
        self.plistPath = plistPath
        self.exitCode = exitCode
    }
}

/// Shell-out client for `brew services` (SPEC §5.11). The brew binary is
/// resolved from fixed candidates only — GUI apps have no Homebrew PATH
/// (SPEC §9.1). Stop semantics map to brew subcommands:
/// stop once = `kill` (keeps login registration), stop & disable = `stop`
/// (unregisters), restart = `run` (starts without registering).
public struct BrewServicesClient: Sendable {
    public static let binaryCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    private let binary: String
    private let runner: any CommandRunner

    public init(binary: String, runner: any CommandRunner = RealCommandRunner()) {
        self.binary = binary
        self.runner = runner
    }

    /// First existing brew binary, or nil when Homebrew isn't installed.
    public static func resolveBinary(fs: any FileSystem = RealFileSystem()) -> String? {
        binaryCandidates.first { fs.exists($0) }
    }

    public func list() throws -> [BrewService] {
        struct Row: Decodable {
            var name: String
            var status: String?
            var user: String?
            var file: String?
            var exit_code: Int?
        }
        let data = try runner.run(executable: binary, arguments: ["services", "list", "--json"])
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.map {
            BrewService(
                name: $0.name,
                status: $0.status ?? "none",
                user: $0.user,
                plistPath: $0.file,
                exitCode: $0.exit_code
            )
        }
    }

    /// Stops the running instance but keeps the login registration.
    public func stopOnce(_ name: String) throws {
        _ = try runner.run(executable: binary, arguments: ["services", "kill", name])
    }

    /// Stops and unregisters from login.
    public func stopAndDisable(_ name: String) throws {
        _ = try runner.run(executable: binary, arguments: ["services", "stop", name])
    }

    /// Starts without registering at login.
    public func runOnce(_ name: String) throws {
        _ = try runner.run(executable: binary, arguments: ["services", "run", name])
    }
}
