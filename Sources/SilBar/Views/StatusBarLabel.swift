import SwiftUI

enum StatusBarMetricKind: CaseIterable {
    case network
    case cpu
    case temp
    case memory
    case storage

    var preferenceKey: String {
        switch self {
        case .network:
            StatusBarPreferences.showNetworkTransfer
        case .cpu:
            StatusBarPreferences.showCPUUsage
        case .temp:
            StatusBarPreferences.showCPUTemperature
        case .memory:
            StatusBarPreferences.showMemoryUsage
        case .storage:
            StatusBarPreferences.showStorageUsage
        }
    }

    var defaultValue: Bool {
        switch self {
        case .network, .cpu, .memory, .storage:
            true
        case .temp:
            false
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .network:
            54
        case .cpu, .temp, .memory, .storage:
            30
        }
    }

    var isEnabled: Bool {
        guard let value = UserDefaults.standard.object(forKey: preferenceKey) as? Bool else {
            return defaultValue
        }
        return value
    }
}

struct StatusBarMetricContent: View {
    let kind: StatusBarMetricKind
    let snapshot: MetricSnapshot

    var body: some View {
        Group {
            switch kind {
            case .network:
                NetworkTransferLabel(
                    upload: ByteFormatter.speed(snapshot.uploadBytesPerSecond),
                    download: ByteFormatter.speed(snapshot.downloadBytesPerSecond)
                )
            case .cpu:
                StatusBarMetric(label: "CPU", value: percent(snapshot.cpuPercent))
            case .temp:
                StatusBarMetric(label: "TEMP", value: temperature(snapshot.cpuTemperatureCelsius))
            case .memory:
                StatusBarMetric(label: "MEM", value: percent(snapshot.memoryPercent))
            case .storage:
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
