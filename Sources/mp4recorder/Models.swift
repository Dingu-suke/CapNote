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

enum QualityPreset: String, Codable, CaseIterable {
    case light, standard, high

    var label: String {
        switch self {
        case .light: return "軽量"
        case .standard: return "標準"
        case .high: return "高画質"
        }
    }

    var fps: Int {
        switch self {
        case .light: return 10
        case .standard: return 15
        case .high: return 30
        }
    }

    /// 1.0 = 論理解像度, 2.0 = Retina物理解像度
    var scale: Double {
        switch self {
        case .light, .standard: return 1.0
        case .high: return 2.0
        }
    }

    var description: String {
        switch self {
        case .light: return "10fps・論理解像度・約1Mbps — 30秒で2〜4MB目安 (推奨)"
        case .standard: return "15fps・論理解像度・約2Mbps — 30秒で5〜8MB目安"
        case .high: return "30fps・Retina解像度 — サイズ大。GitHub添付には不向き"
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
    var preset: QualityPreset = .light
    var showCursor: Bool = true
    var movieDirectory: String = "~/Movies/mp4recorder"
    var pictureDirectory: String = "~/Pictures/mp4recorder"
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
        preset = try c.decodeIfPresent(QualityPreset.self, forKey: .preset) ?? .light
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? true
        movieDirectory = try c.decodeIfPresent(String.self, forKey: .movieDirectory) ?? "~/Movies/mp4recorder"
        pictureDirectory = try c.decodeIfPresent(String.self, forKey: .pictureDirectory) ?? "~/Pictures/mp4recorder"
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
