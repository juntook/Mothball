// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation

/// Snapshot of one process, as read from libproc. Everything here comes from
/// unprivileged user-space APIs (SPEC §5.4 — never sudo, never a helper).
public struct ProcessSnapshot: Sendable, Hashable {
    public var pid: Int32
    public var name: String
    public var executablePath: String?
    public var listeningTCPPorts: [UInt16]
    public var workingDirectory: String?
    public var residentMemoryBytes: UInt64
    public var startDate: Date
    /// Parent pid, for process-tree grouping (SPEC §5.10). 0 when unknown.
    public var parentPID: Int32
    /// Cumulative user+system CPU time in nanoseconds. CPU percentages are
    /// derived by differencing two snapshots (SPEC §5.10); nil when the
    /// kernel refused rusage for this process.
    public var cpuTimeNanos: UInt64?

    public init(
        pid: Int32, name: String, executablePath: String? = nil,
        listeningTCPPorts: [UInt16] = [], workingDirectory: String? = nil,
        residentMemoryBytes: UInt64 = 0, startDate: Date = .distantPast,
        parentPID: Int32 = 0, cpuTimeNanos: UInt64? = nil
    ) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.listeningTCPPorts = listeningTCPPorts
        self.workingDirectory = workingDirectory
        self.residentMemoryBytes = residentMemoryBytes
        self.startDate = startDate
        self.parentPID = parentPID
        self.cpuTimeNanos = cpuTimeNanos
    }
}

/// Abstracts process enumeration so filtering and the stop flow are testable.
public protocol ProcessProvider: Sendable {
    /// All processes owned by the current user.
    func currentUserProcesses() -> [ProcessSnapshot]
    /// A single process, or nil if it no longer exists (stop-flow probing).
    func snapshot(pid: Int32) -> ProcessSnapshot?
    func sendSignal(_ signal: Int32, to pid: Int32) -> Bool
}

/// libproc-backed implementation. Discovery chain per SPEC §5.4:
/// proc_listpids → proc_pidfdinfo (LISTEN sockets) → proc_pidpath →
/// proc_pidvnodepathinfo (cwd) → proc_pid_rusage (memory) + bsdinfo (start).
public struct LibprocProcessProvider: ProcessProvider {
    public init() {}

    public func currentUserProcesses() -> [ProcessSnapshot] {
        let uid = getuid()
        var count = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.stride + 64)
        count = proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        let valid = pids.prefix(Int(count) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
        return valid.compactMap { snapshot(pid: $0) }
    }

    public func snapshot(pid: Int32) -> ProcessSnapshot? {
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else {
            return nil
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let execPath = pathLength > 0 ? String(cString: pathBuffer) : nil

        let name: String
        if let execPath, !execPath.isEmpty {
            name = (execPath as NSString).lastPathComponent
        } else {
            name = withUnsafeBytes(of: bsd.pbi_name) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
        }

        var vnodeInfo = proc_vnodepathinfo()
        let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        var cwd: String?
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, vnodeSize) == vnodeSize {
            cwd = withUnsafeBytes(of: vnodeInfo.pvi_cdir.vip_path) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            if cwd?.isEmpty == true { cwd = nil }
        }

        var rusage = rusage_info_current()
        let rusageOK = withUnsafeMutablePointer(to: &rusage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reptr in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, reptr) == 0
            }
        }
        let memory: UInt64 = rusageOK ? rusage.ri_resident_size : 0
        // ri_*_time are in mach time units; convert to nanoseconds.
        let cpuNanos: UInt64? = rusageOK
            ? Self.machToNanos(rusage.ri_user_time &+ rusage.ri_system_time)
            : nil

        return ProcessSnapshot(
            pid: pid,
            name: name,
            executablePath: execPath,
            listeningTCPPorts: listeningPorts(pid: pid),
            workingDirectory: cwd,
            residentMemoryBytes: memory,
            startDate: Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec)),
            parentPID: Int32(bitPattern: bsd.pbi_ppid),
            cpuTimeNanos: cpuNanos
        )
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func machToNanos(_ machTime: UInt64) -> UInt64 {
        let tb = timebase
        guard tb.denom != 0 else { return machTime }
        return machTime.multipliedReportingOverflow(by: UInt64(tb.numer)).partialValue / UInt64(tb.denom)
    }

    public func sendSignal(_ signal: Int32, to pid: Int32) -> Bool {
        kill(pid, signal) == 0
    }

    private func listeningPorts(pid: Int32) -> [UInt16] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let fdCount = Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount + 32)
        let written = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.stride))
        guard written > 0 else { return [] }

        var ports = Set<UInt16>()
        for fd in fds.prefix(Int(written) / MemoryLayout<proc_fdinfo>.stride)
        where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socketInfo = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.stride)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, size) == size else {
                continue
            }
            guard socketInfo.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = socketInfo.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            if localPort > 0 { ports.insert(localPort) }
        }
        return ports.sorted()
    }
}
