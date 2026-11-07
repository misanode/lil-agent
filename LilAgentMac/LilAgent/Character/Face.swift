import Foundation

struct Expression {
    var eyeOpen = SIMD2<Double>(1, 1)
    var eyeScale = SIMD2<Double>(1, 1)
}

let EXPRESSIONS: [String: Expression] = [
    "neutral": Expression(),
    "happy": Expression(eyeScale: [1.05, 1.05]),
    "sad": Expression(eyeOpen: [0.8, 0.8], eyeScale: [0.95, 0.95]),
    "sleepy": Expression(eyeOpen: [0.28, 0.28]),
    "asleep": Expression(eyeOpen: [0, 0]),
    "curious": Expression(eyeOpen: [1, 0.72], eyeScale: [1.15, 0.92]),
    "surprised": Expression(eyeScale: [1.32, 1.32]),
    "excited": Expression(eyeScale: [1.2, 1.2]),
    "angry": Expression(eyeOpen: [0.85, 0.85]),
    "joy": Expression(),
    "love": Expression(eyeScale: [1.1, 1.1]),
    "uwu": Expression(),
    "crying": Expression(eyeOpen: [0.14, 0.14]),
    "smug": Expression(eyeOpen: [0.42, 0.42]),
    "deadpan": Expression(eyeOpen: [0.1, 0.1]),
    "annoyed": Expression(eyeOpen: [0.45, 0.45]),
    "nervous": Expression(),
    "pouty": Expression(eyeOpen: [0.85, 0.85]),
]

final class FaceDisplay {
    private(set) var expression = "neutral"
    var target = Expression()
    var current = Expression()
    var transitionRate = 9.0

    var look = SIMD2<Double>(0, 0)
    var lookTarget = SIMD2<Double>(0, 0)
    var autoLook = true
    private var nextSaccade = rnd(1, 3)

    var autoBlink = true
    private var blinkPhase = -1.0
    private(set) var blinkFactor = 1.0
    private var nextBlink = rnd(1.5, 4)

    func setExpression(_ name: String) {
        expression = name
        target = EXPRESSIONS[name] ?? Expression()
    }

    func blink() {
        if blinkPhase < 0 { blinkPhase = 0 }
    }

    func lookAt(_ x: Double, _ y: Double) {
        lookTarget = [clamp(x, -1, 1), clamp(y, -1, 1)]
    }

    private func updateBlink(_ dt: Double) -> Double {
        if autoBlink && blinkPhase < 0 {
            nextBlink -= dt
            if nextBlink <= 0 {
                blink()
                nextBlink = Double.random(in: 0..<1) < 0.15 ? 0.22 : rnd(2, 5.5)
            }
        }
        if blinkPhase < 0 { return 1 }
        blinkPhase += dt / 0.18
        if blinkPhase >= 1 {
            blinkPhase = -1
            return 1
        }
        return 1 - sin(blinkPhase * .pi)
    }

    private func updateSaccades(_ dt: Double) {
        guard autoLook else { return }
        nextSaccade -= dt
        if nextSaccade > 0 { return }
        nextSaccade = rnd(0.8, 3.2)
        if Double.random(in: 0..<1) < 0.3 { lookTarget = [0, 0] } else { lookTarget = [rnd(-0.75, 0.75), rnd(-0.4, 0.35)] }
    }

    func update(_ dt: Double) {
        let r = transitionRate
        for i in 0..<2 {
            current.eyeOpen[i] = damp(current.eyeOpen[i], target.eyeOpen[i], r, dt)
            current.eyeScale[i] = damp(current.eyeScale[i], target.eyeScale[i], r, dt)
        }
        updateSaccades(dt)
        look.x = damp(look.x, lookTarget.x, 16, dt)
        look.y = damp(look.y, lookTarget.y, 16, dt)
        blinkFactor = updateBlink(dt)
    }
}
