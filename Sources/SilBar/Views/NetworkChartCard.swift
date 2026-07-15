import SwiftUI

struct NetworkChartCard: View {
    let snapshot: MetricSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("上传 / 下载", systemImage: "chart.bar.xaxis")
                .font(.headline)

            BarChart(samples: snapshot.networkHistory)
                .frame(height: 92)
                .padding(10)
                .lightBackground(cornerRadius: 16)

            HStack {
                SpeedBadge(label: "下载", value: ByteFormatter.speed(snapshot.downloadBytesPerSecond), color: .cyan)
                SpeedBadge(label: "上传", value: ByteFormatter.speed(snapshot.uploadBytesPerSecond), color: .orange)
            }
        }
        .padding(12)
        .lightBackground()
    }
}

private struct BarChart: View {
    let samples: [NetworkSample]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(samples.map { max($0.uploadBytesPerSecond, $0.downloadBytesPerSecond) }.max() ?? 1, 1)
            let barGroupWidth = CGFloat(7)

            HStack(alignment: .center, spacing: 3) {
                ForEach(samples) { sample in
                    let halfHeight = proxy.size.height / 2

                    VStack(spacing: 0) {
                        Capsule()
                            .fill(.orange.gradient)
                            .frame(height: barHeight(sample.uploadBytesPerSecond, maxValue: maxValue, availableHeight: halfHeight))
                            .frame(maxHeight: halfHeight, alignment: .bottom)

                        Capsule()
                            .fill(.cyan.gradient)
                            .frame(height: barHeight(sample.downloadBytesPerSecond, maxValue: maxValue, availableHeight: halfHeight))
                            .frame(maxHeight: halfHeight, alignment: .top)
                    }
                    .frame(width: barGroupWidth, height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(height: 1)
            }
        }
        .animation(nil, value: samples.map(\.id))
        .accessibilityLabel("上传下载柱状图")
    }

    private func barHeight(_ value: UInt64, maxValue: UInt64, availableHeight: CGFloat) -> CGFloat {
        guard value > 0 else {
            return 3
        }

        let maxBarHeight = max(availableHeight - 2, 1)
        let ratio = Double(value) / Double(maxValue)
        return min(maxBarHeight, max(3, maxBarHeight * CGFloat(ratio) * 0.92))
    }
}

private struct SpeedBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .lightCapsuleBackground()
    }
}
