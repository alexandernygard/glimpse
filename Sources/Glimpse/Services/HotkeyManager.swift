import Foundation
import Carbon

/// Global hotkeys via Carbon's RegisterEventHotKey. Works without Accessibility permission.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x474C_4D50 // 'GLMP'

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
            handlers[id] = handler
        } else {
            NSLog("Glimpse: failed to register hotkey \(id), status \(status)")
        }
    }

    private func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            // The application event target dispatches on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire(id: id)
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandlerRef)
    }
}
