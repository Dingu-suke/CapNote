import AppKit
import SwiftUI

extension NSColor {
    convenience init(hexRGB hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// ライト/ダークで切り替わる動的色 (NSApp.appearance に追従)
    static func dynamicHex(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hexRGB: dark)
                : NSColor(hexRGB: light)
        }
    }
}

/// ブランドトークン: ダークチャコール + エメラルド/ティール。
/// すべてライト/ダーク両対応の動的色 (テーマ設定は NSApp.appearance で切替)。
enum Brand {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: .dynamicHex(light: light, dark: dark))
    }

    static let bgNS = NSColor.dynamicHex(light: 0xF2F6F5, dark: 0x0D1413)
    static let bg = Color(nsColor: bgNS)
    static let surface = dyn(0xFFFFFF, 0x141D1B)
    static let surfaceHi = dyn(0xE9F0EE, 0x1B2725)
    static let border = dyn(0xD9E3E0, 0x22302D)
    static let tealA = dyn(0x0E9C81, 0x2BD9A9)
    static let tealB = dyn(0x0A7A6E, 0x0E9C8D)
    static let teal = dyn(0x12A98A, 0x19BE9C)
    static let rec = dyn(0xE14B4B, 0xFF5D5D)
    static let textHi = dyn(0x17211F, 0xF2F7F6)
    static let text = dyn(0x32403D, 0xC4D1CE)
    static let textLo = dyn(0x68807A, 0x7E938F)
    static let canvasBg = dyn(0xDFE7E5, 0x090E0D)

    // 権限バナー (警告系)
    static let warnBg = dyn(0xFBF3D9, 0x3A2E14)
    static let warnBorder = dyn(0xE3CE8C, 0x6B5420)
    static let warnText = dyn(0x6B5420, 0xE9DCB8)
    static let warnIcon = dyn(0xD9A514, 0xE8B93F)

    static let gradient = LinearGradient(
        colors: [tealA, tealB],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let recGradient = LinearGradient(
        colors: [Color(hex: 0xFF7A6B), Color(hex: 0xE0364B)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 注釈エディタの色パレット
    static let palette: [Color] = [
        Color(hex: 0xEF4444), // red (デフォルト)
        Color(hex: 0xF97316), // orange
        Color(hex: 0xFACC15), // yellow
        Color(hex: 0x22C55E), // green
        Color(hex: 0x3B82F6), // blue
        Color(hex: 0xA855F7), // purple
        Color(hex: 0x000000), // black
        Color(hex: 0xFFFFFF), // white
    ]

    /// 波紋の色候補
    static let ripplePalette: [(hex: String, color: Color)] = [
        ("#FACC15", Color(hex: 0xFACC15)),
        ("#EF4444", Color(hex: 0xEF4444)),
        ("#3B82F6", Color(hex: 0x3B82F6)),
        ("#22C55E", Color(hex: 0x22C55E)),
        ("#A855F7", Color(hex: 0xA855F7)),
        ("#FFFFFF", Color(hex: 0xFFFFFF)),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// カード (角丸 + ボーダー)
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Brand.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.border))
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// メインアクション (ティール塗り) ボタン
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.teal))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// サブアクション (枠線) ボタン
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Brand.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Brand.surfaceHi : Brand.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.border))
            )
    }
}

/// 2〜3択トグル (クリップボード / ファイル 等)
struct BrandSegmented<T: Hashable>: View {
    let items: [(value: T, label: String, icon: String?)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 4) {
                        if let icon = item.icon {
                            Image(systemName: icon).font(.system(size: 10))
                        }
                        Text(item.label).font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Brand.teal.opacity(0.2) : .clear)
                    )
                    .foregroundStyle(selected ? Brand.tealA : Brand.textLo)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Brand.bg.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.border))
        )
    }
}
