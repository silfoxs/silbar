import Darwin
import Foundation

struct NetworkCounters {
    let uploadBytes: UInt64
    let downloadBytes: UInt64
    let timestamp: Date
}

final class NetworkInterfaceSampler: @unchecked Sendable {
    private var previous: NetworkCounters?

    func sampleSpeed() -> (upload: UInt64, download: UInt64) {
        let current = readCounters()
        defer {
            previous = current
        }

        guard let previous else {
            return (0, 0)
        }

        let interval = max(current.timestamp.timeIntervalSince(previous.timestamp), 0.1)
        let uploadDelta = current.uploadBytes >= previous.uploadBytes ? current.uploadBytes - previous.uploadBytes : 0
        let downloadDelta = current.downloadBytes >= previous.downloadBytes ? current.downloadBytes - previous.downloadBytes : 0

        return (
            UInt64(Double(uploadDelta) / interval),
            UInt64(Double(downloadDelta) / interval)
        )
    }

    private func readCounters() -> NetworkCounters {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        var upload: UInt64 = 0
        var download: UInt64 = 0

        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return NetworkCounters(uploadBytes: 0, downloadBytes: 0, timestamp: .now)
        }

        defer {
            freeifaddrs(firstAddress)
        }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            let isPointToPoint = (flags & IFF_POINTOPOINT) == IFF_POINTOPOINT
            let isLinkAddress = interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)

            // TUN/VPN interfaces see the same traffic before it is sent through
            // the physical interface. Counting both makes proxied traffic appear twice.
            guard isUp,
                  isRunning,
                  !isLoopback,
                  !isPointToPoint,
                  isLinkAddress,
                  let data = interface.ifa_data else {
                continue
            }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            upload += UInt64(stats.ifi_obytes)
            download += UInt64(stats.ifi_ibytes)
        }

        return NetworkCounters(uploadBytes: upload, downloadBytes: download, timestamp: .now)
    }
}
