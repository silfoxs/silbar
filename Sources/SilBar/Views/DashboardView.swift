import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var page: DashboardPage = .metrics

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                panelToolbar

                switch page {
                case .metrics:
                    metricsPage
                case .settings:
                    SettingsView()
                }
            }
            .padding(14)
        }
        .animation(.snappy(duration: 0.18), value: page)
        .background(MenuBarWindowBackgroundCleaner())
    }

    private var panelToolbar: some View {
        HStack {
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PanelIconButtonStyle(tint: .red))
            .help("退出")

            Spacer()

            Button {
                page = page == .settings ? .metrics : .settings
            } label: {
                Image(systemName: page == .settings ? "chevron.left" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PanelIconButtonStyle(tint: .primary))
            .help(page == .settings ? "返回" : "设置")
        }
    }

    private var metricsPage: some View {
        VStack(spacing: 14) {
            metricStrip
            NetworkChartCard(snapshot: monitor.snapshot)
            ProcessListCard(
                title: "网络占用",
                systemImage: "arrow.up.arrow.down",
                rows: monitor.snapshot.topNetworkApps.map {
                    ProcessRow(
                        pid: $0.pid,
                        name: $0.name,
                        primary: ByteFormatter.speed($0.totalBytesPerSecond),
                        detailItems: [
                            ProcessRowDetail(
                                systemImage: "arrow.down",
                                text: ByteFormatter.speed($0.downloadBytesPerSecond)
                            ),
                            ProcessRowDetail(
                                systemImage: "arrow.up",
                                text: ByteFormatter.speed($0.uploadBytesPerSecond)
                            )
                        ]
                    )
                }
            )
            ProcessListCard(
                title: "内存占用",
                systemImage: "memorychip",
                rows: monitor.snapshot.topMemoryApps.map {
                    ProcessRow(
                        pid: $0.pid,
                        name: $0.name,
                        primary: ByteFormatter.size($0.memoryBytes)
                    )
                }
            )
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 10) {
            MetricCircle(
                title: "网速",
                value: ByteFormatter.speed(monitor.snapshot.downloadBytesPerSecond),
                percent: nil,
                tint: .cyan
            )
            if let temp = monitor.snapshot.cpuTemperatureCelsius {
                MetricCircle(
                    title: "温度",
                    value: "\(Int(temp))°",
                    percent: nil,
                    tint: .red
                )
            }
            MetricCircle(
                title: "CPU",
                value: "\(Int(monitor.snapshot.cpuPercent.rounded()))%",
                percent: monitor.snapshot.cpuPercent,
                tint: .orange
            )
            MetricCircle(
                title: "内存",
                value: "\(Int(monitor.snapshot.memoryPercent.rounded()))%",
                percent: monitor.snapshot.memoryPercent,
                tint: .green
            )
            MetricCircle(
                title: "存储",
                value: "\(Int(monitor.snapshot.storagePercent.rounded()))%",
                percent: monitor.snapshot.storagePercent,
                tint: .purple
            )
        }
    }
}

private enum DashboardPage {
    case metrics
    case settings
}

private struct SettingsView: View {
    @AppStorage(StatusBarPreferences.showNetworkTransfer) private var showNetworkTransfer = true
    @AppStorage(StatusBarPreferences.showCPUUsage) private var showCPUUsage = true
    @AppStorage(StatusBarPreferences.showCPUTemperature) private var showCPUTemperature = false
    @AppStorage(StatusBarPreferences.showMemoryUsage) private var showMemoryUsage = true
    @AppStorage(StatusBarPreferences.showStorageUsage) private var showStorageUsage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("状态栏", systemImage: "menubar.rectangle")
                .font(.headline)

            VStack(spacing: 8) {
                SettingsToggleRow(
                    title: "网络上传下载量",
                    systemImage: "arrow.up.arrow.down",
                    isOn: $showNetworkTransfer
                )
                SettingsToggleRow(
                    title: "CPU 占用",
                    systemImage: "cpu",
                    isOn: $showCPUUsage
                )
                SettingsToggleRow(
                    title: "CPU 温度",
                    systemImage: "thermometer.medium",
                    isOn: $showCPUTemperature
                )
                SettingsToggleRow(
                    title: "内存占用",
                    systemImage: "memorychip",
                    isOn: $showMemoryUsage
                )
                SettingsToggleRow(
                    title: "硬盘占用",
                    systemImage: "internaldrive",
                    isOn: $showStorageUsage
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

private struct PanelIconButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .glassEffect(.regular.interactive(), in: Circle())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct MetricCircle: View {
    let title: String
    let value: String
    let percent: Double?
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.12), lineWidth: 8)

            if let percent {
                Circle()
                    .trim(from: 0, to: min(max(percent / 100, 0), 1))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [7, 9]))
            }

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(width: 86, height: 86)
        .frame(maxWidth: .infinity)
    }
}
