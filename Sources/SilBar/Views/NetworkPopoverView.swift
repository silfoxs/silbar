import SwiftUI

struct NetworkPopoverView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                Label("网络监控", systemImage: "arrow.up.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
            }
            .padding(14)
        }
        .background(MenuBarWindowBackgroundCleaner())
    }
}
