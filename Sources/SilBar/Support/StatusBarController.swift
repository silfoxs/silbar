import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: SystemMonitor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingView: NSHostingView<StatusBarLabel>
    private var snapshotCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var statusVisibilityTimer: Timer?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hostingView = NSHostingView(rootView: StatusBarLabel(snapshot: monitor.snapshot))

        super.init()

        configureStatusButton()
        configurePopover()
        updateStatusLabel(with: monitor.snapshot)

        snapshotCancellable = monitor.$snapshot.sink { [weak self] snapshot in
            self?.updateStatusLabel(with: snapshot)
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.required, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 430, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(monitor: monitor)
                .frame(width: 430)
                .containerBackground(.clear, for: .window)
        )
    }

    private func updateStatusLabel(with snapshot: MetricSnapshot) {
        hostingView.rootView = StatusBarLabel(snapshot: snapshot)
        hostingView.layoutSubtreeIfNeeded()

        let fittingWidth = hostingView.fittingSize.width
        statusItem.length = max(28, fittingWidth + 8)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
            return
        }

        guard let button = statusItem.button else {
            return
        }

        showPopover(relativeTo: button)
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.isOpaque = false
        popover.contentViewController?.view.window?.backgroundColor = .clear
        startPopoverCloseObservers()
    }

    private func closePopover(_ sender: Any?) {
        guard popover.isShown else {
            stopPopoverCloseObservers()
            return
        }

        popover.performClose(sender)
        stopPopoverCloseObservers()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.stopPopoverCloseObservers()
        }
    }

    private func startPopoverCloseObservers() {
        stopPopoverCloseObservers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.closePopoverIfNeeded(for: event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(nil)
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(nil)
            }
        }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfStatusItemHidden()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusVisibilityTimer = timer
    }

    private func stopPopoverCloseObservers() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }

        statusVisibilityTimer?.invalidate()
        statusVisibilityTimer = nil
    }

    private func closePopoverIfNeeded(for event: NSEvent) {
        guard popover.isShown else {
            stopPopoverCloseObservers()
            return
        }

        if isEventInsideStatusButton(event) || isEventInsidePopover(event) {
            return
        }

        closePopover(nil)
    }

    private func isEventInsideStatusButton(_ event: NSEvent) -> Bool {
        guard
            let button = statusItem.button,
            event.window === button.window
        else {
            return false
        }

        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let window = popover.contentViewController?.view.window else {
            return false
        }

        return event.window === window
    }

    private func closePopoverIfStatusItemHidden() {
        guard popover.isShown else {
            stopPopoverCloseObservers()
            return
        }

        guard let window = statusItem.button?.window, window.isVisible else {
            closePopover(nil)
            return
        }
    }
}
