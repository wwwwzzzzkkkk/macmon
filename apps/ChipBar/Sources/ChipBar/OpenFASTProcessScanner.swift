import Foundation
import Darwin
import ChipBarCore

/// Read-only OpenFAST process observer. This actor never creates a Process,
/// runs a shell, modifies a simulation file, or controls a calculation.
/// It only enumerates same-user PIDs and reads bounded input/output bytes.
actor OpenFASTProcessScanner {
    static let shared = OpenFASTProcessScanner()

    private static let maximumProcesses = 8
    private static let maximumArgumentsBytes = 131_072
    private static let maximumInputBytes = 1_048_576
    private static let tailBytes = 16_384

    func scan(now: Date = Date()) -> [ClusterTaskReadout] {
        autoreleasepool {
            let capacity = min(16_384, max(256, Int(proc_listallpids(nil, 0)) + 64))
            var pids = [Int32](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes {
                proc_listallpids($0.baseAddress, Int32($0.count))
            }
            guard count > 0 else { return [] }
            var result: [ClusterTaskReadout] = []
            for pid in pids.prefix(min(Int(count), capacity)) where pid > 0 {
                guard isOpenFASTProcess(pid: pid) else { continue }
                guard let item = inspect(pid: pid, now: now) else { continue }
                result.append(item)
                if result.count >= Self.maximumProcesses { break }
            }
            return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private func isOpenFASTProcess(pid: Int32) -> Bool {
        var name = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &name, UInt32(name.count))
        guard length > 0 else { return false }
        let processName = String(cString: name).lowercased()
        return processName == "openfast" || processName.hasPrefix("openfast-")
            || processName.hasPrefix("openfast_")
    }

    private func inspect(pid: Int32, now: Date) -> ClusterTaskReadout? {
        var bsd = proc_bsdinfo()
        let length = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, length) == length else {
            return nil
        }
        let birth = Double(bsd.pbi_start_tvsec) +
            Double(bsd.pbi_start_tvusec) / 1_000_000
        guard birth > 0, now.timeIntervalSince1970 >= birth else { return nil }
        let elapsed = now.timeIntervalSince1970 - birth
        let args = Self.arguments(pid: pid)
        let fstArg = args.first {
            $0.lowercased().hasSuffix(".fst") && !$0.hasPrefix("-")
        }
        let inputURL = fstArg.flatMap { Self.resolveInput($0, pid: pid) }
        let title = inputURL?.deletingPathExtension().lastPathComponent
            ?? (fstArg.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent })
            ?? "OpenFAST"
        // A PID can be reused; include its process birth time in the task ID.
        let taskID = "openfast-\(pid)-\(Int(birth))"
        let maximum = inputURL.flatMap(Self.readTMax)
        let simulationTime = inputURL.flatMap {
            Self.readLatestSimulationTime(fst: $0, processBirth: birth, now: now)
        }
        let fraction = OpenFASTProgressParsing.fraction(
            current: simulationTime, maximum: maximum)
        let remaining = OpenFASTProgressParsing.remainingSeconds(
            current: simulationTime, maximum: maximum, elapsed: elapsed)
        return ClusterTaskReadout(
            id: taskID, title: title.isEmpty ? "OpenFAST" : title,
            state: "运行中", progress: fraction,
            currentSimTime: fraction == nil ? nil : simulationTime,
            targetSimTime: maximum, elapsedSeconds: elapsed,
            remainingSeconds: remaining)
    }

    private static func readTMax(_ input: URL) -> Double? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: input.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              size > 0, size <= maximumInputBytes,
              let raw = try? Data(contentsOf: input, options: [.mappedIfSafe]),
              let text = String(data: raw, encoding: .utf8) else { return nil }
        return OpenFASTProgressParsing.tMax(in: text)
    }

    private static func readLatestSimulationTime(
        fst: URL, processBirth: TimeInterval, now: Date
    ) -> Double? {
        let out = fst.deletingPathExtension().appendingPathExtension("out")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: out.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              size > 0,
              let modified = attrs[.modificationDate] as? Date,
              // Never display a stale output from a previous run.
              modified.timeIntervalSince1970 >= processBirth - 2,
              now.timeIntervalSince(modified) >= -5,
              now.timeIntervalSince(modified) < 120 else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: out) else { return nil }
        defer { try? handle.close() }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let bytes = try? handle.read(upToCount: tailBytes),
              let text = String(data: bytes, encoding: .utf8) else { return nil }
        return OpenFASTProgressParsing.latestTime(
            in: text, truncatedStart: offset > 0)
    }

    private static func resolveInput(_ input: String, pid: Int32) -> URL? {
        guard input.count <= 2048, !input.isEmpty else { return nil }
        let absolute: URL
        if input.hasPrefix("/") {
            absolute = URL(fileURLWithPath: input)
        } else if let cwd = workingDirectory(pid: pid) {
            absolute = URL(fileURLWithPath: cwd, isDirectory: true)
                .appendingPathComponent(input)
        } else {
            // Never resolve the other process's relative .fst against the
            // current ChipBar working directory: that can display wrong data.
            return nil
        }
        let result = absolute.standardizedFileURL
        guard result.isFileURL,
              FileManager.default.fileExists(atPath: result.path) else {
            return nil
        }
        return result
    }

    private static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let length = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, length) == length else {
            return nil
        }
        let chars = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            Array(bytes.prefix { $0 != 0 })
        }
        guard !chars.isEmpty else { return nil }
        return String(bytes: chars, encoding: .utf8)
    }

    /// KERN_PROCARGS2: argc, executable path, zero padding, then argv.
    /// Read only short, valid argument buffers; do not inspect environments.
    private static func arguments(pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var count: size_t = 0
        let sizeResult = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, u_int($0.count), nil, &count, nil, 0)
        }
        guard sizeResult == 0, count >= 8, count <= maximumArgumentsBytes
        else { return [] }
        var bytes = [UInt8](repeating: 0, count: Int(count))
        let rc = bytes.withUnsafeMutableBytes { buffer in
            mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, u_int($0.count), buffer.baseAddress,
                       &count, nil, 0)
            }
        }
        guard rc == 0, count >= 8 else { return [] }
        let length = min(Int(count), bytes.count)
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0, argc <= 128 else { return [] }
        var cursor = 4
        while cursor < length && bytes[cursor] != 0 { cursor += 1 }
        while cursor < length && bytes[cursor] == 0 { cursor += 1 }
        var items: [String] = []
        for _ in 0..<argc {
            guard cursor < length else { break }
            let start = cursor
            while cursor < length && bytes[cursor] != 0 { cursor += 1 }
            if let arg = String(bytes: bytes[start..<cursor], encoding: .utf8) {
                items.append(arg)
            }
            cursor += 1
        }
        return items
    }
}
