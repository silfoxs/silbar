import Darwin
import Foundation

final class SystemStatsProvider: @unchecked Sendable {
    private var previousCPUInfo: [CPUInfo]?

    struct CPUUsage {
        let overall: Double
        let cores: [Double]
    }

    func cpuUsage() -> CPUUsage {
        let current = readCPUInfo()
        defer {
            previousCPUInfo = current
        }

        guard let previousCPUInfo, previousCPUInfo.count == current.count else {
            return CPUUsage(overall: 0, cores: [])
        }

        let usages = zip(previousCPUInfo, current).compactMap { previous, current -> Double? in
            let user = current.user >= previous.user ? current.user - previous.user : 0
            let system = current.system >= previous.system ? current.system - previous.system : 0
            let nice = current.nice >= previous.nice ? current.nice - previous.nice : 0
            let idle = current.idle >= previous.idle ? current.idle - previous.idle : 0
            let total = user + system + nice + idle

            guard total > 0 else {
                return nil
            }

            return Double(user + system + nice) / Double(total) * 100
        }

        let overall = usages.isEmpty ? 0 : usages.reduce(0, +) / Double(usages.count)
        return CPUUsage(overall: overall, cores: usages)
    }

    func memoryPercent() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        var hostPageSize = vm_size_t(0)
        host_page_size(mach_host_self(), &hostPageSize)
        let pageSize = UInt64(hostPageSize)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize

        let used = active + wired + compressed
        let total = used + inactive + speculative + free

        guard total > 0 else {
            return 0
        }

        return Double(used) / Double(total) * 100
    }

    func storagePercent() -> Double {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            guard
                let available = values.volumeAvailableCapacityForImportantUsage,
                let total = values.volumeTotalCapacity,
                total > 0
            else {
                return 0
            }

            return (Double(total) - Double(available)) / Double(total) * 100
        } catch {
            return 0
        }
    }

    private func readCPUInfo() -> [CPUInfo] {
        var cpuInfo: processor_info_array_t?
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return []
        }

        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), size)
        }

        let buffer = UnsafeBufferPointer(start: cpuInfo, count: Int(infoCount))
        var cpus: [CPUInfo] = []

        for index in 0..<Int(processorCount) {
            let offset = index * Int(CPU_STATE_MAX)
            guard offset + Int(CPU_STATE_IDLE) < buffer.count else {
                continue
            }

            cpus.append(
                CPUInfo(
                    user: UInt64(buffer[offset + Int(CPU_STATE_USER)]),
                    system: UInt64(buffer[offset + Int(CPU_STATE_SYSTEM)]),
                    idle: UInt64(buffer[offset + Int(CPU_STATE_IDLE)]),
                    nice: UInt64(buffer[offset + Int(CPU_STATE_NICE)])
                )
            )
        }

        return cpus
    }
}

private struct CPUInfo {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}
