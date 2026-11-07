import Foundation

final class PointerDirector {
    private static let sleeping: Set<String> = ["sleep", "sleepy"]
    private static let airborneStates: Set<String> = ["carried", "drop"]
    private static let dragThresholdPx = 6.0
    private static let petWindow = 3.0
    private static let gazeDepth = 4.0
    private static let velocityWindow = 0.08
    private static let maxThrow = 14.0
    private static let throwSpeed = 3.5
    private static let wheelZoom = 0.0015

    private struct Drag {
        var offsetX: Double
        var offsetH: Double
        var x: Double
        var h: Double
        var history: [(x: Double, h: Double, t: Double)] = []
    }

    unowned let pet: Pet
    let screen: ScreenSpace
    private var pointer: (x: Double, y: Double)?
    private(set) var over = false
    var cursor: (x: Double, y: Double)?
    private(set) var airborne = false
    var menuOpen = false
    private var press: (x: Double, y: Double)?
    private var drag: Drag?
    private var pets: [Double] = []

    var size: () -> Double = { 210 }
    var onResize: ((Double) -> Void)?
    var onOverChange: ((Bool) -> Void)?
    var onAirborneChange: ((Bool) -> Void)?

    init(pet: Pet, screen: ScreenSpace) {
        self.pet = pet
        self.screen = screen
    }

    var dragging: Bool { drag != nil }

    private func world(_ px: Double, _ py: Double) -> (x: Double, h: Double) {
        (screen.toWorldX(px), screen.heightAboveFloor(py, floorY: pet.placement.floorY))
    }

    private func hits(_ w: (x: Double, h: Double)) -> Bool {
        let s = pet.placement.scale, b = pet.mob.hitBox, dx = w.x - pet.loco.x
        return dx > b.minX * s && dx < b.maxX * s && w.h > pet.lift && w.h < pet.lift + b.top * s
    }

    func move(_ px: Double, _ py: Double) {
        pointer = (px, py)
        let w = world(px, py)
        if let p = press, drag == nil, hypot(px - p.x, py - p.y) > Self.dragThresholdPx { startDrag(w) }
        if var d = drag {
            let t = now()
            d.x = w.x - d.offsetX
            d.h = w.h - d.offsetH
            d.history.append((d.x, d.h, t))
            while d.history.count > 2 && t - d.history[0].t > Self.velocityWindow { d.history.removeFirst() }
            drag = d
        }
    }

    func leave() {
        if drag == nil { pointer = nil }
    }

    private func releaseVelocity(_ d: Drag) -> (vx: Double, vy: Double) {
        let t = now()
        let recent = d.history.filter { t - $0.t <= Self.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.t - first.t >= 0.016, t - last.t <= 0.09 else { return (0, 0) }
        let dt = last.t - first.t
        let cap = Self.maxThrow * pet.placement.scale
        return (clamp((last.x - first.x) / dt, -cap, cap), clamp((last.h - first.h) / dt, -cap, cap))
    }

    func wheel(_ delta: Double) {
        guard let onResize, drag == nil, !menuOpen, over else { return }
        onResize(size() * exp(-clamp(delta, -120, 120) * Self.wheelZoom))
    }

    func down(_ px: Double, _ py: Double) {
        guard !menuOpen, over else { return }
        press = (px, py)
    }

    private func startDrag(_ w: (x: Double, h: Double)) {
        drag = Drag(offsetX: w.x - pet.loco.x, offsetH: w.h - pet.lift, x: pet.loco.x, h: pet.lift)
        pet.carryVX = 0
        pet.trigger("carried", force: true)
    }

    func up() {
        if let d = drag {
            let v = releaseVelocity(d)
            let speed = hypot(v.vx, v.vy) / pet.placement.scale
            if speed < Self.throwSpeed {
                pet.trigger("settle", Params(then: "idle"), force: true)
            } else {
                pet.trigger("drop", Params(then: "idle", vx: v.vx, vy: v.vy), force: true)
            }
            pet.carryVX = nil
            drag = nil
        } else if press != nil {
            petIt()
        }
        press = nil
    }

    private func petIt() {
        let t = now()
        pets = pets.filter { t - $0 < Self.petWindow }
        pets.append(t)
        let count = pets.count
        if Self.sleeping.contains(pet.stateName) {
            pet.trigger("surprised", Params(then: "wake"), force: true)
        } else if count >= 9 && pet.stateName != "dizzy" && pet.settings.allows("dizzy") {
            pet.trigger("dizzy", Params(then: "grumpy"), force: true)
        } else if count >= 5 && pet.stateName != "annoyed" && pet.stateName != "dizzy" && pet.settings.allows("annoyed") {
            pet.trigger("annoyed", Params(then: "idle"), force: true)
        } else if pet.stateName == "annoyed" || pet.stateName == "dizzy" {
            return
        } else {
            pet.trigger("pet", Params(then: "idle", count: count), force: true)
        }
    }

    func update(_ dt: Double) {
        let w = pointer.map { world($0.x, $0.y) }
        let isOver = drag != nil || menuOpen || (w.map(hits) ?? false)
        if isOver != over {
            over = isOver
            onOverChange?(isOver)
        }
        let isAirborne = drag != nil || Self.airborneStates.contains(pet.stateName) || pet.lift > 0.03 || pet.restLift > 0.03
        if isAirborne != airborne {
            airborne = isAirborne
            onAirborneChange?(isAirborne)
        }

        if let d = drag {
            let p = pet.placement
            let x = clamp(d.x, p.minX, p.maxX)
            pet.loco.x = x
            pet.loco.targetX = x
            pet.loco.speed = 0
            pet.lift = max(0, d.h)
            var vx = 0.0
            if let a = d.history.first, let b = d.history.last, b.t > a.t { vx = (b.x - a.x) / (b.t - a.t) }
            pet.carryVX = (pet.carryVX ?? 0) + (vx - (pet.carryVX ?? 0)) * (1 - exp(-8 * dt))
            pet.attention = nil
            return
        }

        if pet.settings.lookAtCursor, pet.stateName != "drop", let c = cursor.map({ world($0.x, $0.y) }) ?? w {
            pet.attention = Vec3(c.x, pet.placement.floorY + c.h, Self.gazeDepth)
        } else {
            pet.attention = nil
        }
    }
}


