import AppKit
import Carbon

final class HotKeys {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    var action: ((Int) -> Void)?

    static let bindings: [(code: UInt32, modifiers: UInt32, label: String)] = [
        (UInt32(kVK_ANSI_Backslash), UInt32(cmdKey), "⌘\\"),
    ]

    @discardableResult
    func register() -> [String] {
        stop()
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr else { return result }
            let me = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let id = Int(key.id)
            DispatchQueue.main.async { me.action?(id) }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return ["Couldn’t install keyboard shortcuts (\(status))."] }
        var errors: [String] = []
        for (i, b) in Self.bindings.enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(b.code, b.modifiers, EventHotKeyID(signature: 0x4C494C41           , id: UInt32(i)),
                                             GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { keys.append(ref) } else {
                errors.append("\(b.label) is unavailable; another app may be using it.")
            }
        }
        return errors
    }

    func stop() {
        for key in keys { UnregisterEventHotKey(key) }
        keys = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
