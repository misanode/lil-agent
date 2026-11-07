import Foundation


private let idleFaces = ["uwu", "smug", "deadpan", "nervous", "pouty", "love"]
private let walkFaces = ["neutral", "neutral", "happy", "uwu", "smug"]
private func coin() -> Bool { Double.random(in: 0..<1) < 0.5 }

private func jump(_ c: Pet, _ t: Double, _ start: Double, _ dur: Double, _ height: Double) {
    c.overlay[.bodyY] += hop(t, start, dur, height)
    c.overlay[.crouch] += dip(t, start - 0.04, 0.07) + dip(t, start + dur + 0.04, 0.06)
}

private func atDesk(_ c: Pet) {
    c.loco.stop()
    c.restLift = c.home?.lift ?? 0
}

private func sideToward(_ c: Pet) -> String {
    if let a = c.attention { return a.x > c.loco.x ? "L" : "R" }
    return coin() ? "L" : "R"
}

let STATES: [String: PetState.Type] = [
    "boot": BootState.self, "idle": IdleState.self, "walk": WalkState.self, "happy": HappyState.self,
    "sad": SadState.self, "sleepy": SleepyState.self, "sleep": SleepState.self, "wake": WakeState.self,
    "curious": CuriousState.self, "surprised": SurprisedState.self, "excited": ExcitedState.self,
    "wave": WaveState.self, "pet": PetPetState.self, "carried": CarriedState.self, "settle": SettleState.self,
    "drop": DropState.self, "grumpy": GrumpyState.self, "typing": TypingState.self, "command": CommandState.self,
    "reading": ReadingState.self, "waiting": WaitingState.self, "attention": AttentionState.self,
    "dance": DanceState.self, "thinking": ThinkingState.self, "searching": SearchingState.self,
    "planning": PlanningState.self, "subagents": SubagentsState.self, "compacting": CompactingState.self,
    "error": ErrorState.self, "permission": PermissionState.self, "question": QuestionState.self, "done": DoneState.self, "donehold": DoneHoldState.self,
    "coffee": CoffeeState.self, "workout": WorkoutState.self, "meditate": MeditateState.self, "idea": IdeaState.self,
    "annoyed": AnnoyedState.self, "dizzy": DizzyState.self,
]

let ACTIONS = ["idle", "happy", "sad", "sleepy", "sleep", "wake", "curious", "surprised", "excited", "wave", "dance", "pet"]

final class BootState: PetState {
    override class var info: StateInfo { StateInfo(priority: 9, autoLook: false, blink: false) }
    override func enter(_ c: Pet, _ p: Params) { c.face.setExpression("asleep") }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 4
        c.target[.headPitch] = t < 1.3 ? 0.4 : 0
        c.target[.crouch] = t < 1.3 ? 0.05 : 0.01
        c.target[.armSwingL] = t < 1.3 ? 0.15 : 0
        c.target[.armSwingR] = c.target[.armSwingL]
        if t > 1.3 && c.face.expression == "asleep" { c.face.setExpression("neutral") }
        if t > 2.4 { return Transition("wave", Params(then: "idle")) }
        return nil
    }
}

final class IdleState: PetState {
    private struct Fidget { var type: String; var t0: Double; var dur: Double; var side: Double }
    private var baseExpr = "neutral"
    private var duration = 0.0
    private var fidget: Fidget?
    private var nextFidget = 0.0

    override func enter(_ c: Pet, _ p: Params) {
        baseExpr = c.socialMode ? "neutral" : c.brain.idleExpression()
        c.face.setExpression(baseExpr)
        duration = p.duration ?? rnd(4, 9)
        nextFidget = rnd(1.5, 4)
    }

    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.target[.torsoRoll] = sin(t * 0.5) * 0.025
        c.target[.crouch] = 0.01 + 0.006 * sin(t * 0.9)

        nextFidget -= dt
        if fidget == nil && nextFidget <= 0 {
            var f = Fidget(type: pick(["tilt", "tilt", "lookBack", "shrug", "hands", "sway", "face", "face"]), t0: t, dur: rnd(1.4, 2.4), side: coin() ? -1 : 1)
            if f.type == "face" {
                f.dur = rnd(1.8, 2.8)
                c.face.setExpression(pick(idleFaces))
            }
            fidget = f
        }
        if let f = fidget {
            let k = (t - f.t0) / f.dur
            if k >= 1 {
                if f.type == "face" { c.face.setExpression(baseExpr) }
                fidget = nil
                nextFidget = rnd(2, 5)
            } else {
                let e = sin(k * .pi)
                switch f.type {
                case "face": c.target[.headRoll] += 0.15 * f.side * e
                case "tilt": c.target[.headRoll] += 0.3 * f.side * e
                case "lookBack":
                    c.target[.headYaw] += 0.75 * f.side * e
                    c.lookHint = [f.side * 0.8 * e, 0.1]
                case "shrug":
                    c.target[.armRaiseL] += 0.3 * e
                    c.target[.armRaiseR] += 0.3 * e
                    c.target[.headRoll] += 0.12 * f.side * e
                case "hands":
                    c.target[.armSwingL] = 0.55 * e
                    c.target[.armSwingR] = 0.55 * e
                    c.target[.elbowL] = 1.0 * e
                    c.target[.elbowR] = 1.0 * e
                    c.target[.headPitch] += 0.3 * e
                    c.lookHint = [0, -0.7 * e]
                case "sway":
                    c.target[.torsoRoll] += 0.08 * f.side * sin(k * .pi * 2)
                    c.target[.headRoll] -= 0.1 * f.side * sin(k * .pi * 2)
                default: break
                }
            }
        }
        if t > duration { return c.brain.nextAction(c) }
        return nil
    }
}

final class WalkState: PetState {
    override class var info: StateInfo { StateInfo(priority: 1) }
    override func enter(_ c: Pet, _ p: Params) {
        c.loco.walkTo(p.x ?? c.loco.x)
        if let lift = p.lift { c.restLift = lift }
        c.face.setExpression(p.mood ?? pick(walkFaces))
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.target[.torsoPitch] = 0.05
        if c.attention == nil { c.lookHint = [-sgn(c.loco.speed) * 0.35, -0.05] }
        if c.loco.arrived && abs(c.restLift - c.lift) < 0.08 * c.placement.scale && t > 0.3 { return then(p) }
        if t > 30 { return Transition("idle") }
        return nil
    }
    override func exit(_ c: Pet) { c.loco.stop() }
}

final class HappyState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2) }
    override func enter(_ c: Pet, _ p: Params) {
        c.face.setExpression("joy")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 10
        if t > 1.5 && c.face.expression == "joy" { c.face.setExpression("happy") }
        jump(c, t, 0.35, 0.42, 0.16)
        jump(c, t, 1.05, 0.42, 0.16)
        let up = env(t, 0.2, 2.4, 0.3)
        c.target[.armRaiseL] = 2.3 * up
        c.target[.armRaiseR] = 2.3 * up
        c.target[.elbowL] = 0.4 * up
        c.target[.elbowR] = 0.4 * up
        c.overlay[.wristL] = sin(t * 12) * 0.4 * up
        c.overlay[.wristR] = -sin(t * 12) * 0.4 * up
        c.target[.headPitch] = -0.12 * up
        if t > 3 { return then(p) }
        return nil
    }
}

final class SadState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2, autoLook: false) }
    private static let length = 2 * 97.0 / 24
    override func enter(_ c: Pet, _ p: Params) { c.face.setExpression("sad") }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 3
        if t > 0.6 && c.face.expression == "sad" { c.face.setExpression("crying") }
        let crying = c.face.expression == "crying"
        c.target[.headPitch] = crying ? 0.18 : 0.45
        c.target[.torsoPitch] = 0.14
        c.target[.crouch] = 0.03
        c.target[.armSwingL] = 0.15
        c.target[.armSwingR] = 0.15
        c.target[.armRaiseL] = -0.08
        c.target[.armRaiseR] = -0.08
        c.target[.headRoll] = 0.1 * sin(t * 0.7)
        c.overlay[.bodyY] = -0.012 * env(t, 1.5, 2.6, 0.5)
        c.lookHint = crying ? [0.15 * sin(t * 0.5), -0.2] : [0.2 * sin(t * 0.5), -0.8]
        if t > Self.length { return then(p) }
        return nil
    }
}

final class SleepyState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2, autoLook: false) }
    override func enter(_ c: Pet, _ p: Params) {
        c.restLift = c.home?.lift ?? 0
        c.face.setExpression("sleepy")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 4
        let yawn = env(t, 0.5, 2.6, 0.5)
        let open = 0.28 * (1 - yawn) + 0.05 * yawn
        c.face.target.eyeOpen = [open, open]
        c.target[.armRaiseL] = 2.6 * yawn
        c.target[.armRaiseR] = 2.6 * yawn
        c.target[.elbowL] = 0.3 * yawn
        c.target[.elbowR] = 0.3 * yawn
        c.target[.torsoPitch] = -0.1 * yawn
        c.target[.headPitch] = -0.25 * yawn
        if t > 2.6 {
            let nod = max(0, sin((t - 2.6) * 2.2))
            c.target[.headPitch] = 0.25 + nod * 0.15
            c.target[.crouch] = 0.03
        }
        if t > 5.5 { return Transition("sleep") }
        return nil
    }
}

final class SleepState: PetState {
    override class var info: StateInfo { StateInfo(priority: 3, autoLook: false, blink: false, attentive: false) }
    private static let napLength = 60.0
    override func enter(_ c: Pet, _ p: Params) {
        c.restLift = c.home?.lift ?? 0
        c.face.setExpression("asleep")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 2.5
        c.target[.sit] = 1
        c.target[.headPitch] = 0.5
        c.target[.headRoll] = 0.15
        c.target[.torsoPitch] = 0.18
        c.target[.armSwingL] = 0.35
        c.target[.armSwingR] = 0.35
        c.target[.elbowL] = 0.5
        c.target[.elbowR] = 0.5
        if c.allowAutoWake && t > Self.napLength {
            c.brain.energy = 1
            return Transition("wake")
        }
        return nil
    }
}

final class WakeState: PetState {
    override class var info: StateInfo { StateInfo(priority: 3, autoLook: false) }
    override func enter(_ c: Pet, _ p: Params) { c.face.setExpression("sleepy") }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 3.5
        if t > (c.mob.hasScreenFace ? 1.8 : 1) && c.face.expression == "sleepy" { c.face.setExpression("neutral") }
        let stretch = env(t, 1.0, 2.4, 0.4)
        c.target[.armRaiseL] = 2.5 * stretch
        c.target[.armRaiseR] = 2.5 * stretch
        c.target[.torsoPitch] = -0.08 * stretch
        c.target[.headPitch] = t < 0.6 ? 0.4 : -0.15 * stretch
        if t > 3 { return then(p) }
        return nil
    }
}

final class CuriousState: PetState {
    override class var info: StateInfo { StateInfo(priority: 1) }
    private var side = 1.0
    private var spot = SIMD2<Double>(0, 0)
    override func enter(_ c: Pet, _ p: Params) {
        c.face.setExpression("curious")
        side = coin() ? -1 : 1
        spot = [rnd(-0.8, 0.8), rnd(-0.3, 0.5)]
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 6
        c.target[.headRoll] = 0.32 * side
        c.target[.torsoPitch] = 0.12
        c.target[.headPitch] = 0.05
        c.target[.armSwingR] = 1.3
        c.target[.elbowR] = 1.9
        c.target[.armRaiseR] = -0.1
        c.overlay[.headRoll] = 0.04 * sin(t * 3)
        if c.attention == nil { c.lookHint = spot }
        if t > 4 { return then(p) }
        return nil
    }
}

final class SurprisedState: PetState {
    override class var info: StateInfo { StateInfo(priority: 4) }
    override func enter(_ c: Pet, _ p: Params) {
        c.face.setExpression("surprised")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 16
        c.target[.sit] = 0
        jump(c, t, 0.06, 0.3, 0.12)
        c.target[.armRaiseL] = 1.0
        c.target[.armRaiseR] = 1.0
        c.target[.elbowL] = 0.9
        c.target[.elbowR] = 0.9
        c.target[.torsoPitch] = -0.12
        c.target[.headPitch] = -0.15
        if t > 1.6 { return then(p) }
        return nil
    }
}

final class ExcitedState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2) }
    private var second = false
    override func enter(_ c: Pet, _ p: Params) {
        c.face.setExpression(Double.random(in: 0..<1) < 0.4 ? "love" : "excited")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 10
        let on = env(t, 0, 3.4, 0.3)
        c.overlay[.bodyY] = abs(sin(t * 8)) * 0.07 * on
        c.target[.armRaiseL] = 1.5 * on
        c.target[.armRaiseR] = 1.5 * on
        c.overlay[.armRaiseL] = sin(t * 8) * 0.6 * on
        c.overlay[.armRaiseR] = -sin(t * 8) * 0.6 * on
        c.target[.elbowL] = 0.8 * on
        c.target[.elbowR] = 0.8 * on
        c.overlay[.headRoll] = sin(t * 4) * 0.12 * on
        if t > 1.6 && !second {
            second = true
            c.face.setExpression("joy")
        }
        if t > 3.5 { return then(p) }
        return nil
    }
}

final class WaveState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2) }
    private var side = "L"
    override func enter(_ c: Pet, _ p: Params) {
        c.face.setExpression(pick(["happy", "uwu", "joy"]))
        side = p.side ?? sideToward(c)
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 9
        let sign: Double = side == "L" ? 1 : -1
        let up = env(t, 0, 2.7, 0.35)
        c.target[.armRaise(side)] = 2.5 * up
        c.target[.elbow(side)] = 0.5 * up
        c.target[.armSwing(side)] = 0.25 * up
        c.overlay[.armRaise(side)] = sin(t * 9) * 0.22 * up
        c.overlay[.wrist(side)] = sin(t * 9 + 0.6) * 0.45 * up
        c.target[.headRoll] = 0.15 * sign * up
        c.target[.torsoRoll] = -0.05 * sign * up
        if t > 2.8 { return then(p) }
        return nil
    }
}

final class PetPetState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2) }
    private var side = 1.0
    override func enter(_ c: Pet, _ p: Params) {
        let count = p.count ?? 1
        c.face.setExpression(count > 3 ? "love" : pick(["uwu", "happy", "love"]))
        side = coin() ? -1 : 1
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 10
        let on = env(t, 0, 1.8, 0.3)
        c.target[.headRoll] = 0.3 * side * on
        c.target[.headPitch] = 0.12 * on
        c.target[.crouch] = 0.03 * on
        c.overlay[.bodyY] = abs(sin(t * 9)) * 0.02 * on
        c.target[.armRaiseL] = 0.6 * on
        c.target[.armRaiseR] = 0.6 * on
        c.target[.elbowL] = 1.2 * on
        c.target[.elbowR] = 1.2 * on
        c.overlay[.headRoll] = sin(t * 5) * 0.05 * on
        if t > 1.9 { return then(p) }
        return nil
    }
}

final class CarriedState: PetState {
    override class var info: StateInfo { StateInfo(priority: 8, autoLook: false, freeLift: true) }
    override func enter(_ c: Pet, _ p: Params) {
        c.loco.stop()
        c.face.setExpression("surprised")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 7
        if t > 0.9 && c.face.expression == "surprised" { c.face.setExpression("nervous") }
        let vx = c.carryVX ?? 0
        let sway = clamp01(abs(vx) / 6) * sgn(vx)
        c.target[.sit] = 0
        c.target[.armRaiseL] = 0.95
        c.target[.armRaiseR] = 0.95
        c.target[.elbowL] = 0.35
        c.target[.elbowR] = 0.35
        c.target[.legSwingL] = 0.25 + sin(t * 5) * 0.2 - sway * 0.4
        c.target[.legSwingR] = 0.25 - sin(t * 5) * 0.2 - sway * 0.4
        c.target[.kneeL] = 0.6
        c.target[.kneeR] = 0.6
        c.target[.torsoRoll] = -sway * 0.25
        c.target[.torsoPitch] = sway * 0.1
        c.target[.headRoll] = sway * 0.2
        c.target[.headPitch] = 0.1
        c.lookHint = [-sway * 0.5, -0.5]
        return nil
    }
}

final class SettleState: PetState {
    override class var info: StateInfo { StateInfo(priority: 8) }
    private var side = 1.0
    override func enter(_ c: Pet, _ p: Params) {
        c.restLift = c.lift
        c.loco.stop()
        c.setHome()
        c.face.setExpression(c.lift > 0.1 ? "happy" : "neutral")
        side = coin() ? -1 : 1
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 9
        let k = exp(-t * 2.2)
        c.overlay[.bodyY] = sin(t * 9) * 0.06 * k
        c.overlay[.torsoRoll] = sin(t * 7) * 0.2 * k * side
        c.target[.headRoll] = 0.15 * side * k
        if t > 1.2 { return then(p) }
        return nil
    }
}

final class DropState: PetState {
    override class var info: StateInfo { StateInfo(priority: 8, autoLook: false, freeLift: true) }
    private var vx = 0.0, vy = 0.0, daze = 0.0, spinDir = 1.0
    private var landed = -1.0
    private var recovered = false
    private var impact = 0.0, slide = 0.0

    override func enter(_ c: Pet, _ p: Params) {
        let scale = c.placement.scale
        vy = p.vy ?? 0
        vx = p.vx ?? 0
        let speed = hypot(vx, vy) / scale
        daze = 0.2 + 0.3 * clamp01(speed / 10)
        spinDir = vx == 0 ? 1 : sgn(vx)
        c.restLift = c.lift
        c.face.setExpression("surprised")
    }

    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 12
        let pl = c.placement
        let scale = pl.scale
        if landed < 0 {
            let dazed = t < daze
            if dazed {
                vy -= 5.5 * scale * dt
                vx *= exp(-0.6 * dt)
            } else {
                vy += -vy * (1 - exp(-7 * dt))
                vx += -vx * (1 - exp(-3 * dt))
                if !recovered {
                    recovered = true
                    c.face.setExpression("nervous")
                }
            }
            c.lift += vy * dt
            let ceiling = pl.halfHeight - pl.floorY - 1.7 * scale
            if c.lift > ceiling {
                c.lift = ceiling
                vy = -abs(vy) * 0.35
            }
            var x = c.loco.x + vx * dt
            if x < pl.minX || x > pl.maxX {
                x = clamp01((x - pl.minX) / (pl.maxX - pl.minX)) * (pl.maxX - pl.minX) + pl.minX
                vx = -vx * 0.45
            }
            c.loco.x = x
            c.loco.targetX = x
            c.restLift = c.lift

            let speed = hypot(vx, vy) / scale
            let spin = clamp01(speed / 6) * smooth(0, 0.08, t) * (1 - smooth(daze - 0.12, daze, t))
            c.overlay[.torsoRoll] = sin(t * 18) * 0.6 * spin * spinDir
            c.overlay[.torsoPitch] = cos(t * 14) * 0.4 * spin
            c.target[.torsoPitch] += (vx / (8 * scale)) * 0.5 * (1 - spin)
            c.target[.torsoRoll] += (-vx / (8 * scale)) * 0.3 * (1 - spin)
            c.target[.headPitch] = -0.15
            c.lookHint = [0, 0.4]

            if c.lift <= 0 {
                c.lift = 0
                c.restLift = 0
                landed = t
                impact = clamp01(-vy / (7 * scale))
                slide = vx * 0.6
                c.face.setExpression(impact > 0.6 ? "annoyed" : "nervous")
                c.loco.stop()
            } else if !dazed && speed < 0.5 {
                return afterLanding(c, hard: daze > 0.35, p)
            }
            return nil
        }
        let k = t - landed
        slide *= exp(-5 * dt)
        let x = min(pl.maxX, max(pl.minX, c.loco.x + slide * dt))
        c.loco.x = x
        c.loco.targetX = x
        let squash = impact * max(0, 1 - k / 0.45)
        c.target[.crouch] = 0.12 * squash
        c.target[.torsoPitch] = 0.22 * squash
        c.target[.headPitch] = 0.35 * squash
        c.target[.sit] = max(0, 1 - k / 1.2)
        c.overlay[.headRoll] = sin(k * 14) * 0.12 * impact * env(k, 0.5, 1.4, 0.18)
        if k > 1.4 { return afterLanding(c, hard: impact > 0.35, p) }
        return nil
    }

    private func afterLanding(_ c: Pet, hard: Bool, _ p: Params) -> Transition {
        let then = p.then ?? "idle"
        let sad = c.settings.allows("sad")
        if hard && c.settings.allows("dizzy") { return Transition("dizzy", Params(then: sad ? "sad" : then)) }
        return sad ? Transition("sad", Params(then: then)) : Transition(then)
    }

    override func exit(_ c: Pet) { c.setHome() }
}

final class GrumpyState: PetState {
    override class var info: StateInfo { StateInfo(priority: 5) }
    override func enter(_ c: Pet, _ p: Params) {
        c.face.setExpression("angry")
        c.loco.stop()
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 9
        let huff = env(t, 0, 3.6, 0.3)
        c.target[.headPitch] = 0.1 * huff
        c.target[.crouch] = 0.02 * huff
        c.overlay[.torsoRoll] = sin(t * 22) * 0.04 * env(t, 0.2, 1.2, 0.2)
        c.overlay[.bodyY] = abs(sin(t * 11)) * 0.015 * env(t, 0.2, 1.2, 0.2)
        if c.attention == nil { c.lookHint = [0, 0] }
        if t > 3.8 { return then(p) }
        return nil
    }
}


final class TypingState: PetState {
    override class var info: StateInfo { StateInfo(priority: 1, autoLook: false, attentive: false, turnBody: false) }
    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression("neutral")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 8
        c.target[.sit] = 1
        c.target[.headPitch] = 0.2
        c.target[.torsoPitch] = 0.06
        c.target[.armSwingL] = 0.6
        c.target[.armSwingR] = 0.6
        c.target[.elbowL] = 1.2
        c.target[.elbowR] = 1.2
        c.overlay[.armSwingL] = max(0, sin(t * 14)) * 0.15
        c.overlay[.armSwingR] = max(0, sin(t * 14 + .pi)) * 0.15
        c.lookHint = [0.2 * sin(t * 0.8), -0.75]
        return nil
    }
}


class ReactionState: PetState {
    override class var info: StateInfo { StateInfo(priority: 1, autoLook: false, attentive: false, turnBody: false) }
    var expression: String { "neutral" }

    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression(expression)
    }

    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 6
        c.lookHint = [0, 0]
        return nil
    }
}

final class ThinkingState: ReactionState {}

final class ReadingState: ReactionState {}

final class SearchingState: ReactionState {
    override var expression: String { "curious" }
}

final class CommandState: ReactionState {
    override var expression: String { "curious" }
}

final class PlanningState: ReactionState {
    override var expression: String { "happy" }
}

final class SubagentsState: ReactionState {
    override var expression: String { "happy" }
}

final class CompactingState: ReactionState {
    override var expression: String { "annoyed" }
}

final class ErrorState: ReactionState {
    override var expression: String { "sad" }
}

final class PermissionState: PetState {
    override class var info: StateInfo { StateInfo(priority: 3, turnBody: false) }
    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression("nervous")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 8
        if c.attention == nil { c.lookHint = [0, 0.1] }
        return nil
    }
}

final class QuestionState: PetState {
    override class var info: StateInfo { StateInfo(priority: 3, turnBody: false) }
    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression("curious")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 8
        if c.attention == nil { c.lookHint = [0, 0.1] }
        return nil
    }
}

final class DoneState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2, turnBody: false) }
    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression("joy")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 8
        if t > 1.2 && c.face.expression == "joy" { c.face.setExpression("happy") }
        if t > 2.4 { return Transition("donehold", Params(then: p.then)) }
        return nil
    }
}

final class WaitingState: PetState {
    override class var info: StateInfo { StateInfo(priority: 1, turnBody: false) }
    private var nextFace = rnd(3, 6)
    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression("neutral")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 6
        c.target[.torsoRoll] = sin(t * 0.8) * 0.03
        c.overlay[.legSwingR] = max(0, sin(t * 7)) * 0.18 * (sin(t * 0.6) > 0 ? 1 : 0)
        if c.attention == nil { c.lookHint = [0, 0] }
        nextFace -= dt
        if nextFace <= 0 {
            c.face.setExpression(c.face.expression == "neutral" ? pick(["curious", "uwu", "smug"]) : "neutral")
            nextFace = rnd(3, 6)
        }
        return nil
    }
}

final class AttentionState: PetState {
    override class var info: StateInfo { StateInfo(priority: 3, turnBody: false) }
    override func enter(_ c: Pet, _ p: Params) {
        atDesk(c)
        c.face.setExpression("surprised")
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 10
        if t > 1 && c.face.expression == "surprised" { c.face.setExpression("nervous") }
        let beat = t.truncatingRemainder(dividingBy: 1.6)
        jump(c, beat, 0.1, 0.32, 0.1)
        c.target[.armRaiseL] = 2.0
        c.target[.armRaiseR] = 2.0
        c.overlay[.armRaiseL] = sin(t * 10) * 0.4
        c.overlay[.armRaiseR] = -sin(t * 10) * 0.4
        c.target[.headPitch] = -0.1
        if c.attention == nil { c.lookHint = [0, 0.1] }
        return nil
    }
}

final class DanceState: PetState {
    override class var info: StateInfo { StateInfo(priority: 1) }
    private var nextNote = 0.2
    override func enter(_ c: Pet, _ p: Params) { c.face.setExpression("happy") }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 12
        let beat = t * .pi * 4
        let on = p.loop ? smooth(0, 0.4, t) : env(t, 0, 6, 0.4)
        c.overlay[.crouch] = (0.03 + 0.03 * sin(beat)) * on
        c.overlay[.torsoRoll] = sin(beat / 2) * 0.12 * on
        c.overlay[.headRoll] = -sin(beat / 2) * 0.2 * on
        c.overlay[.torsoYaw] = sin(beat / 4) * 0.2 * on
        c.target[.armRaiseL] = (1.2 + sin(beat / 2) * 1.0) * on
        c.target[.armRaiseR] = (1.2 - sin(beat / 2) * 1.0) * on
        c.target[.elbowL] = 0.9 * on
        c.target[.elbowR] = 0.9 * on
        c.overlay[.legSwingL] = max(0, sin(beat / 2)) * 0.25 * on
        c.overlay[.legSwingR] = max(0, -sin(beat / 2)) * 0.25 * on
        c.overlay[.kneeL] = c.overlay[.legSwingL] * 1.5
        c.overlay[.kneeR] = c.overlay[.legSwingR] * 1.5
        nextNote -= dt
        if nextNote <= 0 {
            c.face.setExpression(["happy", "joy", "uwu"][Int(t / 1.1) % 3])
            nextNote = 1.1
        }
        if t > 6 && !p.loop { return then(p) }
        return nil
    }
}


class MoodState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2) }
    var expression: String { "neutral" }
    var duration: Double { 5 }
    override func enter(_ c: Pet, _ p: Params) {
        c.loco.stop()
        c.face.setExpression(expression)
    }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 6
        c.lookHint = [0, 0]
        if t > duration { return then(p) }
        return nil
    }
}

final class CoffeeState: MoodState {
    override class var info: StateInfo { StateInfo(priority: 2, autoLook: false, blink: false) }
    override var expression: String { "neutral" }
    private static let loop = 97.0 / 24
    override var duration: Double { Self.loop * 2 + Self.putAway }
    private static let putAway = 0.35
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.mob.mugAmount = smooth(0, 0.3, t) * (1 - smooth(Self.loop * 2, Self.loop * 2 + Self.putAway, t))
        if !c.mob.hasScreenFace && t > Self.loop * 2 { return then(p) }
        let phase = t.truncatingRemainder(dividingBy: Self.loop) * 24 + 1
        let face = phase >= 30 && phase < 56 ? "asleep" : (phase >= 56 && phase < 80 ? "uwu" : "neutral")
        if c.face.expression != face { c.face.setExpression(face) }
        return super.update(c, dt, t, p)
    }
}

final class WorkoutState: MoodState {
    override class var info: StateInfo { StateInfo(priority: 2, autoLook: false) }
    override var expression: String { "annoyed" }
    override var duration: Double { 5 }
}

final class MeditateState: MoodState {
    override class var info: StateInfo { StateInfo(priority: 2, autoLook: false, blink: false, attentive: false) }
    override var expression: String { "asleep" }
    override var duration: Double { 8 }
}

final class IdeaState: MoodState {
    override class var info: StateInfo { StateInfo(priority: 2, autoLook: false) }
    override var expression: String { "surprised" }
    override var duration: Double { 3.2 }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        if t > 1.2 && c.face.expression == "surprised" { c.face.setExpression("happy") }
        return super.update(c, dt, t, p)
    }
}

final class AnnoyedState: MoodState {
    override class var info: StateInfo { StateInfo(priority: 4, autoLook: false) }
    override var expression: String { "angry" }
    override var duration: Double { 73.0 / 24 }
}

final class DizzyState: MoodState {
    override class var info: StateInfo { StateInfo(priority: 5, autoLook: false, attentive: false) }
    override var expression: String { "sleepy" }
    override var duration: Double { 3 }
}

final class DoneHoldState: PetState {
    override class var info: StateInfo { StateInfo(priority: 2, turnBody: false) }
    private static let length = 30.0 - 2.4
    override func enter(_ c: Pet, _ p: Params) { c.face.setExpression("happy") }
    override func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? {
        c.poseRate = 6
        if t > Self.length { return then(p) }
        return nil
    }
}
