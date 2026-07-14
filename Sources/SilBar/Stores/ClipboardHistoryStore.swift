import AppKit
import Combine

struct ClipboardEntry: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        captureCurrentText()
        startMonitoring()
    }

    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        record(entry.text)
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureIfChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func captureIfChanged() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        captureCurrentText()
    }

    private func captureCurrentText() {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        record(text)
    }

    private func record(_ text: String) {
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text), at: 0)

        if entries.count > 20 {
            entries.removeLast(entries.count - 20)
        }
    }
}
