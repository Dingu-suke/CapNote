import AppKit
import SwiftUI

@main
struct CapNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .background(WindowAccessor { window in
                    app.mainWindow = window
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.backgroundColor = Brand.bgNS
                })
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) {} // 新規ウィンドウを無効化 (単一ウィンドウアプリ)
        }

        // 設定は独立ウィンドウ (メインが小さくてもレイアウトが崩れない)
        Window("設定", id: "settings") {
            SettingsView()
                .environmentObject(app)
                .background(WindowAccessor { window in
                    window.backgroundColor = Brand.bgNS
                })
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 録画・範囲選択中はメインウィンドウを orderOut で隠すが、
    /// その状態を AppKit が「最後のウィンドウが閉じた」と判定して terminate し始めるのを防ぐ。
    @MainActor static var suppressAutoTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Self.suppressAutoTerminate
    }
}

/// SwiftUIビューから NSWindow への参照を取るためのブリッジ
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch app.route {
                case .home:
                    HomeView()
                case .editor(let imagePath):
                    AnnotationEditorView(imagePath: imagePath)
                }
            }
            if let toast = app.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.toast)
        .frame(minWidth: 560, minHeight: 480)
        .background(Brand.bg)
    }
}

struct ToastView: View {
    @EnvironmentObject private var app: AppState
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color(hex: 0xFF7A6B) : Brand.tealA)
            Text(toast.message)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.textHi)
                .lineLimit(2)
            if let path = toast.path {
                Button("Finderで表示") {
                    ClipboardService.revealInFinder(path: path)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.tealA)
            }
            Button {
                app.toast = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.textLo)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Brand.surfaceHi)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.border))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        )
        .padding(.horizontal, 24)
    }
}
