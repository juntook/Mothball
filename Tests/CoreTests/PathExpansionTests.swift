// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Path expansion")
struct PathExpansionTests {
    let fs = FakeFileSystem(home: "/Users/test", entries: [
        "/Users/test/.npm": true,
        "/Users/test/.npm/_cacache": true,
        "/Users/test/.npm/_logs": true,
        "/Users/test/.npm/readme.txt": false,
        "/Users/test/Library": true,
        "/Users/test/Library/Caches": true,
        "/Users/test/Library/Caches/WorkBuddyCache": true,
        "/Users/test/Library/Caches/other-workbuddy-cache": true,
        "/Users/test/Library/Caches/Unrelated": true,
        "/Users/test/Library/Caches/.hidden-workbuddy": true,
        "/Users/test/file with spaces/子目录": true,
    ])

    @Test("Tilde expands to the home directory")
    func tilde() throws {
        #expect(try PathExpansion.expandTilde("~/.npm", fs: fs) == "/Users/test/.npm")
        #expect(try PathExpansion.expandTilde("~", fs: fs) == "/Users/test")
        #expect(try PathExpansion.expandTilde("/absolute/path", fs: fs) == "/absolute/path")
    }

    @Test("Dot-dot and double-star are rejected")
    func forbiddenPatterns() {
        #expect(throws: PathExpansion.ExpansionError.self) {
            try PathExpansion.expandTilde("~/foo/../bar", fs: fs)
        }
        #expect(throws: PathExpansion.ExpansionError.self) {
            try PathExpansion.expand("~/foo/**/bar", fs: fs)
        }
    }

    @Test("Literal path expands only when it exists")
    func literalExistence() throws {
        #expect(try PathExpansion.expand("~/.npm/_cacache", fs: fs) == ["/Users/test/.npm/_cacache"])
        #expect(try PathExpansion.expand("~/.npm/_npx", fs: fs).isEmpty)
    }

    @Test("Star matches within one segment only")
    func starWithinSegment() throws {
        let hits = try PathExpansion.expand("~/Library/Caches/*WorkBuddy*", fs: fs)
        #expect(hits == ["/Users/test/Library/Caches/WorkBuddyCache"])

        let caseSensitive = try PathExpansion.expand("~/Library/Caches/*workbuddy*", fs: fs)
        #expect(caseSensitive == ["/Users/test/Library/Caches/other-workbuddy-cache"])
    }

    @Test("Star does not match hidden entries unless the pattern is dotted")
    func hiddenEntries() throws {
        let hits = try PathExpansion.expand("~/Library/Caches/*", fs: fs)
        #expect(!hits.contains("/Users/test/Library/Caches/.hidden-workbuddy"))

        let dotted = try PathExpansion.expand("~/Library/Caches/.hidden*", fs: fs)
        #expect(dotted == ["/Users/test/Library/Caches/.hidden-workbuddy"])
    }

    @Test("Unicode and spaces survive expansion")
    func unicodePaths() throws {
        #expect(try PathExpansion.expand("~/file with spaces/子目录", fs: fs) == ["/Users/test/file with spaces/子目录"])
    }
}
