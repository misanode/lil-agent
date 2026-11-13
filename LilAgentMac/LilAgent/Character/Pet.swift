import SceneKit
import simd

struct Placement {
    var scale = 0.55
    var floorY = -1.5
    var minX = -3.0
    var maxX = 3.0
    var halfWidth = 4.0
    var halfHeight = 2.0
    var maxLift = 0.0
}

final class Pet {
    private(set) var mob: Mascot
    var face: FaceDisplay { mob.face }
    var settings: PetSettings

    var target = Pose()
    var current = Pose()
    var overlay = Pose()
    private var final = Pose()
    var poseRate = 8.0

    var lookHint: SIMD2<Double>?
    var attention: Vec3?
    var socialMode = false
    var allowAutoWake = true
    var placement = Placement()
    private var breathPhase = 0.0
    var lift = 0.0
    var restLift = 0.0
    var home: (x: Double, lift: Double)?
    var homeChanged = false
    private var climb = 0.0
    var carryVX: Double?

    let loco = Locomotion()
    let brain = Personality()
    let keycaps: TypedKeys
    let statusText: StatusText
    private(set) var fsm: StateMachine!

    init(mob: Mascot, scene: SCNScene, settings: PetSettings) {
        self.mob = mob
        self.settings = settings
        keycaps = TypedKeys(scene: scene)
        keycaps.accentHex = settings.keyColor
        statusText = StatusText(scene: scene)
        fsm = StateMachine(self)
        fsm.go(Transition("boot"))
    }

    var stateName: String { fsm.name ?? "boot" }

    @discardableResult
    func trigger(_ name: String, _ params: Params = Params(), force: Bool = false) -> Bool {
        guard let next = STATES[name] else { return false }
        if !force, fsm.state != nil, fsm.info.priority > next.info.priority { return false }
        fsm.go(Transition(name, params))
        return true
    }

    func swapMob(_ next: Mascot) {
        let old = mob
        if let parent = old.root.parent {
            next.root.simdTransform = old.root.simdTransform
            parent.addChildNode(next.root)
        }
        old.root.removeFromParentNode()
        next.face.setExpression(old.face.expression)
        next.stateName = old.stateName
        mob = next
    }

    func setHome() {
        home = (loco.x, restLift)
        homeChanged = true
    }

    func setPlacement(_ p: Placement) {
        placement = p
        loco.setBounds(p.minX, p.maxX)
    }

    func typeChar(_ ch: String, code: Int64 = -1) {
        keycaps.input(ch)
        mob.pressKey(code)
    }

    func releaseKey(_ code: Int64) { mob.releaseKey(code) }

    private func letterOrigin() -> Vec3 {
        if let o = mob.letterOrigin() { return o }
        var p = mob.head.simdWorldPosition.d
        p.y += mob.emoteLift * placement.scale
        return p
    }

    func update(_ dt: Double, _ t: Double) {
        target.reset()
        overlay.reset()
        poseRate = 8
        lookHint = nil

        fsm.update(dt)
        let info = fsm.info
        brain.update(dt, state: stateName)

        let scale = placement.scale
        loco.maxSpeed = 0.9 * settings.walkSpeed
        loco.update(dt, scale: scale)
        if !info.freeLift {
            restLift = clamp(restLift, 0, placement.maxLift)
            let maxV = 1.4 * settings.walkSpeed * scale
            let step = clamp((restLift - lift) * 3, -maxV, maxV) * dt
            lift += step
            climb += (step / max(dt, 1e-3) / scale - climb) * (1 - exp(-6 * dt))
        } else {
            climb *= exp(-6 * dt)
        }
        mob.climb = climb
        mob.lean = loco.walkAmount * 0.28
        mob.walkAmount = loco.walkAmount
        mob.walkPhase = loco.phase
        mob.facing = loco.facing
        mob.stateName = stateName

        current.damp(toward: target, rate: poseRate, dt: dt)
        for i in final.v.indices { final.v[i] = current.v[i] + overlay.v[i] }
        applyWalk()
        applyGaze(info)

        let sleeping = stateName == "sleep"
        breathPhase += dt * (sleeping ? 1.1 : 1.7)
        let breath = sin(breathPhase) * (sleeping ? 1.8 : 1)

        let root = mob.root
        root.simdPosition = SIMD3(Float(loco.x), Float(placement.floorY + lift), 0)
        root.simdScale = SIMD3(repeating: Float(scale))
        root.simdOrientation = quatY(loco.facing)
        mob.applyPose(final, breath: breath)

        face.autoBlink = info.blink
        face.update(dt)
        mob.animate(dt)
        keycaps.accentHex = settings.keyColor
        keycaps.update(dt, laptop: mob.laptopBounds(), fallback: letterOrigin(), scale: scale,
                       bounds: (placement.halfWidth, placement.halfHeight))
        statusText.update(dt, pet: self)
    }

    private func applyWalk() {
        let w = loco.walkAmount
        if w < 0.001 { return }
        let s = sin(loco.phase)
        let c = cos(loco.phase)
        final[.bodyY] += abs(s) * 0.02 * w
        final[.torsoRoll] += s * 0.02 * w
        final[.headRoll] -= s * 0.03 * w
        final[.headPitch] += c * 0.02 * w
        final[.torsoPitch] += 0.05 * w
        final[.armSwingL] += 0.1 * w
        final[.armSwingR] += 0.1 * w
    }

    private var towardCenter: Double {
        let half = (placement.maxX - placement.minX) / 2
        guard half > 0.01 else { return 0 }
        let k = clamp((loco.x - (placement.maxX + placement.minX) / 2) / half, -1, 1)
        return -0.5 * k
    }

    private func applyGaze(_ info: StateInfo) {
        var look: SIMD2<Double>?
        if let a = attention, info.attentive {
            let head = mob.head.simdWorldPosition.d
            let dir = a - head
            let yaw = atan2(dir.x, dir.z)
            let pitch = atan2(dir.y, hypot(dir.x, dir.z))
            look = [clamp((yaw - loco.facing) / 0.9, -1, 1), clamp(pitch / 0.5, -1, 1)]
            loco.idleFacing = info.turnBody ? clamp(yaw * 0.45, -0.6, 0.6) : towardCenter
        } else {
            loco.idleFacing = towardCenter
            look = lookHint
        }

        face.autoLook = look == nil && info.autoLook
        if let look { face.lookAt(look.x, look.y) } else if !info.autoLook { face.lookAt(0, 0) }

        final[.headYaw] += face.look.x * 0.45
        final[.headPitch] -= face.look.y * 0.3
    }
}
