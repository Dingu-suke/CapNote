import AppKit
import CoreGraphics

enum PermissionService {
    static func check() -> [String: Bool] {
        [
            "screenRecording": CGPreflightScreenCaptureAccess(),
            "accessibility": AXIsProcessTrusted(),
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

    static func openSystemSettings(pane: String) {
        let url: String
        switch pane {
        case "accessibility":
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        default:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
