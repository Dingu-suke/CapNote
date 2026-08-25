# 実装計画: 初回フィードバック対応 (2026-07-08)

## 背景

実機テストでのフィードバック7件 + プロセス整備。

## 変更内容

| # | 項目 | 変更ファイル |
|---|------|-------------|
| 1 | 録画の範囲選択が真っ黒になるバグ修正 (暗幕モードの背景を透過に) | Services/SelectionOverlay.swift |
| 2 | テーマ3モード (システム追従/ライト/ダーク)。色トークンを動的化 | UI/Theme.swift, Models.swift, App.swift, AppState.swift |
| 3 | 設定を別ウィンドウ化 (小さいウィンドウでシートが崩れる問題) | App.swift, UI/HomeView.swift, UI/SettingsView.swift |
| 4 | 注釈エディタ改善: クリック判定を画面ピクセル基準に拡大 + 図形内クリックで選択可 / リサイズハンドル (矩形・楕円・ぼかし=四隅、直線・矢印=両端) / 描画ツール中でも要素クリックで選択に切替 / Undo・Redoは常時表示・無効時は薄く | UI/AnnotationModel.swift, UI/AnnotationEditorView.swift |
| 5 | 範囲録画中に範囲外を暗くするインジケータ (キャプチャから除外) | Services/RegionIndicator.swift (新規), AppState.swift |
| 6 | グローバルショートカット (既定: 録画 ⌘⇧6 / スクショ ⌘⇧7、設定でキー変更可) | Services/HotkeyManager.swift (新規), Models.swift, UI/SettingsView.swift, AppState.swift |
| 7 | README にインストール手順 + dmg ダウンロード導線 | README.md |
| 8 | 開発プロセスの明文化 (このファイルの仕組み) | docs/dev-process.md, docs/plans/ |

## 設計メモ

- **テーマ**: `NSColor(name:dynamicProvider:)` でライト/ダーク両対応の動的色を定義し、
  `NSApp.appearance` を設定値 (system=nil / aqua / darkAqua) で切り替える。既定はダーク (現状踏襲)
- **ヒット判定**: これまで画像ピクセル基準だったため、縮小表示時に実質数pxしかなかった。
  表示スケール `fit` から `tol = 10 / fit` (画面上10px相当) を計算して判定に使う
- **ショートカット**: Carbon `RegisterEventHotKey` (アクセシビリティ権限不要)。
  出力先 (コピー/保存) はホームの設定に従う。キーはNSEventローカルモニタで録音するUI
- **範囲インジケータ**: 停止バーと同様に `SCContentFilter` の除外ウィンドウに入れるので録画には写らない

## 検証

- `swift build` + 起動スモークテスト
- エディタのヒット判定・リサイズはロジック確認 (GUI操作の実機確認はユーザーに依頼)

## 結果 (2026-07-08)

- 全8項目実装完了。`swift build` クリーン、起動スモークテスト15秒OK、dmg再生成済み
- エディタ変更点の詳細:
  - ヒット判定は `tol = 10 / fit` (画面上10px) を基準にし、矩形・楕円・ぼかしは内部クリックでも選択可
  - リサイズ: 矩形/楕円/ぼかし=四隅ハンドル、直線/矢印=両端ハンドル。フリーハンド/テキスト/バッジは移動のみ
  - 描画ツール中でも既存要素をクリックすると選択ツールに切替わる
- GUI操作 (ヒット判定・リサイズ・ショートカット・テーマ切替) の実機確認はユーザーに依頼
- 未了: GitHub リポジトリ作成 + Releases への dmg アップロード (ユーザー承認待ち)
