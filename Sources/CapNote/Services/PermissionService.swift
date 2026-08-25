import AVFoundation
import AppKit
import CoreGraphics

enum PermissionService {
    /// 補足: システム音声の録音は「画面収録」権限でカバーされる (専用の権限はない)
    static func check() -> [String: Bool] {
        [
            "screenRecording": CGPreflightScreenCaptureAccess(),
            "accessibility": AXIsProcessTrusted(),
            "microphone": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
        ]
    }

    /// 画面収録権限のプロンプトを出す (既に拒否済みの場合は設定アプリでの許可が必要)
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    /// マイク: 未確認ならプロンプトを出し、拒否済みならシステム設定へ誘導
    static func requestOrOpenMicrophone(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async(execute: completion)
            }
        case .authorized:
            completion()
        default:
            openSystemSettings(pane: "microphone")
            completion()
        }
    }

    static func openSystemSettings(pane: String) {
        let url: String
        switch pane {
        case "accessibility":
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "microphone":
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        default:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
