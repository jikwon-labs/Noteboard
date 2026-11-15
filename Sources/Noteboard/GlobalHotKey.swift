import AppKit
import Carbon
import NoteboardCore

/// 어느 앱에 있든 눌리는 전역 단축키. Carbon RegisterEventHotKey 를 쓰므로 손쉬운 사용 권한이 필요 없다.
final class GlobalHotKey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// 등록에 실패하면(다른 앱이 이미 쓰는 조합 등) false.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        var mods: UInt32 = 0
        if shortcut.command { mods |= UInt32(cmdKey) }
        if shortcut.option { mods |= UInt32(optionKey) }
        if shortcut.control { mods |= UInt32(controlKey) }
        if shortcut.shift { mods |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: OSType(0x4E54_4244), id: 1) // 'NTBD'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            hotKeyRef = nil
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
