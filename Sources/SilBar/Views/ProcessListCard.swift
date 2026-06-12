import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProcessRow: Identifiable {
    let id = UUID()
    let pid: Int32?
    let name: String
    let primary: String
    var detailItems: [ProcessRowDetail] = []
}

struct ProcessRowDetail: Identifiable {
    let id = UUID()
    let systemImage: String
    let text: String
}

struct ProcessListCard: View {
    let title: String
    let systemImage: String
    let rows: [ProcessRow]
    var emptyText = "暂无采样数据"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            if rows.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            ProcessIcon(pid: row.pid, name: row.name)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)

                                if !row.detailItems.isEmpty {
                                    HStack(spacing: 8) {
                                        ForEach(row.detailItems) { item in
                                            Label(item.text, systemImage: item.systemImage)
                                                .labelStyle(.iconOnlyText)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                }
                            }

                            Spacer(minLength: 8)

                            Text(row.primary)
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, row.detailItems.isEmpty ? 6 : 7)
                        .frame(minHeight: row.detailItems.isEmpty ? 36 : 48)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

private struct ProcessIcon: View {
    let pid: Int32?
    let name: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var icon: NSImage {
        if let pid, let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }

        if let app = NSWorkspace.shared.runningApplications.first(where: { app in
            let candidates = [
                app.localizedName,
                app.bundleURL?.deletingPathExtension().lastPathComponent,
                app.executableURL?.deletingPathExtension().lastPathComponent,
                app.executableURL?.lastPathComponent
            ].compactMap { $0?.lowercased() }
            let normalizedName = name.lowercased()
            return candidates.contains(normalizedName) || candidates.contains { normalizedName.contains($0) || $0.contains(normalizedName) }
        }), let icon = app.icon {
            return icon
        }

        return NSWorkspace.shared.icon(for: .application)
    }
}

private struct IconOnlyTextLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

private extension LabelStyle where Self == IconOnlyTextLabelStyle {
    static var iconOnlyText: IconOnlyTextLabelStyle {
        IconOnlyTextLabelStyle()
    }
}
