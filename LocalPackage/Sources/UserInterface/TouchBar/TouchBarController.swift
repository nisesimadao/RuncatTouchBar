/*
 TouchBarController.swift
 RuncatTouchBar

 A tiny Activity Monitor for the Touch Bar: the selected RunCat runner lives in
 the Control Strip, follows the existing CPU-driven animation speed, and opens
 an expanded CPU/RAM/battery/process view when tapped.
 */

import AppKit
import Darwin
import DataSource
import Foundation
import Model

@MainActor
public final class TouchBarController: NSObject, NSTouchBarDelegate {
    public static let shared = TouchBarController()

    private enum ItemID {
        static let tray = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.tray")
        static let close = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.close")
        static let cpu = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.cpu")
        static let ram = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.ram")
        static let battery = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.battery")
        static let processes = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.processes")
        static let activityMonitor = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.activityMonitor")
    }

    private let appStateClient = AppDependencies.shared.appStateClient
    private let systemInfoObserverClient = AppDependencies.shared.systemInfoObserverClient
    private let nsWorkspaceClient = AppDependencies.shared.nsWorkspaceClient
    private let userDefaultsRepository = UserDefaultsRepository(AppDependencies.shared.userDefaultsClient)
    private let privateAPI = TouchBarPrivateAPI.shared

    private var isStarted = false
    private var isExpanded = false
    private var trayItem: NSCustomTouchBarItem?
    private var trayButton: NSButton?
    private var animationTimer: Timer?
    private var trayPresenceTimer: Timer?
    private var liveRefreshTimer: Timer?
    private var liveRefreshInterval: TimeInterval = 0
    private var streamTasks = [Task<Void, Never>]()
    private var processRefreshTask: Task<Void, Never>?
    private var lastBatteryRefresh = Date.distantPast

    private var runnerFrames = [NSImage]()
    private var runnerSpeed: Float = 1.0
    private var frameIndex = 0

    private var cpuText = "CPU --%"
    private var ramUsedBytes = 0.0
    private var ramTotalBytes = Double(ProcessInfo.processInfo.physicalMemory)
    private var ramFraction = 0.0
    private var batterySnapshot = BatterySnapshot.unavailable
    private var topProcesses = [ProcessEntry]()

    private weak var cpuLabel: NSTextField?
    private weak var ramView: RAMUsageView?
    private weak var batteryView: BatteryUsageView?
    private weak var processItem: ProcessScrollTouchBarItem?

    private lazy var expandedTouchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = expandedItemIdentifiers()
        return touchBar
    }()

    private override init() {
        super.init()
    }

    public func start() {
        guard !isStarted, privateAPI.isAvailable else { return }
        isStarted = true

        let item = NSCustomTouchBarItem(identifier: ItemID.tray)
        item.customizationLabel = "RunCat"

        let button = NSButton(
            image: fallbackRunnerImage(),
            target: self,
            action: #selector(showExpandedTouchBar)
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.setAccessibilityLabel("RunCat system monitor")
        item.view = button
        trayItem = item
        trayButton = button

        privateAPI.setSystemModalCloseBoxVisible(false)
        guard privateAPI.addSystemTrayItem(item) else {
            trayItem = nil
            trayButton = nil
            isStarted = false
            return
        }

        ensureTrayPresence()
        startTrayPresenceWatchdog()
        applyInitialState()
        subscribeToRunCatState()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        isExpanded = false

        animationTimer?.invalidate()
        animationTimer = nil
        trayPresenceTimer?.invalidate()
        trayPresenceTimer = nil
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        liveRefreshInterval = 0
        processRefreshTask?.cancel()
        processRefreshTask = nil
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()

        privateAPI.dismiss(expandedTouchBar)
        privateAPI.setControlStripPresence(ItemID.tray, visible: false)
        if let trayItem {
            privateAPI.removeSystemTrayItem(trayItem)
        }
        trayItem = nil
        trayButton = nil
    }

    public func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        if identifier == ItemID.close {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let closeImage = NSImage(named: NSImage.stopProgressFreestandingTemplateName)
                ?? NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
            closeImage?.isTemplate = true

            let button = NSButton(
                image: closeImage ?? NSImage(size: NSSize(width: 18, height: 18)),
                target: self,
                action: #selector(closeExpandedTouchBar)
            )
            configureInlineIconButton(button)
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.setAccessibilityLabel("Close RunCat system monitor")
            item.view = button
            return item
        }

        if identifier == ItemID.cpu {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = statusLabel(cpuText)
            label.widthAnchor.constraint(equalToConstant: 58).isActive = true
            cpuLabel = label
            item.view = label
            return item
        }

        if identifier == ItemID.ram {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let view = RAMUsageView()
            view.update(
                usedBytes: ramUsedBytes,
                totalBytes: ramTotalBytes,
                fraction: ramFraction
            )
            ramView = view
            item.view = view
            return item
        }

        if identifier == ItemID.battery {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let view = BatteryUsageView()
            view.update(snapshot: batterySnapshot)
            batteryView = view
            item.view = view
            return item
        }

        if identifier == ItemID.processes {
            let item = ProcessScrollTouchBarItem(identifier: identifier)
            item.onQuit = { [weak self] pid in
                self?.quitProcess(pid: pid)
            }
            item.onForceKill = { [weak self] pid in
                self?.forceKillProcess(pid: pid)
            }
            item.update(entries: topProcesses)
            processItem = item
            return item
        }

        if identifier == ItemID.activityMonitor {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let image = NSImage(
                systemSymbolName: "chart.bar.xaxis",
                accessibilityDescription: "Open Activity Monitor"
            ) ?? NSImage(size: NSSize(width: 18, height: 18))
            image.isTemplate = true

            let button = NSButton(
                image: image,
                target: self,
                action: #selector(openActivityMonitor)
            )
            configureInlineIconButton(button)
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.setAccessibilityLabel("Open Activity Monitor")
            item.view = button
            return item
        }

        return nil
    }

    private func configureInlineIconButton(_ button: NSButton) {
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .white
    }

    private func expandedItemIdentifiers() -> [NSTouchBarItem.Identifier] {
        let configuration = userDefaultsRepository.systemMetricsConfiguration
        var identifiers = [ItemID.close, ItemID.cpu]
        if configuration.monitorsMemory {
            identifiers.append(ItemID.ram)
        }
        if configuration.monitorsBattery {
            identifiers.append(ItemID.battery)
        }
        identifiers.append(ItemID.processes)
        identifiers.append(ItemID.activityMonitor)
        return identifiers
    }

    private func preferredRefreshInterval() -> TimeInterval {
        TimeInterval(userDefaultsRepository.updateInterval.seconds)
    }

    private func syncTouchBarPreferences() {
        guard isExpanded else { return }

        let identifiers = expandedItemIdentifiers()
        if expandedTouchBar.defaultItemIdentifiers != identifiers {
            let addedBattery = identifiers.contains(ItemID.battery)
                && !expandedTouchBar.defaultItemIdentifiers.contains(ItemID.battery)
            expandedTouchBar.defaultItemIdentifiers = identifiers
            if addedBattery {
                refreshProcessesAndBattery(forceBattery: true)
            }
        }

        let interval = preferredRefreshInterval()
        if abs(liveRefreshInterval - interval) > 0.01 {
            startLiveRefresh()
        }
    }

    private func applyInitialState() {
        let initial = appStateClient.withLock { state in
            (
                state.runnerBundles.latestValue,
                state.runnerSpeeds.latestValue,
                state.metrics.latestValue
            )
        }

        if let bundle = initial.0 {
            applyRunner(bundle)
        } else {
            applyFallbackRunner()
        }
        if let speed = initial.1 {
            applyRunnerSpeed(speed)
        }
        if let metrics = initial.2 {
            applyMetrics(metrics)
        }
    }

    private func subscribeToRunCatState() {
        let runnerStream = appStateClient.withLock { $0.runnerBundles.stream }
        let speedStream = appStateClient.withLock { $0.runnerSpeeds.stream }
        let metricsStream = appStateClient.withLock { $0.metrics.stream }

        streamTasks.append(Task { [weak self] in
            for await bundle in runnerStream {
                guard !Task.isCancelled else { break }
                self?.applyRunner(bundle)
            }
        })
        streamTasks.append(Task { [weak self] in
            for await speed in speedStream {
                guard !Task.isCancelled else { break }
                self?.applyRunnerSpeed(speed)
            }
        })
        streamTasks.append(Task { [weak self] in
            for await metrics in metricsStream {
                guard !Task.isCancelled else { break }
                self?.applyMetrics(metrics)
            }
        })
    }

    private func applyRunner(_ bundle: RunnerBundle) {
        guard case let .keyFrameAnimation(frames) = bundle.displayFormat else { return }
        let images = frames.compactMap {
            image(from: $0, isTemplate: bundle.runner.isTemplate)
        }
        guard !images.isEmpty else {
            applyFallbackRunner()
            return
        }
        runnerFrames = images
        frameIndex = 0
        trayButton?.image = runnerFrames[0]
        restartAnimationTimer()
    }

    private func applyFallbackRunner() {
        runnerFrames = (0..<5).compactMap { index in
            image(from: .preset("cat-frame-\(index)"), isTemplate: true)
        }
        frameIndex = 0
        trayButton?.image = runnerFrames.first ?? fallbackRunnerImage()
        restartAnimationTimer()
    }

    private func applyRunnerSpeed(_ speed: Float) {
        runnerSpeed = max(0.5, min(20.0, speed))
        restartAnimationTimer()
    }

    private func applyMetrics(_ metrics: Metrics) {
        if let cpu = metrics.systemInfoBundle.cpuInfo {
            cpuText = String(format: "CPU %.0f%%", cpu.percentage.value)
        }

        let configuration = userDefaultsRepository.systemMetricsConfiguration
        if configuration.monitorsMemory,
           let memory = metrics.systemInfoBundle.memoryInfo {
            ramUsedBytes = memory.app.byteCount + memory.wired.byteCount + memory.compressed.byteCount
            ramTotalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            ramFraction = min(1.0, max(0.0, memory.percentage.value / 100.0))
        }

        cpuLabel?.stringValue = cpuText
        if configuration.monitorsMemory {
            ramView?.update(
                usedBytes: ramUsedBytes,
                totalBytes: ramTotalBytes,
                fraction: ramFraction
            )
        }
        syncTouchBarPreferences()
    }

    private func refreshMetricsFromObserver() {
        let info = systemInfoObserverClient.currentSystemInfo()
        let configuration = userDefaultsRepository.systemMetricsConfiguration
        if let cpu = info.cpuInfo {
            cpuText = String(format: "CPU %.0f%%", cpu.percentage.value)
        }
        if configuration.monitorsMemory,
           let memory = info.memoryInfo {
            ramUsedBytes = memory.app.byteCount + memory.wired.byteCount + memory.compressed.byteCount
            ramTotalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            ramFraction = min(1.0, max(0.0, memory.percentage.value / 100.0))
        }
        cpuLabel?.stringValue = cpuText
        if configuration.monitorsMemory {
            ramView?.update(
                usedBytes: ramUsedBytes,
                totalBytes: ramTotalBytes,
                fraction: ramFraction
            )
        }
    }

    private func restartAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard runnerFrames.count > 1, isStarted else { return }

        let interval = max(0.025, 0.5 / Double(runnerSpeed))
        animationTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: true
        )
    }

    private func startTrayPresenceWatchdog() {
        trayPresenceTimer?.invalidate()
        trayPresenceTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(reassertTrayPresence),
            userInfo: nil,
            repeats: true
        )
    }

    private func startLiveRefresh() {
        liveRefreshTimer?.invalidate()
        let interval = preferredRefreshInterval()
        liveRefreshInterval = interval
        liveRefreshTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(liveRefreshTick),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopLiveRefresh() {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        liveRefreshInterval = 0
        processRefreshTask?.cancel()
        processRefreshTask = nil
    }

    @objc private func advanceFrame() {
        guard !runnerFrames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % runnerFrames.count
        trayButton?.image = runnerFrames[frameIndex]
    }

    @objc private func reassertTrayPresence() {
        ensureTrayPresence()
    }

    @objc private func liveRefreshTick() {
        guard isExpanded else { return }
        syncTouchBarPreferences()
        refreshMetricsFromObserver()
        refreshProcessesAndBattery()
    }

    private func ensureTrayPresence() {
        guard isStarted, trayItem != nil else { return }
        privateAPI.setControlStripPresence(ItemID.tray, visible: true)
    }

    @objc private func showExpandedTouchBar() {
        guard !isExpanded else { return }
        isExpanded = true
        expandedTouchBar.defaultItemIdentifiers = expandedItemIdentifiers()
        refreshMetricsFromObserver()
        refreshProcessesAndBattery(forceBattery: true)

        guard privateAPI.present(expandedTouchBar, from: ItemID.tray) else {
            isExpanded = false
            stopLiveRefresh()
            ensureTrayPresence()
            return
        }

        startLiveRefresh()
        ensureTrayPresence()
    }

    @objc private func closeExpandedTouchBar() {
        guard isExpanded else { return }
        isExpanded = false
        stopLiveRefresh()
        privateAPI.minimize(expandedTouchBar)
        ensureTrayPresence()
    }

    @objc private func openActivityMonitor() {
        guard let url = nsWorkspaceClient.urlForApplication(String.activityMonitor) else { return }
        nsWorkspaceClient.openApplication(url, .init())
    }

    private func quitProcess(pid: pid_t) {
        guard pid > 1, pid != getpid() else { return }
        let requestedGracefully = NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
        if !requestedGracefully {
            _ = ProcessSampler.terminate(pid: pid)
        }
        refreshProcessesSoon()
    }

    private func forceKillProcess(pid: pid_t) {
        guard pid > 1, pid != getpid() else { return }
        let requestedForcefully = NSRunningApplication(processIdentifier: pid)?.forceTerminate() ?? false
        if !requestedForcefully {
            _ = ProcessSampler.forceTerminate(pid: pid)
        }
        refreshProcessesSoon()
    }

    private func refreshProcessesSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.refreshProcessesAndBattery()
        }
    }

    private func refreshProcessesAndBattery(forceBattery: Bool = false) {
        guard processRefreshTask == nil else { return }

        let configuration = userDefaultsRepository.systemMetricsConfiguration
        let shouldRefreshBattery = configuration.monitorsBattery
            && (forceBattery || Date().timeIntervalSince(lastBatteryRefresh) >= 15)

        processRefreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                (
                    ProcessSampler.topProcesses(limit: 16),
                    shouldRefreshBattery ? BatterySampler.snapshot() : nil
                )
            }.value

            guard !Task.isCancelled, let self else { return }
            defer { self.processRefreshTask = nil }

            self.topProcesses = snapshot.0
            self.processItem?.update(entries: snapshot.0)

            if let battery = snapshot.1 {
                self.batterySnapshot = battery
                self.lastBatteryRefresh = Date()
                self.batteryView?.update(snapshot: battery)
            }
        }
    }

    private func statusLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func image(from frame: Frame, isTemplate: Bool) -> NSImage? {
        let source: NSImage?
        switch frame {
        case let .preset(resourceName):
            source = NSImage(resource: .init(name: resourceName, bundle: .module))
        case let .custom(data):
            source = NSImage(data: data)
        case .broken:
            source = nil
        }
        guard let source, let image = source.copy() as? NSImage else { return nil }

        let original = image.size
        if original.width > 0, original.height > 0 {
            let targetHeight = 18.0
            let width = min(42.0, targetHeight * original.width / original.height)
            image.size = NSSize(width: width, height: targetHeight)
        }

        if isTemplate {
            return whiteRasterizedImage(from: image)
        }
        image.isTemplate = false
        return image
    }

    private func whiteRasterizedImage(from image: NSImage) -> NSImage {
        let size = image.size
        let result = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }

    private func fallbackRunnerImage() -> NSImage {
        let image = NSImage(
            systemSymbolName: "hare.fill",
            accessibilityDescription: "RunCat"
        ) ?? NSImage(size: NSSize(width: 22, height: 18))
        image.size = NSSize(width: 22, height: 18)
        return whiteRasterizedImage(from: image)
    }
}

@MainActor
private final class UsageBarView: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    var fillColor: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 58, height: 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 0, rect.height > 0 else { return }

        let radius = rect.height / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.18).setFill()
        track.fill()

        let fillWidth = max(0, rect.width * fraction)
        guard fillWidth > 0.5 else { return }

        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        fillColor.setFill()
        fill.fill()
    }
}

@MainActor
private final class RAMUsageView: NSView {
    private let label = NSTextField(labelWithString: "RAM --/--G")
    private let bar = UsageBarView()

    override var intrinsicContentSize: NSSize {
        NSSize(width: 125, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 125, height: 30))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        label.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .white
        label.alignment = .right
        label.lineBreakMode = .byClipping

        let stack = NSStackView(views: [label, bar])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        bar.widthAnchor.constraint(equalToConstant: 45).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 7).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(usedBytes: Double, totalBytes: Double, fraction: Double) {
        let gib = 1_073_741_824.0
        guard totalBytes > 0 else {
            label.stringValue = "RAM --/--G"
            bar.fraction = 0
            return
        }

        label.stringValue = String(
            format: "RAM %.1f/%.1fG",
            usedBytes / gib,
            totalBytes / gib
        )
        bar.fraction = fraction
        bar.fillColor = UsagePalette.color(for: fraction)
    }
}

@MainActor
private final class BatteryUsageView: NSView {
    private let label = NSTextField(labelWithString: "BAT --%")
    private let bar = UsageBarView()

    override var intrinsicContentSize: NSSize {
        NSSize(width: 95, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 95, height: 30))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        label.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .white
        label.alignment = .right
        label.lineBreakMode = .byClipping

        let stack = NSStackView(views: [label, bar])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        bar.widthAnchor.constraint(equalToConstant: 34).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 7).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(snapshot: BatterySnapshot) {
        guard snapshot.isAvailable else {
            label.stringValue = "BAT --%"
            bar.fraction = 0
            bar.fillColor = .secondaryLabelColor
            return
        }

        label.stringValue = snapshot.isCharging
            ? String(format: "BAT %.0f%%⚡", snapshot.fraction * 100)
            : String(format: "BAT %.0f%%", snapshot.fraction * 100)

        bar.fraction = snapshot.fraction
        if snapshot.isCharging {
            bar.fillColor = .systemGreen
        } else if snapshot.fraction <= 0.2 {
            bar.fillColor = .systemRed
        } else if snapshot.fraction <= 0.4 {
            bar.fillColor = .systemOrange
        } else {
            bar.fillColor = .systemGreen
        }
    }
}

@MainActor
private enum UsagePalette {
    static func color(for fraction: Double) -> NSColor {
        if fraction >= 0.90 { return .systemRed }
        if fraction >= 0.75 { return .systemOrange }
        return .systemGreen
    }
}

@MainActor
private final class ProcessScrollTouchBarItem: NSCustomTouchBarItem {
    var onQuit: ((pid_t) -> Void)?
    var onForceKill: ((pid_t) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 30))
    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No active user processes")
    private var rowsByPID = [pid_t: ProcessRowView]()
    private var orderedPIDs = [pid_t]()
    private var lastScrollChange = Date.distantPast
    private var lastRankRefresh = Date.distantPast

    private let scrollIdleDelay: TimeInterval = 1.1
    private let rankRefreshInterval: TimeInterval = 3.0

    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.widthAnchor.constraint(equalToConstant: 460).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 30).isActive = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        emptyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 3),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 30),
        ])

        scrollView.documentView = contentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        view = scrollView
        update(entries: [])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entries: [ProcessEntry]) {
        let now = Date()
        let visibleX = scrollView.documentVisibleRect.origin.x
        let incomingPIDs = entries.map(\.pid)
        let incomingSet = Set(incomingPIDs)
        let isActivelyScrolling = now.timeIntervalSince(lastScrollChange) < scrollIdleDelay
        var rankAnchor: (pid: pid_t, offset: CGFloat)?
        var didReorder = false

        for pid in Array(rowsByPID.keys) where !incomingSet.contains(pid) {
            if let row = rowsByPID.removeValue(forKey: pid) {
                stack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
            orderedPIDs.removeAll { $0 == pid }
        }

        if entries.isEmpty {
            for row in rowsByPID.values {
                stack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
            rowsByPID.removeAll()
            orderedPIDs.removeAll()
            if !stack.arrangedSubviews.contains(where: { $0 === emptyLabel }) {
                stack.addArrangedSubview(emptyLabel)
            }
        } else {
            if stack.arrangedSubviews.contains(where: { $0 === emptyLabel }) {
                stack.removeArrangedSubview(emptyLabel)
                emptyLabel.removeFromSuperview()
            }

            for entry in entries {
                if let row = rowsByPID[entry.pid] {
                    row.update(entry: entry)
                } else {
                    let row = makeProcessRow(entry: entry)
                    rowsByPID[entry.pid] = row
                    orderedPIDs.append(entry.pid)
                    stack.addArrangedSubview(row)
                }
            }

            let shouldRefreshRanking = !isActivelyScrolling
                && now.timeIntervalSince(lastRankRefresh) >= rankRefreshInterval

            if shouldRefreshRanking {
                lastRankRefresh = now
                if orderedPIDs != incomingPIDs {
                    rankAnchor = visibleAnchor(at: visibleX)
                    let rankedRows = incomingPIDs.compactMap { rowsByPID[$0] }
                    for row in rankedRows {
                        stack.removeArrangedSubview(row)
                        row.removeFromSuperview()
                    }
                    for row in rankedRows {
                        stack.addArrangedSubview(row)
                    }
                    orderedPIDs = incomingPIDs
                    didReorder = true
                }
            }
        }

        stack.layoutSubtreeIfNeeded()
        let contentWidth = max(460, stack.fittingSize.width + 13)
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 30)
        contentView.layoutSubtreeIfNeeded()

        var preferredX = visibleX
        if didReorder,
           let rankAnchor,
           let row = rowsByPID[rankAnchor.pid] {
            let rowFrame = row.convert(row.bounds, to: contentView)
            preferredX = rowFrame.minX - rankAnchor.offset
        }

        let maxX = max(0, contentWidth - scrollView.documentVisibleRect.width)
        let targetX = min(max(0, preferredX), maxX)
        if abs(scrollView.documentVisibleRect.origin.x - targetX) > 0.5 {
            scrollView.contentView.scroll(to: NSPoint(x: targetX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func visibleAnchor(at visibleX: CGFloat) -> (pid: pid_t, offset: CGFloat)? {
        let visibleMaxX = visibleX + scrollView.documentVisibleRect.width
        for pid in orderedPIDs {
            guard let row = rowsByPID[pid] else { continue }
            let frame = row.convert(row.bounds, to: contentView)
            if frame.maxX > visibleX, frame.minX < visibleMaxX {
                return (pid, frame.minX - visibleX)
            }
        }
        return nil
    }

    @objc private func scrollBoundsDidChange(_ notification: Notification) {
        lastScrollChange = Date()
    }

    private func makeProcessRow(entry: ProcessEntry) -> ProcessRowView {
        let quit = makeIconButton(
            symbolName: "rectangle.portrait.and.arrow.forward",
            accessibilityLabel: "Quit \(entry.name)",
            action: #selector(quitPressed(_:))
        )
        quit.tag = Int(entry.pid)

        let force = makeForceKillButton(pid: entry.pid, processName: entry.name)
        return ProcessRowView(
            entry: entry,
            icon: processIcon(for: entry),
            quitButton: quit,
            forceButton: force
        )
    }

    private func processIcon(for entry: ProcessEntry) -> NSImage {
        if let image = NSRunningApplication(processIdentifier: entry.pid)?.icon?.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        if !entry.commandPath.isEmpty {
            let image = NSWorkspace.shared.icon(forFile: entry.commandPath)
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "app.fill",
            accessibilityDescription: entry.name
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }

    private func makeIconButton(
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) -> NSButton {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        image?.isTemplate = true

        let button = NSButton(
            image: image ?? NSImage(size: NSSize(width: 15, height: 15)),
            target: self,
            action: action
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .white
        button.widthAnchor.constraint(equalToConstant: 27).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    private func makeForceKillButton(pid: pid_t, processName: String) -> NSButton {
        let image = redPowerImage(accessibilityLabel: "Force quit \(processName)")
        let button = NSButton(
            image: image,
            target: self,
            action: #selector(forceKillPressed(_:))
        )
        button.tag = Int(pid)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = nil
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setAccessibilityLabel("Force quit \(processName)")
        return button
    }

    private func redPowerImage(accessibilityLabel: String) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        guard let symbol = NSImage(
            systemSymbolName: "power",
            accessibilityDescription: accessibilityLabel
        ) else {
            return NSImage(size: size)
        }
        symbol.size = size
        symbol.isTemplate = false

        let result = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.systemRed.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }

    @objc private func quitPressed(_ sender: NSButton) {
        onQuit?(pid_t(sender.tag))
    }

    @objc private func forceKillPressed(_ sender: NSButton) {
        onForceKill?(pid_t(sender.tag))
    }
}

@MainActor
private final class ProcessRowView: NSStackView {
    let pid: pid_t

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(entry: ProcessEntry, icon: NSImage, quitButton: NSButton, forceButton: NSButton) {
        pid = entry.pid
        super.init(frame: .zero)

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .left
        label.usesSingleLineMode = true
        label.widthAnchor.constraint(equalToConstant: 112).isActive = true

        let actions = NSStackView(views: [quitButton, forceButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 2

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        addArrangedSubview(iconView)
        addArrangedSubview(label)
        addArrangedSubview(actions)
        update(entry: entry)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entry: ProcessEntry) {
        let shortName = String(entry.name.prefix(18))
        label.stringValue = String(format: "%@ %.0f%%", shortName, entry.cpu)
        label.toolTip = "PID \(entry.pid) — \(entry.name)"
    }
}

private struct ProcessEntry: Sendable {
    let pid: pid_t
    let cpu: Double
    let name: String
    let commandPath: String
}

private struct BatterySnapshot: Sendable {
    let isAvailable: Bool
    let fraction: Double
    let isCharging: Bool

    static let unavailable = BatterySnapshot(
        isAvailable: false,
        fraction: 0,
        isCharging: false
    )
}

private enum ProcessSampler {
    nonisolated static func topProcesses(limit: Int) -> [ProcessEntry] {
        let task = Foundation.Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "uid=,pid=,pcpu=,comm="]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        guard task.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let ownUID = getuid()
        let ownPID = getpid()
        var entries = [ProcessEntry]()

        for line in text.split(whereSeparator: \Character.isNewline) {
            let fields = line.split(
                maxSplits: 3,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard fields.count == 4,
                  let uid = uid_t(String(fields[0])),
                  uid == ownUID,
                  let pid = pid_t(String(fields[1])),
                  pid > 1,
                  pid != ownPID,
                  let cpu = Double(fields[2]),
                  cpu > 0.05 else {
                continue
            }

            let commandPath = String(fields[3])
            let name = URL(fileURLWithPath: commandPath).lastPathComponent
            guard !name.isEmpty, name != "ps" else { continue }

            entries.append(
                ProcessEntry(
                    pid: pid,
                    cpu: cpu,
                    name: name,
                    commandPath: commandPath
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.cpu == rhs.cpu { return lhs.name < rhs.name }
            return lhs.cpu > rhs.cpu
        }.prefix(limit).map { $0 }
    }

    @discardableResult
    nonisolated static func terminate(pid: pid_t) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        return kill(pid, SIGTERM) == 0
    }

    @discardableResult
    nonisolated static func forceTerminate(pid: pid_t) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        return kill(pid, SIGKILL) == 0
    }
}

private enum BatterySampler {
    nonisolated static func snapshot() -> BatterySnapshot {
        let task = Foundation.Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "batt"]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .unavailable
        }
        guard task.terminationStatus == 0 else { return .unavailable }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return .unavailable
        }

        guard let percentIndex = text.firstIndex(of: "%") else {
            return .unavailable
        }

        var start = percentIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isNumber else { break }
            start = previous
        }

        guard start < percentIndex,
              let percent = Double(text[start..<percentIndex]) else {
            return .unavailable
        }

        let lower = text.lowercased()
        let charging = lower.contains("charging")
            || lower.contains("charged")
            || lower.contains("ac attached")
            || lower.contains("ac power")

        return BatterySnapshot(
            isAvailable: true,
            fraction: min(1, max(0, percent / 100)),
            isCharging: charging
        )
    }
}
