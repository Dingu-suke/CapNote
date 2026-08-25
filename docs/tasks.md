# タスク一覧 (tasks)

人間・AIどちらが着手しても分かるよう、フェーズ (M0〜M6) ごとにチェックボックスで管理する。
着手前に対応する docs を読むこと。完了したら `[x]` にする。

## M0: 環境構築・雛形

- [x] Flutter SDK インストール確認 (`make doctor` / README.md 参照)
- [x] `flutter create` で macOS desktop プロジェクト生成 (本リポジトリ直下)
- [x] `flutter run -d macos` でテンプレアプリが起動することを確認 (ビルド済appの起動確認済)
- [x] macos/Runner の entitlements 確認 (App Sandbox は無効化 → open-questions #4)
- [x] Info.plist に権限の説明文言を追加 (NSScreenCaptureUsageDescription 等)
- [x] lib/ ディレクトリ構成を design.md のとおり作成
- [x] テーマ設定 (Tailwindパレット再現、ダークモード対応)

## M1: ネイティブ基盤 (Swift)

- [x] MethodChannel/EventChannel の骨組み (`getDisplays`, `checkPermissions`)
- [x] 権限チェックとシステム設定への誘導 (画面収録・アクセシビリティ)
- [ ] `DisplayInfo` 取得 + 座標系の正規化 (左下原点→左上原点) のユニットテスト

## M2: 録画 (コア) — docs/features/recording.md

- [x] ScreenCaptureKit で全画面キャプチャ → AVAssetWriter で mp4 出力 (固定設定でまず1本撮れる)
- [x] カーソル表示 (`showsCursor`)
- [x] fps / scale / bitrate をプリセットから反映
- [x] ディスプレイ選択録画
- [x] 停止フローティングバー (キャプチャ除外) + メニューバーアイコン
- [x] カウントダウン → 開始 → 停止 → 保存の一連フロー (Flutter側状態管理)
- [x] ファイル保存 + 完了通知 (Finderで表示)
- [x] クリップボード (ファイル参照) コピー
- [ ] 受け入れ基準の確認 (30秒≦5MB、GitHubで再生可)

## M3: クリック波紋 — docs/features/click-ripple.md

- [x] グローバルクリック監視 (NSEvent global monitor)
- [x] 透明・クリック透過オーバーレイ (全ディスプレイ)
- [x] ring スタイルのアニメーション実装
- [x] 残り3スタイル (filledCircle / doubleRing / highlight)
- [x] 設定UI (スタイル・色・サイズ・プレビュー) + 永続化
- [x] 録画中のみ有効化する制御
- [ ] fps=10 での視認性を実機確認 (必要なら duration 調整)

## M4: スクショ — docs/features/screenshot-annotation.md

- [x] 全画面フリーズキャプチャ + 範囲選択オーバーレイ (単一ディスプレイ)
- [x] マルチモニターの範囲選択
- [x] キャプチャ結果を注釈エディタへ渡す
- [x] クリップボード (PNG) コピー / ファイル保存

## M5: 注釈エディタ — docs/features/screenshot-annotation.md

- [x] エディタ画面の骨組み (画像表示 + ツールバー)
- [x] 矩形 / 楕円 / 直線 / 矢印
- [x] フリーハンド
- [x] テキスト (再編集含む)
- [x] 番号バッジ
- [x] ぼかし (モザイク)
- [x] 選択ツール (移動・削除・リサイズ。図形内クリックで選択可)
- [x] 色・太さピッカー
- [x] Undo / Redo
- [x] 画像合成出力 (PNG)
- [x] トリミング (推奨)

## M6: 仕上げ

- [x] ホーム画面の最終調整 (S-1 のレイアウト)
- [x] 設定画面 (S-5) 全項目
- [x] 保存先・ファイル名テンプレート設定
- [x] グローバルショートカット (⌘⇧6 / ⌘⇧7 既定、設定でキー変更可)
- [x] クイックモード (注釈スキップして即コピー) (推奨)
- [ ] ウィンドウ選択モード (Space切替) (推奨)
- [ ] エラーケースの網羅確認 (各featureのエラーケース表)
- [x] README.md の使い方セクション更新

### 実装メモ (設計からの差分)

- **2026-07-08: Flutter + Swift ハイブリッド → SwiftUI に全面書き換え** (open-questions #1)。
  M0〜M6 の完了状態は SwiftUI 版でも維持されている (機能パリティで移植済み)

- 範囲選択オーバーレイ (S-2) は Flutter ではなく **Swiftネイティブ実装** (`SelectionOverlay.swift`)。
  マルチウィンドウ・フリーズ画像表示はネイティブの方が単純なため
- 完了通知は OS通知ではなく **アプリ内スナックバー + Finderで表示** で代替 (通知権限の複雑さ回避)
- 録画中はメインウィンドウを最小化ではなく **非表示 (orderOut)** にし、停止後に復帰

## 継続タスク

- [ ] open-questions.md の未決事項を、着手フェーズの前までに決める
- [ ] 各フェーズ完了時に受け入れ基準をチェック
