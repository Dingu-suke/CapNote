import AppKit

/// 録画中に画面下部中央に出す停止バー (`[■ 停止] 00:23 ● REC`)。
/// このウィンドウはキャプチャから除外する (RecorderService側で windowNumber を除外指定)。
@MainActor
final class FloatingStopBar {
    private var panel: NSPanel?
    private var timeLabel: NSTextField?
    private var timer: Timer?
    private var levelTimer: Timer?
    private var startedAt: Date?
    private var systemMeter: AudioMeterView?
    private var micMeter: AudioMeterView?
    var onStop: (() -> Void)?

    var windowNumber: Int? { panel?.windowNumber }

    /// systemAudio / mic: 録音中のソース。メーターは常時2つ表示し、OFFのものは斜線アイコンで消灯
    func show(
        on screen: NSScreen,
        systemAudio: Bool = false,
        mic: Bool = false,
        levels: (() -> (system: Float?, mic: Float?))? = nil
    ) {
        hide()
        let meterWidth: CGFloat = 56
        let width: CGFloat = 220 + meterWidth * 2
        let height: CGFloat = 44
        let rect = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.minY + 32,
            width: width, height: height
        )
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1) // 波紋オーバーレイより上
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        let stopButton = NSButton(title: "■ 停止", target: self, action: #selector(stopPressed))
        stopButton.bezelStyle = .rounded
        stopButton.frame = NSRect(x: 12, y: 8, width: 78, height: 28)

        let time = NSTextField(labelWithString: "00:00")
        time.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        time.textColor = .labelColor
        time.frame = NSRect(x: 100, y: 13, width: 54, height: 18)

        let rec = NSTextField(labelWithString: "● REC")
        rec.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        rec.textColor = .systemRed
        rec.frame = NSRect(x: 160, y: 14, width: 52, height: 16)

        container.addSubview(stopButton)
        container.addSubview(time)
        container.addSubview(rec)

        // 音声レベルメーター (常時2つ。OFFは斜線アイコン+消灯で「入っていない」ことを示す)
        let sysM = AudioMeterView(
            symbol: "speaker.wave.2.fill", disabledSymbol: "speaker.slash.fill",
            enabled: systemAudio,
            frame: NSRect(x: 212, y: 12, width: meterWidth - 6, height: 20)
        )
        container.addSubview(sysM)
        systemMeter = sysM
        let micM = AudioMeterView(
            symbol: "mic.fill", disabledSymbol: "mic.slash.fill",
            enabled: mic,
            frame: NSRect(x: 212 + meterWidth, y: 12, width: meterWidth - 6, height: 20)
        )
        container.addSubview(micM)
        micMeter = micM

        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.timeLabel = time
        self.startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let started = self.startedAt else { return }
            let sec = Int(Date().timeIntervalSince(started))
            self.timeLabel?.stringValue = String(format: "%02d:%02d", sec / 60, sec % 60)
        }
        if let levels, systemAudio || mic {
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                let v = levels()
                self.systemMeter?.setRMS(v.system ?? 0)
                self.micMeter?.setRMS(v.mic ?? 0)
            }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        panel?.orderOut(nil)
        panel = nil
        timeLabel = nil
        systemMeter = nil
        micMeter = nil
        startedAt = nil
    }

    @objc private func stopPressed() {
        onStop?()
    }
}

/// 停止バー内の小さな音声レベルメーター (アイコン + 横バー)。
/// 音が入っているかの確認用なので厳密なdB表示はしない。
final class AudioMeterView: NSView {
    private let fill = CALayer()
    private let track = CALayer()
    private let enabled: Bool
    private var displayLevel: Float = 0
    private let barX: CGFloat = 21
    private var barWidth: CGFloat { bounds.width - barX }

    init(symbol: String, disabledSymbol: String, enabled: Bool, frame: NSRect) {
        self.enabled = enabled
        super.init(frame: frame)
        wantsLayer = true

        let icon = NSImageView(frame: NSRect(x: 0, y: 2, width: 17, height: 16))
        icon.image = NSImage(
            systemSymbolName: enabled ? symbol : disabledSymbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        // ON = ティール (録音中) / OFF = 赤の斜線 (入っていない) — Discord風に一目で分かる配色
        icon.contentTintColor = enabled
            ? NSColor(hexRGB: 0x2BD9A9)
            : NSColor(hexRGB: 0xFF5D5D).withAlphaComponent(0.9)
        addSubview(icon)

        track.frame = NSRect(x: barX, y: bounds.height / 2 - 2, width: barWidth, height: 4)
        track.backgroundColor = enabled
            ? NSColor.white.withAlphaComponent(0.15).cgColor
            : NSColor(hexRGB: 0xFF5D5D).withAlphaComponent(0.12).cgColor // OFF: 薄い赤で消灯
        track.cornerRadius = 2
        layer?.addSublayer(track)

        if enabled {
            fill.frame = NSRect(x: barX, y: bounds.height / 2 - 2, width: 0, height: 4)
            fill.backgroundColor = NSColor(hexRGB: 0x2BD9A9).cgColor
            fill.cornerRadius = 2
            layer?.addSublayer(fill)
        }

        toolTip = enabled ? "録音中" : "録音していません (ホームでON/OFF)"
    }

    required init?(coder: NSCoder) { fatalError() }

    /// RMS (0〜1) を対数スケールでバー表示。立ち上がりは即時、下がりは滑らかに
    func setRMS(_ rms: Float) {
        guard enabled else { return }
        let db = 20 * log10(max(rms, 1e-5))
        let target = max(0, min(1, (db + 50) / 50)) // -50dB〜0dB を 0〜1 に
        displayLevel = max(target, displayLevel * 0.7)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        fill.frame.size.width = barWidth * CGFloat(displayLevel)
        CATransaction.commit()
    }
}

/// メニューバーの録画停止アイコン
@MainActor
final class StatusBarController {
    private var item: NSStatusItem?
    var onStop: (() -> Void)?

    func showRecording() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "録画停止")
            button.contentTintColor = .systemRed
            button.target = self
            button.action = #selector(stopPressed)
        }
        self.item = item
    }

    func hide() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func stopPressed() {
        onStop?()
    }
}

/// 録画開始前の 3・2・1 カウントダウン表示
@MainActor
final class CountdownOverlay {
    private var window: NSWindow?

    func run(on screen: NSScreen, seconds: Int = 3, completion: @escaping () -> Void) {
        let size: CGFloat = 160
        let rect = NSRect(
            x: screen.frame.midX - size / 2,
            y: screen.frame.midY - size / 2,
            width: size, height: size
        )
        let win = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: rect.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        container.layer?.cornerRadius = size / 2

        let label = NSTextField(labelWithString: "\(seconds)")
        label.font = NSFont.systemFont(ofSize: 80, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = container.bounds.insetBy(dx: 0, dy: (size - 96) / 2)
        container.addSubview(label)
        win.contentView = container
        win.orderFrontRegardless()
        window = win

        var remaining = seconds
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                self?.window?.orderOut(nil)
                self?.window = nil
                completion()
            } else {
                label.stringValue = "\(remaining)"
            }
        }
    }
}
