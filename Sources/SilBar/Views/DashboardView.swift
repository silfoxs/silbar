import AppKit
import SwiftUI

struct DashboardView: View {
    let monitor: SystemMonitor
    @State private var page: DashboardPage = .metrics

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                panelToolbar
                pageContent
            }
            .padding(14)
        }
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
                withAnimation(Self.pageAnimation) {
                    page = page == .settings ? .metrics : .settings
                }
            } label: {
                Image(systemName: page == .settings ? "chevron.left" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PanelIconButtonStyle(tint: .primary))
            .help(page == .settings ? "返回" : "设置")
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .metrics:
            MetricsPage(monitor: monitor)
                .transition(Self.pageTransition)
        case .settings:
            SettingsView()
                .transition(Self.pageTransition)
        }
    }

    private static let pageAnimation = Animation.easeOut(duration: 0.14)
    private static let pageTransition = AnyTransition.opacity.combined(
        with: .offset(x: 0, y: 6)
    )
}

private enum DashboardPage {
    case metrics
    case settings
}

private struct MetricsPage: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 14) {
            metricStrip
            NetworkChartCard(snapshot: monitor.snapshot)
            ProcessListCard(
                title: "网络占用",
                systemImage: "arrow.up.arrow.down",
                rows: monitor.snapshot.topNetworkApps.prefix(5).map {
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
                rows: monitor.snapshot.topMemoryApps.prefix(5).map {
                    ProcessRow(
                        pid: $0.pid,
                        name: $0.name,
                        primary: ByteFormatter.size($0.memoryBytes)
                    )
                }
            )
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 8) {
            MetricCircle(
                title: "网速",
                value: ByteFormatter.speed(monitor.snapshot.downloadBytesPerSecond),
                percent: nil,
                tint: .cyan
            )
            if let temp = monitor.snapshot.cpuTemperatureCelsius {
                MetricCircle(
                    title: "TEMP",
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

private struct SettingsView: View {
    @AppStorage(StatusBarPreferences.showNetworkTransfer) private var showNetworkTransfer = true
    @AppStorage(StatusBarPreferences.showCPUUsage) private var showCPUUsage = true
    @AppStorage(StatusBarPreferences.showCPUTemperature) private var showCPUTemperature = false
    @AppStorage(StatusBarPreferences.showMemoryUsage) private var showMemoryUsage = true
    @AppStorage(StatusBarPreferences.showStorageUsage) private var showStorageUsage = true
    @State private var metricOrder = StatusBarPreferences.orderedMetricKinds()
    @State private var draggedKind: StatusBarMetricKind?
    @State private var dragStartIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("状态栏", systemImage: "menubar.rectangle")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(metricOrder) { kind in
                    SettingsMetricRow(
                        kind: kind,
                        isOn: binding(for: kind)
                    )
                    .contentShape(Rectangle())
                    .opacity(draggedKind == kind ? 0.76 : 1)
                    .offset(y: offset(for: kind))
                    .zIndex(draggedKind == kind ? 1 : 0)
                    .animation(.snappy(duration: 0.16), value: dragTargetIndex)
                    .simultaneousGesture(reorderGesture(for: kind))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func binding(for kind: StatusBarMetricKind) -> Binding<Bool> {
        switch kind {
        case .network:
            $showNetworkTransfer
        case .cpu:
            $showCPUUsage
        case .temp:
            $showCPUTemperature
        case .memory:
            $showMemoryUsage
        case .storage:
            $showStorageUsage
        }
    }

    private func reorderGesture(for kind: StatusBarMetricKind) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if draggedKind == nil {
                    draggedKind = kind
                    dragStartIndex = metricOrder.firstIndex(of: kind)
                    dragTargetIndex = dragStartIndex
                }

                guard
                    draggedKind == kind,
                    let startIndex = dragStartIndex
                else {
                    return
                }

                let targetIndex = targetIndex(startIndex: startIndex, translation: value.translation.height)
                dragTranslation = value.translation.height
                if dragTargetIndex != targetIndex {
                    dragTargetIndex = targetIndex
                }
            }
            .onEnded { value in
                defer {
                    draggedKind = nil
                    dragStartIndex = nil
                    dragTargetIndex = nil
                    dragTranslation = 0
                }

                guard
                    draggedKind == kind,
                    let startIndex = dragStartIndex,
                    let currentIndex = metricOrder.firstIndex(of: kind)
                else {
                    return
                }

                let targetIndex = targetIndex(startIndex: startIndex, translation: value.translation.height)

                if targetIndex != currentIndex {
                    metricOrder.move(
                        fromOffsets: IndexSet(integer: currentIndex),
                        toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                    )
                }
                StatusBarPreferences.setMetricOrder(metricOrder)
            }
    }

    private func offset(for kind: StatusBarMetricKind) -> CGFloat {
        guard
            let draggedKind,
            let startIndex = dragStartIndex,
            let targetIndex = dragTargetIndex,
            let index = metricOrder.firstIndex(of: kind)
        else {
            return 0
        }

        if kind == draggedKind {
            return dragTranslation
        }

        if targetIndex > startIndex, index > startIndex, index <= targetIndex {
            return -Self.rowStride
        }

        if targetIndex < startIndex, index >= targetIndex, index < startIndex {
            return Self.rowStride
        }

        return 0
    }

    private func targetIndex(startIndex: Int, translation: CGFloat) -> Int {
        let offset = Int((translation / Self.rowStride).rounded())
        return min(max(startIndex + offset, 0), metricOrder.count - 1)
    }

    private static let rowStride: CGFloat = 46

}

private struct SettingsMetricRow: View {
    let kind: StatusBarMetricKind
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label(kind.title, systemImage: kind.systemImage)
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
                .stroke(.primary.opacity(0.12), lineWidth: 6)

            if let percent {
                Circle()
                    .trim(from: 0, to: min(max(percent / 100, 0), 1))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [7, 9]))
            }

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .frame(width: 72, height: 72)
        .frame(maxWidth: .infinity)
    }
}
