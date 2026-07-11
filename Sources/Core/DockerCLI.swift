// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Runs external commands. Injectable so Docker parsing is testable with
/// canned CLI output.
public protocol CommandRunner: Sendable {
    func run(executable: String, arguments: [String]) throws -> Data
}

public struct RealCommandRunner: CommandRunner {
    public init() {}

    public struct CommandError: Error, LocalizedError {
        public var command: String
        public var exitCode: Int32
        public var stderr: String
        public var errorDescription: String? { "\(command) exited \(exitCode): \(stderr)" }
    }

    public func run(executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandError(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }
        return data
    }
}

/// Locates the docker binary and endpoint. GUI apps do not inherit the shell
/// PATH (SPEC §9.1), so only fixed candidates are consulted.
public struct DockerEnvironment: Sendable {
    public struct Diagnostics: Sendable {
        public var binaryPath: String?
        public var socketCandidatesFound: [String]
        public var dockerHostEnv: String?
        public var currentContextEndpoint: String?
        public var daemonReachable: Bool
        public var podmanDetected: Bool
    }

    public static let binaryCandidates = [
        "/opt/homebrew/bin/docker",
        "/usr/local/bin/docker",
        "~/.orbstack/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    public static let socketCandidates = [
        "~/.docker/run/docker.sock",
        "~/.orbstack/run/docker.sock",
        "~/.colima/default/docker.sock",
        "/var/run/docker.sock",
    ]

    public static let podmanCandidates = [
        "/opt/homebrew/bin/podman",
        "/usr/local/bin/podman",
    ]

    private let fs: any FileSystem
    private let runner: any CommandRunner

    public init(fs: any FileSystem = RealFileSystem(), runner: any CommandRunner = RealCommandRunner()) {
        self.fs = fs
        self.runner = runner
    }

    public func resolveBinary() -> String? {
        for candidate in Self.binaryCandidates {
            let expanded = (try? PathExpansion.expandTilde(candidate, fs: fs)) ?? candidate
            if fs.exists(expanded) { return expanded }
        }
        return nil
    }

    /// Full endpoint discovery per SPEC §5.5, everything recorded.
    public func diagnose() -> Diagnostics {
        let binary = resolveBinary()
        let sockets = Self.socketCandidates.compactMap { candidate -> String? in
            let expanded = (try? PathExpansion.expandTilde(candidate, fs: fs)) ?? candidate
            return fs.exists(expanded) ? expanded : nil
        }
        let dockerHost = ProcessInfo.processInfo.environment["DOCKER_HOST"]

        var contextEndpoint: String?
        var reachable = false
        if let binary {
            if let data = try? runner.run(executable: binary, arguments: ["context", "inspect", "--format", "{{.Endpoints.docker.Host}}"]) {
                contextEndpoint = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // A cheap liveness probe.
            reachable = (try? runner.run(executable: binary, arguments: ["version", "--format", "{{.Server.Version}}"])) != nil
        }

        let podman = Self.podmanCandidates.contains { candidate in
            fs.exists(candidate)
        }

        return Diagnostics(
            binaryPath: binary,
            socketCandidatesFound: sockets,
            dockerHostEnv: dockerHost,
            currentContextEndpoint: contextEndpoint,
            daemonReachable: reachable,
            podmanDetected: podman
        )
    }
}
