import Darwin
import Foundation

final class ProcessSampler: @unchecked Sendable {
    private var previousNetworkCounters: [String: NetworkProcessCounter] = [:]

    func topNetworkApps(limit: Int = 5) -> [ProcessNetworkUsage] {
        let output = run("/usr/bin/nettop", arguments: ["-P", "-L", "1", "-x", "-n"])
        let now = Date()
        let counters = Dictionary(
            grouping: output
                .split(whereSeparator: \.isNewline)
                .compactMap(parseNettopLine),
            by: \.name
        )
        .mapValues { rows in
            rows.reduce(NetworkProcessCounter(pid: rows[0].pid, name: rows[0].name, downloadBytes: 0, uploadBytes: 0, timestamp: now)) { partial, row in
                NetworkProcessCounter(
                    pid: partial.pid ?? row.pid,
                    name: partial.name,
                    downloadBytes: partial.downloadBytes + row.downloadBytes,
                    uploadBytes: partial.uploadBytes + row.uploadBytes,
                    timestamp: now
                )
            }
        }

        defer {
            previousNetworkCounters = counters
        }

        let rows = counters.compactMap { name, current -> ProcessNetworkUsage? in
            guard let previous = previousNetworkCounters[name] else {
                return nil
            }

            let interval = max(current.timestamp.timeIntervalSince(previous.timestamp), 0.1)
            let downloadDelta = current.downloadBytes >= previous.downloadBytes ? current.downloadBytes - previous.downloadBytes : 0
            let uploadDelta = current.uploadBytes >= previous.uploadBytes ? current.uploadBytes - previous.uploadBytes : 0
            let usage = ProcessNetworkUsage(
                pid: current.pid,
                name: displayName(from: name),
                uploadBytesPerSecond: UInt64(Double(uploadDelta) / interval),
                downloadBytesPerSecond: UInt64(Double(downloadDelta) / interval)
            )

            return usage.totalBytesPerSecond > 0 ? usage : nil
        }
        .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }

        return Array(rows.prefix(limit))
    }

    func topMemoryApps(limit: Int = 5) -> [ProcessMemoryUsage] {
        let nativeRows = topMemoryAppsFromLibproc(limit: limit)
        if !nativeRows.isEmpty {
            return nativeRows
        }

        return topMemoryAppsFromPS(limit: limit)
    }

    private func topMemoryAppsFromLibproc(limit: Int) -> [ProcessMemoryUsage] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else {
            return []
        }

        let pidCapacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: pidCapacity)
        let usedBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        let usedCount = min(pids.count, max(0, Int(usedBytes) / MemoryLayout<pid_t>.stride))

        let rows = pids.prefix(usedCount).compactMap { pid -> ProcessMemoryUsage? in
            guard pid > 0 else {
                return nil
            }

            var taskInfo = proc_taskinfo()
            let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<proc_taskinfo>.size) { reboundPointer in
                    proc_pidinfo(
                        pid,
                        Int32(PROC_PIDTASKINFO),
                        0,
                        reboundPointer,
                        Int32(MemoryLayout<proc_taskinfo>.size)
                    )
                }
            }

            guard result == Int32(MemoryLayout<proc_taskinfo>.size), taskInfo.pti_resident_size > 0 else {
                return nil
            }

            return ProcessMemoryUsage(
                pid: pid,
                name: displayName(from: processName(pid: pid)),
                memoryBytes: UInt64(taskInfo.pti_resident_size)
            )
        }
        .sorted { $0.memoryBytes > $1.memoryBytes }

        return Array(rows.prefix(limit))
    }

    private func topMemoryAppsFromPS(limit: Int) -> [ProcessMemoryUsage] {
        let output = run("/bin/ps", arguments: ["-axo", "rss=,command="])
        let rows = output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseMemoryLine)
            .sorted { $0.memoryBytes > $1.memoryBytes }

        return Array(rows.prefix(limit))
    }

    private func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_name(pid, pointer.baseAddress, UInt32(pointer.count))
        }

        guard length > 0 else {
            return "\(pid)"
        }

        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func parseNettopLine(_ line: Substring) -> NetworkProcessCounter? {
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard
            columns.count >= 6,
            columns[0] != "time",
            !columns[1].isEmpty,
            let download = UInt64(columns[4]),
            let upload = UInt64(columns[5])
        else {
            return nil
        }

        return NetworkProcessCounter(
            pid: processIdentifier(from: columns[1]),
            name: columns[1],
            downloadBytes: download,
            uploadBytes: upload,
            timestamp: .now
        )
    }

    private func parseMemoryLine(_ line: Substring) -> ProcessMemoryUsage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }

        let rssText = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let command = String(trimmed[separator...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rssKB = UInt64(rssText), !command.isEmpty else {
            return nil
        }

        return ProcessMemoryUsage(
            pid: nil,
            name: displayName(from: command),
            memoryBytes: rssKB * 1024
        )
    }

    private func displayName(from rawValue: String) -> String {
        let command = rawValue.removingProcessIdentifier
        let url = URL(fileURLWithPath: command)
        let name = url.lastPathComponent.isEmpty ? command : url.lastPathComponent

        return name.count > 28 ? String(name.prefix(25)) + "..." : name
    }

    private func run(_ launchPath: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

private struct NetworkProcessCounter {
    let pid: Int32?
    let name: String
    let downloadBytes: UInt64
    let uploadBytes: UInt64
    let timestamp: Date
}

private func processIdentifier(from rawValue: String) -> Int32? {
    guard let dot = rawValue.lastIndex(of: ".") else {
        return nil
    }

    let suffix = rawValue[rawValue.index(after: dot)...]
    return suffix.allSatisfy(\.isNumber) ? Int32(suffix) : nil
}

private extension String {
    var removingProcessIdentifier: String {
        guard let dot = lastIndex(of: ".") else {
            return self
        }

        let suffix = self[index(after: dot)...]
        return suffix.allSatisfy(\.isNumber) ? String(self[..<dot]) : self
    }
}
