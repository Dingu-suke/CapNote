import SwiftUI

/// S-1: ホーム画面。録画 / スクショ の2大ボタン + 出力先・範囲・波紋の設定
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !app.screenRecordingGranted {
                permissionBanner
            }
            HStack(spacing: 14) {
                ActionCard(
                    icon: "record.circle.fill",
                    gradient: Brand.recGradient,
                    accent: Color(hex: 0xFF7A6B),
                    title: recTitle,
                    subtitle: "\(app.settings.fps)fps・\(app.settings.resolution.shortLabel)・mp4",
                    enabled: !app.isBusy
                ) {
                    app.startRecording()
                }
                ActionCard(
                    icon: "crop",
                    gradient: Brand.gradient,
                    accent: Brand.tealA,
                    title: "スクショ",
                    subtitle: "切り取り → 注釈 (Shiftで即コピー)",
                    enabled: !app.isBusy
                ) {
                    app.takeScreenshot()
                }
            }
            .frame(maxHeight: .infinity)
            settingsCard
        }
        .padding(24)
        .background(Brand.bg)
    }

    private var recTitle: String {
        switch app.recPhase {
        case .idle: return "録画"
        case .countdown: return "カウントダウン中…"
        case .recording: return "録画中…"
        case .encoding: return "保存中…"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Brand.gradient)
                .frame(width: 26, height: 26)
                .overlay(Circle().fill(.white).frame(width: 9, height: 9))
            Text("mp4recorder")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.textHi)
            Spacer()
            Button {
                app.refreshPermissions()
                openWindow(id: "settings")
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.textLo)
            }
            .buttonStyle(.plain)
            .help("設定")
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: 0xE8B93F))
                .font(.system(size: 14))
            Text("画面収録の権限がありません。許可するとmacOSがアプリを終了させるので、再起動してください。")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: 0xE9DCB8))
            Spacer()
            Button("設定を開く") {
                PermissionService.openSystemSettings(pane: "screenRecording")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Brand.tealA)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0x3A2E14))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x6B5420)))
        )
    }

    // MARK: - 設定カード

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "tray.and.arrow.up", label: "出力先") {
                BrandSegmented(
                    items: [
                        (OutputTarget.clipboard, "クリップボード", "doc.on.doc"),
                        (OutputTarget.file, "ファイル", "square.and.arrow.down"),
                    ],
                    selection: $app.settings.outputTarget
                )
            }
            Divider().overlay(Brand.border)
            settingRow(icon: "viewfinder", label: "録画範囲") {
                scopePicker
            }
            Divider().overlay(Brand.border)
            settingRow(icon: "dot.circle.and.hand.point.up.left.fill", label: "波紋") {
                Picker("", selection: $app.settings.ripple.style) {
                    ForEach(RippleStyleKind.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Brand.text)
                .frame(width: 160)
            }
        }
        .card()
    }

    /// 録画範囲: region / fullScreen / display:<id> を1つのPickerで扱う
    private var scopePicker: some View {
        Picker("", selection: scopeBinding) {
            Text("切り取り (ドラッグで範囲指定)").tag("region")
            Text("画面全体 (メインディスプレイ)").tag("full")
            ForEach(app.displays) { d in
                Text("\(d.name) (\(d.width)×\(d.height))\(d.isMain ? " — メイン" : "")")
                    .tag("display:\(d.id)")
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Brand.text)
        .frame(width: 240)
    }

    private var scopeBinding: Binding<String> {
        Binding {
            switch app.settings.scopeType {
            case .region: return "region"
            case .fullScreen: return "full"
            case .display:
                let id = app.settings.displayId ?? app.displays.first?.id ?? 0
                return "display:\(id)"
            }
        } set: { v in
            if v == "region" {
                app.settings.scopeType = .region
            } else if v == "full" {
                app.settings.scopeType = .fullScreen
            } else if let id = Int(v.dropFirst("display:".count)) {
                app.settings.scopeType = .display
                app.settings.displayId = id
            }
        }
    }

    private func settingRow(icon: String, label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Brand.textLo)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Brand.textLo)
                .frame(width: 64, alignment: .leading)
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// 録画 / スクショ の2大アクションカード (ホバーで枠が光る)
struct ActionCard: View {
    let icon: String
    let gradient: LinearGradient
    let accent: Color
    let title: String
    let subtitle: String
    let enabled: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Circle()
                    .fill(enabled ? AnyShapeStyle(gradient) : AnyShapeStyle(Brand.border))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Brand.textHi)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textLo)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(hover && enabled ? Brand.surfaceHi : Brand.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(hover && enabled ? accent.opacity(0.55) : Brand.border)
                    )
                    .shadow(
                        color: hover && enabled ? accent.opacity(0.14) : .clear,
                        radius: 20
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
