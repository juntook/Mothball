// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Directory sizing")
struct DirectorySizerTests {
    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mothball-sizer-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 10_000).write(to: root.appendingPathComponent("f1"))
        try Data(repeating: 0x42, count: 20_000).write(to: root.appendingPathComponent("a/f2"))
        try Data(repeating: 0x43, count: 30_000).write(to: root.appendingPathComponent("a/b/f3"))
        return root
    }

    @Test("Counts allocated blocks for a small tree")
    func sizesTree() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let serial = DirectorySizer.allocatedSize(atPath: root.path)
        let concurrent = await DirectorySizer.allocatedSizeConcurrent(atPath: root.path)

        // Allocated size is at least the logical 60 KB, rounded up to blocks.
        #expect(serial >= 60_000)
        #expect(concurrent == serial)
    }

    @Test("Symlinks are counted as links, never followed")
    func symlinkNotFollowed() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("mothball-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 0x5A, count: 5_000_000).write(to: outside.appendingPathComponent("big"))

        let before = DirectorySizer.allocatedSize(atPath: root.path)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )
        let after = DirectorySizer.allocatedSize(atPath: root.path)

        // The 5 MB behind the symlink must not be included; only the link inode.
        #expect(after - before < 100_000)
    }

    @Test("A file argument returns its own allocated size")
    func singleFile() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let size = DirectorySizer.allocatedSize(atPath: root.appendingPathComponent("f1").path)
        #expect(size >= 10_000)
        #expect(size < 1_000_000)
    }

    @Test("Missing path sizes to zero")
    func missingPath() {
        #expect(DirectorySizer.allocatedSize(atPath: "/nonexistent/mothball/path") == 0)
    }

    @Test("SF_DATALESS flag detection drives the skip-descend decision")
    func datalessFlagDetection() {
        // SF_DATALESS is settable only by the kernel, so the predicate that
        // gates fts_set(FTS_SKIP) is what gets verified here.
        #expect(DirectorySizer.isDatalessFlags(UInt32(SF_DATALESS)))
        #expect(DirectorySizer.isDatalessFlags(UInt32(SF_DATALESS) | UInt32(UF_HIDDEN)))
        #expect(!DirectorySizer.isDatalessFlags(0))
        #expect(!DirectorySizer.isDatalessFlags(UInt32(UF_HIDDEN)))
    }
}
