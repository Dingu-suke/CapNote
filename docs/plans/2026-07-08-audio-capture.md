# 実装計画: 音声録音 (システム音声・マイク) (2026-07-08)

## 背景

録画にmacの出力音声・マイク音声を入れたい (それぞれトグルで切替)。
ホームの設定カード (出力先・録画範囲・波紋) の下に2項目追加する。

## 変更内容

| ファイル | 変更 |
|---------|------|
| Package.swift / Support/Info.plist | 対応OSを macOS 15 に (SCKのマイク取得が15+)。NSMicrophoneUsageDescription 追加 |
| Models.swift | `captureSystemAudio` / `captureMicrophone` (既定 false) を AppSettings に追加 |
| Services/RecorderService.swift | SCStreamConfiguration.capturesAudio / captureMicrophone。AVAssetWriter に AACトラック追加 (システム=48kHz 2ch 160kbps / マイク=1ch 96kbps)。自アプリの音は除外 |
| AppState.swift | 設定を RecordConfig に受け渡し |
| UI/HomeView.swift | 「システム音声」「マイク」トグル行を波紋の下に追加 |
| README.md | 機能・要件更新 |

## 設計メモ

- 音声はビデオと同じ SCStream から `.audio` / `.microphone` 出力で受け、リアルタイムでAACエンコード
- 自アプリの再生音は `excludesCurrentProcessAudio = true` で除外
- **両方ONの場合はmp4に音声2トラック**になる。QuickTimeは両方再生するが、
  ブラウザ再生では片方 (先頭トラック=システム音声) しか再生されない場合がある
  → ミックスして1トラック化は将来課題 (open-questions #11)
- マイクは初回にマイク権限のプロンプトが出る (Info.plist に説明文言)

## 検証

- swift build + 起動スモークテスト
- 実録画での音声確認 (マイク権限・音出し) はユーザーに依頼

## 結果 (2026-07-08)

- 実装完了。swift build クリーン、起動スモークテストOK、dmg再生成済み
- swift-tools-version を 6.0 に更新 (`.macOS(.v15)` 指定に必要。言語モードは Swift 5 を維持)
- 音出し・マイクの実録画確認はユーザーに依頼 (マイクは初回に権限プロンプトが出る)

## 追記 (2026-08-25): 両方ON時のミックス実装

- 実機で「マイクが入らない」報告 → 調査の結果、録音自体は成功していた (mic track peak=1.06)。
  再生側が第1トラック (システム音声) しか再生していなかった
- 対応: `Services/AudioMixdown.swift` を追加。両方ONの録画は停止時に1トラックへミックス。
  実録画ファイルで検証済み (2トラック→1トラック、両音源のデータ保持、ビデオ無劣化)
