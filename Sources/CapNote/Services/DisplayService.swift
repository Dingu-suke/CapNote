import AppKit

/// ディスプレイ情報の取得と座標系の正規化。
/// macOSのグローバル座標は左下原点。Channel境界では左上原点に正規化して返す (data-model.md)。
enum DisplayService {
    /// 全ディスプレイの合計領域の最大Y (左下原点座標系)。左上原点変換の基準。
    static var globalMaxY: CGFloat {
        NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }

    /// 左上原点・論理座標のディスプレイ一覧
    static func getDisplays() -> [[String: Any]] {
        let maxY = globalMaxY
        return NSScreen.screens.map { screen in
            let f = screen.frame
            return [
                "id": Int(displayID(of: screen)),
                "x": f.origin.x,
                "y": maxY - f.maxY,
                "width": f.width,
                "height": f.height,
                "scale": screen.backingScaleFactor,
                "isMain": screen == NSScreen.main,
                "name": screen.localizedName,
            ]
        }
    }
}
