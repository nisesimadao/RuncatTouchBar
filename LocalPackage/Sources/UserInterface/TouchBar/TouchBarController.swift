/*
 TouchBarController.swift
 RuncatTouchBar

 A tiny Activity Monitor for the Touch Bar: the selected RunCat runner lives in
 the Control Strip, follows the existing CPU-driven animation speed, and opens
 an expanded CPU/RAM/process view when tapped.
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
        static let cpu = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.cpu")
        static let ram = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.ram")
        static let refresh = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.refresh")
        static let close = NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.close")
        static let processes = (0..<3).map {
            NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.process.\($0)")
        }
        static let quitButtons = (0..<3).map {
            NSTouchBarItem.Identifier("dev.nisesimadao.RuncatTouchBar.quit.\($0)")
        }
    }

    private let appStateClient = AppDependencies.shared.appStateClient
    private let privateAPI = TouchBarPrivateAPI.shared

    private var isStarted = false
    private var trayItem: NSCustomTouchBarItem?
    private var trayButton: NSButton?
    private var animationTimer: Timer?
    private var streamTasks = [Task<Void, Never>]()
    private var processRefreshTask: Task<Void, Never>?

    private var runnerFrames = [NSImage]()
    private var runnerSpeed: Float = 1.0
    private var frameIndex = 0

    private var cpuText = "CPU --%"
    private var ramText = "RAM --"
    private var topProcesses = [ProcessEntry]()

    private weak var cpuLabel: NSTextField?
    private weak var ramLabel: NSTextField?
    private var processLabels = [NSTextField?](repeating: nil, count: 3)
    private var quitButtons = [NSButton?](repeating: nil, count: 3)

    private lazy var expandedTouchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            ItemID.cpu,
            ItemID.ram,
            .flexibleSpace,
            ItemID.refresh,
            ItemID.processes[0], ItemID.quitButtons[0],
            ItemID.processes[1], ItemID.quitButtons[1],
            ItemID.processes[2], ItemID.quitButtons[2],
            ItemID.close,
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
        let button = NSButton(image: fallbackRunnerImage(), target: self, action: #selector(showExpandedTouchBar))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.setAccessibilityLabel("RunCat system monitor")
        item.view = button
        trayItem = item
        trayButton = button

        privateAPI.setSystemModalCloseBoxVisible(true)
        guard privateAPI.addSystemTrayItem(item) else {
            trayItem = nil
            trayButton = nil
            isStarted = false
            return
        }
        privateAPI.setControlStripPresence(ItemID.tray, visible: true)

        applyInitialState()
        subscribeToRunCatState()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false

        animationTimer?.invalidate()
        animationTimer = nil
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
        if identifier == ItemID.cpu {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = statusLabel(cpuText)
            cpuLabel = label
            item.view = label
            return item
        }

        if identifier == ItemID.ram {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = statusLabel(ramText)
            ramLabel = label
            item.view = label
            return item
        }

        if identifier == ItemID.refresh {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                title: "↻",
                target: self,
                action: #selector(refreshProcessesButtonPressed)
            )
            button.setAccessibilityLabel("Refresh process list")
            item.view = button
            return item
        }

        if identifier == ItemID.close {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                title: "×",
                target: self,
                action: #selector(closeExpandedTouchBar)
            )
            button.setAccessibilityLabel("Close RunCat system monitor")
            item.view = button
            return item
        }

        if let index = ItemID.processes.firstIndex(of: identifier) {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = statusLabel(processTitle(at: index))
            processLabels[index] = label
            item.view = label
            return item
        }

        if let index = ItemID.quitButtons.firstIndex(of: identifier) {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                title: "Quit",
                target: self,
                action: #selector(quitProcessButtonPressed(_:))
            )
            button.tag = index
            button.isEnabled = index < topProcesses.count
            button.setAccessibilityLabel("Quit process")
            quitButtons[index] = button
            item.view = button
            return item
        }

        return nil
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
            let usedBytes = memory.app.byteCount + memory.wired.byteCount + memory.compressed.byteCount
            let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            let gib = 1_073_741_824.0
            ramText = String(
                format: "RAM %.1f/%.1fGB %.0f%%",
                usedBytes / gib,
                totalBytes / gib,
                memory.percentage.value
            )
        }
        cpuLabel?.stringValue = cpuText
        ramLabel?.stringValue = ramText
    }

    private func restartAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard runnerFrames.count > 1, isStarted else { return }

        // RunCat Neo's RunnerLayer uses 0.5 s per frame at speed 1.0.
        let interval = max(0.025, 0.5 / Double(runnerSpeed))
        animationTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func advanceFrame() {
        guard !runnerFrames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % runnerFrames.count
        trayButton?.image = runnerFrames[frameIndex]
    }

    @objc private func showExpandedTouchBar() {
        refreshProcesses()
        _ = privateAPI.present(expandedTouchBar, from: ItemID.tray)
    }

    @objc private func closeExpandedTouchBar() {
        privateAPI.dismiss(expandedTouchBar)
    }

    @objc private func refreshProcessesButtonPressed() {
        refreshProcesses()
    }

    @objc private func quitProcessButtonPressed(_ sender: NSButton) {
        guard topProcesses.indices.contains(sender.tag) else { return }
        let entry = topProcesses[sender.tag]
        guard entry.pid > 1, entry.pid != getpid() else { return }
        _ = ProcessSampler.terminate(pid: entry.pid)
        refreshProcesses()
    }

    private func refreshProcesses() {
        processRefreshTask?.cancel()
        processRefreshTask = Task { [weak self] in
            let entries = await Task.detached(priority: .utility) {
                ProcessSampler.topProcesses(limit: 3)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.topProcesses = entries
            self.updateProcessViews()
        }
    }

    private func updateProcessViews() {
        for index in 0..<3 {
            processLabels[index]?.stringValue = processTitle(at: index)
            quitButtons[index]?.isEnabled = index < topProcesses.count
        }
    }

    private func processTitle(at index: Int) -> String {
        guard topProcesses.indices.contains(index) else { return "—" }
        let entry = topProcesses[index]
        let shortName = String(entry.name.prefix(18))
        return String(format: "%@ %.0f%%", shortName, entry.cpu)
    }

    private func statusLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
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
        image.isTemplate = isTemplate
        return image
    }

    private func fallbackRunnerImage() -> NSImage {
        let image = NSImage(
            systemSymbolName: "hare.fill",
            accessibilityDescription: "RunCat"
        ) ?? NSImage(size: NSSize(width: 22, height: 18))
        image.isTemplate = true
        return image
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
                  let cpu = Double(fields[2]) else {
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
}
