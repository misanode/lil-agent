import AppKit
import QuartzCore

var launchStart = CACurrentMediaTime()

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let startupLimit = 60.0

    private var controller: PetController?
    private var splash: SplashWindow?
    private var startup: StartupCoordinator?
    private var watchdog: Timer?
    private let debug = ProcessInfo.processInfo.environment

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty && debug["LILAGENT_SNAPSHOT"] == nil {
            NSLog("\(Brand.name) is already running (check the menu bar). Quitting this copy.")
            NSApp.terminate(nil)
            return
        }
        let film = debug["LILAGENT_SPLASH_FILM"]
        let coordinator = StartupCoordinator(entered: debug["LILAGENT_SNAPSHOT"] != nil)
        startup = coordinator
        coordinator.onFinish = { [weak self] in self?.finishStartup() }
        coordinator.onFail = { [weak self] message in self?.failStartup(message) }
        if debug["LILAGENT_SNAPSHOT"] == nil, let splash = SplashWindow(screen: NSScreen.screens.first) {
            self.splash = splash
            splash.show { [weak self] in
                if film == nil { self?.startup?.entranceDone() }
            }
            if let film { filmSplash(splash, into: film) }
        } else {
            coordinator.entranceDone()
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: Self.startupLimit, repeats: false) { [weak self] _ in
            self?.startup?.fail("\(Brand.name) took too long to start. Try opening it again.")
        }

        let saved = SettingsStore().values.character
        let character = PetCharacter(rawValue: debug["LILAGENT_CHARACTER"] ?? saved) ?? .clawd
        let t0 = CACurrentMediaTime()
        let failLoad = debug["LILAGENT_FAIL_STARTUP"] != nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result<Mascot, Error> {
                if failLoad { throw GLTFError(message: "Startup failure requested by LILAGENT_FAIL_STARTUP.") }
                return Mascot(asset: try character.loadModel())
            }
            let t1 = CACurrentMediaTime()
            DispatchQueue.main.async { self?.modelLoaded(result, character: character, t0: t0, t1: t1) }
        }
    }

    private func modelLoaded(_ result: Result<Mascot, Error>, character: PetCharacter, t0: CFTimeInterval, t1: CFTimeInterval) {
        guard startup?.phase == .starting else { return }
        switch result {
        case .success(let mob):
            let t2 = CACurrentMediaTime()
            let controller = PetController(mob: mob, character: character)
            controller.onFirstFrames = { [weak self] in self?.startup?.appReady() }
            self.controller = controller
            NSLog("startup: model parse %.0f ms, setup %.0f ms", (t1 - t0) * 1000, (CACurrentMediaTime() - t2) * 1000)
            launchStart = t0
        case .failure(let error):
            startup?.fail(error.localizedDescription)
        }
    }

    private func finishStartup() {
        watchdog?.invalidate()
        watchdog = nil
        controller?.reveal()
        splash?.dismiss { [weak self] in self?.splash = nil }
    }

    private func failStartup(_ message: String) {
        watchdog?.invalidate()
        watchdog = nil
        splash?.tearDown()
        splash = nil
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(Brand.name) couldn't start"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func filmSplash(_ splash: SplashWindow, into dir: String) {
        let times = (debug["LILAGENT_SPLASH_FILM_AT"] ?? "0,0.05,24").split(separator: ",").compactMap { Double($0) }
        guard times.count == 3 else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let start = DispatchTime.now()
        for k in 0..<Int(times[2]) {
            DispatchQueue.main.asyncAfter(deadline: start + times[0] + Double(k) * times[1]) {
                if let png = splash.capture()?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "f%02d.png", k)))
                }
                if k == Int(times[2]) - 1 { NSApp.terminate(nil) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startup?.cancel()
        watchdog?.invalidate()
        splash?.tearDown()
    }
}
