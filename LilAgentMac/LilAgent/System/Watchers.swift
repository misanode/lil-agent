import AppKit
import CoreGraphics

final class KeyWatcher {
    enum Status: String {
        case off, ready, unavailable
        case needsPermission = "needs-permission"
    }

    private(set) var status: Status = .off {
        didSet { if oldValue != status { onStatus?() } }
    }
    var onKey: ((Int64, String) -> Void)?
    var onKeyUp: ((Int64) -> Void)?
    var onStatus: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var wanted = false
    private var asked = false
    private var retry: Timer?

    func sync(_ enabled: Bool) {
        wanted = enabled
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard wanted, tap == nil else { return }
        retry?.invalidate()
        retry = nil
        if !CGPreflightListenEventAccess() {
            status = .needsPermission
            if !asked {
                asked = true
                CGRequestListenEventAccess()
            }
            scheduleRetry()
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: keyTapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status = .unavailable
            scheduleRetry()
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        status = .ready
    }

    private func scheduleRetry() {
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.start() }
    }

    func stop() {
        retry?.invalidate()
        retry = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        status = .off
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp { return onKeyUp?(code) ?? () }
        guard type == .keyDown else { return }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { return }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        if length > 0 { onKey?(code, String(utf16CodeUnits: chars, count: length)) }
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<KeyWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) }
    return Unmanaged.passUnretained(event)
}

final class MusicWatcher {
    private static let players = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")]
    private(set) var playing = false
    private let enabled: () -> Bool
    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var busy = false

    init(enabled: @escaping () -> Bool, onChange: @escaping (Bool) -> Void) {
        self.enabled = enabled
        self.onChange = onChange
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.poll() }
        }
        poll()
    }

    func poll() {
        guard !busy else { return }
        guard enabled() else { return set(false) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let apps = Self.players.filter { running.contains($0.0) }.map(\.1)
        if apps.isEmpty { return set(false) }
        busy = true
        DispatchQueue.global(qos: .utility).async {
            let now = apps.contains { Self.state(of: $0) == "playing" }
            DispatchQueue.main.async {
                self.busy = false
                self.set(now)
            }
        }
    }

    private func set(_ now: Bool) {
        if now != playing {
            playing = now
            onChange(now)
        }
    }

    private static func state(of app: String) -> String {
        let script = "if application \"\(app)\" is running then\n  tell application \"\(app)\" to return (player state as text)\nend if\nreturn \"stopped\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "unknown" }
        let deadline = Date().addingTimeInterval(4)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return "unknown" }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func systemIdleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}
