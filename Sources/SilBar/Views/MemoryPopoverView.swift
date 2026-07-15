import SwiftUI

struct MemoryPopoverView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                headerSection
                topMemoryAppsSection
            }
            .padding(14)
        }
        .background(MenuBarWindowBackgroundCleaner())
    }

    private var headerSection: some View {
        HStack {
            Label("内存监控", systemImage: "memorychip")
                .font(.headline)
            Spacer()
            Text("\(Int(monitor.snapshot.memoryPercent.rounded()))%")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .lightBackground(cornerRadius: 8)
        }
    }

    private var topMemoryAppsSection: some View {
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
