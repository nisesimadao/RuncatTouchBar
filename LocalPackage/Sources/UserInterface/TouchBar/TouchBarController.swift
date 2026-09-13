/*
 TouchBarController.swift
 RuncatTouchBar

 RunCat in the Control Strip + a compact live Activity Monitor.
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
        static let refresh = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.refresh")
        static let processes = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.processes")
    }

    private let appStateClient = AppDependencies.shared.appStateClient
    private let systemInfoObserverClient = AppDependencies.shared.systemInfoObserverClient
    private let privateAPI = TouchBarPrivateAPI.shared

    private var isStarted = false
    private var isExpanded = false
    private var trayItem: NSCustomTouchBarItem?
    private var trayButton: NSButton?
    private var animationTimer: Timer?
    private var trayPresenceTimer: Timer?
    private var expandedRefreshTimer: Timer?
    private var streamTasks = [Task<Void, Never>]()
    private var processRefreshTask: Task<Void, Never>?

    private var runnerFrames = [NSImage]()
    private var runnerSpeed: Float = 1.0
    private var frameIndex = 0

    private var cpuText = "CPU --%"
    private var ramUsedBytes = 0.0
    private var ramTotalBytes = Double(ProcessInfo.processInfo.physicalMemory)
    private var ramFraction = 0.0
    private var topProcesses = [ProcessEntry]()

    private weak var cpuLabel: NSTextField?
    private weak var ramView: RAMUsageView?
    private weak var processItem: ProcessScrollTouchBarItem?

    private lazy var expandedTouchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            ItemID.close,
            ItemID.cpu,
            ItemID.ram,
            ItemID.refresh,
            ItemID.processes,
        ]
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
        expandedRefreshTimer?.invalidate()
        expandedRefreshTimer = nil
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
            configureBorderlessIconButton(button, width: 30)
            button.setAccessibilityLabel("Close RunCat system monitor")
            item.view = button
            return item
        }

        if identifier == ItemID.cpu {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = statusLabel(cpuText)
            label.widthAnchor.constraint(equalToConstant: 62).isActive = true
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

        if identifier == ItemID.refresh {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let image = NSImage(
                systemSymbolName: "arrow.clockwise",
                accessibilityDescription: "Refresh"
            )
            image?.isTemplate = true
            let button = NSButton(
                image: image ?? NSImage(size: NSSize(width: 16, height: 16)),
                target: self,
                action: #selector(refreshProcessesButtonPressed)
            )
            configureBorderlessIconButton(button, width: 28)
            button.setAccessibilityLabel("Refresh now")
            item.view = button
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

        return nil
    }

    private func configureBorderlessIconButton(_ button: NSButton, width: CGFloat) {
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .white
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
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
        if let memory = metrics.systemInfoBundle.memoryInfo {
            applyMemory(
                app: memory.app.byteCount,
                wired: memory.wired.byteCount,
                compressed: memory.compressed.byteCount,
                percentage: memory.percentage.value
            )
        }
        updateMetricViews()
    }

    private func refreshMetricsFromObserver() {
        let info = systemInfoObserverClient.currentSystemInfo()
        if let cpu = info.cpuInfo {
            cpuText = String(format: "CPU %.0f%%", cpu.percentage.value)
        }
        if let memory = info.memoryInfo {
            applyMemory(
                app: memory.app.byteCount,
                wired: memory.wired.byteCount,
                compressed: memory.compressed.byteCount,
                percentage: memory.percentage.value
            )
        }
        updateMetricViews()
    }

    private func applyMemory(
        app: Double,
        wired: Double,
        compressed: Double,
        percentage: Double
    ) {
        ramUsedBytes = app + wired + compressed
        ramTotalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        ramFraction = min(1.0, max(0.0, percentage / 100.0))
    }

    private func updateMetricViews() {
        cpuLabel?.stringValue = cpuText
        ramView?.update(
            usedBytes: ramUsedBytes,
            totalBytes: ramTotalBytes,
            fraction: ramFraction
        )
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

    private func startExpandedRefreshTimer() {
        expandedRefreshTimer?.invalidate()
        expandedRefreshTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(refreshExpandedContent),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopExpandedRefreshTimer() {
        expandedRefreshTimer?.invalidate()
        expandedRefreshTimer = nil
    }

    @objc private func advanceFrame() {
        guard !runnerFrames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % runnerFrames.count
        trayButton?.image = runnerFrames[frameIndex]
    }

    @objc private func reassertTrayPresence() {
        ensureTrayPresence()
    }

    @objc private func refreshExpandedContent() {
        guard isExpanded else { return }
        refreshMetricsFromObserver()
        refreshProcesses()
    }

    private func ensureTrayPresence() {
        guard isStarted, trayItem != nil else { return }
        privateAPI.setControlStripPresence(ItemID.tray, visible: true)
    }

    @objc private func showExpandedTouchBar() {
        isExpanded = true
        refreshMetricsFromObserver()
        refreshProcesses()
        startExpandedRefreshTimer()
        _ = privateAPI.present(expandedTouchBar, from: ItemID.tray)
        ensureTrayPresence()
    }

    @objc private func closeExpandedTouchBar() {
        isExpanded = false
        stopExpandedRefreshTimer()
        privateAPI.minimize(expandedTouchBar)
        ensureTrayPresence()
    }

    @objc private func refreshProcessesButtonPressed() {
        refreshMetricsFromObserver()
        refreshProcesses()
    }

    private func quitProcess(pid: pid_t) {
        guard pid > 1, pid != getpid() else { return }
        _ = ProcessSampler.terminate(pid: pid)
        refreshProcessesSoon()
    }

    private func forceKillProcess(pid: pid_t) {
        guard pid > 1, pid != getpid() else { return }
        _ = ProcessSampler.forceTerminate(pid: pid)
        refreshProcessesSoon()
    }

    private func refreshProcessesSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.refreshProcesses()
        }
    }

    private func refreshProcesses() {
        processRefreshTask?.cancel()
        processRefreshTask = Task { [weak self] in
            let entries = await Task.detached(priority: .utility) {
                ProcessSampler.topProcesses(limit: 16)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.topProcesses = entries
            self.processItem?.update(entries: entries)
        }
    }

    private func statusLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
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
private final class RAMUsageView: NSView {
    private let label = NSTextField(labelWithString: "RAM --/--GB")
    private let progress = NSProgressIndicator()

    override var intrinsicContentSize: NSSize {
        NSSize(width: 145, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 145, height: 30))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.alignment = .right
        label.lineBreakMode = .byClipping

        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0

        let stack = NSStackView(views: [label, progress])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        progress.widthAnchor.constraint(equalToConstant: 44).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 6).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(usedBytes: Double, totalBytes: Double, fraction: Double) {
        let gib = 1_073_741_824.0
        guard totalBytes > 0 else {
            label.stringValue = "RAM --/--GB"
            progress.doubleValue = 0
            return
        }
        label.stringValue = String(
            format: "RAM %.1f/%.1f",
            usedBytes / gib,
            totalBytes / gib
        )
        progress.doubleValue = min(1, max(0, fraction))
    }
}

@MainActor
private final class ProcessScrollTouchBarItem: NSCustomTouchBarItem {
    var onQuit: ((pid_t) -> Void)?
    var onForceKill: ((pid_t) -> Void)?

    private let scrollView = NSScrollView()

    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.widthAnchor.constraint(equalToConstant: 520).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        view = scrollView

        update(entries: [])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entries: [ProcessEntry]) {
        let oldX = scrollView.contentView.bounds.origin.x
        let views: [NSView]

        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "No active user processes")
            empty.font = .systemFont(ofSize: 11, weight: .medium)
            empty.textColor = .secondaryLabelColor
            views = [empty]
        } else {
            views = entries.map(makeProcessView)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 8)

        let fitting = stack.fittingSize
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: max(fitting.width, 520),
            height: 30
        )
        scrollView.documentView = stack
        scrollView.layoutSubtreeIfNeeded()

        let maxX = max(0, stack.frame.width - scrollView.contentSize.width)
        scrollView.contentView.scroll(to: NSPoint(x: min(oldX, maxX), y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func makeProcessView(entry: ProcessEntry) -> NSView {
        let shortName = String(entry.name.prefix(18))
        let label = NSTextField(
            labelWithString: String(format: "%@ %.0f%%", shortName, entry.cpu)
        )
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = "PID \(entry.pid) — \(entry.name)"
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true

        let quitImage = NSImage(
            systemSymbolName: "rectangle.portrait.and.arrow.right",
            accessibilityDescription: "Quit"
        )
        quitImage?.isTemplate = true
        let quit = NSButton(
            image: quitImage ?? NSImage(size: NSSize(width: 15, height: 15)),
            target: self,
            action: #selector(quitPressed(_:))
        )
        quit.tag = Int(entry.pid)
        configurePlainActionButton(quit)
        quit.setAccessibilityLabel("Quit \(entry.name)")

        let killImage = NSImage(
            systemSymbolName: "power",
            accessibilityDescription: "Force quit"
        )
        killImage?.isTemplate = true
        let kill = NSButton(
            image: killImage ?? NSImage(size: NSSize(width: 15, height: 15)),
            target: self,
            action: #selector(forceKillPressed(_:))
        )
        kill.tag = Int(entry.pid)
        kill.imagePosition = .imageOnly
        kill.imageScaling = .scaleProportionallyDown
        kill.imageHugsTitle = true
        kill.isBordered = true
        kill.bezelStyle = .rounded
        kill.bezelColor = .systemRed
        kill.contentTintColor = .white
        kill.controlSize = .small
        kill.widthAnchor.constraint(equalToConstant: 28).isActive = true
        kill.setAccessibilityLabel("Force quit \(entry.name)")

        let actions = NSStackView(views: [quit, kill])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 2

        let pair = NSStackView(views: [label, actions])
        pair.orientation = .horizontal
        pair.alignment = .centerY
        pair.spacing = 4
        return pair
    }

    private func configurePlainActionButton(_ button: NSButton) {
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = .white
        button.controlSize = .small
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @objc private func quitPressed(_ sender: NSButton) {
        onQuit?(pid_t(sender.tag))
    }

    @objc private func forceKillPressed(_ sender: NSButton) {
        onForceKill?(pid_t(sender.tag))
    }
}

private struct ProcessEntry: Sendable {
    let pid: pid_t
    let cpu: Double
    let name: String
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

            let command = String(fields[3])
            let name = URL(fileURLWithPath: command).lastPathComponent
            guard !name.isEmpty else { continue }
            entries.append(ProcessEntry(pid: pid, cpu: cpu, name: name))
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
