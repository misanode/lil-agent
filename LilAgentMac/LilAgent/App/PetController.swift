import AppKit
import SwiftUI
import SceneKit
import ServiceManagement

final class PetController: NSObject, NSMenuDelegate, SCNSceneRendererDelegate {
    private static let stripHeightRatio = 2.6
    private static let idlePoll = 5.0
    private static let awayWhileWaiting = 30.0 * 60
    private static let asleep: Set<String> = ["sleep", "sleepy"]
    private static let agentBusy = AgentBridge.working.union(["attention", "permission", "question"])
    private static let claudeStatus = ["attention": "Claude needs you", "permission": "Claude needs your permission",
                                       "question": "Claude has a question", "thinking": "Claude is thinking",
                                       "typing": "Claude is writing", "reading": "Claude is reading", "searching": "Claude is searching",
                                       "command": "Claude is running a command", "planning": "Claude is planning",
                                       "subagents": "Claude sent out helpers", "compacting": "Claude is compacting",
                                       "error": "Something failed", "waiting": "Claude is waiting for you", "idle": "Claude is idle"]
    private static let sizeStep = 1.15

    private let store = SettingsStore()
    private let stage = Stage()
    private let screenSpace: ScreenSpace
    private let window: PetWindow
    private let view: PetView
    private let pet: Pet
    private let pointer: PointerDirector
    private let agent: AgentDirector
    private var bridge: AgentBridge!
    private var music: MusicWatcher!
    private let keys = KeyWatcher()
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let settingsModel: SettingsModel
    private var settingsWindow: SettingsWindow?
    private let hotKeys = HotKeys()
    private let updates = UpdateChecker(current: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    private var mascotHidden = false
    private var expanded = false
    private var idleSleeping = false
    private var idleTimer: Timer?
    private let debug = ProcessInfo.processInfo.environment

    private struct Shared {
        var settings: PetSettings
        var viewSize: CGSize
        var windowFrame: NSRect
        var screenHeight: Double
        var backingScale: Double
    }

    private struct Published {
        var stateName = "boot"
        var over = false
        var dragging = false
        var activity: AgentActivity?
        var userTyping = false
        var petRect = CGRect.zero
    }

    private let simLock = NSLock()
    private var simQueue: [() -> Void] = []
    private var shared: Shared
    private var published = Published()

    private var lastTime: TimeInterval?
    private var avgFrame = 1.0 / 60
    private var elapsed = 0.0
    private var homeRestored = false
    private var centeredHome = false
    private var simScreenHeight = 900.0
    private var lastPointer: (Double, Double)?
    private var simSettings: PetSettings

    private var character: PetCharacter
    private var loadingCharacter: PetCharacter?

    var onFirstFrames: (() -> Void)?
    private var revealed = false

    init(mob: Mascot, character: PetCharacter = .clawd) {
        self.character = character
        screenSpace = ScreenSpace(stage: stage)
        stage.scene.rootNode.addChildNode(mob.root)
        window = PetWindow(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        view = PetView(frame: window.contentLayoutRect, options: [SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue)])
        pet = Pet(mob: mob, scene: stage.scene, settings: store.values)
        pointer = PointerDirector(pet: pet, screen: screenSpace)
        agent = AgentDirector(pet: pet, settings: store.values)
        shared = Shared(settings: store.values, viewSize: .zero, windowFrame: .zero, screenHeight: 900, backingScale: 2)
        simSettings = store.values
        settingsModel = SettingsModel(values: store.values)
        super.init()

        view.autoresizingMask = [.width, .height]
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 120
        view.wantsLayer = true
        view.layer?.isOpaque = false
        window.contentView = view
        updateWindowFrame()

        view.onDown = { [weak self] x, y in
            self?.onSim {
                guard let self else { return }
                self.pointer.move(x, y)
                self.pointer.down(x, y)
            }
        }
        view.onUp = { [weak self] in self?.onSim { self?.pointer.up() } }
        view.onRightDown = { [weak self] e in self?.rightClicked(e) }
        view.onScroll = { [weak self] d in self?.onSim { self?.pointer.wheel(d) } }
        pointer.size = { [weak self] in Double(self?.simSettings.petSize ?? PetSizes.defaultSize) }
        pointer.onResize = { [weak self] px in DispatchQueue.main.async { self?.store.update { $0.petSize = PetSizes.clampSize(px) } } }
        pointer.onOverChange = { [weak self] over in DispatchQueue.main.async { self?.window.ignoresMouseEvents = !over } }
        pointer.onAirborneChange = { [weak self] on in
            DispatchQueue.main.async {
                self?.expanded = on
                self?.updateWindowFrame()
            }
        }

        store.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }

        bridge = AgentBridge { [weak self] a in self?.onSim { self?.agent.setAgent(a) } }
        bridge.start()
        music = MusicWatcher(enabled: { [weak self] in self?.store.values.musicDance ?? false },
                             onChange: { [weak self] playing in self?.onSim { self?.agent.setMusic(playing) } })
        music.start()
        keys.onKey = { [weak self] code, ch in
            guard let self, !self.mascotHidden else { return }
            self.onSim { self.agent.onKey(ch, code: code) }
        }
        keys.onKeyUp = { [weak self] code in self?.onSim { self?.agent.onKeyUp(code) } }
        keys.onStatus = { [weak self] in self?.keyStatusChanged() }
        keys.sync(store.values.typeAlong && debug["LILAGENT_NO_KEYS"] == nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = Bundle.main.image(forResource: "trayTemplate") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "🦀"
        }
        statusItem.button?.toolTip = character.title
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        window.level = store.values.keepOnTop ? .floating : .normal
        setUpSettings()
        updates.onChange = { [weak self] status in
            self?.settingsModel.update = status
            self?.buildStatusMenu()
        }
        if debug["LILAGENT_SNAPSHOT"] == nil && debug["LILAGENT_SPLASH_FILM"] == nil { updates.start() }
        hotKeys.action = { [weak self] _ in
            guard let self, self.store.values.showHideShortcut else { return }
            self.toggleMascot()
        }
        syncShowHideShortcut()

        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idlePoll, repeats: true) { [weak self] _ in self?.pollIdle() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateWindowFrame()
        }
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
            self?.refreshShared()
        }
        view.postsFrameChangedNotifications = true
        refreshShared()

        view.delegate = self
        window.alphaValue = 0
        window.orderFrontRegardless()
        startDebugHooks()
    }


    private var screen: NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    private func stripFrame() -> NSRect {
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let h = expanded ? vf.height : min(vf.height, (Double(store.values.petSize) * Self.stripHeightRatio).rounded())
        return NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: h)
    }

    private func updateWindowFrame() {
        let f = stripFrame()
        if window.frame != f { window.setFrame(f, display: true) }
        refreshShared()
    }


    private func onSim(_ job: @escaping () -> Void) {
        simLock.lock()
        simQueue.append(job)
        simLock.unlock()
    }

    private func refreshShared() {
        let s = Shared(settings: store.values, viewSize: view.bounds.size, windowFrame: window.frame,
                       screenHeight: Double(screen?.visibleFrame.height ?? 900), backingScale: Double(window.backingScaleFactor))
        simLock.lock()
        shared = s
        simLock.unlock()
    }

    private var pub: Published {
        simLock.lock()
        defer { simLock.unlock() }
        return published
    }


    private var profTicks: [Double] = []
    private var profDts: [Double] = []
    private var profStart = now()
    private var renderTimes: [Double] = []
    private let renderLock = NSLock()

    private var framesDrawn = 0

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        framesDrawn += 1
        if framesDrawn == 1 {
            NSLog("startup: first frame drawn %.0f ms after launch", (CACurrentMediaTime() - launchStart) * 1000)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let ready = self.onFirstFrames { ready() } else { self.reveal() }
            }
        }
        guard debug["LILAGENT_PROFILE"] != nil else { return }
        renderLock.lock()
        renderTimes.append(now())
        renderLock.unlock()
    }

    private func profile(_ dt: Double, _ cost: Double) {
        profTicks.append(cost)
        profDts.append(dt)
        guard now() - profStart > 3 else { return }
        let sortedDt = profDts.sorted()
        let median = sortedDt[sortedDt.count / 2]
        let late = profDts.filter { $0 > median * 1.5 }.count
        renderLock.lock()
        defer { renderLock.unlock() }
        let renders = renderTimes.count
        let gaps = zip(renderTimes.dropFirst(), renderTimes).map { $0 - $1 }.sorted()
        let renderMedian = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
        let renderLate = gaps.filter { $0 > renderMedian * 1.5 }.count
        renderTimes = []
        NSLog(String(format: "renders %d (late %d, median gap %.2f ms)", renders, renderLate, renderMedian * 1000))
        NSLog(String(format: "frames %d  fps %.1f  median dt %.2f ms  late %d  tick avg %.2f ms  max %.2f ms", profDts.count,
                     Double(profDts.count) / (now() - profStart), median * 1000, late,
                     profTicks.reduce(0, +) / Double(profTicks.count) * 1000, (profTicks.max() ?? 0) * 1000))
        var hist: [Int: Int] = [:]
        for d in profDts { hist[Int((d * 1000).rounded()), default: 0] += 1 }
        NSLog("dt histogram (ms: count): " + hist.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " "))
        profTicks = []
        profDts = []
        profStart = now()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let tickStart = now()
        simLock.lock()
        let jobs = simQueue
        simQueue.removeAll()
        let snap = shared
        simLock.unlock()

        let raw = lastTime.map { max(time - $0, 0) } ?? 0
        lastTime = time
        if raw > 0 && raw < 0.1 { avgFrame += (raw - avgFrame) * 0.05 }
        let interval = avgFrame < 0.0125 ? 1.0 / 120 : 1.0 / 60
        let dt = raw > 0 ? min(max(1, (raw / interval).rounded()) * interval, 1.0 / 20) : 0
        elapsed += dt
        simSettings = snap.settings
        simScreenHeight = max(snap.screenHeight, 1)
        pet.settings = snap.settings
        agent.settings = snap.settings
        pet.statusText.backingScale = snap.backingScale
        stage.resize(width: Double(snap.viewSize.width), height: Double(snap.viewSize.height))
        pet.keycaps.cameraDistance = Double(stage.cameraNode.simdPosition.z)

        for job in jobs { job() }
        pollPointer(snap.windowFrame)
        updatePlacement(snap)
        if !homeRestored { restoreHome() }
        if centeredHome { followCenter() }
        pointer.update(dt)
        agent.update()
        if pet.homeChanged {
            centeredHome = false
            saveHome()
        }
        pet.update(dt, elapsed)

        let p = Published(stateName: pet.stateName, over: pointer.over, dragging: pointer.dragging,
                          activity: agent.activity, userTyping: agent.userTyping, petRect: petOutline(renderer))
        simLock.lock()
        published = p
        simLock.unlock()
        if debug["LILAGENT_PROFILE"] != nil { profile(dt, now() - tickStart) }
    }

    private func petOutline(_ renderer: SCNSceneRenderer) -> CGRect {
        let root = pet.mob.root.simdWorldPosition
        let s = Float(pet.placement.scale), box = pet.mob.hitBox
        let a = renderer.projectPoint(SCNVector3(root.x + Float(box.minX) * s, root.y, root.z))
        let b = renderer.projectPoint(SCNVector3(root.x + Float(box.maxX) * s, root.y + Float(box.top) * s, root.z))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func pollPointer(_ f: NSRect) {
        let m = NSEvent.mouseLocation
        pointer.cursor = (Double(m.x - f.minX), Double(f.maxY - m.y))
        if f.contains(m) || pointer.dragging {
            let p = (Double(m.x - f.minX), Double(f.maxY - m.y))
            if lastPointer == nil || lastPointer! != p {
                lastPointer = p
                pointer.move(p.0, p.1)
            }
        } else if lastPointer != nil {
            lastPointer = nil
            pointer.leave()
        }
    }

    private func updatePlacement(_ snap: Shared) {
        let scale = screenSpace.scaleForPixels(Double(snap.settings.petSize))
        let mob = pet.mob, facing = pet.loco.facing
        let (minX, maxX) = screenSpace.movementRange(scale, halfWidth: mob.edgeHalfWidth, halfDepth: mob.edgeHalfDepth, facing: facing)
        let floorY = screenSpace.floorY(scale, halfWidth: mob.edgeHalfWidth, halfDepth: mob.edgeHalfDepth, facing: facing)
        let screenH = max(snap.screenHeight, stage.height)
        let maxLift = max(0, (screenH - 24) / screenSpace.pixelsPerUnit - pet.mob.height * scale)
        pet.setPlacement(Placement(scale: scale, floorY: floorY, minX: minX, maxX: maxX,
                                   halfWidth: screenSpace.halfWidth, halfHeight: screenSpace.halfHeight, maxLift: maxLift))
        stage.setFocus(x: pet.loco.x, floorY: floorY, scale: scale)
        stage.setShadowStrength(1 - pet.lift / (1.2 * scale))
    }

    private func centerHome() -> (x: Double, lift: Double) {
        let p = pet.placement
        let floorOffset = p.floorY + screenSpace.halfHeight
        let lift = simScreenHeight / (2 * screenSpace.pixelsPerUnit) - floorOffset - pet.mob.height * p.scale / 2
        return (0, min(p.maxLift, max(0, lift)))
    }

    private func placeAtCenter() {
        let home = centerHome()
        pet.loco.x = home.x
        pet.loco.targetX = home.x
        pet.lift = home.lift
        pet.restLift = home.lift
        pet.home = home
        centeredHome = true
    }

    private func followCenter() {
        guard let old = pet.home else { return }
        let home = centerHome()
        guard abs(home.lift - old.lift) > 0.01 else { return }
        if abs(pet.restLift - old.lift) < 0.01 { pet.restLift = home.lift }
        pet.home = home
    }

    private func restoreHome() {
        homeRestored = true
        guard debug["LILAGENT_IGNORE_HOME"] == nil else { return }
        guard let h = simSettings.home else { return placeAtCenter() }
        let mob = pet.mob
        let (minX, maxX) = screenSpace.movementRange(pet.placement.scale, halfWidth: mob.edgeHalfWidth, halfDepth: mob.edgeHalfDepth, facing: pet.loco.facing)
        let x = min(maxX, max(minX, screenSpace.toWorldX(h.x * stage.width)))
        let lift = max(0, h.lift / screenSpace.pixelsPerUnit)
        pet.loco.x = x
        pet.loco.targetX = x
        pet.lift = lift
        pet.restLift = lift
        pet.home = (x, lift)
    }

    private func saveHome() {
        pet.homeChanged = false
        guard let home = pet.home else { return }
        let x = home.x / (2 * screenSpace.halfWidth) + 0.5
        let lift = (home.lift * screenSpace.pixelsPerUnit).rounded()
        DispatchQueue.main.async { self.store.update { $0.home = PetSettings.Home(x: x, lift: lift) } }
    }


    private func settingsChanged(_ old: PetSettings, _ new: PetSettings) {
        refreshShared()
        settingsModel.values = new
        if old.showHideShortcut != new.showHideShortcut { syncShowHideShortcut() }
        if old.keepOnTop != new.keepOnTop {
            window.level = new.keepOnTop ? .floating : .normal
            keepMascotInFront()
        }
        if old.showInDock != new.showInDock {
            NSApp.setActivationPolicy(new.showInDock ? .regular : .accessory)
            if let s = settingsWindow, s.isVisible {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    s.makeKeyAndOrderFront(nil)
                }
            }
        }
        if old.petSize != new.petSize { updateWindowFrame() }
        if old.typeAlong != new.typeAlong { keys.sync(new.typeAlong) }
        if old.musicDance != new.musicDance { music.poll() }
        if old.character != new.character, let c = PetCharacter(rawValue: new.character) { switchCharacter(to: c) }
        if old.openAtLogin != new.openAtLogin {
            do {
                if new.openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Open at login: \(error)")
            }
        }
    }


    private func syncShowHideShortcut() {
        hotKeys.stop()
        settingsModel.shortcutErrors = store.values.showHideShortcut && debug["LILAGENT_SNAPSHOT"] == nil ? hotKeys.register() : []
        buildStatusMenu()
    }

    private func switchCharacter(to next: PetCharacter) {
        guard next != character || loadingCharacter != nil, next != loadingCharacter else { return }
        loadingCharacter = next
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset: GLTFAsset
            do {
                asset = try next.loadModel()
            } catch {
                NSLog("Couldn't load \(next.rawValue): \(error)")
                DispatchQueue.main.async { self?.loadingCharacter = nil }
                return
            }
            let mob = Mascot(asset: asset)
            DispatchQueue.main.async {
                guard let self, self.loadingCharacter == next else { return }
                self.loadingCharacter = nil
                self.character = next
                self.statusItem.button?.toolTip = next.title
                self.onSim { self.pet.swapMob(mob) }
            }
        }
    }

    private func characterMenu() -> NSMenuItem {
        let menu = NSMenu()
        let current = PetCharacter(rawValue: store.values.character) ?? character
        for c in PetCharacter.allCases {
            menu.addItem(radio(c.title, c == current) { $0.character = c.rawValue })
        }
        let item = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }


    private var permissionAlertShown = false

    private func keyStatusChanged() {
        NSLog("Type along: \(keys.status.rawValue)")
        guard keys.status == .needsPermission, store.values.typeAlong, !permissionAlertShown, debug["LILAGENT_SNAPSHOT"] == nil else { return }
        permissionAlertShown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.keys.status == .needsPermission else { return }
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Let \(Brand.name) see your typing"
            a.informativeText = "To type along with you, \(Brand.name) needs Input Monitoring. Open System Settings › Privacy & Security › Input Monitoring and enable \(Brand.name). If it isn’t listed, use + to add this copy of the app. Show App in Finder locates it. After granting access, quit and reopen the app if macOS asks. Keys are never stored."
            a.addButton(withTitle: "Open System Settings")
            a.addButton(withTitle: "Show App in Finder")
            a.addButton(withTitle: "Not Now")
            let response = a.runModal()
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            if response == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }


    private var isAsleep: Bool { Self.asleep.contains(pub.stateName) }

    private func trigger(_ name: String, surprised: Bool = false) {
        onSim { [weak self] in
            guard let self else { return }
            if name == "wake" && self.agent.userTyping { return }
            if name == "wake" && surprised {
                self.pet.trigger("surprised", Params(then: "wake"), force: true)
            } else if name == "wake" {
                self.pet.trigger("wake", force: true)
            } else if ACTIONS.contains(name) {
                self.pet.trigger(name, Params(then: "idle"), force: true)
            }
        }
    }

    private func pollIdle() {
        let idle = systemIdleSeconds()
        var limit = store.values.idleSleepMin * 60
    
        if pub.activity?.activity == "waiting" {
            limit = limit > 0 ? min(limit, Self.awayWhileWaiting) : Self.awayWhileWaiting
        }
        let claudeBusy = Self.agentBusy.contains(pub.activity?.activity ?? "")
   
        if limit > 0 && !idleSleeping && idle >= limit && !claudeBusy {
            idleSleeping = true
            onSim { [weak self] in self?.agent.setIdleAsleep(true) }
            if !isAsleep { trigger("sleepy") }
        } else if idleSleeping && (idle < Self.idlePoll || claudeBusy || limit == 0) {
           
            idleSleeping = false
            onSim { [weak self] in self?.agent.setIdleAsleep(false) }
            if isAsleep { trigger("wake", surprised: idle < Self.idlePoll) }
        }
    }


    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu { buildStatusMenu() }
    }

    private func toggle(_ title: String, _ on: Bool, _ change: @escaping (inout PetSettings, Bool) -> Void) -> NSMenuItem {
        ActionItem(title, state: on ? .on : .off) { [weak self] _ in self?.store.update { change(&$0, !on) } }
    }

    private func radio(_ title: String, _ on: Bool, _ change: @escaping (inout PetSettings) -> Void) -> NSMenuItem {
        ActionItem(title, state: on ? .on : .off) { [weak self] _ in self?.store.update(change) }
    }

    private func claudeStatusLabel() -> String {
        guard bridge.listening else { return "Agents: not listening" }
        let a = pub.activity ?? AgentActivity(activity: "idle", project: nil, sessions: 0, reason: nil)
        let name = a.provider == "codex" ? "Codex" : "Claude"
        let label = a.provider == nil ? "Agents are idle" : (Self.claudeStatus[a.activity] ?? "Claude is idle").replacingOccurrences(of: "Claude", with: name)
        return label + (a.project.map { " · \($0)" } ?? "")
    }

    private func buildStatusMenu() {
        let m = statusMenu
        m.removeAllItems()
        let s = store.values
        let asleep = isAsleep
        if case .available(let latest, _) = updates.status {
            m.addItem(ActionItem("Update Available (\(latest))…") { [weak self] _ in self?.openUpdatePage() })
            m.addItem(.separator())
        }
        m.addItem(ActionItem("Settings…") { [weak self] _ in self?.showSettingsBesideMascot() })
        let hide = ActionItem(mascotHidden ? "Show \(character.title)" : "Hide \(character.title)") { [weak self] _ in self?.toggleMascot() }
        hide.keyEquivalent = s.showHideShortcut ? "\\" : ""
        hide.keyEquivalentModifierMask = .command
        m.addItem(hide)
        m.addItem(.separator())
        m.addItem(ActionItem(asleep ? "Wake up" : "Go to sleep") { [weak self] _ in self?.trigger(asleep ? "wake" : "sleepy") })
        m.addItem(ActionItem("Dance", enabled: !asleep) { [weak self] _ in self?.trigger("dance") })
        m.addItem(ActionItem("Wave", enabled: !asleep) { [weak self] _ in self?.trigger("wave") })
        m.addItem(.separator())
        let status = NSMenuItem(title: claudeStatusLabel(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        m.addItem(status)
        m.addItem(toggle("React to Claude Code and Codex", s.agentReactions) { $0.agentReactions = $1 })
        m.addItem(toggle("Dance to music (Spotify, Music)", s.musicDance) { $0.musicDance = $1 })
        let keyNote = keys.status == .needsPermission ? " (allow Input Monitoring)" : (keys.status == .unavailable ? " (unavailable)" : "")
        m.addItem(toggle("Type along with my keyboard\(keyNote)", s.typeAlong) { $0.typeAlong = $1 })
        m.addItem(hooksItem())
        m.addItem(codexHooksItem())
        m.addItem(.separator())
        m.addItem(characterMenu())
        m.addItem(toggle("Wanders around", s.autoWalk) { $0.autoWalk = $1 })
        m.addItem(toggle("Looks at the cursor", s.lookAtCursor) { $0.lookAtCursor = $1 })

        let size = NSMenu()
        size.addItem(ActionItem("Bigger") { [weak self] _ in self?.store.update { $0.petSize = PetSizes.clampSize(Double($0.petSize) * Self.sizeStep) } })
        size.addItem(ActionItem("Smaller") { [weak self] _ in self?.store.update { $0.petSize = PetSizes.clampSize(Double($0.petSize) / Self.sizeStep) } })
        size.addItem(.separator())
        for (name, px) in PetSizes.presets { size.addItem(radio(name, s.petSize == px) { $0.petSize = px }) }
        if !PetSizes.presets.contains(where: { $0.1 == s.petSize }) { size.addItem(radio("Custom (\(s.petSize) px)", true) { _ in }) }
        size.addItem(.separator())
        let tip = NSMenuItem(title: "Tip: scroll over the pet to resize", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        size.addItem(tip)
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = size
        m.addItem(sizeItem)

        let idle = NSMenu()
        for (title, minutes) in [("Never", 0.0), ("After 30 seconds", 0.5), ("After 5 min", 5.0), ("After 15 min", 15.0), ("After 25 min", 25.0)] {
            idle.addItem(radio(title, s.idleSleepMin == minutes) { $0.idleSleepMin = minutes })
        }
        let idleItem = NSMenuItem(title: "Sleep when idle", action: nil, keyEquivalent: "")
        idleItem.submenu = idle
        m.addItem(idleItem)
        m.addItem(toggle("Open at login", s.openAtLogin) { $0.openAtLogin = $1 })
        m.addItem(.separator())
        m.addItem(ActionItem("Quit \(Brand.name)") { _ in NSApp.terminate(nil) })
    }

    private func hooksItem() -> NSMenuItem {
        ActionItem(ClaudeHooks.installed() ? "Remove Claude Code hooks" : "Connect to Claude Code…") { [weak self] _ in self?.toggleClaudeHooks() }
    }

    private func codexHooksItem() -> NSMenuItem {
        ActionItem(CodexHooks.installed() ? "Remove Codex hooks" : "Connect to Codex…") { [weak self] _ in self?.toggleCodexHooks() }
    }

    private func toggleClaudeHooks() {
        let installed = ClaudeHooks.installed()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        do {
            if installed { try ClaudeHooks.uninstall() } else { try ClaudeHooks.install() }
            a.messageText = installed ? "Removed the Claude Code hooks." : "Connected: \(Brand.name) will now react to Claude Code."
            a.informativeText = "Restart any Claude Code sessions that are already open."
        } catch {
            a.alertStyle = .warning
            a.messageText = "Claude Code hooks"
            a.informativeText = error.localizedDescription
        }
        a.runModal()
        refreshSettingsStatus()
    }

    private func toggleCodexHooks() {
        let installed = CodexHooks.installed()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        do {
            if installed { try CodexHooks.uninstall() } else { try CodexHooks.install() }
            alert.messageText = installed ? "Removed the Codex hooks." : "\(Brand.name)’s Codex hooks are installed."
            alert.informativeText = installed
                ? "Restart open Codex sessions to reload the hook configuration."
                : "Open /hooks in Codex CLI to review and trust \(Brand.name)’s hooks, then start a new session. Hooks must be enabled in Codex."
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Codex hooks"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
        refreshSettingsStatus()
    }


    private func rightClicked(_ e: NSEvent) {
        let p0 = pub
        guard !p0.dragging else { return }
        showSettings(beside: window.convertToScreen(p0.petRect))
    }

    private func setUpSettings() {
        let m = settingsModel
        m.change = { [weak self] f in self?.store.update(f) }
        m.preview = { [weak self] state in self?.onSim { self?.agent.preview(state) } }
        m.command = { [weak self] name in self?.trigger(name) }
        m.resetPosition = { [weak self] in self?.resetPosition() }
        m.toggleClaudeHooks = { [weak self] in self?.toggleClaudeHooks() }
        m.toggleCodexHooks = { [weak self] in self?.toggleCodexHooks() }
        m.openInputMonitoring = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
        }
        m.revealApp = { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
        m.close = { [weak self] in self?.settingsWindow?.orderOut(nil) }
        m.checkUpdates = { [weak self] in self?.updates.check() }
        m.openUpdate = { [weak self] in self?.openUpdatePage() }
    }

    private func openUpdatePage() {
        guard case .available(_, let page) = updates.status else { return }
        NSWorkspace.shared.open(page)
    }

    private func refreshSettingsStatus() {
        let m = settingsModel
        m.claudeConnected = ClaudeHooks.installed()
        m.codexConnected = CodexHooks.installed()
        m.agentStatus = claudeStatusLabel()
        m.asleep = isAsleep
        m.typingNote = store.values.typeAlong && keys.status == .needsPermission ? "Enable Input Monitoring. If missing, add this app using +."
            : (store.values.typeAlong && keys.status == .unavailable ? "Typing along isn’t available." : nil)
    }

    private var settingsTimer: Timer?

    func showSettingsBesideMascot() {
        showSettings(beside: mascotHidden ? nil : window.convertToScreen(pub.petRect))
    }

    func showSettings(beside pet: NSRect? = nil) {
        refreshSettingsStatus()
        if settingsWindow == nil {
            let w = SettingsWindow(size: SettingsView.defaultSize)
            w.contentView = NSHostingView(rootView: SettingsView(model: settingsModel))
            w.setContentSize(SettingsView.defaultSize)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.settingsTimer?.invalidate()
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didMoveNotification] {
                NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in self?.keepMascotInFront() }
            }
            settingsWindow = w
        }
        guard let w = settingsWindow else { return }
        if let pet, pet.width > 0 {
            w.setFrameOrigin(Self.origin(for: w.frame.size, beside: pet, on: screen))
        } else if !w.isVisible {
            w.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        keepMascotInFront()
        settingsTimer?.invalidate()
        settingsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.settingsWindow?.isVisible == true else { self?.settingsTimer?.invalidate(); return }
            self.refreshSettingsStatus()
        }
    }

    private func keepMascotInFront() {
        guard !mascotHidden, let s = settingsWindow, s.isVisible else { return }
        if !store.values.keepOnTop { window.order(.above, relativeTo: s.windowNumber) }
    }

    static func origin(for size: CGSize, beside pet: NSRect, on screen: NSScreen?) -> NSPoint {
        let center = NSPoint(x: pet.midX, y: pet.midY)
        let vf = (NSScreen.screens.first { $0.frame.contains(center) } ?? screen)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 14, margin: CGFloat = 8
        let fitsRight = pet.maxX + gap + size.width <= vf.maxX - margin
        let fitsLeft = pet.minX - gap - size.width >= vf.minX + margin
        var x: CGFloat, y: CGFloat
        if fitsRight || fitsLeft {
            x = fitsRight ? pet.maxX + gap : pet.minX - gap - size.width
            y = pet.minY
        } else {
            x = pet.midX - size.width / 2
            y = pet.maxY + gap
        }
        x = min(max(x, vf.minX + margin), vf.maxX - size.width - margin)
        y = min(max(y, vf.minY + margin), vf.maxY - size.height - margin)
        return NSPoint(x: x, y: y)
    }

    private func resetPosition() {
        store.update { $0.home = nil }
        onSim { [weak self] in
            guard let self else { return }
            let home = self.centerHome()
            self.pet.home = home
            self.pet.restLift = home.lift
            self.centeredHome = true
            self.pet.trigger("walk", Params(x: home.x, lift: home.lift), force: true)
        }
    }

    func reveal() {
        guard !revealed else { return }
        revealed = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    private func toggleMascot() {
        guard revealed else { return }
        mascotHidden.toggle()
        if mascotHidden {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.mascotHidden else { return }
                self.window.orderOut(nil)
                self.view.isPlaying = false
            })
        } else {
            view.isPlaying = true
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 1
            }
        }
    }


    private func startDebugHooks() {
        if let state = debug["LILAGENT_STATE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onSim { self?.pet.trigger(state, Params(loop: true), force: true) }
            }
        }
        if let text = debug["LILAGENT_TYPE"] {
            for (i, ch) in text.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * (Double(self.debug["LILAGENT_TYPE_INTERVAL"] ?? "") ?? 0.12)) { [weak self] in
                    self?.onSim { self?.agent.onKey(String(ch)) }
                }
            }
        }
        if let script = debug["LILAGENT_KEYSCRIPT"] {
            for item in script.split(separator: ";") {
                let f = item.split(separator: ",").map(String.init)
                guard f.count == 4, let code = Int64(f[1]), let down = Double(f[2]), let up = Double(f[3]) else { continue }
                DispatchQueue.main.asyncAfter(deadline: .now() + down) { [weak self] in self?.onSim { self?.agent.onKey(f[0], code: code) } }
                DispatchQueue.main.asyncAfter(deadline: .now() + up) { [weak self] in self?.onSim { self?.agent.onKeyUp(code) } }
            }
        }
        if let next = debug["LILAGENT_SWITCH_TO"].flatMap(PetCharacter.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.switchCharacter(to: next) }
        }
        if debug["LILAGENT_ARMLOG"] != nil {
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.onSim { if let self { NSLog("t=%.1f arms L R: %@", self.elapsed, self.pet.mob.armHeights) } }
            }
        }
        if let path = debug["LILAGENT_SNAPSHOT"] {
            let after = Double(debug["LILAGENT_SNAPSHOT_AFTER"] ?? "") ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self else { return }
                let image = self.view.snapshot()
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }
}




