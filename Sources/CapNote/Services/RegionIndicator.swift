import AppKit

/// 範囲録画中に「どこを録画しているか」を示すオーバーレイ。
/// 範囲外を薄暗くし、範囲の境界に枠線を出す。
/// このウィンドウは SCContentFilter の除外に入れるので録画には写らない。
@MainActor
final class RegionIndicatorWindow {
    private var window: NSWindow?

    var windowNumber: Int? { window?.windowNumber }

    /// regionTopLeft: ディスプレイローカル・左上原点・論理座標
    func show(on screen: NSScreen, regionTopLeft: CGRect) {
        hide()
        let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .screenSaver
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 左上原点 → AppKitローカル (左下原点)
        let local = CGRect(
            x: regionTopLeft.minX,
            y: screen.frame.height - regionTopLeft.maxY,
            width: regionTopLeft.width,
            height: regionTopLeft.height
        )
        win.contentView = RegionIndicatorView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            region: local
        )
        win.orderFrontRegardless()
        window = win
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

final class RegionIndicatorView: NSView {
    private let region: CGRect

    init(frame: NSRect, region: CGRect) {
        self.region = region
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 範囲外を薄暗く
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.beginPath()
        ctx.addRect(bounds)
        ctx.addRect(region)
        ctx.fillPath(using: .evenOdd)
        // 境界線 (このウィンドウごとキャプチャ除外なので写らない)
        ctx.setStrokeColor(NSColor(hexRGB: 0x2BD9A9).withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(region.insetBy(dx: -1, dy: -1))
    }
}
