import Foundation

struct MetricSnapshot {
    var cpuPercent: Double = 0
    var cpuTemperatureCelsius: Double?
    var memoryPercent: Double = 0
    var storagePercent: Double = 0
    var uploadBytesPerSecond: UInt64 = 0
    var downloadBytesPerSecond: UInt64 = 0
    var networkHistory: [NetworkSample] = []
    var topNetworkApps: [ProcessNetworkUsage] = []
    var topMemoryApps: [ProcessMemoryUsage] = []
    var topCPUApps: [ProcessCPUUsage] = []
    var coreUsages: [Double] = []
    var updatedAt: Date = .now
}

struct NetworkSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let uploadBytesPerSecond: UInt64
    let downloadBytesPerSecond: UInt64
}

struct ProcessNetworkUsage: Identifiable {
    let id = UUID()
    let pid: Int32?
    let name: String
    let uploadBytesPerSecond: UInt64
    let downloadBytesPerSecond: UInt64

    var totalBytesPerSecond: UInt64 {
        uploadBytesPerSecond + downloadBytesPerSecond
    }
}

struct ProcessMemoryUsage: Identifiable {
    let id = UUID()
    let pid: Int32?
    let name: String
    let memoryBytes: UInt64
}

struct ProcessCPUUsage: Identifiable {
    let id = UUID()
    let pid: Int32?
    let name: String
    let cpuPercent: Double
}
