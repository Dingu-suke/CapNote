# mp4recorder

PR証跡用の macOS 録画 + スクショアプリ。**Swift / SwiftUI 製ネイティブアプリ** (アプリ本体 約3MB)。

- 📹 軽量mp4録画 (カーソル表示・クリック波紋つき) — GitHub PRにそのまま添付できるサイズを目指す
- ✂️ 切り取りスクショ + 注釈 (矢印・テキスト・ぼかし等、Awesome Screenshot風)
- 📋 クリップボードコピー / 💾 ファイル保存 を選択可
- 🖥 マルチモニター対応

技術: SwiftUI (UI) + ScreenCaptureKit / AVAssetWriter (キャプチャ・エンコード)。Xcodeプロジェクトなし、SwiftPM + Makefile だけでビルドできる。

## ドキュメント

| ファイル | 内容 |
|---------|------|
| [docs/requirements.md](docs/requirements.md) | 要件定義 |
| [docs/design/design.md](docs/design/design.md) | アーキテクチャ設計 |
| [docs/design/design-ui.md](docs/design/design-ui.md) | 画面設計 |
| [docs/design/data-model.md](docs/design/data-model.md) | データモデル |
| [docs/features/](docs/features/) | 機能別詳細仕様 (録画 / 波紋 / スクショ注釈) |
| [docs/tasks.md](docs/tasks.md) | タスク一覧 |
| [docs/open-questions.md](docs/open-questions.md) | 未確定事項・考慮事項 |

## インストール (ビルド不要・dmgから)

1. **[最新の dmg をダウンロード](https://github.com/Dingu-suke/mp4recorder/releases/latest)** (`mp4recorder.dmg`)
2. dmg を開いて `mp4recorder.app` を `Applications` フォルダにドラッグ
3. 初回は Gatekeeper に止められるので、アプリを **右クリック → 開く** → 「開く」
   (または `xattr -cr /Applications/mp4recorder.app`)
4. 起動すると **画面収録の権限** を求められる。システム設定で許可 →
   **macOS がアプリを一度終了させる (OSの仕様)** ので、もう一度起動する
5. (任意) クリック波紋を使う場合はアクセシビリティ権限も許可

> dmg は Apple Developer 証明書なしの ad-hoc 署名のため手順3が必要。
> 署名済み配布にするには Apple Developer Program (年99ドル) + notarization が要る。

## ビルド・起動 (ソースから)

前提: Xcode (ビルドツールとして。App Storeから) + Command Line Tools。

```sh
make run       # ビルドして起動
make install   # /Applications にインストール
make dmg       # 配布用 dmg を dist/ に作成
make clean
```

初回起動時に **画面収録の権限** を求められます。
**許可すると macOS がアプリを一度終了させる (OSの仕様) ので、再起動してください。**
波紋用のアクセシビリティ権限は任意です (なくても録画はできます)。

## 使い方

### ショートカット・テーマ

- グローバルショートカット (既定): **録画 開始/停止 ⌘⇧6 / スクショ ⌘⇧7**。設定でキー変更・無効化可
- テーマ: ダーク (既定) / ライト / Macの設定に追従 を設定で切替

### 録画 (mp4)

1. ホームで出力先 (クリップボード / ファイル) と録画範囲を選ぶ。**既定は「切り取り」(ドラッグで範囲指定)**
2. 「録画」→ (切り取りならドラッグ) → 3秒カウントダウン → 録画開始
3. 録画中はクリック位置に波紋が写り込む。停止は画面下の停止バー or メニューバーの■アイコン
4. 停止すると出力先に従って mp4 をコピー / 保存 (`~/Movies/mp4recorder/rec_日時.mp4`)

既定は 10fps・論理解像度・約1Mbps。1080p・30秒で 2〜4MB 程度になり、
GitHub PR にそのままドラッグ&ドロップ / Cmd+V で添付できる (添付上限100MB)。
**fps (5〜30) と解像度 (論理 / Retina 2x) は設定画面で個別に選択**でき、組み合わせごとの容量目安も表示される。

### スクショ + 注釈

1. 「スクショ」→ 画面がフリーズし、ドラッグで切り取り (Esc でキャンセル、**Shift+確定でエディタを飛ばして即出力**)
2. 注釈エディタで 矩形 / 楕円 / 直線 / 矢印 / フリーハンド / テキスト / 番号バッジ / ぼかし を描く
   - Undo/Redo: Cmd+Z / Cmd+Shift+Z。選択ツールで移動・Delete削除、テキストはダブルクリックで再編集
   - トリミングは下部のボタンから
3. 「コピー」(PNGをクリップボードへ) or 「保存」(`~/Pictures/mp4recorder/shot_日時.png`)

## 配布 (dmg)

```sh
make dmg    # → dist/mp4recorder.dmg
```

現状は **ad-hoc署名 (Apple Developer 証明書なし)** なので、配布先の Mac では初回に Gatekeeper に止められる。
受け取った人は次のどちらかで開ける:

- アプリを **右クリック → 開く** (「開発元を確認できません」→ 開く)
- またはターミナルで `xattr -cr /Applications/mp4recorder.app`

警告なしで配りたくなったら Apple Developer Program (年99ドル) に加入して
Developer ID 署名 + notarization が必要 (→ docs/open-questions.md #4)。

### リリース手順 (メンテナ向け)

```sh
make dmg
gh release create v1.x.x dist/mp4recorder.dmg --title "v1.x.x" --notes "変更点"
```

これで README 冒頭の「最新の dmg をダウンロード」リンク (releases/latest) が新しい dmg を指す。

## 補足

- 当初 Flutter + Swift のハイブリッドで実装したが、コア機能がすべて Swift 側になり
  Flutter の利点がなかったため **SwiftUI に全面書き換えた** (履歴は git 参照)。
  アプリサイズが約50MB→約3MBになり、起動も速くなった
