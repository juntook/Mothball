// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation

/// Computes allocated (physical) on-disk size using bulk fts(3) traversal.
///
/// Constraints from SPEC §5.2:
/// - never follows symbolic links (FTS_PHYSICAL);
/// - never materializes iCloud dataless files — they are counted at their
///   metadata size only and never opened or descended into;
/// - sizes concurrently across top-level subdirectories.
public enum DirectorySizer {
    /// Allocated size of a single file or an entire tree, traversed serially.
    /// The path itself is never resolved through a symlink.
    public static func allocatedSize(atPath path: String) -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) != S_IFDIR {
            return Int64(st.st_blocks) * 512
        }
        return sizeOfTree(rootPath: path)
    }

    /// Allocated size of a directory, fanned out across its top-level children.
    public static func allocatedSizeConcurrent(atPath path: String) async -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            return Int64(st.st_blocks) * 512
        }

        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        var total = Int64(st.st_blocks) * 512

        var files: [String] = []
        var dirs: [String] = []
        for name in children {
            let child = path + "/" + name
            var cst = stat()
            guard lstat(child, &cst) == 0 else { continue }
            if (cst.st_mode & S_IFMT) == S_IFDIR, !isDataless(cst) {
                dirs.append(child)
            } else {
                files.append(child)
            }
        }
        for file in files {
            var cst = stat()
            if lstat(file, &cst) == 0 { total += Int64(cst.st_blocks) * 512 }
        }

        total += await withTaskGroup(of: Int64.self) { group in
            for dir in dirs {
                group.addTask { sizeOfTree(rootPath: dir) }
            }
            var sum: Int64 = 0
            for await part in group { sum += part }
            return sum
        }
        return total
    }

    /// SF_DATALESS marks iCloud placeholder content; touching it can trigger a
    /// download, so such entries are counted as-is and never entered.
    static func isDatalessFlags(_ flags: UInt32) -> Bool {
        (flags & UInt32(SF_DATALESS)) != 0
    }

    private static func isDataless(_ st: stat) -> Bool {
        isDatalessFlags(st.st_flags)
    }

    private static func sizeOfTree(rootPath: String) -> Int64 {
        var total: Int64 = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(rootPath), nil]
        defer { free(argv[0]) }

        // FTS_PHYSICAL: lstat semantics, never follow symlinks.
        // FTS_XDEV intentionally NOT set: a target may legitimately span volumes.
        guard let stream = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return 0
        }
        defer { fts_close(stream) }

        while let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D:
                if let st = entry.pointee.fts_statp?.pointee {
                    total += Int64(st.st_blocks) * 512
                    if isDataless(st) {
                        // Count the placeholder's metadata, skip its contents.
                        fts_set(stream, entry, FTS_SKIP)
                    }
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                // Files are never opened, so dataless entries contribute only the
                // blocks the placeholder already occupies — no download risk.
                if let st = entry.pointee.fts_statp?.pointee {
                    total += Int64(st.st_blocks) * 512
                }
            default:
                break // FTS_DP (postorder revisit), FTS_DNR/FTS_NS errors: nothing to add
            }
        }
        return total
    }
}
