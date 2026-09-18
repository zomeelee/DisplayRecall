import AppKit
import Foundation
import OSLog
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case settling
        case saving
        case restoring
        case cooldown

        var label: String {
            switch self {
            case .idle: return "就绪"
            case .settling: return "等待显示器稳定"
            case .saving: return "正在保存"
            case .restoring: return "正在恢复"
            case .cooldown: return "恢复完成"
            }
        }
    }

    @Published private(set) var permissionGranted = false
    @Published private(set) var topologySummary = "正在检测显示器"
    @Published private(set) var hasExternalDisplay = false
    @Published private(set) var snapshotSummary: SnapshotSummary?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusMessage = "等待首次保存布局"
    @Published var autoRestore: Bool {
        didSet { defaults.set(autoRestore, forKey: Keys.autoRestore) }
    }
    @Published var restoreOnLaunch: Bool {
        didSet { defaults.set(restoreOnLaunch, forKey: Keys.restoreOnLaunch) }
    }
    @Published var restoreOnWake: Bool {
        didSet { defaults.set(restoreOnWake, forKey: Keys.restoreOnWake) }
    }
    @Published private(set) var launchAtLogin = false

    let store: LayoutStore

    private let defaults: UserDefaults
    private let accessibility: AccessibilityClient
    private let displayInventory: DisplayInventory
    private let displayMonitor: DisplayMonitor
    private let engine: RestoreEngine
    private let logger = Logger(subsystem: "com.zomeelee.DisplayRecall", category: "Restore")
    private var settleTask: Task<Void, Never>?
    private var permissionPollingTask: Task<Void, Never>?
    private var topologyWatchTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var started = false
    private var cooldownUntil = Date.distantPast
    private var observedTopologySignature = ""

    private enum Keys {
        static let autoRestore = "autoRestore"
        static let restoreOnLaunch = "restoreOnLaunch"
        static let restoreOnWake = "restoreOnWake"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accessibility = AccessibilityClient()
        displayInventory = DisplayInventory()
        displayMonitor = DisplayMonitor()
        store = LayoutStore()
        engine = RestoreEngine(accessibility: accessibility, displays: displayInventory)

        if defaults.object(forKey: Keys.autoRestore) == nil {
            defaults.set(true, forKey: Keys.autoRestore)
        }
        if defaults.object(forKey: Keys.restoreOnLaunch) == nil {
            defaults.set(true, forKey: Keys.restoreOnLaunch)
        }
        if defaults.object(forKey: Keys.restoreOnWake) == nil {
            defaults.set(true, forKey: Keys.restoreOnWake)
        }
        autoRestore = defaults.bool(forKey: Keys.autoRestore)
        restoreOnLaunch = defaults.bool(forKey: Keys.restoreOnLaunch)
        restoreOnWake = defaults.bool(forKey: Keys.restoreOnWake)

        start()
    }

    deinit {
        settleTask?.cancel()
        permissionPollingTask?.cancel()
        topologyWatchTask?.cancel()
        displayMonitor.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func start() {
        guard !started else {
            return
        }
        started = true

        displayMonitor.onConfigurationChanged = { [weak self] in
            self?.displayConfigurationChanged(reason: "显示器配置变化")
        }
        displayMonitor.start()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.restoreOnWake else { return }
                self.displayConfigurationChanged(reason: "Mac 已唤醒")
            }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionState()
            }
        }

        let initialTopology = refresh()
        observedTopologySignature = initialTopology.signature
        startTopologyWatch()
        if !permissionGranted {
            requestAccessibilityPermission()
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.restoreOnLaunch, self.autoRestore, self.hasExternalDisplay else {
                return
            }
            await self.restoreNow(trigger: "启动时自动恢复")
        }
    }

    @discardableResult
    func refresh() -> DisplayTopology {
        permissionGranted = accessibility.isTrusted
        let topology = displayInventory.capture()
        topologySummary = topology.summary
        hasExternalDisplay = topology.hasExternalDisplay
        snapshotSummary = store.summary()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        return topology
    }

    func requestAccessibilityPermission() {
        accessibility.requestTrustPrompt()
        statusMessage = "请在系统设置中开启 DisplayRecall 的辅助功能权限，App 会自动检测授权结果"
        refreshPermissionState()
        pollForAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
        pollForAccessibilityPermission()
    }

    func saveCurrentLayout() {
        guard phase == .idle || phase == .cooldown else {
            statusMessage = "显示器或窗口仍在变化，请稍后再保存"
            return
        }

        phase = .saving
        do {
            let snapshot = try engine.captureSnapshot()
            try store.save(snapshot)
            snapshotSummary = store.summary()
            statusMessage = "已保存 \(snapshot.windows.count) 个窗口；断开显示器后不会覆盖此布局"
        } catch {
            statusMessage = error.localizedDescription
        }
        phase = .idle
        refresh()
    }

    func restoreManually() {
        Task { [weak self] in
            await self?.restoreNow(trigger: "手动恢复")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = "开机启动设置失败：\(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func revealDataFolder() {
        do {
            try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } catch {
            statusMessage = "无法打开数据目录：\(error.localizedDescription)"
        }
    }

    private func refreshPermissionState() {
        let wasGranted = permissionGranted
        permissionGranted = accessibility.isTrusted
        if permissionGranted, !wasGranted {
            statusMessage = "辅助功能权限已启用，可以保存或恢复布局"
        }
    }

    private func pollForAccessibilityPermission() {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { [weak self] in
            for _ in 0..<120 {
                if Task.isCancelled { return }
                guard let self else { return }
                self.refreshPermissionState()
                if self.permissionGranted { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startTopologyWatch() {
        topologyWatchTask?.cancel()
        topologyWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                guard let self else { return }

                let topology = self.displayInventory.capture()
                guard topology.signature != self.observedTopologySignature else {
                    continue
                }
                self.observedTopologySignature = topology.signature
                self.logger.notice("Display topology change detected by watchdog")
                self.displayConfigurationChanged(reason: "检测到显示器配置变化")
            }
        }
    }

    private func displayConfigurationChanged(reason: String) {
        guard phase != .restoring, Date() >= cooldownUntil else {
            return
        }

        // 进入 settling 后不允许保存，避免把显示器断开后挤回主屏的窗口覆盖到正确快照。
        phase = .settling
        statusMessage = "\(reason)，正在等待系统窗口坐标稳定"
        logger.notice("Display configuration settling started")
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            guard let self else { return }
            var previousSignature = ""
            var stableSamples = 0

            for _ in 0..<20 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }

                let topology = self.displayInventory.capture()
                if topology.signature == previousSignature {
                    stableSamples += 1
                } else {
                    previousSignature = topology.signature
                    stableSamples = 0
                }

                if stableSamples >= 3 {
                    self.observedTopologySignature = topology.signature
                    self.topologySummary = topology.summary
                    self.hasExternalDisplay = topology.hasExternalDisplay
                    if topology.hasExternalDisplay, self.autoRestore {
                        self.logger.notice("Stable external display detected; starting automatic restore")
                        await self.restoreNow(trigger: "显示器接入后自动恢复")
                    } else {
                        self.phase = .idle
                        self.statusMessage = topology.hasExternalDisplay
                            ? "显示器已稳定，自动恢复已关闭"
                            : "外接显示器已断开；已保留原双屏布局"
                    }
                    return
                }
            }

            self.refresh()
            self.phase = .idle
            self.statusMessage = "显示器配置长时间未稳定，已取消本次自动恢复"
        }
    }

    private func restoreNow(trigger: String) async {
        guard phase != .restoring else {
            return
        }

        refresh()
        guard permissionGranted else {
            statusMessage = DisplayRecallError.accessibilityPermissionRequired.localizedDescription
            phase = .idle
            return
        }
        guard hasExternalDisplay else {
            statusMessage = DisplayRecallError.externalDisplayRequired.localizedDescription
            phase = .idle
            return
        }

        do {
            guard let snapshot = try store.load() else {
                throw DisplayRecallError.noSnapshot
            }
            phase = .restoring
            let topology = displayInventory.capture()
            let usesReplacement = topology.usesReplacementExternalDisplay(
                comparedTo: snapshot.displays
            )
            if usesReplacement {
                statusMessage = "\(trigger)：检测到另一台外接显示器，正在等待窗口稳定"
                logger.notice("Replacement external display detected; using delayed multi-pass restore")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } else {
                statusMessage = "\(trigger)：正在匹配窗口"
            }

            let maximumPasses = usesReplacement ? 3 : 1
            var bestReport: RestoreReport?
            for pass in 0..<maximumPasses {
                if pass > 0 {
                    statusMessage = "\(trigger)：正在执行第 \(pass + 1) 次恢复校正"
                    let delay: UInt64 = pass == 1 ? 900_000_000 : 1_800_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }

                let report = try await engine.restore(snapshot)
                logger.notice(
                    "Restore pass \(pass + 1): matched=\(report.matchedWindowCount), restored=\(report.restoredWindowCount), failed=\(report.failedWindowCount)"
                )
                if bestReport == nil ||
                    report.restoredWindowCount > bestReport!.restoredWindowCount ||
                    (report.restoredWindowCount == bestReport!.restoredWindowCount &&
                        report.matchedWindowCount > bestReport!.matchedWindowCount) {
                    bestReport = report
                }

                if !usesReplacement ||
                    (report.matchedWindowCount > 0 && report.failedWindowCount == 0) {
                    break
                }
            }

            guard let report = bestReport else {
                throw DisplayRecallError.noWindows
            }
            let prefix = usesReplacement ? "已跨显示器恢复" : "已恢复"
            statusMessage = "\(prefix) \(report.restoredWindowCount)/\(report.savedWindowCount) 个窗口，匹配到 \(report.matchedWindowCount) 个"
            if report.failedWindowCount > 0 {
                statusMessage += "，\(report.failedWindowCount) 个窗口被应用拒绝或位置受限"
            }
            phase = .cooldown
            cooldownUntil = Date().addingTimeInterval(1.5)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            phase = .idle
        } catch {
            statusMessage = error.localizedDescription
            phase = .idle
        }
        refresh()
    }
}
