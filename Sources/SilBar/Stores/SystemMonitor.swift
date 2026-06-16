import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = MetricSnapshot()

    private let networkSampler = NetworkInterfaceSampler()
    private let statsProvider = SystemStatsProvider()
    private let temperatureSampler = CPUTemperatureSampler()
    private let processSampler = ProcessSampler()
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    init() {
        Task { @MainActor in
            start()
        }
    }

    func start() {
        guard timer == nil else {
            return
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() {
        guard refreshTask == nil else {
            return
        }

        let previousHistory = snapshot.networkHistory
        let networkSampler = networkSampler
        let statsProvider = statsProvider
        let temperatureSampler = temperatureSampler
        let processSampler = processSampler

        refreshTask = Task.detached(priority: .utility) {
            let networkSpeed = networkSampler.sampleSpeed()
            let cpuUsage = statsProvider.cpuUsage()
            let cpuTemperatureCelsius = temperatureSampler.sampleCelsius()
            let memoryPercent = statsProvider.memoryPercent()
            let storagePercent = statsProvider.storagePercent()
            let topMemoryApps = processSampler.topMemoryApps()
            let topNetworkApps = processSampler.topNetworkApps()
            let topCPUApps = processSampler.topCPUApps()
            let sample = NetworkSample(
                timestamp: .now,
                uploadBytesPerSecond: networkSpeed.upload,
                downloadBytesPerSecond: networkSpeed.download
            )

            await MainActor.run {
                var history = previousHistory
                history.append(sample)
                if history.count > 36 {
                    history.removeFirst(history.count - 36)
                }

                self.snapshot = MetricSnapshot(
                    cpuPercent: cpuUsage.overall,
                    cpuTemperatureCelsius: cpuTemperatureCelsius,
                    memoryPercent: memoryPercent,
                    storagePercent: storagePercent,
                    uploadBytesPerSecond: networkSpeed.upload,
                    downloadBytesPerSecond: networkSpeed.download,
                    networkHistory: history,
                    topNetworkApps: topNetworkApps,
                    topMemoryApps: topMemoryApps,
                    topCPUApps: topCPUApps,
                    coreUsages: cpuUsage.cores,
                    updatedAt: .now
                )
                self.refreshTask = nil
            }
        }
    }
}
