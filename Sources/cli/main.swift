// SPDX-License-Identifier: Apache-2.0
// Debug CLI exposing Core capabilities for development-time verification.
// Output is intentionally English-only and not localized (SPEC §8.5).
import Core
import Foundation

let version = "0.1.0"

func printUsage() {
    print("""
    mothball \(version) — debug CLI for the Mothball Core engine

    USAGE: mothball <command>

    COMMANDS:
      version    Print version
      help       Show this help
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "version":
    print(version)
case "help", nil:
    printUsage()
default:
    printUsage()
    exit(2)
}
