import AppKit
import SwiftUI

/// S-5: 設定画面 (独立ウィンドウ)。テーマ・画質・波紋・ショートカット・保存先・権限
struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                appearanceSection
                qualitySection
                rippleSection
                shortcutSection
                saveSection
                permissionSection
            }
            .padding(20)
        }
        .frame(width: 480, height: 620)
        .background(Brand.bg)
        .onAppear { app.refreshPermissions() }
    }

    // MARK: - テーマ

    private var appearanceSection: some View {
        section("テーマ") {
            BrandSegmented(
                items: Appearance.allCases.map { ($0, $0.label, nil as String?) },
                selection: $app.settings.appearance
            )
        }
    }

    // MARK: - 画質

    private var qualitySection: some View {
        section("録画の画質 (ファイルサイズ優先)") {
            row("フレームレート") {
                Picker("", selection: $app.settings.fps) {
                    ForEach(AppSettings.fpsOptions, id: \.self) { f in
                        Text("\(f) fps").tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            row("解像度") {
                Picker("", selection: $app.settings.resolution) {
                    ForEach(ResolutionScale.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            Text(sizeEstimate)
                .font(.system(size: 11))
                .foregroundStyle(Brand.textLo)
            Toggle(isOn: $app.settings.showCursor) {
                Text("マウスカーソルを録画に含める")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.text)
            }
            .toggleStyle(.switch)
            .tint(Brand.teal)
        }
    }

    /// 現在の設定での容量目安 (メインディスプレイ全画面・自動ビットレート ~0.05bpp 基準)
    private var sizeEstimate: String {
        guard let d = app.displays.first(where: { $0.isMain }) ?? app.displays.first else { return "" }
        let scale = app.settings.resolution.rawValue
        let w = Double(d.width) * scale
        let h = Double(d.height) * scale
        let bitrate = max(300_000, w * h * Double(app.settings.fps) * 0.05)
        let mb30 = bitrate / 8 * 30 / 1_000_000
        let mb60 = mb30 * 2
        return String(format: "目安: 30秒 ≈ %.0f MB / 1分 ≈ %.0f MB (メインディスプレイ全画面。範囲録画ならさらに小さい)", mb30, mb60)
    }

    // MARK: - 波紋

    private var rippleSection: some View {
        section("クリック波紋 (録画中のみ表示)") {
            Toggle(isOn: $app.settings.ripple.enabled) {
                Text("波紋を表示する")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.text)
            }
            .toggleStyle(.switch)
            .tint(Brand.teal)

            row("スタイル") {
                Picker("", selection: $app.settings.ripple.style) {
                    ForEach(RippleStyleKind.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            row("色") {
                HStack(spacing: 6) {
                    ForEach(Brand.ripplePalette, id: \.hex) { item in
                        let selected = app.settings.ripple.colorHex.uppercased() == item.hex
                        Button {
                            app.settings.ripple.colorHex = item.hex
                        } label: {
                            Circle()
                                .fill(item.color)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(
                                    selected ? Brand.tealA : Brand.border,
                                    lineWidth: selected ? 2.5 : 1
                                ))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            row("サイズ  \(Int(app.settings.ripple.size))px") {
                Slider(value: $app.settings.ripple.size, in: 20...80, step: 5)
                    .frame(width: 180)
                    .tint(Brand.teal)
            }

            Button {
                app.previewRipple()
            } label: {
                Label("プレビュー (マウス位置に波紋を表示)", systemImage: "play.circle")
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    // MARK: - ショートカット

    private var shortcutSection: some View {
        section("グローバルショートカット") {
            HotkeyRecorderField(label: "録画 開始 / 停止", hotkey: $app.settings.hotkeyRecord)
            HotkeyRecorderField(label: "スクショ (切り取り)", hotkey: $app.settings.hotkeyScreenshot)
            Text("アプリがバックグラウンドでも効きます。出力先 (コピー / 保存) はホームの設定に従います")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textLo)
        }
    }

    // MARK: - 保存先

    private var saveSection: some View {
        section("保存先 (出力先が「ファイル」の時に使用)") {
            directoryRow("録画 (mp4)", text: $app.settings.movieDirectory)
            directoryRow("スクショ (png)", text: $app.settings.pictureDirectory)
            Text("ファイル名: rec_日時.mp4 / shot_日時.png")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textLo)
        }
    }

    private func directoryRow(_ label: String, text: Binding<String>) -> some View {
        row(label) {
            HStack(spacing: 6) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 210)
                Button("選択…") {
                    chooseDirectory(into: text)
                }
                .buttonStyle(GhostButtonStyle())
                .help("フォルダをFinderで選択")
            }
        }
    }

    /// フォルダ選択パネル。選んだパスは ~ 短縮表記で保存
    private func chooseDirectory(into binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "選択"
        let current = (binding.wrappedValue as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: current) {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    // MARK: - 権限

    private var permissionSection: some View {
        section("権限") {
            permissionRow(
                name: "画面収録",
                desc: "録画・スクショ・システム音声の録音に必須",
                granted: app.screenRecordingGranted,
                pane: "screenRecording"
            )
            permissionRow(
                name: "マイク",
                desc: "マイク音声の録音に使用 (「マイク」ONの録画に必要)",
                granted: app.microphoneGranted,
                pane: "microphone"
            ) {
                // 未確認ならその場でプロンプト、拒否済みならシステム設定へ
                PermissionService.requestOrOpenMicrophone {
                    app.refreshPermissions()
                }
            }
            permissionRow(
                name: "アクセシビリティ",
                desc: "クリック波紋の検知に使用 (なくても録画は可能)",
                granted: app.accessibilityGranted,
                pane: "accessibility"
            )
            Button {
                app.refreshPermissions()
            } label: {
                Label("再チェック", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private func permissionRow(
        name: String, desc: String, granted: Bool, pane: String,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Brand.tealA : Color(hex: 0xFF7A6B))
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Brand.textHi)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textLo)
            }
            Spacer()
            if !granted {
                Button("設定を開く") {
                    if let action {
                        action()
                    } else {
                        PermissionService.openSystemSettings(pane: pane)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Brand.tealA)
            }
        }
    }

    // MARK: - Layout helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.textHi)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Brand.textLo)
            Spacer()
            control()
        }
    }
}

/// ショートカットのキーレコーダー。クリック → 次のキー入力を割り当て (Escでキャンセル)
struct HotkeyRecorderField: View {
    let label: String
    @Binding var hotkey: Hotkey

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Brand.text)
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? "キーを入力…" : (hotkey.enabled ? hotkey.display : "未設定"))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(recording ? Brand.tealA : (hotkey.enabled ? Brand.textHi : Brand.textLo))
                    .frame(minWidth: 76)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Brand.bg.opacity(0.6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(recording ? Brand.tealA : Brand.border))
                    )
            }
            .buttonStyle(.plain)
            .help("クリックしてキーを入力 (修飾キー必須、Escでキャンセル)")

            Button {
                hotkey.enabled = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(hotkey.enabled ? Brand.textLo : Brand.border)
            }
            .buttonStyle(.plain)
            .disabled(!hotkey.enabled)
            .help("ショートカットを無効にする")
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            if ev.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            if let hk = Hotkey.from(event: ev) {
                hotkey = hk
                stopRecording()
                return nil
            }
            return nil // 修飾キーなしの入力は無視 (誤爆防止)
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
