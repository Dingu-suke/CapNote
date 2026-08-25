import AVFoundation
import AppKit
import ScreenCaptureKit

/// 録画設定 (Flutterから受け取るJSONを正規化したもの)
struct RecordConfig {
    var fps: Int = 10
    var scale: Double = 1.0 // 1.0 = 論理解像度, 2.0 = 物理 (Retina)
    var bitrateKbps: Int? // nil = 自動 (~0.05bpp)
    var displayId: CGDirectDisplayID?
    /// ディスプレイローカル・左上原点・論理座標の切り出し矩形 (nil = ディスプレイ全体)
    var region: CGRect?
    var showCursor: Bool = true
    var outputTarget: String = "clipboard" // clipboard | file
    var saveDirectory: String?
    var fileName: String?
    var maxMinutes: Int = 30

    static func from(_ dict: [String: Any]) -> RecordConfig {
        var c = RecordConfig()
        c.fps = dict["fps"] as? Int ?? c.fps
        c.scale = dict["scale"] as? Double ?? c.scale
        c.bitrateKbps = dict["bitrateKbps"] as? Int
        if let id = dict["displayId"] as? Int { c.displayId = CGDirectDisplayID(id) }
        if let r = dict["region"] as? [String: Any],
           let x = r["x"] as? Double, let y = r["y"] as? Double,
           let w = r["w"] as? Double, let h = r["h"] as? Double {
            c.region = CGRect(x: x, y: y, width: w, height: h)
        }
        c.showCursor = dict["showCursor"] as? Bool ?? c.showCursor
        c.outputTarget = dict["outputTarget"] as? String ?? c.outputTarget
        c.saveDirectory = dict["saveDirectory"] as? String
        c.fileName = dict["fileName"] as? String
        c.maxMinutes = dict["maxMinutes"] as? Int ?? c.maxMinutes
        return c
    }
}

/// ScreenCaptureKit → AVAssetWriter (H.264/mp4) のリアルタイム書き込み。
/// ファイルサイズ最優先: 低fps・低ビットレート・論理解像度 (docs/features/recording.md)。
final class RecorderService: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private var tempURL: URL?
    private var config: RecordConfig?
    private var autoStopTimer: Timer?
    private let sampleQueue = DispatchQueue(label: "mp4recorder.samples")

    var isRecording: Bool { stream != nil }
    /// ディスプレイ構成変更などでストリームが死んだ時の通知
    var onStreamError: ((String) -> Void)?

    /// excludingWindowNumbers: 停止バー等、録画に写したくない自アプリのウィンドウ
    func start(config: RecordConfig, excludingWindowNumbers: [Int]) async throws {
        guard !isRecording else { throw RecorderError.busy }
        self.config = config

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = config.displayId ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayNotFound
        }
        let excluded = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        // 出力ピクセルサイズ: 論理サイズ × scale (Retina 2xをそのまま撮らない)
        let sourceSize = config.region?.size ?? CGSize(width: display.width, height: display.height)
        let width = max(2, Int(sourceSize.width * config.scale)) & ~1 // H.264は偶数サイズ
        let height = max(2, Int(sourceSize.height * config.scale)) & ~1

        let scConfig = SCStreamConfiguration()
        scConfig.width = width
        scConfig.height = height
        scConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        scConfig.showsCursor = config.showCursor
        scConfig.pixelFormat = kCVPixelFormatType_32BGRA
        scConfig.queueDepth = 5
        if let region = config.region {
            scConfig.sourceRect = region // 論理座標・ディスプレイローカル・左上原点
        }

        // AVAssetWriter (mp4 / H.264 High Profile)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mp4recorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("rec_\(Self.timestamp()).mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // 自動ビットレート: ~0.05 bpp (1080p/10fpsで約1Mbps)
        let bitrate = config.bitrateKbps.map { $0 * 1000 }
            ?? max(300_000, Int(Double(width * height * config.fps) * 0.05))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 5,
                AVVideoExpectedSourceFrameRateKey: config.fps,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerFailed
        }

        let stream = SCStream(filter: filter, configuration: scConfig, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.writer = writer
        self.input = input
        self.tempURL = url
        self.sessionStarted = false

        // 長時間録画の自動停止 (証跡用途なので上限で切る)
        let limit = TimeInterval(config.maxMinutes * 60)
        DispatchQueue.main.async { [weak self] in
            self?.autoStopTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { _ in
                self?.onStreamError?("maxDuration")
            }
        }
    }

    /// 停止してmp4を確定。戻り値は一時ファイルパス。
    func stop() async throws -> String {
        guard let stream, let writer, let input, let tempURL else { throw RecorderError.notRecording }
        DispatchQueue.main.async { [weak self] in
            self?.autoStopTimer?.invalidate()
            self?.autoStopTimer = nil
        }
        try? await stream.stopCapture()
        self.stream = nil

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sampleQueue.async {
                input.markAsFinished()
                writer.finishWriting { cont.resume() }
            }
        }
        self.writer = nil
        self.input = nil
        self.config = nil
        self.tempURL = nil
        self.sessionStarted = false
        if writer.status == .failed {
            try? FileManager.default.removeItem(at: tempURL)
            throw writer.error ?? RecorderError.writerFailed
        }
        return tempURL.path
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let writer, let input else { return }
        // 完全フレームのみ書く (idle/blankフレームを除外)
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStreamError?(error.localizedDescription)
        }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

enum RecorderError: LocalizedError {
    case busy, displayNotFound, notRecording, writerFailed

    var errorDescription: String? {
        switch self {
        case .busy: return "すでに録画中です"
        case .displayNotFound: return "対象ディスプレイが見つかりません"
        case .notRecording: return "録画していません"
        case .writerFailed: return "動画の書き込みに失敗しました"
        }
    }
}
