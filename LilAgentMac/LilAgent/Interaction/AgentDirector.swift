import Foundation

final class AgentDirector {
    private static let needsYou: Set<String> = ["permission", "question", "attention"]
    private static let working = AgentBridge.working
    private static let agentStates: Set<String> = working.union(needsYou).union(["waiting", "done"])
    private static let interruptible: Set<String> = agentStates.union(["idle", "walk", "curious", "dance", "coffee", "workout", "meditate", "idea",
                                                                                                  "donehold"])
    private static let minWorkHold = 1.6
    private static let minThinkHold = 2.5
    private static let sleeping: Set<String> = ["sleep", "sleepy"]
    private static let held: Set<String> = ["carried", "drop", "settle"]
    private static let waitAtDesk = 20.0
    private static let userTypingHold = 1.6

    unowned let pet: Pet
    var settings: PetSettings
    private(set) var activity: AgentActivity?
    private var music = false
    private var pendingDone = false
    private var waitingSince: Double?
    private var dozing = false
    private var idleAsleep = false
    private var userTypingUntil = 0.0
    private var managing = false

    init(pet: Pet, settings: PetSettings) {
        self.pet = pet
        self.settings = settings
    }

    func setAgent(_ a: AgentActivity) {
        activity = a
        if a.reason == "done" { pendingDone = true }
    }

    private var held = Set<Int64>()

    func onKey(_ ch: String, code: Int64 = -1) {
        guard settings.typeAlong else { return }
        userTypingUntil = now() + Self.userTypingHold
        if code >= 0 { held.insert(code) }
        pet.typeChar(ch, code: code)
    }

    func onKeyUp(_ code: Int64) {
        guard held.remove(code) != nil else { return }
        userTypingUntil = now() + Self.userTypingHold
        pet.releaseKey(code)
    }

    func setMusic(_ playing: Bool) { music = playing }

    var userTyping: Bool { settings.typeAlong && (now() < userTypingUntil || !held.isEmpty) }

    private var desired: String? {
        let claude = settings.agentReactions ? activity.map(\.activity).flatMap { settings.allows($0) ? $0 : nil } : nil
        if let claude, Self.needsYou.contains(claude) { return claude }
        if userTyping { return "typing" }
        if let claude, Self.working.contains(claude) { return claude }
        if settings.musicDance && music { return "dance" }
        if claude == "waiting", now() - (waitingSince ?? now()) < Self.waitAtDesk { return "waiting" }
        return nil
    }

    private func setDozing(_ on: Bool) {
        dozing = on
        syncAutoWake()
    }

    func setIdleAsleep(_ on: Bool) {
        idleAsleep = on
        syncAutoWake()
    }

    private func syncAutoWake() { pet.allowAutoWake = !(dozing || idleAsleep) }

    private static let previewLength = 5.0
    private var preview: (state: String, until: Double)?

    func preview(_ state: String) {
        preview = (state, now() + Self.previewLength)
        managing = false
        pendingDone = false
        pet.trigger(state, Params(then: "idle"), force: true)
    }

    func update() {
        let t = now()
        if let p = preview {
            if t < p.until { return }
            preview = nil
            if pet.stateName == p.state { pet.trigger("idle", force: true) }
        }
        let current = pet.stateName
        let desired = self.desired
        let claudeWaiting = settings.agentReactions && activity?.activity == "waiting"
        waitingSince = claudeWaiting ? (waitingSince ?? t) : nil

        guard let desired else {
            pendingDone = false
            if dozing { setDozing(false) }
            if managing && (Self.agentStates.contains(current) || current == "dance") { pet.trigger("idle", force: true) }
            managing = false
            return
        }

        if Self.needsYou.contains(desired) {
            pendingDone = false
            if dozing { setDozing(false) }
            if current == desired || Self.held.contains(current) { return }
            managing = true
            if Self.sleeping.contains(current) {
                pet.trigger("surprised", Params(then: desired), force: true)
            } else {
                pet.trigger(desired, force: true)
            }
            return
        }

        if desired == "typing" && userTyping {
            pendingDone = false
            if dozing { setDozing(false) }
            if Self.held.contains(current) || (current == "typing" && managing) { return }
            managing = true
            pet.trigger("typing", force: true)
            return
        }

        if dozing {
            if desired == "waiting" {
                if Self.sleeping.contains(current) || !Self.interruptible.contains(current) { return }
                setDozing(false)
                waitingSince = t
            } else {
                setDozing(false)
                if Self.sleeping.contains(current) {
                    managing = true
                    pet.trigger("wake", Params(then: desired), force: true)
                    return
                }
            }
        }


        if Self.sleeping.contains(current) || !Self.interruptible.contains(current) { return }

        if pendingDone && !settings.allows("done") { pendingDone = false }
        if pendingDone && !Self.working.contains(desired) {
            pendingDone = false
            managing = true
            pet.trigger("done", Params(then: "idle"), force: true)
            return
        }
        if current == desired && managing { return }
        if (current == "done" || current == "donehold") && !Self.working.contains(desired) { return }
        if managing, Self.working.contains(current), Self.working.contains(desired),
           pet.fsm.time < (desired == "thinking" ? Self.minThinkHold : Self.minWorkHold) { return }
        managing = true
        pet.trigger(desired, desired == "dance" ? Params(loop: true) : Params(), force: true)
    }
}
