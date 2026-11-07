import Foundation

final class Locomotion {
    private static let walkFacing = 1.0
    private static let cycleLength = 0.8

    var x = 0.0
    var targetX = 0.0
    var speed = 0.0
    var maxSpeed = 0.9
    var phase = 0.0
    var walkAmount = 0.0
    var facing = 0.0
    var idleFacing = 0.0
    var minX = -3.0
    var maxX = 3.0
    var scale = 1.0

    func setBounds(_ minX: Double, _ maxX: Double) {
        self.minX = minX
        self.maxX = maxX
        x = clamp(x, minX, maxX)
        targetX = clamp(targetX, minX, maxX)
    }

    func walkTo(_ x: Double) { targetX = clamp(x, minX, maxX) }
    func stop() { targetX = x }

    var arrived: Bool { abs(targetX - x) < 0.04 * scale && abs(speed) < 0.08 * scale }

    func update(_ dt: Double, scale: Double) {
        self.scale = scale
        let vmax = maxSpeed * scale
        let dx = targetX - x
        let desired = abs(dx) > 0.01 * scale ? sgn(dx) * min(vmax, abs(dx) * 2.5) : 0
        speed += (desired - speed) * (1 - exp(-5 * dt))
        let nextX = x + speed * dt
        x = clamp(nextX, minX, maxX)
        if x != nextX { speed = 0 }

        walkAmount = min(1, abs(speed) / (0.35 * vmax))
        phase += (abs(speed) / (Self.cycleLength * scale)) * .pi * 2 * dt

        let facingTarget = abs(speed) > 0.12 * vmax ? sgn(speed) * Self.walkFacing : idleFacing
        facing += (facingTarget - facing) * (1 - exp(-6 * dt))
    }
}

final class Personality {
    var energy = 1.0
    private static let tired = 0.18
    private static let awakeTime = 30.0 * 60

    func update(_ dt: Double, state: String) {
        if state == "sleep" {
            energy = min(1, energy + dt / 35)
        } else {
            energy = max(0, energy - dt * (1 - Self.tired) / Self.awakeTime)
        }
    }

    func idleExpression() -> String { energy < 0.3 ? "sleepy" : "neutral" }

    private func weightedPick(_ options: [(String, Double)]) -> String {
        let total = options.reduce(0) { $0 + $1.1 }
        var r = Double.random(in: 0..<1) * total
        for (name, w) in options {
            r -= w
            if r <= 0 { return name }
        }
        return options[0].0
    }

    func nextAction(_ c: Pet) -> Transition {
        if energy < Self.tired { return Transition("sleepy") }
        let options: [(String, Double)] = c.socialMode
            ? [("idle", 3), ("curious", 1.2), ("happy", 0.8), ("wave", 0.5), ("dance", 0.6), ("excited", 0.4)]
            : [("walk", c.settings.autoWalk ? 4 : 0), ("idle", 2), ("curious", 1), ("happy", 0.5), ("dance", 0.4),
               ("excited", 0.3), ("sad", 0.2), ("wave", 0.25),
               ("coffee", 0.45), ("workout", 0.3), ("meditate", 0.3), ("idea", 0.35)]
        let name = weightedPick(options.filter { $0.0 == "walk" || $0.0 == "idle" || c.settings.allows($0.0) })
        if name != "walk" { return Transition(name) }

        let loco = c.loco
        if let home = c.home {
            let reach = 0.8 * c.placement.scale
            let near = min(loco.maxX, max(loco.minX, home.x + rnd(-reach, reach)))
            return Transition("walk", Params(x: near, lift: home.lift))
        }
        let range = loco.maxX - loco.minX
        var target = loco.x
        var i = 0
        while i < 6 && abs(target - loco.x) < range * 0.25 {
            target = rnd(loco.minX, loco.maxX)
            i += 1
        }
        var params = Params(x: target)
        let maxLift = c.placement.maxLift
        if maxLift > 0 {
            let r = Double.random(in: 0..<1)
            if r < 0.25 { params.lift = 0 }
            else if r < 0.6 { params.lift = rnd(0, maxLift) }
            else { params.lift = min(maxLift, max(0, c.restLift + rnd(-1.5, 1.5) * c.placement.scale)) }
        }
        return Transition("walk", params)
    }
}
