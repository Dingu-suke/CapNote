import AppKit
import SwiftUI

/// 注釈ツール
enum AnnotTool: CaseIterable {
    case select, rect, ellipse, line, arrow, freehand, text, badge, blur

    var label: String {
        switch self {
        case .select: return "選択"
        case .rect: return "矩形"
        case .ellipse: return "楕円"
        case .line: return "直線"
        case .arrow: return "矢印"
        case .freehand: return "フリーハンド"
        case .text: return "テキスト"
        case .badge: return "番号バッジ"
        case .blur: return "ぼかし"
        }
    }

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .freehand: return "pencil.line"
        case .text: return "textformat"
        case .badge: return "1.circle"
        case .blur: return "drop.halffull"
        }
    }
}

/// 注釈オブジェクト。座標は元画像のピクセル座標系。
/// 値型なので Undo/Redo は配列スナップショットで済む。
struct Annot: Identifiable, Equatable {
    var id = UUID()
    var color: Color
    var strokeWidth: CGFloat // 論理値 (細=2 / 中=3.5 / 太=6)。unitを掛けて描画
    var kind: Kind

    enum Kind: Equatable {
        case rect(CGRect)
        case ellipse(CGRect)
        case line(CGPoint, CGPoint)
        case arrow(CGPoint, CGPoint)
        case freehand([CGPoint])
        case text(CGPoint, String, CGFloat) // 位置(左上)・内容・フォントサイズ
        case badge(CGPoint, Int) // 中心・番号
        case blur(CGRect)
    }

    // MARK: - 幾何

    func translated(by d: CGSize) -> Annot {
        var a = self
        func mv(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        func mv(_ r: CGRect) -> CGRect { r.offsetBy(dx: d.width, dy: d.height) }
        switch kind {
        case .rect(let r): a.kind = .rect(mv(r))
        case .ellipse(let r): a.kind = .ellipse(mv(r))
        case .line(let s, let e): a.kind = .line(mv(s), mv(e))
        case .arrow(let s, let e): a.kind = .arrow(mv(s), mv(e))
        case .freehand(let pts): a.kind = .freehand(pts.map(mv))
        case .text(let p, let t, let f): a.kind = .text(mv(p), t, f)
        case .badge(let p, let n): a.kind = .badge(mv(p), n)
        case .blur(let r): a.kind = .blur(mv(r))
        }
        return a
    }

    func bounds(unit: CGFloat) -> CGRect {
        switch kind {
        case .rect(let r), .ellipse(let r), .blur(let r):
            return r.standardized
        case .line(let s, let e), .arrow(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(s.x - e.x), height: abs(s.y - e.y))
        case .freehand(let pts):
            guard let first = pts.first else { return .zero }
            var r = CGRect(origin: first, size: .zero)
            for p in pts {
                r = r.union(CGRect(origin: p, size: .zero))
            }
            return r
        case .text(let p, let t, let f):
            let size = Annot.measureText(t, fontSize: f * unit)
            return CGRect(origin: p, size: size)
        case .badge(let p, _):
            let r = badgeRadius(unit: unit)
            return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        }
    }

    func badgeRadius(unit: CGFloat) -> CGFloat { (14 + strokeWidth * 2) * unit }

    static func measureText(_ text: String, fontSize: CGFloat) -> CGSize {
        let attr = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
        )
        let s = attr.size()
        return CGSize(width: ceil(s.width), height: ceil(s.height))
    }

    /// tol は「画面上で押しやすい距離」を画像座標に換算した値 (エディタ側で 10/fit 等を渡す)。
    /// 矩形・楕円は内部クリックでも選択できる (Awesome Screenshot と同じ操作感)。
    func hitTest(_ p: CGPoint, unit: CGFloat, tol: CGFloat) -> Bool {
        let tol = max(tol, (strokeWidth + 4) * unit)
        switch kind {
        case .rect(let raw), .blur(let raw):
            return raw.standardized.insetBy(dx: -tol, dy: -tol).contains(p)
        case .ellipse(let raw):
            let r = raw.standardized
            guard r.width > 1, r.height > 1 else { return false }
            let nx = (p.x - r.midX) / (r.width / 2 + tol)
            let ny = (p.y - r.midY) / (r.height / 2 + tol)
            return nx * nx + ny * ny <= 1
        case .line(let s, let e), .arrow(let s, let e):
            return Annot.nearSegment(p, s, e, tol)
        case .freehand(let pts):
            for i in 0..<max(0, pts.count - 1) {
                if Annot.nearSegment(p, pts[i], pts[i + 1], tol) { return true }
            }
            return false
        case .text, .badge:
            return bounds(unit: unit).insetBy(dx: -tol, dy: -tol).contains(p)
        }
    }

    // MARK: - リサイズハンドル

    enum Handle {
        case tl, tr, bl, br // 矩形系の四隅
        case p1, p2 // 直線・矢印の両端
    }

    /// 選択中に表示・掴めるハンドル位置 (画像座標)
    func handles(unit: CGFloat) -> [(handle: Handle, point: CGPoint)] {
        switch kind {
        case .rect(let raw), .ellipse(let raw), .blur(let raw):
            let r = raw.standardized
            return [
                (.tl, CGPoint(x: r.minX, y: r.minY)),
                (.tr, CGPoint(x: r.maxX, y: r.minY)),
                (.bl, CGPoint(x: r.minX, y: r.maxY)),
                (.br, CGPoint(x: r.maxX, y: r.maxY)),
            ]
        case .line(let a, let b), .arrow(let a, let b):
            return [(.p1, a), (.p2, b)]
        case .freehand, .text, .badge:
            return [] // 移動のみ (テキストはダブルクリックで再編集)
        }
    }

    /// ハンドルを p までドラッグしたときの変形
    mutating func applyHandle(_ h: Handle, to p: CGPoint) {
        func resized(_ raw: CGRect) -> CGRect {
            let r = raw.standardized
            let anchor: CGPoint
            switch h {
            case .tl: anchor = CGPoint(x: r.maxX, y: r.maxY)
            case .tr: anchor = CGPoint(x: r.minX, y: r.maxY)
            case .bl: anchor = CGPoint(x: r.maxX, y: r.minY)
            case .br: anchor = CGPoint(x: r.minX, y: r.minY)
            case .p1, .p2: return r
            }
            return CGRect(
                x: min(anchor.x, p.x), y: min(anchor.y, p.y),
                width: abs(anchor.x - p.x), height: abs(anchor.y - p.y)
            )
        }
        switch kind {
        case .rect(let r): kind = .rect(resized(r))
        case .ellipse(let r): kind = .ellipse(resized(r))
        case .blur(let r): kind = .blur(resized(r))
        case .line(let a, let b): kind = h == .p1 ? .line(p, b) : .line(a, p)
        case .arrow(let a, let b): kind = h == .p1 ? .arrow(p, b) : .arrow(a, p)
        case .freehand, .text, .badge: break
        }
    }

    static func nearSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ tol: CGFloat) -> Bool {
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        var t: CGFloat = len2 == 0 ? 0 : ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2
        t = min(max(t, 0), 1)
        let proj = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
        return hypot(p.x - proj.x, p.y - proj.y) <= tol
    }

    /// ドラッグ量が小さすぎる描き損じを捨てる
    var isMeaningful: Bool {
        switch kind {
        case .rect(let r), .ellipse(let r), .blur(let r):
            return r.standardized.width > 3 || r.standardized.height > 3
        case .line(let s, let e), .arrow(let s, let e):
            return hypot(e.x - s.x, e.y - s.y) > 3
        case .freehand(let pts):
            return pts.count > 1
        case .text, .badge:
            return true
        }
    }
}

/// 表示・書き出しで共用する描画。座標系は画像ピクセル (呼び出し側でスケールする)。
enum AnnotRenderer {
    static func draw(
        _ ctx: inout GraphicsContext,
        annots: [Annot],
        image: Image,
        imageSize: CGSize,
        unit: CGFloat
    ) {
        for a in annots {
            drawOne(&ctx, a, image: image, imageSize: imageSize, unit: unit)
        }
    }

    static func drawOne(
        _ ctx: inout GraphicsContext,
        _ a: Annot,
        image: Image,
        imageSize: CGSize,
        unit: CGFloat
    ) {
        let stroke = StrokeStyle(lineWidth: a.strokeWidth * unit, lineCap: .round, lineJoin: .round)
        switch a.kind {
        case .rect(let r):
            ctx.stroke(Path(r.standardized), with: .color(a.color), style: stroke)

        case .ellipse(let r):
            ctx.stroke(Path(ellipseIn: r.standardized), with: .color(a.color), style: stroke)

        case .line(let s, let e):
            var p = Path()
            p.move(to: s)
            p.addLine(to: e)
            ctx.stroke(p, with: .color(a.color), style: stroke)

        case .arrow(let s, let e):
            var p = Path()
            p.move(to: s)
            p.addLine(to: e)
            let angle = atan2(e.y - s.y, e.x - s.x)
            let headLen = (10 + a.strokeWidth * 2.5) * unit
            let headAngle: CGFloat = .pi / 7
            let h1 = CGPoint(x: e.x - cos(angle - headAngle) * headLen,
                             y: e.y - sin(angle - headAngle) * headLen)
            let h2 = CGPoint(x: e.x - cos(angle + headAngle) * headLen,
                             y: e.y - sin(angle + headAngle) * headLen)
            p.move(to: e)
            p.addLine(to: h1)
            p.move(to: e)
            p.addLine(to: h2)
            ctx.stroke(p, with: .color(a.color), style: stroke)

        case .freehand(let pts):
            guard pts.count > 1 else { break }
            var p = Path()
            p.move(to: pts[0])
            for pt in pts.dropFirst() {
                p.addLine(to: pt)
            }
            ctx.stroke(p, with: .color(a.color), style: stroke)

        case .text(let pos, let str, let fontSize):
            let t = Text(str)
                .font(.system(size: fontSize * unit, weight: .semibold))
                .foregroundColor(a.color)
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5 * unit,
                                        x: unit, y: unit))
                layer.draw(t, at: pos, anchor: .topLeading)
            }

        case .badge(let center, let n):
            let r = a.badgeRadius(unit: unit)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(a.color))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2 * unit)
            ctx.draw(
                Text("\(n)").font(.system(size: r * 1.05, weight: .bold)).foregroundColor(.white),
                at: center, anchor: .center
            )

        case .blur(let raw):
            let r = raw.standardized
            guard !r.isEmpty else { break }
            ctx.drawLayer { layer in
                layer.clip(to: Path(r))
                layer.addFilter(.blur(radius: 10 * unit))
                layer.draw(image, in: CGRect(origin: .zero, size: imageSize))
            }
        }
    }
}
