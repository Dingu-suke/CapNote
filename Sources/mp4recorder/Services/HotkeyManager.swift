import AppKit
import Carbon.HIToolbox

/// グローバルショートカットのキー定義。
/// Carbon の RegisterEventHotKey を使うためアクセシビリティ権限は不要。
struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var carbonModifiers: UInt32
    var display: String // 例: "⌘⇧6"
    var enabled: Bool = true

    static let defaultRecord = Hotkey(keyCode: 22, carbonModifiers: UInt32(cmdKey | shiftKey), display: "⌘⇧6")
    static let defaultScreenshot = Hotkey(keyCode: 26, carbonModifiers: UInt32(cmdKey | shiftKey), display: "⌘⇧7")

    // 後から enabled を追加したため decodeIfPresent
    init(keyCode: UInt16, carbonModifiers: UInt32, display: String, enabled: Bool = true) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        carbonModifiers = try c.decode(UInt32.self, forKey: .carbonModifiers)
        display = try c.decode(String.self, forKey: .display)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// 設定画面のキーレコーダー用: NSEvent から生成。修飾キーなしは不可 (誤爆防止)
    static func from(event: NSEvent) -> Hotkey? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else { return nil }
        var carbon: UInt32 = 0
        var sym = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); sym += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); sym += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); sym += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); sym += "⌘" }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        return Hotkey(keyCode: event.keyCode, carbonModifiers: carbon, display: sym + key)
    }
}

/// Carbon ホットキーの登録・ディスパッチ
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    fileprivate func dispatch(id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID
            )
            let id = hkID.id
            Task { @MainActor in HotkeyManager.shared.dispatch(id: id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// id ごとに1つのホットキーを登録。hotkey が nil / disabled なら解除のみ。
    func set(id: UInt32, hotkey: Hotkey?, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
        actions[id] = nil
        guard let hk = hotkey, hk.enabled else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D50_4452), id: id) // 'MPDR'
        let status = RegisterEventHotKey(
            UInt32(hk.keyCode), hk.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[id] = ref
            actions[id] = action
        }
    }
}
