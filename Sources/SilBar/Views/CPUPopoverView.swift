import SwiftUI

struct CPUPopoverView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                headerSection
                coreUsageSection
                topCPUAppsSection
            }
            .padding(14)
        }
        .background(MenuBarWindowBackgroundCleaner())
    }

    private var headerSection: some View {
        HStack {
            Label("CPU 监控", systemImage: "cpu")
                .font(.headline)
            Spacer()
            if let temp = monitor.snapshot.cpuTemperatureCelsius {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(.red)
                    Text("\(Int(temp))°C")
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .lightBackground(cornerRadius: 8)
            }
        }
    }

    private var coreUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("核心占用", systemImage: "cpu")
                .font(.headline)

            let cores = monitor.snapshot.coreUsages
            if cores.isEmpty {
                Text("采样中...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(cores.count, 4))
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(cores.indices, id: \.self) { index in
                        CoreUsageCell(index: index, usage: cores[index])
                    }
                }
            }
        }
        .padding(12)
        .lightBackground()
    }

    private var topCPUAppsSection: some View {
        ProcessListCard(
            title: "CPU 占用",
            systemImage: "cpu",
            rows: monitor.snapshot.topCPUApps.map {
                ProcessRow(
                    pid: $0.pid,
                    name: $0.name,
                    primary: String(format: "%.1f%%", $0.cpuPercent)
                )
            }
        )
    }
}

private struct CoreUsageCell: View {
    let index: Int
    let usage: Double

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.12), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: min(max(usage / 100, 0), 1))
                    .stroke(usageColor.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text("\(Int(usage.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Text("Core \(index)")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 44, height: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .lightBackground(cornerRadius: 10)
    }

    private var usageColor: Color {
        if usage > 80 {
            return .red
        } else if usage > 50 {
            return .orange
        } else {
            return .green
        }
    }
}
