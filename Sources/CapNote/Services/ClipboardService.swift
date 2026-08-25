import AppKit

enum ClipboardService {
    /// PNG画像をクリップボードにコピー (GitHub PR等に Cmd+V で貼れる)
    static func copyImage(path: String) -> Bool {
        guard let image = NSImage(contentsOfFile: path) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([image])
    }

    /// ファイル参照をコピー (mp4用。Finder的なファイルコピー扱い)
    static func copyFileURL(path: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
    }

    static func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
