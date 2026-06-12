import SwiftUI

struct StatusBarLabel: View {
    let snapshot: MetricSnapshot

    @AppStorage(StatusBarPreferences.showNetworkTransfer) private var showNetworkTransfer = true
    @AppStorage(StatusBarPreferences.showCPUUsage) private var showCPUUsage = true
    @AppStorage(StatusBarPreferences.showCPUTemperature) private var showCPUTemperature = false
    @AppStorage(StatusBarPreferences.showMemoryUsage) private var showMemoryUsage = true
    @AppStorage(StatusBarPreferences.showStorageUsage) private var showStorageUsage = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 13, weight: .semibold))

            if showNetworkTransfer {
                NetworkTransferLabel(
                    upload: ByteFormatter.speed(snapshot.uploadBytesPerSecond),
                    download: ByteFormatter.speed(snapshot.downloadBytesPerSecond)
                )
            }

            if showCPUUsage {
                StatusBarMetric(label: "CPU", value: percent(snapshot.cpuPercent))
            }

            if showCPUTemperature {
                StatusBarMetric(label: "TEMP", value: temperature(snapshot.cpuTemperatureCelsius))
            }

            if showMemoryUsage {
                StatusBarMetric(label: "MEM", value: percent(snapshot.memoryPercent))
            }

            if showStorageUsage {
                StatusBarMetric(label: "SSD", value: percent(snapshot.storagePercent))
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func temperature(_ value: Double?) -> String {
        guard let value else {
            return "--°"
        }

        return "\(Int(value.rounded()))°"
    }
}

private struct NetworkTransferLabel: View {
    let upload: String
    let download: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TransferLine(systemImage: "arrow.up", value: upload)
            TransferLine(systemImage: "arrow.down", value: download)
        }
        .frame(height: 20, alignment: .center)
        .font(.system(size: 8.5, weight: .medium))
        .lineLimit(1)
    }
}

private struct TransferLine: View {
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .bold))
            Text(value)
                .monospacedDigit()
        }
        .frame(height: 10, alignment: .leading)
    }
}

private struct StatusBarMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
        }
        .frame(height: 20, alignment: .center)
        .lineLimit(1)
    }
}
