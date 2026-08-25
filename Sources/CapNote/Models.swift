import AppKit
import Foundation

// MARK: - 設定 (UserDefaults にJSONで永続化)

enum OutputTarget: String, Codable, CaseIterable {
    case clipboard, file

    var label: String {
        switch self {
        case .clipboard: return "クリップボード"
        case .file: return "ファイル"
        }
    }
}

enum ScopeType: String, Codable {
    case region, fullScreen, display
}

/// 録画解像度 (fpsとは独立して選択)
enum ResolutionScale: Double, Codable, CaseIterable {
    case logical = 1.0 // 論理解像度 (Retinaでも1x。軽い)
    case retina = 2.0 // 物理解像度 (高精細・サイズ大)

    var label: String {
        switch self {
        case .logical: return "論理解像度 (軽い)"
        case .retina: return "Retina (2x・高精細)"
        }
    }

    /// ホーム画面などの短い表示用
    var shortLabel: String {
        switch self {
        case .logical: return "論理解像度"
        case .retina: return "Retina 2x"
        }
    }
}

enum RippleStyleKind: String, Codable, CaseIterable {
    case ring, filledCircle, doubleRing, highlight

    var label: String {
        switch self {
        case .ring: return "リング"
        case .filledCircle: return "塗り円"
        case .doubleRing: return "二重リング"
        case .highlight: return "ハイライト"
        }
    }
}

struct RippleUserSettings: Codable, Equatable {
    var style: RippleStyleKind = .ring
    var colorHex: String = "#FACC15" // 黄 (視認性優先)
    var size: Double = 40
    var durationMs: Int = 700
    var enabled: Bool = true

    var config: RippleConfig {
        var c = RippleConfig()
        c.style = style.rawValue
        c.color = NSColor(hexString: colorHex) ?? .systemYellow
        c.size = CGFloat(size)
        c.durationMs = durationMs
        c.enabled = enabled
        return c
    }
}

/// テーマ (FR: ライト/ダーク/システム追従)
enum Appearance: String, Codable, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "Macの設定に追従"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct AppSettings: Codable, Equatable {
    var outputTarget: OutputTarget = .clipboard
    var scopeType: ScopeType = .region // 既定は「切り取り (範囲選択)」
    var displayId: Int? = nil
    var fps: Int = 10
    var resolution: ResolutionScale = .logical
    var showCursor: Bool = true
    var captureSystemAudio: Bool = false
    var captureMicrophone: Bool = false

    static let fpsOptions = [5, 10, 15, 24, 30]
    var movieDirectory: String = "~/Movies/CapNote"
    var pictureDirectory: String = "~/Pictures/CapNote"
    var maxMinutes: Int = 30
    var ripple = RippleUserSettings()
    var appearance: Appearance = .dark // 既定はダーク (現状の見た目)
    var hotkeyRecord: Hotkey = .defaultRecord
    var hotkeyScreenshot: Hotkey = .defaultScreenshot

    init() {}

    // 設定項目を後から追加してもデコード失敗で既存設定が飛ばないよう、全キー decodeIfPresent
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outputTarget = try c.decodeIfPresent(OutputTarget.self, forKey: .outputTarget) ?? .clipboard
        scopeType = try c.decodeIfPresent(ScopeType.self, forKey: .scopeType) ?? .region
        displayId = try c.decodeIfPresent(Int.self, forKey: .displayId)
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 10
        resolution = try c.decodeIfPresent(ResolutionScale.self, forKey: .resolution) ?? .logical
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? true
        captureSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .captureSystemAudio) ?? false
        captureMicrophone = try c.decodeIfPresent(Bool.self, forKey: .captureMicrophone) ?? false
        movieDirectory = try c.decodeIfPresent(String.self, forKey: .movieDirectory) ?? "~/Movies/CapNote"
        pictureDirectory = try c.decodeIfPresent(String.self, forKey: .pictureDirectory) ?? "~/Pictures/CapNote"
        maxMinutes = try c.decodeIfPresent(Int.self, forKey: .maxMinutes) ?? 30
        ripple = try c.decodeIfPresent(RippleUserSettings.self, forKey: .ripple) ?? RippleUserSettings()
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .dark
        hotkeyRecord = try c.decodeIfPresent(Hotkey.self, forKey: .hotkeyRecord) ?? .defaultRecord
        hotkeyScreenshot = try c.decodeIfPresent(Hotkey.self, forKey: .hotkeyScreenshot) ?? .defaultScreenshot
    }

    private static let key = "appSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - 実行時モデル

struct DisplayItem: Identifiable, Equatable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    let isMain: Bool

    static func current() -> [DisplayItem] {
        NSScreen.screens.map { screen in
            DisplayItem(
                id: Int(DisplayService.displayID(of: screen)),
                name: screen.localizedName,
                width: Int(screen.frame.width),
                height: Int(screen.frame.height),
                isMain: screen == NSScreen.main
            )
        }
    }
}

enum RecPhase: Equatable {
    case idle, countdown, recording, encoding
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var path: String? // あれば「Finderで表示」を出す
    var isError = false
}

func timestampNow() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd_HHmmss"
    return f.string(from: Date())
}
