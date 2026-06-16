import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: SystemMonitor
    private let mainStatusItem: NSStatusItem
    private let popover = NSPopover()
    private let networkPopover = NSPopover()
    private let mainHostingView: NSHostingView<MainStatusIcon>
    private var metricItems: [StatusBarMetricKind: MetricStatusItem] = [:]
    private var visibleMetricKinds: [StatusBarMetricKind] = []
    private var snapshotCancellable: AnyCancellable?
    private var preferencesCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var statusVisibilityTimer: Timer?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        mainStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mainHostingView = NSHostingView(rootView: MainStatusIcon())

        super.init()

        configureMainStatusButton()
        rebuildMetricStatusItems()
        configurePopover()
        configureNetworkPopover()
        updateStatusItems(with: monitor.snapshot)

        snapshotCancellable = monitor.$snapshot.sink { [weak self] snapshot in
            self?.updateStatusItems(with: snapshot)
        }

        preferencesCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                updateStatusItems(with: monitor.snapshot)
            }
    }

    private func configureMainStatusButton() {
        guard let button = mainStatusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        mainHostingView.translatesAutoresizingMaskIntoConstraints = false
        mainHostingView.setContentHuggingPriority(.required, for: .horizontal)
        mainHostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addSubview(mainHostingView)

        NSLayoutConstraint.activate([
            mainHostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            mainHostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            mainHostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        mainHostingView.layoutSubtreeIfNeeded()
        mainStatusItem.length = max(28, mainHostingView.fittingSize.width + 8)
    }

    private func rebuildMetricStatusItems() {
        for metricItem in metricItems.values {
            NSStatusBar.system.removeStatusItem(metricItem.item)
        }

        metricItems.removeAll()
        visibleMetricKinds = currentVisibleMetricKinds()

        for kind in visibleMetricKinds.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let hostingView = NSHostingView(rootView: StatusBarMetricContent(kind: kind, snapshot: monitor.snapshot))
            guard let button = item.button else {
                continue
            }

            button.title = ""
            button.image = nil

            if kind == .network {
                button.target = self
                button.action = #selector(toggleNetworkPopover(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }

            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.setContentHuggingPriority(.required, for: .horizontal)
            hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])

            metricItems[kind] = MetricStatusItem(item: item, hostingView: hostingView)
        }
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

    private func configureNetworkPopover() {
        networkPopover.behavior = .transient
        networkPopover.delegate = self
        networkPopover.contentSize = NSSize(width: 430, height: 620)
        networkPopover.contentViewController = NSHostingController(
            rootView: NetworkPopoverView(monitor: monitor)
                .frame(width: 430)
                .containerBackground(.clear, for: .window)
        )
    }

    private func updateStatusItems(with snapshot: MetricSnapshot) {
        let currentKinds = currentVisibleMetricKinds()
        if currentKinds != visibleMetricKinds {
            rebuildMetricStatusItems()
        }

        for kind in visibleMetricKinds {
            guard let metricItem = metricItems[kind] else {
                continue
            }

            metricItem.hostingView.rootView = StatusBarMetricContent(kind: kind, snapshot: snapshot)
            metricItem.hostingView.layoutSubtreeIfNeeded()

            let fittingWidth = metricItem.hostingView.fittingSize.width
            metricItem.item.length = max(kind.minimumWidth, fittingWidth + 8)
        }
    }

    private func currentVisibleMetricKinds() -> [StatusBarMetricKind] {
        StatusBarPreferences.orderedMetricKinds().filter(\.isEnabled)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
            return
        }

        guard let button = mainStatusItem.button else {
            return
        }

        showPopover(relativeTo: button)
    }

    @objc private func toggleNetworkPopover(_ sender: Any?) {
        if networkPopover.isShown {
            closeNetworkPopover(sender)
            return
        }

        guard let networkItem = metricItems[.network]?.item.button else {
            return
        }

        showNetworkPopover(relativeTo: networkItem)
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

    private func showNetworkPopover(relativeTo button: NSStatusBarButton) {
        networkPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        networkPopover.contentViewController?.view.window?.isOpaque = false
        networkPopover.contentViewController?.view.window?.backgroundColor = .clear
        startNetworkPopoverCloseObservers()
    }

    private func closeNetworkPopover(_ sender: Any?) {
        guard networkPopover.isShown else {
            stopNetworkPopoverCloseObservers()
            return
        }

        networkPopover.performClose(sender)
        stopNetworkPopoverCloseObservers()
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

    private func startNetworkPopoverCloseObservers() {
        stopNetworkPopoverCloseObservers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.closeNetworkPopoverIfNeeded(for: event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeNetworkPopover(nil)
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeNetworkPopover(nil)
            }
        }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.closeNetworkPopoverIfStatusItemHidden()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusVisibilityTimer = timer
    }

    private func stopNetworkPopoverCloseObservers() {
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
            let button = mainStatusItem.button,
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

        guard let window = mainStatusItem.button?.window, window.isVisible else {
            closePopover(nil)
            return
        }
    }

    private func closeNetworkPopoverIfNeeded(for event: NSEvent) {
        guard networkPopover.isShown else {
            stopNetworkPopoverCloseObservers()
            return
        }

        if isEventInsideNetworkStatusButton(event) || isEventInsideNetworkPopover(event) {
            return
        }

        closeNetworkPopover(nil)
    }

    private func isEventInsideNetworkStatusButton(_ event: NSEvent) -> Bool {
        guard
            let button = metricItems[.network]?.item.button,
            event.window === button.window
        else {
            return false
        }

        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func isEventInsideNetworkPopover(_ event: NSEvent) -> Bool {
        guard let window = networkPopover.contentViewController?.view.window else {
            return false
        }

        return event.window === window
    }

    private func closeNetworkPopoverIfStatusItemHidden() {
        guard networkPopover.isShown else {
            stopNetworkPopoverCloseObservers()
            return
        }

        guard let window = metricItems[.network]?.item.button?.window, window.isVisible else {
            closeNetworkPopover(nil)
            return
        }
    }
}

private struct MetricStatusItem {
    let item: NSStatusItem
    let hostingView: NSHostingView<StatusBarMetricContent>
}

private struct MainStatusIcon: View {
    var body: some View {
        Image(systemName: "circle.hexagongrid.circle")
            .font(.system(size: 13, weight: .semibold))
    }
}
