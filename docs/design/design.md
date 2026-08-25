# 設計 (アーキテクチャ)

## 技術スタック

| レイヤ | 技術 | 備考 |
|--------|------|------|
| UI | **SwiftUI** (macOS 14+) | ホーム・設定・注釈エディタ |
| 画面キャプチャ | **ScreenCaptureKit** | カーソル込みキャプチャ対応 |
| 動画エンコード | **AVAssetWriter** + H.264 | 低ビットレート設定でmp4出力 |
| クリック検知 | NSEvent global monitor | アクセシビリティ権限が必要 (なくても録画可) |
| 波紋表示 | 透明・クリック透過の NSWindow オーバーレイ | 全ディスプレイに1枚ずつ |
| スクショ | ScreenCaptureKit (SCScreenshotManager) | |
| クリップボード | NSPasteboard | 画像はPNG、動画はファイルURL |
| 設定永続化 | UserDefaults (JSON) | |
| ビルド | SwiftPM + Makefile (Xcodeプロジェクトなし) | `make build` で .app 生成 |

> 履歴: 当初 Flutter + Swift ハイブリッドだったが、コア機能が全てSwift側になり
> Platform Channel の橋渡しコストだけが残ったため SwiftUI に全面移行した (open-questions #1)。

## 全体構成

```
Sources/mp4recorder/
  App.swift          … @main / ルーティング / トースト
  AppState.swift     … オーケストレーション (録画フロー・スクショフロー・出力)
  Models.swift       … 設定 (AppSettings) / 実行時モデル
  UI/
    Theme.swift              … ブランドトークン (ダーク + ティール)
    HomeView.swift           … S-1 ホーム
    SettingsView.swift       … S-5 設定シート
    AnnotationModel.swift    … 注釈モデル + 共用レンダラ (表示/書き出し)
    AnnotationEditorView.swift … S-4 注釈エディタ
  Services/
    RecorderService.swift    … ScreenCaptureKit → AVAssetWriter
    ClickRippleService.swift … クリック監視 + 波紋オーバーレイ
    ScreenshotService.swift  … フリーズキャプチャ + 切り抜き
    SelectionOverlay.swift   … Cmd+Shift+4風 範囲選択 (全ディスプレイ)
    FloatingStopBar.swift    … 停止バー / メニューバー / カウントダウン
    DisplayService.swift     … ディスプレイ列挙・座標正規化
    PermissionService.swift  … 画面収録・アクセシビリティ権限
    ClipboardService.swift   … NSPasteboard / Finderで表示
Support/
  Info.plist / AppIcon.icns
```

## 主要な設計判断

### 1. 波紋は「オーバーレイ方式」で録画に写す

クリック波紋は、**画面の最前面に透明なオーバーレイウィンドウを置いてアニメーション描画**し、
それごと画面キャプチャする。動画への後合成 (ポストプロセス) はしない。

- 利点: 実装が単純。録画したまま = 見たままになる。リアルタイムプレビューも兼ねる
- 欠点: 録画していない時も波紋を出すかどうかの制御が要る (録画中のみONにする)
- オーバーレイは `ignoresMouseEvents = true` でクリックを透過させる
- マルチモニター: `NSScreen.screens` ごとにオーバーレイを1枚生成。ディスプレイ構成変更を監視して追従

### 2. ファイルサイズ最小化の戦略

「カクつき・画質低下は許容、とにかく軽く」が要件なので:

| パラメータ | デフォルト値 | 説明 |
|-----------|-------------|------|
| fps | 10 | 操作証跡には十分。カクつき許容 |
| コーデック | H.264 (High Profile) | 互換性最優先。GitHub/ブラウザで再生可 |
| ビットレート | 解像度に応じ約 0.05 bpp (1080p/10fps で ~1Mbps) | 画質プリセットで変更可 |
| ダウンスケール | Retinaは1x (論理解像度) に落とす | 5K物理解像度をそのまま撮らない |
| キーフレーム間隔 | 5秒 | サイズ削減 |

画質プリセット: `軽量 (デフォルト)` / `標準` / `高画質` の3段階。→ [data-model.md](data-model.md)

- 検討メモ: H.265(HEVC)の方が同画質で~40%軽いが、GitHub上のブラウザ再生互換に不安があるためデフォルトはH.264。→ open-questions

### 3. 録画のクリップボードコピー

動画バイナリはクリップボードに直接載せられないため、mp4は一時ファイルに保存した上で
**ファイル参照 (file URL) としてコピー**する。GitHub PRのテキストエリアに Cmd+V で添付できる。

### 4. 権限

| 権限 | 用途 | 案内タイミング |
|------|------|---------------|
| 画面収録 (Screen Recording) | 録画・スクショ | 初回起動時にチェック→設定アプリへ誘導 |
| アクセシビリティ or 入力監視 | グローバルクリック検知 (波紋) | 波紋機能を初めて使う時 |

## 参照

- UI詳細: [design-ui.md](design-ui.md)
- データモデル: [data-model.md](data-model.md)
- 機能別仕様: [../features/](../features/)
