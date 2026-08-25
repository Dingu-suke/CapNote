import AppKit
import SwiftUI

/// アプリ全体のオーケストレーション。
/// 録画 (カウントダウン→録画→停止→出力)・スクショ・出力先処理をここで束ねる。
@MainActor
final class AppState: ObservableObject {
    enum Route: Equatable {
        case home
        case editor(imagePath: String)
    }

    @Published var route: Route = .home
    @Published var recPhase: RecPhase = .idle
    @Published var toast: Toast?
    @Published var displays: [DisplayItem] = DisplayItem.current()
    @Published var screenRecordingGranted = true
    @Published var accessibilityGranted = true
    @Published var microphoneGranted = true
    @Published var settings = AppSettings.load() {
        didSet {
            settings.save()
            if settings.appearance != oldValue.appearance { applyAppearance() }
            if settings.hotkeyRecord != oldValue.hotkeyRecord
                || settings.hotkeyScreenshot != oldValue.hotkeyScreenshot {
                applyHotkeys()
            }
        }
    }

    weak var mainWindow: NSWindow?

    private let recorder = RecorderService()
    private let ripple = ClickRippleService()
    private let screenshot = ScreenshotService()
    private let stopBar = FloatingStopBar()
    private let statusBar = StatusBarController()
    private let countdown = CountdownOverlay()
    private let regionIndicator = RegionIndicatorWindow()
    private var toastTask: Task<Void, Never>?

    init() {
        stopBar.onStop = { [weak self] in Task { @MainActor in self?.stopRecording() } }
        statusBar.onStop = { [weak self] in Task { @MainActor in self?.stopRecording() } }
        recorder.onStreamError = { [weak self] reason in
            // ディスプレイ抜け・上限時間: そこまでの録画を保存して止める
            Task { @MainActor in self?.stopRecording(reason: reason) }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.displays = DisplayItem.current() }
        }
        applyAppearance()
        applyHotkeys()
        refreshPermissions(promptIfNeeded: true)
    }

    // MARK: - テーマ / ショートカット

    func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    func applyHotkeys() {
        HotkeyManager.shared.set(id: 1, hotkey: settings.hotkeyRecord) { [weak self] in
            self?.toggleRecording()
        }
        HotkeyManager.shared.set(id: 2, hotkey: settings.hotkeyScreenshot) { [weak self] in
            self?.takeScreenshot()
        }
    }

    /// ホットキー用: 録画中なら停止、そうでなければ開始
    func toggleRecording() {
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - 権限

    func refreshPermissions(promptIfNeeded: Bool = false) {
        let p = PermissionService.check()
        screenRecordingGranted = p["screenRecording"] ?? false
        accessibilityGranted = p["accessibility"] ?? false
        microphoneGranted = p["microphone"] ?? false
        if promptIfNeeded && !screenRecordingGranted {
            // 初回プロンプト。付与するとmacOSがアプリを終了させるので再起動が必要
            screenRecordingGranted = PermissionService.requestScreenRecording()
        }
    }

    // MARK: - 録画

    var isBusy: Bool { recPhase != .idle }

    func startRecording() {
        guard !isBusy, !recorder.isRecording else { return }
        refreshPermissions()
        guard screenRecordingGranted else {
            showToast(Toast(message: "画面収録の権限がありません。設定から許可してください", isError: true))
            return
        }

        Task { @MainActor in
            var config = RecordConfig()
            let s = settings
            config.fps = s.fps
            config.scale = s.resolution.rawValue
            config.showCursor = s.showCursor
            config.outputTarget = s.outputTarget.rawValue
            config.saveDirectory = s.movieDirectory
            config.fileName = "rec_\(timestampNow()).mp4"
            config.maxMinutes = s.maxMinutes
            config.captureSystemAudio = s.captureSystemAudio
            config.captureMicrophone = s.captureMicrophone

            // 範囲選択 (切り取り)
            var screen: NSScreen
            switch s.scopeType {
            case .region:
                self.hideMainWindow()
                guard let sel = await screenshot.selectRegion(),
                      let selScreen = DisplayService.screen(for: sel.displayId) else {
                    restoreMainWindow()
                    return // キャンセル
                }
                config.displayId = sel.displayId
                config.region = sel.rect
                screen = selScreen
            case .display:
                let id = CGDirectDisplayID(s.displayId ?? Int(CGMainDisplayID()))
                screen = DisplayService.screen(for: id) ?? NSScreen.main!
                config.displayId = DisplayService.displayID(of: screen)
            case .fullScreen:
                screen = NSScreen.main!
                config.displayId = DisplayService.displayID(of: screen)
            }

            self.ripple.config = s.ripple.config
            self.hideMainWindow() // アプリウィンドウは録画に写さない
            // 範囲録画: どこを録画しているか分かるよう範囲外を暗くする (キャプチャからは除外)
            if let region = config.region {
                self.regionIndicator.show(on: screen, regionTopLeft: region)
            }
            self.recPhase = .countdown
            self.countdown.run(on: screen) {
                Task { @MainActor in
                    do {
                        self.stopBar.show(
                            on: screen,
                            systemAudio: config.captureSystemAudio,
                            mic: config.captureMicrophone,
                            levels: { [weak self] in
                                self?.recorder.readLevels() ?? (nil, nil)
                            }
                        )
                        self.statusBar.showRecording()
                        var excluded: [Int] = []
                        if let n = self.stopBar.windowNumber { excluded.append(n) }
                        if let n = self.regionIndicator.windowNumber { excluded.append(n) }
                        try await self.recorder.start(config: config, excludingWindowNumbers: excluded)
                        self.activeConfig = config
                        self.ripple.start() // 波紋は録画中のみ (ON/OFFは設定で判定)
                        self.recPhase = .recording
                    } catch {
                        self.stopBar.hide()
                        self.statusBar.hide()
                        self.regionIndicator.hide()
                        self.recPhase = .idle
                        self.restoreMainWindow()
                        self.showToast(Toast(message: "録画を開始できませんでした: \(error.localizedDescription)", isError: true))
                    }
                }
            }
        }
    }

    private var activeConfig: RecordConfig?

    func stopRecording(reason: String? = nil) {
        guard recorder.isRecording else { return }
        let config = activeConfig
        activeConfig = nil
        Task { @MainActor in
            self.ripple.stop()
            self.stopBar.hide()
            self.statusBar.hide()
            self.regionIndicator.hide()
            self.recPhase = .encoding
            do {
                let tempPath = try await self.recorder.stop()
                let output = try OutputService.finalize(
                    tempPath: tempPath,
                    target: OutputTarget(rawValue: config?.outputTarget ?? "clipboard") ?? .clipboard,
                    directory: config?.saveDirectory,
                    fileName: config?.fileName,
                    defaultSubdir: "Movies/mp4recorder"
                )
                self.recPhase = .idle
                self.restoreMainWindow()
                let clip = output.target == .clipboard
                self.showToast(Toast(
                    message: clip
                        ? "録画をコピーしました。GitHub PR に Cmd+V で添付できます"
                        : "録画を保存しました",
                    path: output.path
                ))
            } catch {
                self.recPhase = .idle
                self.restoreMainWindow()
                self.showToast(Toast(message: "録画の保存に失敗しました: \(error.localizedDescription)", isError: true))
            }
        }
    }

    // MARK: - スクショ

    func takeScreenshot() {
        guard !isBusy else { return }
        if case .editor = route { return } // 編集中は多重起動しない
        refreshPermissions()
        guard screenRecordingGranted else {
            showToast(Toast(message: "画面収録の権限がありません。設定から許可してください", isError: true))
            return
        }
        hideMainWindow()
        Task { @MainActor in
            do {
                let outcome = try await self.screenshot.interactiveCapture()
                self.restoreMainWindow()
                guard let outcome else { return } // キャンセル
                if outcome.quick {
                    // クイックモード (Shift+確定): 注釈スキップで即出力
                    let out = try OutputService.finalize(
                        tempPath: outcome.path,
                        target: self.settings.outputTarget,
                        directory: self.settings.pictureDirectory,
                        fileName: "shot_\(timestampNow()).png",
                        defaultSubdir: "Pictures/mp4recorder",
                        asImage: true
                    )
                    self.showToast(Toast(
                        message: out.target == .clipboard
                            ? "スクショをコピーしました (クイックモード)"
                            : "スクショを保存しました (クイックモード)",
                        path: out.path
                    ))
                } else {
                    self.route = .editor(imagePath: outcome.path)
                }
            } catch {
                self.restoreMainWindow()
                self.showToast(Toast(message: "スクショに失敗しました: \(error.localizedDescription)", isError: true))
            }
        }
    }

    /// 注釈エディタからの出力 (合成済みPNG)
    func outputAnnotated(cgImage: CGImage, target: OutputTarget) {
        do {
            guard let temp = ScreenshotService.writePNG(cgImage, prefix: "annotated") else {
                throw RecorderError.writerFailed
            }
            let out = try OutputService.finalize(
                tempPath: temp,
                target: target,
                directory: settings.pictureDirectory,
                fileName: "shot_\(timestampNow()).png",
                defaultSubdir: "Pictures/mp4recorder",
                asImage: true
            )
            route = .home
            showToast(Toast(
                message: out.target == .clipboard
                    ? "スクショをコピーしました。Cmd+V で PR に貼れます"
                    : "スクショを保存しました",
                path: out.path
            ))
        } catch {
            showToast(Toast(message: "出力に失敗しました: \(error.localizedDescription)", isError: true))
        }
    }

    // MARK: - 波紋プレビュー

    func previewRipple() {
        ripple.config = settings.ripple.config
        ripple.preview()
    }

    // MARK: - Helper

    /// メインウィンドウを隠す間は「最後のウィンドウが閉じた→終了」の自動判定を止める
    private func hideMainWindow() {
        AppDelegate.suppressAutoTerminate = true
        mainWindow?.orderOut(nil)
    }

    private func restoreMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.suppressAutoTerminate = false
    }

    func showToast(_ t: Toast) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, self.toast?.id == t.id { self.toast = nil }
        }
    }
}

/// 出力共通: clipboard = 参照コピー (画像は中身コピー) / file = 保存先へ移動 + Finderで表示
enum OutputService {
    static func finalize(
        tempPath: String, target: OutputTarget, directory: String?, fileName: String?,
        defaultSubdir: String, asImage: Bool = false
    ) throws -> (path: String, target: OutputTarget) {
        switch target {
        case .file:
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dirURL = directory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                ?? home.appendingPathComponent(defaultSubdir)
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let ext = (tempPath as NSString).pathExtension
            let name = fileName ?? (tempPath as NSString).lastPathComponent
            var dest = dirURL.appendingPathComponent(name)
            if dest.pathExtension.isEmpty { dest = dest.appendingPathExtension(ext) }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: URL(fileURLWithPath: tempPath), to: dest)
            ClipboardService.revealInFinder(path: dest.path)
            return (dest.path, target)
        case .clipboard:
            let ok = asImage
                ? ClipboardService.copyImage(path: tempPath)
                : ClipboardService.copyFileURL(path: tempPath)
            if !ok { throw RecorderError.writerFailed }
            return (tempPath, target)
        }
    }
}
