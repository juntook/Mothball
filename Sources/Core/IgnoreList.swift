// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Path-level ignore list (SPEC §5.6): ignored entries are still counted by
/// scans but collapse in the UI and can never be selected for cleanup.
public struct IgnoreList: Sendable {
    public static let defaultStorePath = "~/Library/Application Support/Mothball/ignored.json"

    private let storeURL: URL

    public init(storePath: String = IgnoreList.defaultStorePath, fs: any FileSystem = RealFileSystem()) {
        let expanded = (try? PathExpansion.expandTilde(storePath, fs: fs)) ?? storePath
        self.storeURL = URL(fileURLWithPath: expanded)
    }

    public func load() -> Set<String> {
        guard let data = try? Data(contentsOf: storeURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(paths)
    }

    public func save(_ paths: Set<String>) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(paths.sorted()).write(to: storeURL)
        } catch {
            FileHandle.standardError.write(Data("ignore-list save failed: \(error)\n".utf8))
        }
    }

    public func add(_ path: String) {
        var paths = load()
        paths.insert(path)
        save(paths)
    }

    public func remove(_ path: String) {
        var paths = load()
        paths.remove(path)
        save(paths)
    }
}
