import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: SystemMonitor
    private let clipboardHistory: ClipboardHistoryStore
    private let clipboardStatusItem: NSStatusItem
    private let mainStatusItem: NSStatusItem
    private let popover = NSPopover()
    private let networkPopover = NSPopover()
    private let cpuPopover = NSPopover()
    private let tempPopover = NSPopover()
    private let memoryPopover = NSPopover()
    private let clipboardPopover = NSPopover()
    private let clipboardHostingView: NSHostingView<ClipboardStatusIcon>
    private let mainHostingView: NSHostingView<MainStatusIcon>
    private var metricItems: [StatusBarMetricKind: MetricStatusItem] = [:]
    private var visibleMetricKinds: [StatusBarMetricKind] = []
    private var snapshotCancellable: AnyCancellable?
    private var preferencesCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var statusVisibilityTimer: Timer?
    private var activePopoverID: ObjectIdentifier?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        clipboardHistory = ClipboardHistoryStore()
        clipboardStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        mainStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        clipboardHostingView = NSHostingView(rootView: ClipboardStatusIcon())
        mainHostingView = NSHostingView(rootView: MainStatusIcon())

        super.init()

        configureClipboardStatusButton()
        mainStatusItem.autosaveName = "SilBar.main"
        mainStatusItem.isVisible = true
        configureMainStatusButton()
        rebuildMetricStatusItems()
        configurePopover()
        configureNetworkPopover()
        configureCPUPopover(cpuPopover)
        configureCPUPopover(tempPopover)
        configureMemoryPopover()
        configureClipboardPopover()
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

    private func configureClipboardStatusButton() {
        clipboardStatusItem.autosaveName = "SilBar.clipboard"
        clipboardStatusItem.isVisible = StatusBarPreferences.isClipboardHistoryEnabled()

        guard let button = clipboardStatusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(toggleClipboardPopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        clipboardHostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(clipboardHostingView)

        NSLayoutConstraint.activate([
            clipboardHostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            clipboardHostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    private func rebuildMetricStatusItems() {
        for metricItem in metricItems.values {
            NSStatusBar.system.removeStatusItem(metricItem.item)
        }

        metricItems.removeAll()
        visibleMetricKinds = currentVisibleMetricKinds()

        for kind in visibleMetricKinds.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "SilBar.metric.\(kind.rawValue)"
            item.isVisible = true

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
            } else if kind == .cpu || kind == .temp {
                button.target = self
                button.action = #selector(toggleCPUPopover(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            } else if kind == .memory {
                button.target = self
                button.action = #selector(toggleMemoryPopover(_:))
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

    private func configureCPUPopover(_ popover: NSPopover) {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 430, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: CPUPopoverView(monitor: monitor)
                .frame(width: 430)
                .containerBackground(.clear, for: .window)
        )
    }

    private func configureMemoryPopover() {
        memoryPopover.behavior = .transient
        memoryPopover.delegate = self
        memoryPopover.contentSize = NSSize(width: 430, height: 620)
        memoryPopover.contentViewController = NSHostingController(
            rootView: MemoryPopoverView(monitor: monitor)
                .frame(width: 430)
                .containerBackground(.clear, for: .window)
        )
    }

    private func configureClipboardPopover() {
        clipboardPopover.behavior = .transient
        clipboardPopover.delegate = self
        clipboardPopover.contentSize = NSSize(width: 430, height: 620)
        clipboardPopover.contentViewController = NSHostingController(
            rootView: ClipboardPopoverView(store: clipboardHistory) { [weak self] entry in
                self?.clipboardHistory.copy(entry)
            }
            .frame(width: 430)
            .containerBackground(.clear, for: .window)
        )
    }

    private func updateStatusItems(with snapshot: MetricSnapshot) {
        clipboardStatusItem.isVisible = StatusBarPreferences.isClipboardHistoryEnabled()

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
            metricItem.item.isVisible = true

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

    @objc private func toggleCPUPopover(_ sender: Any?) {
        guard
            let button = sender as? NSStatusBarButton,
            let targetPopover = cpuPopover(for: button)
        else {
            return
        }

        if targetPopover.isShown {
            closeCPUPopover(targetPopover, sender)
            return
        }

        closeOtherCPUPopovers(except: targetPopover)
        showCPUPopover(targetPopover, relativeTo: button)
    }

    @objc private func toggleMemoryPopover(_ sender: Any?) {
        if memoryPopover.isShown {
            closeMemoryPopover(sender)
            return
        }

        guard let memoryItem = metricItems[.memory]?.item.button else {
            return
        }

        showMemoryPopover(relativeTo: memoryItem)
    }

    @objc private func toggleClipboardPopover(_ sender: Any?) {
        if clipboardPopover.isShown {
            closeClipboardPopover(sender)
            return
        }

        guard let clipboardItem = clipboardStatusItem.button else {
            return
        }

        showClipboardPopover(relativeTo: clipboardItem)
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        activePopoverID = ObjectIdentifier(popover)
        closeOtherPopovers(except: popover)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configureTransparentWindow(for: popover)
        startPopoverCloseObservers()
    }

    private func closePopover(_ sender: Any?) {
        guard popover.isShown else {
            stopPopoverCloseObserversIfActive(popover)
            return
        }

        popover.performClose(sender)
        stopPopoverCloseObserversIfActive(popover)
    }

    private func showNetworkPopover(relativeTo button: NSStatusBarButton) {
        activePopoverID = ObjectIdentifier(networkPopover)
        closeOtherPopovers(except: networkPopover)
        networkPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configureTransparentWindow(for: networkPopover)
        startNetworkPopoverCloseObservers()
    }

    private func closeNetworkPopover(_ sender: Any?) {
        guard networkPopover.isShown else {
            stopPopoverCloseObserversIfActive(networkPopover)
            return
        }

        networkPopover.performClose(sender)
        stopPopoverCloseObserversIfActive(networkPopover)
    }

    private func showMemoryPopover(relativeTo button: NSStatusBarButton) {
        activePopoverID = ObjectIdentifier(memoryPopover)
        closeOtherPopovers(except: memoryPopover)
        memoryPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configureTransparentWindow(for: memoryPopover)
        startMemoryPopoverCloseObservers()
    }

    private func closeMemoryPopover(_ sender: Any?) {
        guard memoryPopover.isShown else {
            stopPopoverCloseObserversIfActive(memoryPopover)
            return
        }

        memoryPopover.performClose(sender)
        stopPopoverCloseObserversIfActive(memoryPopover)
    }

    private func showClipboardPopover(relativeTo button: NSStatusBarButton) {
        activePopoverID = ObjectIdentifier(clipboardPopover)
        closeOtherPopovers(except: clipboardPopover)
        clipboardPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configureTransparentWindow(for: clipboardPopover)
        startClipboardPopoverCloseObservers()
    }

    private func closeClipboardPopover(_ sender: Any?) {
        guard clipboardPopover.isShown else {
            stopPopoverCloseObserversIfActive(clipboardPopover)
            return
        }

        clipboardPopover.performClose(sender)
        stopPopoverCloseObserversIfActive(clipboardPopover)
    }

    private func showCPUPopover(_ popover: NSPopover, relativeTo button: NSStatusBarButton) {
        activePopoverID = ObjectIdentifier(popover)
        closeOtherPopovers(except: popover)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configureTransparentWindow(for: popover)
        startCPUPopoverCloseObservers()
    }

    private func configureTransparentWindow(for popover: NSPopover) {
        popover.contentViewController?.view.window?.isOpaque = false
        popover.contentViewController?.view.window?.backgroundColor = .clear
    }

    private func closeCPUPopover(_ popover: NSPopover, _ sender: Any?) {
        guard popover.isShown else {
            stopPopoverCloseObserversIfActive(popover)
            return
        }

        popover.performClose(sender)
        stopPopoverCloseObserversIfActive(popover)
    }

    private func closeShownCPUPopovers(_ sender: Any?) {
        closeOtherCPUPopovers(except: nil, sender)
        if activePopoverID == ObjectIdentifier(cpuPopover) || activePopoverID == ObjectIdentifier(tempPopover) {
            stopCPUPopoverCloseObservers()
            activePopoverID = nil
        }
    }

    private func closeOtherPopovers(except activePopover: NSPopover?, _ sender: Any? = nil) {
        for popover in [popover, networkPopover, cpuPopover, tempPopover, memoryPopover, clipboardPopover] where popover !== activePopover && popover.isShown {
            popover.performClose(sender)
        }
    }

    private func closeOtherCPUPopovers(except activePopover: NSPopover?, _ sender: Any? = nil) {
        for popover in [cpuPopover, tempPopover] where popover !== activePopover && popover.isShown {
            popover.performClose(sender)
        }
    }

    private func cpuPopover(for button: NSStatusBarButton) -> NSPopover? {
        if button === metricItems[.cpu]?.item.button {
            return cpuPopover
        }
        if button === metricItems[.temp]?.item.button {
            return tempPopover
        }
        return nil
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        let closedPopoverID = (notification.object as AnyObject?).map(ObjectIdentifier.init)

        Task { @MainActor in
            guard let closedPopoverID else {
                self.stopPopoverCloseObservers()
                self.stopNetworkPopoverCloseObservers()
                self.stopCPUPopoverCloseObservers()
                self.stopMemoryPopoverCloseObservers()
                self.stopClipboardPopoverCloseObservers()
                self.activePopoverID = nil
                return
            }

            guard closedPopoverID == self.activePopoverID else {
                return
            }

            if closedPopoverID == ObjectIdentifier(self.popover) {
                self.stopPopoverCloseObservers()
            } else if closedPopoverID == ObjectIdentifier(self.networkPopover) {
                self.stopNetworkPopoverCloseObservers()
            } else if closedPopoverID == ObjectIdentifier(self.cpuPopover) || closedPopoverID == ObjectIdentifier(self.tempPopover) {
                if !self.isCPUPopoverShown {
                    self.stopCPUPopoverCloseObservers()
                }
            } else if closedPopoverID == ObjectIdentifier(self.memoryPopover) {
                self.stopMemoryPopoverCloseObservers()
            } else if closedPopoverID == ObjectIdentifier(self.clipboardPopover) {
                self.stopClipboardPopoverCloseObservers()
            }

            if !self.isAnyPopoverShown {
                self.activePopoverID = nil
            }
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

    private func startCPUPopoverCloseObservers() {
        stopCPUPopoverCloseObservers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.closeCPUPopoverIfNeeded(for: event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeShownCPUPopovers(nil)
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeShownCPUPopovers(nil)
            }
        }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.closeCPUPopoverIfStatusItemHidden()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusVisibilityTimer = timer
    }

    private func stopCPUPopoverCloseObservers() {
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

    private func startMemoryPopoverCloseObservers() {
        stopMemoryPopoverCloseObservers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.closeMemoryPopoverIfNeeded(for: event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeMemoryPopover(nil)
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeMemoryPopover(nil)
            }
        }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.closeMemoryPopoverIfStatusItemHidden()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusVisibilityTimer = timer
    }

    private func stopMemoryPopoverCloseObservers() {
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

    private func startClipboardPopoverCloseObservers() {
        stopClipboardPopoverCloseObservers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.closeClipboardPopoverIfNeeded(for: event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeClipboardPopover(nil)
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeClipboardPopover(nil)
            }
        }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.closeClipboardPopoverIfStatusItemHidden()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusVisibilityTimer = timer
    }

    private func stopClipboardPopoverCloseObservers() {
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

    private func stopPopoverCloseObserversIfActive(_ popover: NSPopover) {
        guard activePopoverID == ObjectIdentifier(popover) else {
            return
        }

        if popover === self.popover {
            stopPopoverCloseObservers()
        } else if popover === networkPopover {
            stopNetworkPopoverCloseObservers()
        } else if popover === cpuPopover || popover === tempPopover {
            stopCPUPopoverCloseObservers()
        } else if popover === memoryPopover {
            stopMemoryPopoverCloseObservers()
        } else if popover === clipboardPopover {
            stopClipboardPopoverCloseObservers()
        }

        activePopoverID = nil
    }

    private func closePopoverIfNeeded(for event: NSEvent) {
        guard popover.isShown else {
            stopPopoverCloseObserversIfActive(popover)
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
            stopPopoverCloseObserversIfActive(popover)
            return
        }

        guard let window = mainStatusItem.button?.window, window.isVisible else {
            closePopover(nil)
            return
        }
    }

    private func closeNetworkPopoverIfNeeded(for event: NSEvent) {
        guard networkPopover.isShown else {
            stopPopoverCloseObserversIfActive(networkPopover)
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
            stopPopoverCloseObserversIfActive(networkPopover)
            return
        }

        guard let window = metricItems[.network]?.item.button?.window, window.isVisible else {
            closeNetworkPopover(nil)
            return
        }
    }

    private func closeCPUPopoverIfNeeded(for event: NSEvent) {
        guard isCPUPopoverShown else {
            if activePopoverID == ObjectIdentifier(cpuPopover) || activePopoverID == ObjectIdentifier(tempPopover) {
                stopCPUPopoverCloseObservers()
                activePopoverID = nil
            }
            return
        }

        if isEventInsideCPUStatusButton(event) || isEventInsideCPUPopover(event) {
            return
        }

        closeShownCPUPopovers(nil)
    }

    private func isEventInsideCPUStatusButton(_ event: NSEvent) -> Bool {
        [metricItems[.cpu]?.item.button, metricItems[.temp]?.item.button].contains { button in
            guard let button, event.window === button.window else {
                return false
            }

            let point = button.convert(event.locationInWindow, from: nil)
            return button.bounds.contains(point)
        }
    }

    private func isEventInsideCPUPopover(_ event: NSEvent) -> Bool {
        [cpuPopover, tempPopover].contains { popover in
            guard let window = popover.contentViewController?.view.window else {
                return false
            }

            return event.window === window
        }
    }

    private func closeCPUPopoverIfStatusItemHidden() {
        guard isCPUPopoverShown else {
            if activePopoverID == ObjectIdentifier(cpuPopover) || activePopoverID == ObjectIdentifier(tempPopover) {
                stopCPUPopoverCloseObservers()
                activePopoverID = nil
            }
            return
        }

        let cpuButton = metricItems[.cpu]?.item.button
        let tempButton = metricItems[.temp]?.item.button
        guard let button = cpuButton ?? tempButton, let window = button.window, window.isVisible else {
            closeShownCPUPopovers(nil)
            return
        }
    }

    private var isCPUPopoverShown: Bool {
        cpuPopover.isShown || tempPopover.isShown
    }

    private func closeMemoryPopoverIfNeeded(for event: NSEvent) {
        guard memoryPopover.isShown else {
            stopPopoverCloseObserversIfActive(memoryPopover)
            return
        }

        if isEventInsideMemoryStatusButton(event) || isEventInsideMemoryPopover(event) {
            return
        }

        closeMemoryPopover(nil)
    }

    private func isEventInsideMemoryStatusButton(_ event: NSEvent) -> Bool {
        guard
            let button = metricItems[.memory]?.item.button,
            event.window === button.window
        else {
            return false
        }

        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func isEventInsideMemoryPopover(_ event: NSEvent) -> Bool {
        guard let window = memoryPopover.contentViewController?.view.window else {
            return false
        }

        return event.window === window
    }

    private func closeMemoryPopoverIfStatusItemHidden() {
        guard memoryPopover.isShown else {
            stopPopoverCloseObserversIfActive(memoryPopover)
            return
        }

        guard let window = metricItems[.memory]?.item.button?.window, window.isVisible else {
            closeMemoryPopover(nil)
            return
        }
    }

    private func closeClipboardPopoverIfNeeded(for event: NSEvent) {
        guard clipboardPopover.isShown else {
            stopPopoverCloseObserversIfActive(clipboardPopover)
            return
        }

        if isEventInsideClipboardStatusButton(event) || isEventInsideClipboardPopover(event) {
            return
        }

        closeClipboardPopover(nil)
    }

    private func isEventInsideClipboardStatusButton(_ event: NSEvent) -> Bool {
        guard
            let button = clipboardStatusItem.button,
            event.window === button.window
        else {
            return false
        }

        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func isEventInsideClipboardPopover(_ event: NSEvent) -> Bool {
        guard let window = clipboardPopover.contentViewController?.view.window else {
            return false
        }

        return event.window === window
    }

    private func closeClipboardPopoverIfStatusItemHidden() {
        guard clipboardPopover.isShown else {
            stopPopoverCloseObserversIfActive(clipboardPopover)
            return
        }

        guard let window = clipboardStatusItem.button?.window, window.isVisible else {
            closeClipboardPopover(nil)
            return
        }
    }

    private var isAnyPopoverShown: Bool {
        popover.isShown || networkPopover.isShown || isCPUPopoverShown || memoryPopover.isShown || clipboardPopover.isShown
    }
}

private struct MetricStatusItem {
    let item: NSStatusItem
    let hostingView: NSHostingView<StatusBarMetricContent>
}

private struct ClipboardStatusIcon: View {
    var body: some View {
        Image(systemName: "clipboard")
            .font(.system(size: 13, weight: .semibold))
    }
}

private struct MainStatusIcon: View {
    var body: some View {
        Image(systemName: "circle.hexagongrid.circle")
            .font(.system(size: 13, weight: .semibold))
    }
}
