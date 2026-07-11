// SPDX-License-Identifier: Apache-2.0
// Test-first per CLAUDE.md: every rejection branch of the deletion gate
// (SPEC §5.6) is specified here before/alongside the implementation.
import Foundation
import Testing
@testable import Core

@Suite("Deletion gate — rejection branches")
struct DeletionGateTests {
    /// Gate wired to a real temp directory so realpath normalization is exercised.
    struct Fixture {
        let root: URL
        let home: String
        let allowed: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("mothball-gate-\(UUID().uuidString)")
            let fm = FileManager.default
            home = root.appendingPathComponent("home").path
            allowed = root.appendingPathComponent("home/.npm/_cacache")
            try fm.createDirectory(at: allowed.appendingPathComponent("pkg"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: allowed.appendingPathComponent("pkg/file.bin"))
        }

        func gate(directDelete: Bool = false) -> DeletionGate {
            DeletionGate(
                allowedPrefixes: [allowed.path],
                homeDirectoryPath: home,
                directDeleteEnabled: directDelete
            )
        }

        func item(_ path: String, safety: Safety = .regenerable) -> CleanupItem {
            CleanupItem(path: path, safety: safety, ruleID: "npm", targetID: "cacache")
        }
    }

    @Test("Rejects the filesystem root")
    func rejectsRoot() throws {
        let f = try Fixture()
        #expect(f.gate().check(f.item("/"), method: .trash) == .rejected(.forbiddenPath))
    }

    @Test("Rejects the home directory itself")
    func rejectsHome() throws {
        let f = try Fixture()
        #expect(f.gate().check(f.item(f.home), method: .trash) == .rejected(.forbiddenPath))
    }

    @Test("Rejects any path containing dot-dot")
    func rejectsDotDot() throws {
        let f = try Fixture()
        let sneaky = f.allowed.path + "/pkg/../../../etc"
        #expect(f.gate().check(f.item(sneaky), method: .trash) == .rejected(.forbiddenPath))
    }

    @Test("Rejects paths shorter than 8 characters")
    func rejectsShortPaths() throws {
        let f = try Fixture()
        #expect(f.gate().check(f.item("/a/b/c"), method: .trash) == .rejected(.forbiddenPath))
    }

    @Test("Rejects /System and system-level /Library")
    func rejectsSystemPaths() throws {
        let f = try Fixture()
        #expect(f.gate().check(f.item("/System/Library/Caches/foo"), method: .trash) == .rejected(.forbiddenPath))
        #expect(f.gate().check(f.item("/Library/Caches/com.apple.foo"), method: .trash) == .rejected(.forbiddenPath))
    }

    @Test("Rejects paths outside every allowed rule prefix")
    func rejectsOutsidePrefixes() throws {
        let f = try Fixture()
        let outside = f.home + "/.npm/_logs/debug.log"
        #expect(f.gate().check(f.item(outside), method: .trash) == .rejected(.outsideAllowedPrefixes))
    }

    @Test("Rejects symlink escape: parent chain resolving outside the prefix")
    func rejectsSymlinkEscape() throws {
        let f = try Fixture()
        // allowed/link -> home (outside target subtree); deleting through the
        // link must normalize to the real location and be rejected.
        let link = f.allowed.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: f.home
        )
        let through = link.path + "/Documents-ish"
        let result = f.gate().check(f.item(through), method: .trash)
        #expect(result == .rejected(.outsideAllowedPrefixes) || result == .rejected(.forbiddenPath))
    }

    @Test("Rejects protected items unconditionally")
    func rejectsProtected() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/file.bin"
        #expect(f.gate().check(f.item(path, safety: .protected), method: .trash) == .rejected(.protectedSafety))
        #expect(f.gate(directDelete: true).check(f.item(path, safety: .protected), method: .delete) == .rejected(.protectedSafety))
    }

    @Test("Rejects direct delete of user_data even when direct delete is enabled")
    func userDataTrashOnly() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/file.bin"
        #expect(f.gate(directDelete: true).check(f.item(path, safety: .userData), method: .delete) == .rejected(.userDataRequiresTrash))
    }

    @Test("Rejects direct delete when the setting is off")
    func directDeleteNeedsSetting() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/file.bin"
        #expect(f.gate(directDelete: false).check(f.item(path), method: .delete) == .rejected(.directDeleteDisabled))
    }

    @Test("Rejects nonexistent paths")
    func rejectsMissing() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/never-existed.bin"
        #expect(f.gate().check(f.item(path), method: .trash) == .rejected(.notFound))
    }

    @Test("Accepts a valid regenerable trash operation")
    func acceptsValidTrash() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/file.bin"
        #expect(f.gate().check(f.item(path), method: .trash) == .allowed)
    }

    @Test("Accepts user_data to trash")
    func acceptsUserDataTrash() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/file.bin"
        #expect(f.gate().check(f.item(path, safety: .userData), method: .trash) == .allowed)
    }

    @Test("Accepts regenerable direct delete when enabled")
    func acceptsDirectDeleteWhenEnabled() throws {
        let f = try Fixture()
        let path = f.allowed.path + "/pkg/file.bin"
        #expect(f.gate(directDelete: true).check(f.item(path), method: .delete) == .allowed)
    }

    @Test("Deleting a symlink itself inside the prefix is allowed (link, not target)")
    func symlinkLeafInsidePrefix() throws {
        let f = try Fixture()
        let link = f.allowed.appendingPathComponent("pkg/leaf-link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: f.home
        )
        #expect(f.gate().check(f.item(link.path), method: .trash) == .allowed)
    }
}
