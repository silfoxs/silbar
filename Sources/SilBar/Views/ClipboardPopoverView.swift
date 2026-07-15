import SwiftUI

struct ClipboardPopoverView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let onCopy: (ClipboardEntry) -> Void
    @State private var showsCopyConfirmation = false
    @State private var confirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            history
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MenuBarWindowBackgroundCleaner())
        .overlay(alignment: .bottom) {
            if showsCopyConfirmation {
                Label("已复制", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsCopyConfirmation)
        .onDisappear {
            confirmationTask?.cancel()
        }
    }

    private var header: some View {
        Label("剪贴板历史", systemImage: "clipboard")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var history: some View {
        if store.entries.isEmpty {
            Text("复制文本后会显示在这里")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.horizontal, 14)
                .padding(.top, 24)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(store.entries) { entry in
                        Button {
                            onCopy(entry)
                            showCopyConfirmation()
                        } label: {
                            ClipboardHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .scrollClipDisabled(false)
            .clipped()
            .padding(.horizontal, 14)
            .id(store.presentationID)
        }
    }

    private func showCopyConfirmation() {
        confirmationTask?.cancel()
        showsCopyConfirmation = true
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else {
                return
            }
            showsCopyConfirmation = false
        }
    }
}

private struct ClipboardHistoryRow: View {
    let entry: ClipboardEntry
    @State private var isHovered = false

    var body: some View {
        Text(entry.text)
            .font(.system(size: 15))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(isHovered ? 0.08 : 0))
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
