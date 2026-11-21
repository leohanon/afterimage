import AppKit
import Carbon.HIToolbox

/// One system-wide keyboard shortcut, registered with Carbon's RegisterEventHotKey.
/// It works in the App Sandbox and needs no Accessibility permission.
final class HotKey {
    struct Combo: Equatable {
        var keyCode: UInt32
        var modifiers: NSEvent.ModifierFlags
        var display: String
    }

    var onPress: () -> Void = {}
    private(set) var combo: Combo?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private static let defaultsKey = "toggleShortcut"
    private static weak var current: HotKey?

    init() {
        let d = UserDefaults.standard.dictionary(forKey: Self.defaultsKey)
        if let code = d?["keyCode"] as? Int, let mods = d?["modifiers"] as? Int, let display = d?["display"] as? String {
            combo = Combo(keyCode: UInt32(code), modifiers: NSEvent.ModifierFlags(rawValue: UInt(mods)), display: display)
        }
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.current?.onPress() }
            return noErr
        }, 1, &spec, nil, &handler)
        register()
    }

    /// Saves (or clears, with nil) the shortcut and registers it.
    func set(_ new: Combo?) {
        combo = new
        if let c = new {
            UserDefaults.standard.set(["keyCode": Int(c.keyCode), "modifiers": Int(c.modifiers.rawValue), "display": c.display],
                                      forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
        register()
    }

    /// Stops listening while the user is choosing a new shortcut, so pressing the old one doesn't toggle.
    func suspend() { unregister() }
    func resume() { register() }

    private func register() {
        unregister()
        guard let c = combo else { return }
        let id = EventHotKeyID(signature: OSType(0x4146_5449), id: 1)  // 'AFTI'
        RegisterEventHotKey(c.keyCode, Self.carbonModifiers(c.modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private static func carbonModifiers(_ m: NSEvent.ModifierFlags) -> UInt32 {
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.option) { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        if m.contains(.shift) { r |= UInt32(shiftKey) }
        return r
    }

    /// Builds a shortcut from a key press, or nil if it isn't usable as a global shortcut.
    static func combo(from event: NSEvent) -> Combo? {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let fKeys: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        ]
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        let key: String
        if let f = fKeys[code] {
            key = f
        } else if let n = named[code] {
            key = n
        } else if let ch = event.charactersIgnoringModifiers?.uppercased(), !ch.isEmpty,
                  ch.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            key = ch
        } else {
            return nil
        }
        // Without ⌘, ⌥ or ⌃ the shortcut would swallow ordinary typing; function keys are fine alone.
        guard fKeys[code] != nil || !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return Combo(keyCode: UInt32(code), modifiers: mods, display: s + key)
    }
}
