import AVFoundation

/// システム音声 + マイクの2トラックを1本のステレオAACにミックスする後処理。
/// 2トラックのままだとブラウザ等で片方しか再生されないため (open-questions #11)。
/// ビデオは再エンコードせずそのままコピーする (画質・サイズ・処理時間に影響なし)。
enum AudioMixdown {
    /// 音声トラックが2本以上ある場合のみミックスし、元ファイルを置き換える。
    /// 戻り値は最終的なファイルパス (1本以下ならそのまま)。
    static func mixIfNeeded(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count >= 2 else { return path }
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return path
        }
        let videoFormat = try await videoTrack.load(.formatDescriptions).first

        let reader = try AVAssetReader(asset: asset)
        // ビデオはデコードせず圧縮サンプルをそのまま読む (outputSettings: nil = パススルー)
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(videoOut)
        // 全音声トラックをミックスしてPCMで受け取る
        let audioOut = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
        ])
        reader.add(audioOut)

        let outURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_mix.mp4")
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ])
        audioIn.expectsMediaDataInRealTime = false
        writer.add(audioIn)

        guard reader.startReading() else { throw reader.error ?? RecorderError.writerFailed }
        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            pump(input: videoIn, output: videoOut, queue: DispatchQueue(label: "mixdown.video"), group: group)
            pump(input: audioIn, output: audioOut, queue: DispatchQueue(label: "mixdown.audio"), group: group)
            group.notify(queue: .global()) { cont.resume() }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outURL)
            // ミックス失敗時は2トラックの元ファイルをそのまま使う (録画自体は失わない)
            return path
        }
        // 元ファイルを置き換え (ファイル名は維持)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: outURL, to: url)
        return url.path
    }

    private static func pump(
        input: AVAssetWriterInput, output: AVAssetReaderOutput,
        queue: DispatchQueue, group: DispatchGroup
    ) {
        group.enter()
        var finished = false
        input.requestMediaDataWhenReady(on: queue) {
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                if let sb = output.copyNextSampleBuffer() {
                    if !input.append(sb) {
                        finished = true
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                } else {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }
}
