import AppKit

/// 範囲選択の結果。rect はディスプレイローカル・左上原点・論理座標。
struct SelectionResult {
    let screen: NSScreen
    let rect: CGRect
    /// Shiftを押しながら確定 = クイックモード (注釈スキップ)
    let quick: Bool
}

/// Cmd+Shift+4 風の範囲選択オーバーレイ。全ディスプレイに暗幕を出し、ドラッグで矩形選択。
/// - freezeImages を渡すとフリーズ画像の上で選択できる (スクショ用。選択中に画面が動かない)
/// - nil なら暗幕のみ (録画の範囲選択用)
/// NSWindow の生成・破棄を伴うためメインスレッド専用 (@MainActor)。
@MainActor
final class SelectionSession {
    private var windows: [SelectionWindow] = []
    private var keyMonitor: Any?
    private var completion: ((SelectionResult?) -> Void)?
    private var finished = false

    func begin(freezeImages: [CGDirectDisplayID: CGImage]?, completion: @escaping (SelectionResult?) -> Void) {
        self.completion = completion
        self.finished = false
        windows = NSScreen.screens.map { screen in
            let image = freezeImages?[DisplayService.displayID(of: screen)]
            return SelectionWindow(screen: screen, freezeImage: image, session: self)
        }
        windows.forEach { $0.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        // Escでキャンセル
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 { // Esc
                self?.finish(nil)
                return nil
            }
            return ev
        }
    }

    func finish(_ result: SelectionResult?) {
        guard !finished else { return }
        finished = true
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        let cb = completion
        completion = nil
        cb?(result)
    }
}

final class SelectionWindow: NSWindow {
    init(screen: NSScreen, freezeImage: CGImage?, session: SelectionSession) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = freezeImage != nil
        // 暗幕のみモード (録画の範囲選択) は下の画面が透けるように .clear にする。
        // .black のままだと画面全体が真っ黒になり選択できない
        backgroundColor = freezeImage != nil ? .black : .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        contentView = SelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen, freezeImage: freezeImage, session: session
        )
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    private let targetScreen: NSScreen
    private let freezeImage: CGImage?
    private weak var session: SelectionSession?
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?

    init(frame: NSRect, screen: NSScreen, freezeImage: CGImage?, session: SelectionSession) {
        self.targetScreen = screen
        self.freezeImage = freezeImage
        self.session = session
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
    }

    private var selectionRect: NSRect? {
        guard let s = dragStart, let c = dragCurrent else { return nil }
        return NSRect(
            x: min(s.x, c.x), y: min(s.y, c.y),
            width: abs(s.x - c.x), height: abs(s.y - c.y)
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragCurrent = nil; needsDisplay = true }
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else { return } // 誤クリック対策
        // 左上原点へ変換
        let topLeft = CGRect(
            x: rect.origin.x,
            y: bounds.height - rect.maxY,
            width: rect.width, height: rect.height
        )
        session?.finish(SelectionResult(
            screen: targetScreen,
            rect: topLeft,
            quick: event.modifierFlags.contains(.shift)
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current!.cgContext
        if let image = freezeImage {
            ctx.draw(image, in: bounds) // フリーズ画像 (選択中に画面が動かない)
        }
        // 暗幕 (選択領域だけくり抜く)
        ctx.setFillColor(NSColor.black.withAlphaComponent(freezeImage != nil ? 0.4 : 0.25).cgColor)
        if let sel = selectionRect {
            ctx.beginPath()
            ctx.addRect(bounds)
            ctx.addRect(sel)
            ctx.fillPath(using: .evenOdd)
            // 選択枠と背景 (フリーズ画像を明るく見せる)
            if let image = freezeImage {
                ctx.saveGState()
                ctx.clip(to: sel)
                ctx.draw(image, in: bounds)
                ctx.restoreGState()
            }
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel(for: sel)
        } else {
            ctx.fill(bounds)
        }
    }

    private func drawSizeLabel(for sel: NSRect) {
        let scale = targetScreen.backingScaleFactor
        let text = "\(Int(sel.width * scale)) × \(Int(sel.height * scale)) px"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        var origin = NSPoint(x: sel.maxX - size.width - 8, y: sel.minY - size.height - 10)
        if origin.y < 4 { origin.y = sel.minY + 8 }
        if origin.x < 4 { origin.x = sel.minX + 4 }
        let bg = NSRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attrs)
    }
}
