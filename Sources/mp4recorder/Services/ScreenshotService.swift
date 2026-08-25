import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// スクリーンショット: 全画面フリーズキャプチャ → 範囲選択 → 切り抜きPNG。
/// スクショは画質優先で物理解像度 (Retina 2x) で撮る (録画と方針が違う点に注意)。
/// NSWindow (SelectionOverlay) を生成するため必ずメインスレッドで動かす (@MainActor)。
@MainActor
final class ScreenshotService {
    private var session: SelectionSession?

    struct CaptureOutcome {
        let path: String
        let widthPx: Int
        let heightPx: Int
        let quick: Bool
    }

    /// 各ディスプレイを物理解像度でキャプチャ (カーソルなし)
    @MainActor
    static func captureAllDisplays() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var images: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            let id = DisplayService.displayID(of: screen)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = false
            config.captureResolution = .best
            images[id] = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        return images
    }

    /// フリーズ画像の上で範囲選択させ、切り抜いたPNGを一時ファイルに書いて返す。nil = キャンセル
    func interactiveCapture() async throws -> CaptureOutcome? {
        let frozen = try await Self.captureAllDisplays()
        return await withCheckedContinuation { (cont: CheckedContinuation<CaptureOutcome?, Never>) in
            let session = SelectionSession()
            self.session = session
            session.begin(freezeImages: frozen) { [weak self] result in
                self?.session = nil
                guard let result,
                      let image = frozen[DisplayService.displayID(of: result.screen)] else {
                    cont.resume(returning: nil)
                    return
                }
                // 論理座標 → 物理ピクセル (フリーズ画像は左上原点)
                let scale = CGFloat(image.width) / result.screen.frame.width
                let pixelRect = CGRect(
                    x: result.rect.origin.x * scale,
                    y: result.rect.origin.y * scale,
                    width: result.rect.width * scale,
                    height: result.rect.height * scale
                ).integral
                guard let cropped = image.cropping(to: pixelRect),
                      let path = Self.writePNG(cropped, prefix: "shot") else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: CaptureOutcome(
                    path: path, widthPx: cropped.width, heightPx: cropped.height, quick: result.quick
                ))
            }
        }
    }

    /// 録画用の範囲選択 (暗幕のみ・フリーズなし)。戻り値: (displayId, 左上原点論理rect)
    func selectRegion() async -> (displayId: CGDirectDisplayID, rect: CGRect)? {
        await withCheckedContinuation { cont in
            let session = SelectionSession()
            self.session = session
            session.begin(freezeImages: nil) { [weak self] result in
                self?.session = nil
                guard let result else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (DisplayService.displayID(of: result.screen), result.rect))
            }
        }
    }

    static func writePNG(_ image: CGImage, prefix: String) -> String? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mp4recorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(prefix)_\(RecorderService.timestamp()).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url.path : nil
    }
}
