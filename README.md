# CapNote

macOS用の 録画 + スクリーンショットアプリ。画面を録画して軽い mp4 にしたり、スクショに矢印や文字を書き込んだりして、そのまま GitHub や Slack に貼れます。

[![Download](https://img.shields.io/badge/%E2%AC%87%EF%B8%8E%20%E3%83%80%E3%82%A6%E3%83%B3%E3%83%AD%E3%83%BC%E3%83%89-CapNote.dmg-19BE9C?style=for-the-badge&labelColor=141D1B)](https://github.com/Dingu-suke/CapNote/releases/latest/download/CapNote.dmg)

- 📹 **録画** — 範囲を切り取って録画。軽い mp4 になるので GitHub PR にそのまま貼れる。クリックした場所に波紋が表示される
- 🔊 **音声** — Mac の音・マイクの声も録音できる (ON/OFF切替)
- ✂️ **スクショ + 注釈** — 範囲を切り取って、矢印・文字・ぼかし・番号などを書き込める
- 📋 出力は **クリップボードにコピー** か **ファイル保存** を選べる

## インストール (3分)

1. 上の **「⬇︎ ダウンロード CapNote.dmg」ボタン**を押す
2. ダウンロードした `CapNote.dmg` をダブルクリックで開き、中の **CapNote を Applications フォルダにドラッグ**する

|  |  |  |
| --- | --- | --- | 
| 3. アプリアイコンをクリック | ![image](https://i.gyazo.com/ecd8984a497d393e8a4efbc791f36b05.png) |  |
| 4. モーダルウィンドウが表示されますので、完了を押す | ![image](https://i.gyazo.com/483d4dce881a45f97db8e4b256c92870.png) |  |
| 5. 設定 → プライバシーとセキュリティ → このまま開く | ![image](https://i.gyazo.com/98b2a380c73e5a96e6d88253cc22afa9.png) |  |
| 6. このまま開く | ![image](https://i.gyazo.com/0526d5751e572db1391094449f30886f.png) |  |
| 7. アプリケーションを開き、右上の ≡ から設定を開く → 権限を追加する | ![image](https://i.gyazo.com/77c40ade286c0e15e6a867bea1e4ba63.png) |  |

対応OS: **macOS 15 以降**

<br/>
<br/>

## 使い方

### 録画する

1. 「録画」ボタン → マウスをドラッグして録画したい範囲を選ぶ
2. 3秒カウントダウンのあと録画開始。クリックした場所には波紋が付きます
3. 画面下の「■ 停止」で終了。クリップボード設定なら **そのまま Cmd+V で GitHub や Slack に貼れます**

- 音を入れたいときはホームの「システム音声」「マイク」をONにする (録画中は停止バーのメーターで音が入っているか確認できる)
- ショートカット: **⌘⇧6 で録画の開始/停止** (設定で変更可)

### スクショを撮る

1. 「スクショ」ボタン → ドラッグで範囲を選ぶ
2. エディタが開くので、矢印・文字・ぼかし・番号バッジなどを書き込む
3. 「コピー」または「保存」で完了。**Shift を押しながら範囲確定すると、エディタを飛ばして即コピー**もできます

- ショートカット: **⌘⇧7 でスクショ** (設定で変更可)

### 設定 (右上のスライダーアイコン)

- テーマ (ダーク / ライト / Macに追従)
- 画質: fps と解像度を個別に選択。組み合わせごとのファイルサイズ目安も表示
- 波紋のスタイル・色・サイズ (プレビュー付き)
- ショートカットキーの変更
- 保存先フォルダ (📁ボタンで選択)

---

## 開発者向け

技術: Swift / SwiftUI + ScreenCaptureKit / AVAssetWriter。Xcodeプロジェクトなし、SwiftPM + Makefile のみ (アプリ本体 約3MB)。

```sh
make run       # ビルドして起動
make install   # /Applications にインストール
make dmg       # 配布用 dmg を dist/ に作成
make clean
```

### リリース手順

```sh
make dmg
gh release create v1.x.x dist/CapNote.dmg --title "v1.x.x" --notes "変更点"
```

dmg のファイル名は **`CapNote.dmg` 固定**にすること。README のダウンロードボタンは
`releases/latest/download/CapNote.dmg` (最新リリースの同名アセットへの直リンク) を指しているため、
リリースを作るだけでボタンの先が自動的に最新になる。

### 配布形態について

- dmg は **ad-hoc署名** (Apple Developer 証明書なし)。そのため初回に「右クリック → 開く」が必要
- 警告なしで配るには Apple Developer Program (年99ドル) + Developer ID 署名 + notarization が必要 (→ docs/open-questions.md #4)

### ライセンス

MIT
