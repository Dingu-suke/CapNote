# データモデル (data-model)

アプリはDBを持たない。モデルは「設定 (永続化)」と「実行時状態」の2種類。

## 設定 (UserDefaults / shared_preferences に永続化)

### AppSettings

```dart
class AppSettings {
  OutputTarget outputTarget;       // clipboard | file
  String saveDirectory;            // 既定: ~/Movies/mp4recorder, ~/Pictures/mp4recorder
  String fileNameTemplate;         // "rec_{timestamp}" / "shot_{timestamp}"
  RecordingSettings recording;
  RippleSettings ripple;
  AnnotationDefaults annotation;
}
```

### OutputTarget

```dart
enum OutputTarget { clipboard, file }
// 録画のclipboardは「ファイルURL参照のコピー」(mp4本体は一時ファイルに書く)
```

### RecordingSettings

```dart
class RecordingSettings {
  QualityPreset preset;        // light(既定) | standard | high
  int fps;                     // light=10, standard=15, high=30
  double scale;                // 1.0 = 論理解像度 (Retinaでも1x)。high=物理解像度
  int? bitrateKbps;            // null=プリセット自動 (~0.05bpp)
  CaptureScope scope;          // fullScreen | display(displayId) | region(rect)
  bool showCursor;             // 既定 true
}

enum QualityPreset { light, standard, high }
```

| preset | fps | scale | 1080p換算ビットレート | 30秒の目安サイズ |
|--------|-----|-------|----------------------|-----------------|
| light (既定) | 10 | 1.0 (論理) | ~1.0 Mbps | ~2-4 MB |
| standard | 15 | 1.0 | ~2.0 Mbps | ~5-8 MB |
| high | 30 | 2.0 (物理) | ~6.0 Mbps | ~20 MB+ |

### RippleSettings

```dart
class RippleSettings {
  RippleStyle style;       // ring(既定) | filledCircle | doubleRing | highlight
  Color color;             // 既定: 黄 (視認性)
  double size;             // 波紋の最大半径 px。既定 40
  int durationMs;          // アニメーション時間。既定 500
  bool enabled;            // 既定 true (録画中のみ表示)
}

enum RippleStyle { ring, filledCircle, doubleRing, highlight }
```

| style | 見た目 |
|-------|--------|
| ring | 円周だけの輪が広がって消える |
| filledCircle | 半透明の塗り円がフェードアウト |
| doubleRing | 輪が2重で時間差で広がる |
| highlight | クリック位置に一定時間スポット表示 (じわっと消える) |

### AnnotationDefaults

```dart
class AnnotationDefaults {
  Color color;          // 既定: 赤
  double strokeWidth;   // 既定: 3 (細=2/中=3/太=6)
  double fontSize;      // 既定: 16
}
```

## 実行時モデル

### RecordingSession

```dart
class RecordingSession {
  String id;
  RecordingState state;    // idle | countdown | recording | encoding | done | error
  DateTime startedAt;
  Duration elapsed;
  CaptureScope scope;
  String? outputPath;      // 完了後にセット
}
```

### Annotation (注釈エディタ)

```dart
sealed class Annotation {
  String id;
  Color color;
  double strokeWidth;
}
class RectAnnotation extends Annotation { Rect rect; bool filled; }
class EllipseAnnotation extends Annotation { Rect rect; bool filled; }
class LineAnnotation extends Annotation { Offset start, end; }
class ArrowAnnotation extends Annotation { Offset start, end; }
class FreehandAnnotation extends Annotation { List<Offset> points; }
class TextAnnotation extends Annotation { Offset position; String text; double fontSize; }
class BadgeAnnotation extends Annotation { Offset position; int number; }
class BlurAnnotation extends Annotation { Rect rect; double intensity; }
```

- エディタ状態: `List<Annotation>` + undo/redoスタック (`List<List<Annotation>>` のスナップショット方式で十分)
- 出力時に元画像 + 注釈を1枚に合成 (Canvas → PNG)

### DisplayInfo (マルチモニター)

```dart
class DisplayInfo {
  int displayId;        // CGDirectDisplayID
  Rect frame;           // グローバル座標
  double scaleFactor;   // Retina=2.0
  bool isMain;
}
```

- Swift側から `getDisplays()` で取得。録画のディスプレイ選択・範囲選択のグローバル座標変換に使う
- 座標系メモ: macOSのグローバル座標は左下原点、Flutterは左上原点。**Channel境界で必ず左上原点に正規化**する

## Platform Channel API (Dart ⇔ Swift)

| Method | 引数 | 戻り |
|--------|------|------|
| `getDisplays` | – | `List<DisplayInfo>` |
| `checkPermissions` | – | `{screenRecording: bool, accessibility: bool}` |
| `startRecording` | RecordingSettings(JSON) | sessionId |
| `stopRecording` | sessionId | outputPath |
| `takeScreenshot` | CaptureScope(JSON) | PNG一時ファイルパス |
| `copyToClipboard` | path, type(image/fileUrl) | bool |
| `setRippleStyle` | RippleSettings(JSON) | – |

| Event (EventChannel) | 内容 |
|----------------------|------|
| `recordingState` | state遷移・経過時間 |
| `error` | 権限エラー・エンコード失敗など |
