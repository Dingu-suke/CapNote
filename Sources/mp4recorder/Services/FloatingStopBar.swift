import AppKit

/// 録画中に画面下部中央に出す停止バー (`[■ 停止] 00:23 ● REC`)。
/// このウィンドウはキャプチャから除外する (RecorderService側で windowNumber を除外指定)。
@MainActor
final class FloatingStopBar {
    private var panel: NSPanel?
    private var timeLabel: NSTextField?
    private var timer: Timer?
    private var startedAt: Date?
    var onStop: (() -> Void)?

    var windowNumber: Int? { panel?.windowNumber }

    func show(on screen: NSScreen) {
        hide()
        let width: CGFloat = 220, height: CGFloat = 44
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
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        timeLabel = nil
        startedAt = nil
    }

    @objc private func stopPressed() {
        onStop?()
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
