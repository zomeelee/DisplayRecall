import AppKit
import Foundation
import OSLog
import ServiceManagement

enum AutomaticRestoreRetryPolicy {
    // Some applications do not expose their windows to Accessibility until well after
    // macOS has finished publishing the replacement display topology.
    static let delaysInSeconds: [UInt64] = [4, 8, 15, 25, 40, 60]
    static let minimumAttemptsBeforeAcceptingStablePartialResult = 3

    static func shouldRetry(_ report: RestoreReport) -> Bool {
        report.needsAutomaticRetry
    }

    static func shouldAcceptStablePartialResult(
        _ report: RestoreReport,
        attemptCount: Int,
        consecutiveAttemptsWithoutProgress: Int
    ) -> Bool {
        report.matchedWindowCount > 0 &&
            report.failedWindowCount == 0 &&
            attemptCount >= minimumAttemptsBeforeAcceptingStablePartialResult &&
            consecutiveAttemptsWithoutProgress >= 2
    }
}

enum ImmediateRestorePassPolicy {
    static func shouldStop(
        usesReplacementDisplay: Bool,
        report: RestoreReport
    ) -> Bool {
        guard usesReplacementDisplay else {
            return true
        }
        return !report.needsAutomaticRetry
    }
}

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

        var allowsManualRestore: Bool {
            self == .idle || self == .cooldown
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
    private let commandStatusStore: CommandStatusStore
    private let accessibility: AccessibilityClient
    private let displayInventory: DisplayInventory
    private let displayMonitor: DisplayMonitor
    private let engine: RestoreEngine
    private let logger = Logger(subsystem: "com.zomeelee.DisplayRecall", category: "Restore")
    private var settleTask: Task<Void, Never>?
    private var automaticRetryTask: Task<Void, Never>?
    private var permissionPollingTask: Task<Void, Never>?
    private var topologyWatchTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var commandURLObserver: NSObjectProtocol?
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
        let layoutStore = LayoutStore()
        store = layoutStore
        commandStatusStore = CommandStatusStore(directoryURL: layoutStore.directoryURL)
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
        automaticRetryTask?.cancel()
        permissionPollingTask?.cancel()
        topologyWatchTask?.cancel()
        displayMonitor.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let commandURLObserver {
            NotificationCenter.default.removeObserver(commandURLObserver)
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

        commandURLObserver = NotificationCenter.default.addObserver(
            forName: .displayRecallCommandURLReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleCommandURL(url)
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
            let report = await self.restoreNow(trigger: "启动时自动恢复")
            if let report, AutomaticRestoreRetryPolicy.shouldRetry(report) {
                self.scheduleAutomaticRetry(
                    reason: "启动时仍有窗口尚未恢复",
                    initialReport: report
                )
            }
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

    @discardableResult
    func saveCurrentLayout() -> Bool {
        guard phase == .idle || phase == .cooldown else {
            statusMessage = "显示器或窗口仍在变化，请稍后再保存"
            return false
        }

        phase = .saving
        var succeeded = false
        do {
            let snapshot = try engine.captureSnapshot()
            try store.save(snapshot)
            snapshotSummary = store.summary()
            statusMessage = "已保存 \(snapshot.windows.count) 个窗口；断开显示器后不会覆盖此布局"
            succeeded = true
        } catch {
            statusMessage = error.localizedDescription
        }
        phase = .idle
        refresh()
        return succeeded
    }

    func restoreManually(
        completion: (@MainActor (RestoreReport?) -> Void)? = nil
    ) {
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
        Task { [weak self] in
            guard let self else {
                completion?(nil)
                return
            }
            guard await self.waitUntilManualRestoreCanStart() else {
                completion?(nil)
                return
            }
            let report = await self.restoreNow(trigger: "手动恢复")
            completion?(report)
        }
    }

    func handleCommandURL(_ url: URL) {
        guard let request = DisplayRecallCommandRequest(url: url) else {
            logger.error("Rejected unsupported command URL")
            return
        }

        switch request.action {
        case .status:
            refresh()
            writeCommandStatus(
                request: request,
                state: .completed,
                message: statusMessage
            )
        case .save:
            let succeeded = saveCurrentLayout()
            writeCommandStatus(
                request: request,
                state: succeeded ? .completed : .failed,
                message: statusMessage
            )
        case .restore:
            writeCommandStatus(
                request: request,
                state: .pending,
                message: "已收到恢复命令，正在匹配窗口"
            )
            restoreManually { [weak self] report in
                guard let self else { return }
                self.writeCommandStatus(
                    request: request,
                    state: report == nil ? .failed : .completed,
                    message: self.statusMessage,
                    report: report
                )
            }
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

    private func waitUntilManualRestoreCanStart() async -> Bool {
        for _ in 0..<240 {
            if phase.allowsManualRestore {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                statusMessage = "手动恢复已取消"
                return false
            }
        }
        statusMessage = "等待当前显示器恢复结束超时，请稍后再试"
        return false
    }

    private func writeCommandStatus(
        request: DisplayRecallCommandRequest,
        state: DisplayRecallCommandStatus.State,
        message: String,
        report: RestoreReport? = nil
    ) {
        let summary = store.summary()
        let status = DisplayRecallCommandStatus(
            requestID: request.requestID,
            command: request.action,
            state: state,
            message: message,
            updatedAt: Date(),
            permissionGranted: permissionGranted,
            hasExternalDisplay: hasExternalDisplay,
            savedWindowCount: summary?.windowCount,
            savedAt: summary?.savedAt,
            externalDisplayName: summary?.externalDisplayName,
            matchedWindowCount: report?.matchedWindowCount,
            restoredWindowCount: report?.restoredWindowCount,
            failedWindowCount: report?.failedWindowCount
        )
        do {
            try commandStatusStore.save(status)
        } catch {
            logger.error("Unable to save command status: \(error.localizedDescription, privacy: .public)")
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

        automaticRetryTask?.cancel()
        automaticRetryTask = nil

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
                        let report = await self.restoreNow(trigger: "显示器接入后自动恢复")
                        if let report, AutomaticRestoreRetryPolicy.shouldRetry(report) {
                            self.scheduleAutomaticRetry(
                                reason: "显示器接入后仍有窗口尚未恢复",
                                initialReport: report
                            )
                        }
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

    private func scheduleAutomaticRetry(reason: String, initialReport: RestoreReport) {
        automaticRetryTask?.cancel()
        statusMessage = "\(reason)，将在后台继续自动重试"
        logger.notice(
            "Automatic restore incomplete (saved=\(initialReport.savedWindowCount), matched=\(initialReport.matchedWindowCount), restored=\(initialReport.restoredWindowCount), failed=\(initialReport.failedWindowCount)); scheduling background retries"
        )

        automaticRetryTask = Task { [weak self] in
            var bestMatchedCount = initialReport.matchedWindowCount
            var bestRestoredCount = initialReport.restoredWindowCount
            var consecutiveAttemptsWithoutProgress = 0

            for (attempt, delay) in AutomaticRestoreRetryPolicy.delaysInSeconds.enumerated() {
                do {
                    try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self, self.autoRestore else {
                    return
                }

                let topology = self.refresh()
                guard topology.hasExternalDisplay else {
                    return
                }

                while self.phase != .idle {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                }

                self.logger.notice("Starting automatic restore background retry \(attempt + 1)")
                let report = await self.restoreNow(trigger: "显示器接入后自动重试")
                guard let report else {
                    continue
                }

                let madeProgress = report.matchedWindowCount > bestMatchedCount ||
                    report.restoredWindowCount > bestRestoredCount
                if madeProgress {
                    bestMatchedCount = max(bestMatchedCount, report.matchedWindowCount)
                    bestRestoredCount = max(bestRestoredCount, report.restoredWindowCount)
                    consecutiveAttemptsWithoutProgress = 0
                } else {
                    consecutiveAttemptsWithoutProgress += 1
                }

                if !AutomaticRestoreRetryPolicy.shouldRetry(report) {
                    self.logger.notice(
                        "Automatic restore background retry completed all \(report.savedWindowCount) windows"
                    )
                    return
                }

                if AutomaticRestoreRetryPolicy.shouldAcceptStablePartialResult(
                    report,
                    attemptCount: attempt + 1,
                    consecutiveAttemptsWithoutProgress: consecutiveAttemptsWithoutProgress
                ) {
                    self.statusMessage = "已恢复当前可访问的 \(bestRestoredCount) 个窗口；其余保存窗口当前未出现"
                    self.logger.notice(
                        "Automatic restore stabilized at matched=\(bestMatchedCount), restored=\(bestRestoredCount) after \(attempt + 1) retries"
                    )
                    return
                }
            }

            guard let self, !Task.isCancelled else { return }
            if bestMatchedCount > 0 {
                self.statusMessage = "已恢复当前可访问的 \(bestRestoredCount) 个窗口；仍有保存窗口未出现或受应用限制"
                self.logger.notice(
                    "Automatic restore retries exhausted at matched=\(bestMatchedCount), restored=\(bestRestoredCount)"
                )
            } else {
                self.statusMessage = "自动恢复暂未发现可访问窗口；切换到对应桌面后可点击手动恢复"
                self.logger.notice("Automatic restore background retries exhausted without a window match")
            }
        }
    }

    @discardableResult
    private func restoreNow(trigger: String) async -> RestoreReport? {
        guard phase != .restoring else {
            return nil
        }

        refresh()
        guard permissionGranted else {
            statusMessage = DisplayRecallError.accessibilityPermissionRequired.localizedDescription
            phase = .idle
            return nil
        }
        guard hasExternalDisplay else {
            statusMessage = DisplayRecallError.externalDisplayRequired.localizedDescription
            phase = .idle
            return nil
        }

        var completedReport: RestoreReport?
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

                // During a display replacement, applications can republish their AX
                // windows at different times. A partial match with no write failures is
                // still partial and must not end the immediate correction passes.
                if ImmediateRestorePassPolicy.shouldStop(
                    usesReplacementDisplay: usesReplacement,
                    report: report
                ) {
                    break
                }
            }

            guard let report = bestReport else {
                throw DisplayRecallError.noWindows
            }
            completedReport = report
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
        return completedReport
    }
}
