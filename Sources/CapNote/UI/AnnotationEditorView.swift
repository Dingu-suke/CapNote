import AppKit
import SwiftUI

/// S-4: 注釈エディタ (Awesome Screenshot 踏襲)。
/// 注釈は元画像のピクセル座標で持ち、表示時にフィットスケール、書き出しはピクセル等倍。
struct AnnotationEditorView: View {
    let imagePath: String
    @EnvironmentObject private var app: AppState

    @State private var cgImage: CGImage?
    @State private var annots: [Annot] = []
    @State private var undoStack: [[Annot]] = []
    @State private var redoStack: [[Annot]] = []
    @State private var draft: Annot?
    @State private var selectedId: UUID?
    @State private var cropRect: CGRect?
    @State private var cropDraft: CGRect?
    @State private var cropMode = false

    @State private var tool: AnnotTool = .rect
    @State private var color: Color = Brand.palette[0] // 赤
    @State private var strokeWidth: CGFloat = 3.5
    @State private var fontSize: CGFloat = 16

    @State private var dragStart: CGPoint?
    @State private var lastDrag: CGPoint?
    @State private var movedSelection = false
    @State private var textSheet: TextSheetState?
    @State private var confirmDiscard = false

    /// 進行中ドラッグの種別 (選択ツール: ハンドルリサイズ / 移動 を区別)
    private enum DragOp: Equatable {
        case none, draw, move
        case resize(Annot.Handle)
    }

    @State private var dragOp: DragOp = .none

    struct TextSheetState: Identifiable {
        let id = UUID()
        var position: CGPoint
        var editingId: UUID? // 既存テキストの再編集
        var text: String
    }

    /// 画像幅に応じた描画係数 (Retinaでも見た目の太さを揃える)
    private var unit: CGFloat {
        guard let img = cgImage else { return 1 }
        return max(1, CGFloat(img.width) / 1400)
    }

    private var imageSize: CGSize {
        guard let img = cgImage else { return .zero }
        return CGSize(width: img.width, height: img.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Brand.border)
            canvasArea
            Divider().overlay(Brand.border)
            bottomBar
        }
        .background(Brand.bg)
        .onAppear(perform: load)
        .sheet(item: $textSheet) { sheet in
            TextInputSheet(state: sheet) { result in
                applyText(sheet: sheet, text: result)
            }
        }
        .confirmationDialog("注釈を破棄しますか?", isPresented: $confirmDiscard) {
            Button("破棄する", role: .destructive) { app.route = .home }
            Button("編集に戻る", role: .cancel) {}
        } message: {
            Text("コピー・保存せずに閉じると注釈は失われます。")
        }
    }

    private func load() {
        guard let dataProvider = CGDataProvider(filename: imagePath),
              let img = CGImage(
                  pngDataProviderSource: dataProvider,
                  decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else {
            app.route = .home
            app.showToast(Toast(message: "画像を読み込めませんでした", isError: true))
            return
        }
        cgImage = img
    }

    // MARK: - Undo / Redo

    private func pushUndo() {
        undoStack.append(annots)
        redoStack.removeAll()
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(annots)
        annots = last
        selectedId = nil
    }

    private func redo() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(annots)
        annots = last
        selectedId = nil
    }

    private func deleteSelected() {
        guard let id = selectedId else { return }
        pushUndo()
        annots.removeAll { $0.id == id }
        selectedId = nil
        renumberBadges()
    }

    /// バッジ削除時に ①②③… を振り直す
    private func renumberBadges() {
        var n = 1
        for i in annots.indices {
            if case .badge(let p, _) = annots[i].kind {
                annots[i].kind = .badge(p, n)
                n += 1
            }
        }
    }

    private var nextBadgeNumber: Int {
        annots.filter { if case .badge = $0.kind { return true } else { return false } }.count + 1
    }

    // MARK: - ツールバー

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button {
                if annots.isEmpty { app.route = .home } else { confirmDiscard = true }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.textLo)
            }
            .buttonStyle(.plain)
            .help("戻る")

            Divider().frame(height: 18).overlay(Brand.border)

            ForEach(AnnotTool.allCases, id: \.self) { t in
                toolButton(t)
            }

            Divider().frame(height: 18).overlay(Brand.border)

            // 色パレット
            ForEach(Array(Brand.palette.enumerated()), id: \.offset) { _, c in
                Button {
                    color = c
                    if let id = selectedId, let i = annots.firstIndex(where: { $0.id == id }) {
                        pushUndo()
                        annots[i].color = c
                    }
                } label: {
                    Circle()
                        .fill(c)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(
                            color == c ? Brand.tealA : Brand.border,
                            lineWidth: color == c ? 2 : 1
                        ))
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 18).overlay(Brand.border)

            // 線の太さ
            BrandSegmented(
                items: [(CGFloat(2), "細", nil), (CGFloat(3.5), "中", nil), (CGFloat(6), "太", nil)],
                selection: Binding(
                    get: { strokeWidth },
                    set: { v in
                        strokeWidth = v
                        if let id = selectedId, let i = annots.firstIndex(where: { $0.id == id }) {
                            pushUndo()
                            annots[i].strokeWidth = v
                        }
                    }
                )
            )

            if tool == .text {
                Text("文字 \(Int(fontSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textLo)
                Slider(value: $fontSize, in: 10...48, step: 2)
                    .frame(width: 90)
                    .tint(Brand.teal)
            }

            Spacer()

            if selectedId != nil {
                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xFF7A6B))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: [])
                .help("選択を削除 (Delete)")
            }

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
                    .foregroundStyle(undoStack.isEmpty ? Brand.textLo.opacity(0.35) : Brand.text)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(undoStack.isEmpty)
            .help("元に戻す (Cmd+Z)")

            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12))
                    .foregroundStyle(redoStack.isEmpty ? Brand.textLo.opacity(0.35) : Brand.text)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(redoStack.isEmpty)
            .help("やり直す (Cmd+Shift+Z)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolButton(_ t: AnnotTool) -> some View {
        Button {
            tool = t
            if t != .select { selectedId = nil }
        } label: {
            Image(systemName: t.icon)
                .font(.system(size: 13))
                .foregroundStyle(tool == t ? Brand.tealA : Brand.textLo)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tool == t ? Brand.teal.opacity(0.18) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(t.label)
    }

    // MARK: - キャンバス

    private var canvasArea: some View {
        GeometryReader { geo in
            if let img = cgImage {
                let fit = min(
                    (geo.size.width - 32) / CGFloat(img.width),
                    (geo.size.height - 32) / CGFloat(img.height)
                )
                let dispW = CGFloat(img.width) * fit
                let dispH = CGFloat(img.height) * fit
                canvas(img: img, fit: fit)
                    .frame(width: dispW, height: dispH)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            } else {
                ProgressView()
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.canvasBg)
    }

    private func canvas(img: CGImage, fit: CGFloat) -> some View {
        let swiftImage = Image(decorative: img, scale: 1)
        return Canvas { ctx, _ in
            ctx.scaleBy(x: fit, y: fit)
            ctx.draw(swiftImage, in: CGRect(origin: .zero, size: imageSize))
            AnnotRenderer.draw(&ctx, annots: annots, image: swiftImage, imageSize: imageSize, unit: unit)
            if let d = draft {
                AnnotRenderer.drawOne(&ctx, d, image: swiftImage, imageSize: imageSize, unit: unit)
            }
            // 選択ハイライト + リサイズハンドル (線の太さは画面ピクセル基準 = /fit)
            if let id = selectedId, let sel = annots.first(where: { $0.id == id }) {
                let b = sel.bounds(unit: unit).insetBy(dx: -6 * unit, dy: -6 * unit)
                ctx.stroke(
                    Path(b), with: .color(Brand.tealA),
                    style: StrokeStyle(lineWidth: 1.5 / fit, dash: [4 / fit, 3 / fit])
                )
                let hs = 9 / fit
                for h in sel.handles(unit: unit) {
                    let r = CGRect(x: h.point.x - hs / 2, y: h.point.y - hs / 2, width: hs, height: hs)
                    ctx.fill(Path(ellipseIn: r), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: r), with: .color(Brand.tealA), lineWidth: 1.5 / fit)
                }
            }
            // トリミング範囲外を暗く
            if let crop = (cropDraft ?? cropRect)?.standardized {
                var p = Path(CGRect(origin: .zero, size: imageSize))
                p.addRect(crop)
                ctx.fill(p, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                ctx.stroke(Path(crop), with: .color(.white), lineWidth: 1.5 * unit)
            }
        }
        .gesture(dragGesture(fit: fit))
        .highPriorityGesture(doubleTapGesture(fit: fit))
    }

    // MARK: - ジェスチャ (画像ピクセル座標に変換して処理)

    private func toImage(_ p: CGPoint, fit: CGFloat) -> CGPoint {
        CGPoint(x: p.x / fit, y: p.y / fit)
    }

    private func dragGesture(fit: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = toImage(v.location, fit: fit)
                if dragStart == nil {
                    dragStart = toImage(v.startLocation, fit: fit)
                    lastDrag = dragStart
                    onDragBegan(at: dragStart!, tol: hitTolerance(fit: fit))
                }
                onDragChanged(to: p)
                lastDrag = p
            }
            .onEnded { v in
                let start = toImage(v.startLocation, fit: fit)
                let end = toImage(v.location, fit: fit)
                let isTap = hypot(end.x - start.x, end.y - start.y) * fit < 3
                onDragEnded(at: end, isTap: isTap, tol: hitTolerance(fit: fit))
                dragStart = nil
                lastDrag = nil
            }
    }

    /// クリック許容距離: 画面上で約10pxに相当する画像座標の距離
    private func hitTolerance(fit: CGFloat) -> CGFloat {
        10 / max(fit, 0.01)
    }

    private func doubleTapGesture(fit: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { v in
                let p = toImage(v.location, fit: fit)
                let tol = hitTolerance(fit: fit)
                // テキストをダブルクリック → 再編集
                if let hit = annots.reversed().first(where: { $0.hitTest(p, unit: unit, tol: tol) }),
                   case .text(let pos, let str, _) = hit.kind {
                    textSheet = TextSheetState(position: pos, editingId: hit.id, text: str)
                }
            }
    }

    private func onDragBegan(at p: CGPoint, tol: CGFloat) {
        if cropMode {
            cropDraft = CGRect(origin: p, size: .zero)
            return
        }
        switch tool {
        case .select:
            movedSelection = false
            // 選択中の要素のハンドルを掴んだらリサイズ
            if let id = selectedId, let sel = annots.first(where: { $0.id == id }),
               let h = sel.handles(unit: unit)
                   .first(where: { hypot($0.point.x - p.x, $0.point.y - p.y) <= tol * 1.4 })?.handle {
                dragOp = .resize(h)
                return
            }
            if let hit = annots.reversed().first(where: { $0.hitTest(p, unit: unit, tol: tol) }) {
                selectedId = hit.id
                dragOp = .move
            } else {
                selectedId = nil
                dragOp = .none
            }
        case .rect:
            draft = Annot(color: color, strokeWidth: strokeWidth, kind: .rect(CGRect(origin: p, size: .zero)))
        case .ellipse:
            draft = Annot(color: color, strokeWidth: strokeWidth, kind: .ellipse(CGRect(origin: p, size: .zero)))
        case .line:
            draft = Annot(color: color, strokeWidth: strokeWidth, kind: .line(p, p))
        case .arrow:
            draft = Annot(color: color, strokeWidth: strokeWidth, kind: .arrow(p, p))
        case .freehand:
            draft = Annot(color: color, strokeWidth: strokeWidth, kind: .freehand([p]))
        case .blur:
            draft = Annot(color: color, strokeWidth: strokeWidth, kind: .blur(CGRect(origin: p, size: .zero)))
        case .text, .badge:
            break // タップで処理
        }
    }

    private func onDragChanged(to p: CGPoint) {
        guard let start = dragStart else { return }
        if cropMode {
            cropDraft = rect(from: start, to: p)
            return
        }
        switch tool {
        case .select:
            guard let id = selectedId, let i = annots.firstIndex(where: { $0.id == id }) else { return }
            switch dragOp {
            case .resize(let h):
                if !movedSelection {
                    pushUndo() // 変形開始時に1回だけ積む
                    movedSelection = true
                }
                annots[i].applyHandle(h, to: p)
            case .move:
                guard let last = lastDrag else { return }
                if !movedSelection {
                    pushUndo()
                    movedSelection = true
                }
                annots[i] = annots[i].translated(by: CGSize(width: p.x - last.x, height: p.y - last.y))
            default:
                break
            }
        case .rect:
            draft?.kind = .rect(rect(from: start, to: p))
        case .ellipse:
            draft?.kind = .ellipse(rect(from: start, to: p))
        case .line:
            draft?.kind = .line(start, p)
        case .arrow:
            draft?.kind = .arrow(start, p)
        case .freehand:
            if case .freehand(var pts) = draft?.kind {
                pts.append(p)
                draft?.kind = .freehand(pts)
            }
        case .blur:
            draft?.kind = .blur(rect(from: start, to: p))
        case .text, .badge:
            break
        }
    }

    private func onDragEnded(at p: CGPoint, isTap: Bool, tol: CGFloat) {
        defer { dragOp = .none }
        if cropMode {
            if let c = cropDraft?.standardized, c.width > 8, c.height > 8 {
                cropRect = c
            }
            cropDraft = nil
            cropMode = false
            return
        }
        if isTap {
            draft = nil
            switch tool {
            case .text:
                textSheet = TextSheetState(position: p, editingId: nil, text: "")
            case .badge:
                pushUndo()
                annots.append(Annot(color: color, strokeWidth: strokeWidth,
                                    kind: .badge(p, nextBadgeNumber)))
            case .select:
                selectedId = annots.reversed().first { $0.hitTest(p, unit: unit, tol: tol) }?.id
            default:
                // 描画ツール中でも既存要素をクリックしたら選択に切替 (Awesome Screenshot風)
                if let hit = annots.reversed().first(where: { $0.hitTest(p, unit: unit, tol: tol) }) {
                    tool = .select
                    selectedId = hit.id
                }
            }
            return
        }
        if let d = draft, d.isMeaningful {
            pushUndo()
            annots.append(d)
        }
        draft = nil
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func applyText(sheet: TextSheetState, text: String) {
        guard !text.isEmpty else { return }
        pushUndo()
        if let id = sheet.editingId, let i = annots.firstIndex(where: { $0.id == id }),
           case .text(let pos, _, let f) = annots[i].kind {
            annots[i].kind = .text(pos, text, f)
        } else {
            annots.append(Annot(color: color, strokeWidth: strokeWidth,
                                kind: .text(sheet.position, text, fontSize)))
        }
    }

    // MARK: - 下部バー / 出力

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                if cropRect != nil {
                    cropRect = nil
                    cropMode = false
                } else {
                    cropMode.toggle()
                }
            } label: {
                Label(
                    cropRect == nil ? (cropMode ? "範囲をドラッグ…" : "トリミング") : "トリミング解除",
                    systemImage: "crop"
                )
                .foregroundStyle(cropMode || cropRect != nil ? Brand.tealA : Brand.text)
            }
            .buttonStyle(GhostButtonStyle())

            Spacer()

            outputButton(.clipboard, label: "コピー", icon: "doc.on.doc")
            outputButton(.file, label: "保存", icon: "square.and.arrow.down")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func outputButton(_ target: OutputTarget, label: String, icon: String) -> some View {
        let primary = app.settings.outputTarget == target
        Button {
            export(target: target)
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(primary ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(GhostButtonStyle()))
    }

    @MainActor
    private func export(target: OutputTarget) {
        guard let img = cgImage else { return }
        let full = CGRect(origin: .zero, size: imageSize)
        let crop = (cropRect ?? full).standardized.intersection(full).integral
        guard crop.width >= 1, crop.height >= 1 else { return }

        let swiftImage = Image(decorative: img, scale: 1)
        let annotsCopy = annots
        let unitCopy = unit
        let sizeCopy = imageSize
        let content = Canvas { ctx, _ in
            ctx.translateBy(x: -crop.minX, y: -crop.minY)
            ctx.draw(swiftImage, in: CGRect(origin: .zero, size: sizeCopy))
            AnnotRenderer.draw(&ctx, annots: annotsCopy, image: swiftImage, imageSize: sizeCopy, unit: unitCopy)
        }
        .frame(width: crop.width, height: crop.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let out = renderer.cgImage else {
            app.showToast(Toast(message: "画像の書き出しに失敗しました", isError: true))
            return
        }
        app.outputAnnotated(cgImage: out, target: target)
    }
}

/// テキスト入力シート
struct TextInputSheet: View {
    let state: AnnotationEditorView.TextSheetState
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.editingId == nil ? "テキストを追加" : "テキストを編集")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.textHi)
            TextField("テキスト", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .frame(width: 320)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: commit)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(Brand.surface)
        .onAppear { text = state.text }
    }

    private func commit() {
        onCommit(text)
        dismiss()
    }
}

/// ButtonStyle の型消去 (条件でスタイルを切り替えるため)
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
