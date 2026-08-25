# 機能仕様: 画面録画

対応要件: FR-1, FR-3

## ユーザーフロー

1. ホームで録画範囲 (画面全体 / ディスプレイ / 範囲選択) と出力先を確認
2. 「録画」ボタン押下
   - 範囲選択の場合はオーバーレイで矩形をドラッグ
3. 3秒カウントダウン → 録画開始。アプリウィンドウは自動最小化
4. 録画中はフローティング停止バー + メニューバーアイコン表示。クリック波紋が有効
5. 「停止」→ エンコード完了 (AVAssetWriterはリアルタイム書き込みなので数秒)
6. 出力:
   - ファイル: 設定ディレクトリに `rec_YYYYMMDD_HHmmss.mp4` 保存 → 通知 (クリックでFinder表示)
   - クリップボード: 一時ファイルに保存し、ファイル参照をコピー → 通知「Cmd+VでPRに添付できます」

## 技術詳細

### キャプチャ (Swift / ScreenCaptureKit)

- `SCStream` + `SCStreamConfiguration`
  - `showsCursor = true` (FR-1.3)
  - `minimumFrameInterval = 1/fps` (低fpsでフレーム自体を間引く → CPU・サイズ両方に効く)
  - `width/height` = 論理解像度 × scale (Retina 2xをそのまま撮らない)
- 除外ウィンドウ: 自アプリのフローティング停止バーは `SCContentFilter` で除外
  - **波紋オーバーレイは除外しない** (写すのが目的)
- 範囲指定録画: `sourceRect` で切り出し

### エンコード (Swift / AVAssetWriter)

- H.264, `AVVideoProfileLevelH264HighAutoLevel`
- `AVVideoAverageBitRateKey` = プリセット値 (data-model.md の表)
- `AVVideoMaxKeyFrameIntervalDurationKey` = 5秒
- フレームはSCStreamのコールバックから直接 `AVAssetWriterInput` へ (中間ファイルなし)
- 出力コンテナ: `.mp4` (QuickTimeの .mov にしない — GitHub/ブラウザ互換のため)

### エラーケース

| ケース | 挙動 |
|--------|------|
| 画面収録権限なし | 録画開始前にチェックし、案内ダイアログ → システム設定へ誘導 |
| 録画中にディスプレイ構成変更 (対象ディスプレイが抜かれた) | 録画を停止し、そこまでの動画を保存 + 警告 |
| ディスク容量不足 / 書き込み失敗 | エラー通知、部分ファイルは削除 |
| 長時間録画 | 上限30分で自動停止 (証跡用途なので十分。設定で変更可) |

## 受け入れ基準

- [ ] 1080p相当・30秒の録画が 5MB 以下 (lightプリセット)
- [ ] 生成mp4が GitHub PR にドラッグ&ドロップで添付でき、ブラウザ上で再生できる
- [ ] カーソルが映っている
- [ ] クリップボードモードで Cmd+V 添付ができる
- [ ] 外部ディスプレイを選んで録画できる
- [ ] 停止バーが録画に写り込まない
