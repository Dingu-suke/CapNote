import AppKit
import QuartzCore

/// クリック波紋の設定 (docs/features/click-ripple.md)
struct RippleConfig {
    var style: String = "ring" // ring | filledCircle | doubleRing | highlight
    var color: NSColor = .systemYellow
    var size: CGFloat = 40
    var durationMs: Int = 700
    var enabled: Bool = true

    static func from(_ dict: [String: Any]?) -> RippleConfig {
        var c = RippleConfig()
        guard let d = dict else { return c }
        c.style = d["style"] as? String ?? c.style
        if let hex = d["colorHex"] as? String, let col = NSColor(hexString: hex) { c.color = col }
        if let s = d["size"] as? Double { c.size = CGFloat(s) }
        if let ms = d["durationMs"] as? Int { c.durationMs = ms }
        c.enabled = d["enabled"] as? Bool ?? c.enabled
        return c
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let a = hasAlpha ? CGFloat((v >> 24) & 0xFF) / 255 : 1
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: a
        )
    }
}

/// 透明・クリック透過のオーバーレイ。波紋描画用に全ディスプレイに1枚ずつ置く。
/// キャプチャに「写す」必要があるので sharingType は既定のまま。
final class RippleOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        contentView = v
        orderFrontRegardless()
    }
}

@MainActor
final class ClickRippleService {
    private var overlays: [RippleOverlayWindow] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: Any?
    var config = RippleConfig()

    var isActive: Bool { globalMonitor != nil }

    func start() {
        guard !isActive else { return }
        buildOverlays()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            self?.handle(ev)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            self?.handle(ev)
            return ev
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.buildOverlays()
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func buildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { RippleOverlayWindow(screen: $0) }
    }

    private func handle(_ ev: NSEvent) {
        // 右クリックは色違い (推奨仕様)
        let isRight = ev.type == .rightMouseDown
        show(at: NSEvent.mouseLocation, color: isRight ? config.color.withSystemBlueFallback() : config.color)
    }

    /// 設定画面のプレビュー用: 現在のマウス位置に1発出す
    func preview() {
        let hadOverlays = !overlays.isEmpty
        if !hadOverlays { buildOverlays() }
        show(at: NSEvent.mouseLocation, color: config.color)
        if !hadOverlays {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(config.durationMs) / 1000 + 0.5) { [weak self] in
                guard let self, !self.isActive else { return }
                self.overlays.forEach { $0.orderOut(nil) }
                self.overlays = []
            }
        }
    }

    /// point はグローバル座標 (左下原点)
    private func show(at point: NSPoint, color: NSColor) {
        guard config.enabled else { return }
        guard let window = overlays.first(where: { $0.frame.contains(point) }) ?? overlays.first,
              let layerHost = window.contentView?.layer else { return }
        let local = CGPoint(x: point.x - window.frame.origin.x, y: point.y - window.frame.origin.y)
        let duration = Double(config.durationMs) / 1000

        switch config.style {
        case "filledCircle":
            addCircle(to: layerHost, at: local, radius: config.size * 0.75, color: color, filled: true,
                      duration: duration, scaleFrom: 0.6, opacityFrom: 0.5)
        case "doubleRing":
            addRing(to: layerHost, at: local, maxRadius: config.size, color: color, duration: duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak layerHost] in
                guard let host = layerHost else { return }
                self.addRing(to: host, at: local, maxRadius: self.config.size, color: color, duration: duration)
            }
        case "highlight":
            addHighlight(to: layerHost, at: local, radius: config.size * 0.6, color: color, duration: duration)
        default: // ring
            addRing(to: layerHost, at: local, maxRadius: config.size, color: color, duration: duration)
        }
    }

    private func makeShape(at point: CGPoint, radius: CGFloat, color: NSColor, filled: Bool) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        layer.path = CGPath(ellipseIn: rect, transform: nil)
        layer.position = point
        if filled {
            layer.fillColor = color.cgColor
            layer.strokeColor = nil
        } else {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = 4
        }
        return layer
    }

    private func addRing(to host: CALayer, at point: CGPoint, maxRadius: CGFloat, color: NSColor, duration: Double) {
        let layer = makeShape(at: point, radius: maxRadius, color: color, filled: false)
        host.addSublayer(layer)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.2
        scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = 5.0
        thin.toValue = 1.0
        animate(layer, [scale, fade, thin], duration: duration)
    }

    private func addCircle(to host: CALayer, at point: CGPoint, radius: CGFloat, color: NSColor, filled: Bool,
                           duration: Double, scaleFrom: CGFloat, opacityFrom: Float) {
        let layer = makeShape(at: point, radius: radius, color: color, filled: filled)
        host.addSublayer(layer)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = scaleFrom
        scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacityFrom
        fade.toValue = 0.0
        animate(layer, [scale, fade], duration: duration)
    }

    /// クリック位置に一定時間スポット表示してじわっと消える
    private func addHighlight(to host: CALayer, at point: CGPoint, radius: CGFloat, color: NSColor, duration: Double) {
        let layer = makeShape(at: point, radius: radius, color: color, filled: true)
        layer.opacity = 0.55
        host.addSublayer(layer)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.55, 0.55, 0.0]
        fade.keyTimes = [0, 0.4, 1.0]
        animate(layer, [fade], duration: duration)
    }

    private func animate(_ layer: CALayer, _ animations: [CAAnimation], duration: Double) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.opacity = 0 // アニメーション終了後のちらつき防止 (表示はアニメーション側で行う)
        layer.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}

private extension NSColor {
    /// 右クリック用の識別色 (設定色が青系なら黄に倒す)
    func withSystemBlueFallback() -> NSColor {
        let rgb = usingColorSpace(.sRGB) ?? self
        return rgb.blueComponent > 0.6 && rgb.redComponent < 0.5 ? .systemYellow : .systemBlue
    }
}
