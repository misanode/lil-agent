import Foundation
import QuartzCore
import simd

@inline(__always) func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, x)) }
@inline(__always) func clamp01(_ x: Double) -> Double { clamp(x, 0, 1) }
func rnd(_ a: Double, _ b: Double) -> Double { a + Double.random(in: 0..<1) * (b - a) }
func pick<T>(_ options: [T]) -> T { options.randomElement()! }
func sgn(_ x: Double) -> Double { x > 0 ? 1 : (x < 0 ? -1 : 0) }

func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

func env(_ t: Double, _ a: Double, _ b: Double, _ fade: Double = 0.25) -> Double {
    smooth(a, a + fade, t) * (1 - smooth(b - fade, b, t))
}

func hop(_ t: Double, _ start: Double, _ dur: Double, _ h: Double) -> Double {
    let k = (t - start) / dur
    return k > 0 && k < 1 ? 4 * h * k * (1 - k) : 0
}

func dip(_ t: Double, _ at: Double, _ depth: Double, _ width: Double = 0.12) -> Double {
    depth * max(0, 1 - abs(t - at) / width)
}

func damp(_ current: Double, _ target: Double, _ rate: Double, _ dt: Double) -> Double {
    current + (target - current) * (1 - exp(-rate * dt))
}

func easeOutBack(_ x: Double) -> Double { 1 + 2.70158 * pow(x - 1, 3) + 1.70158 * pow(x - 1, 2) }
func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func now() -> Double { CACurrentMediaTime() }

func quatXYZ(_ x: Double, _ y: Double, _ z: Double) -> simd_quatf {
    simd_quatf(angle: Float(x), axis: [1, 0, 0]) * simd_quatf(angle: Float(y), axis: [0, 1, 0]) * simd_quatf(angle: Float(z), axis: [0, 0, 1])
}

func quatY(_ y: Double) -> simd_quatf { simd_quatf(angle: Float(y), axis: [0, 1, 0]) }

typealias Vec3 = SIMD3<Double>

extension SIMD3 where Scalar == Float {
    var d: Vec3 { Vec3(Double(x), Double(y), Double(z)) }
}

extension SIMD3 where Scalar == Double {
    var f: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
