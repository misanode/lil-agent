import SceneKit
import simd

final class ClipAction {
    let clip: GLTFClip
    var time: Float = 0
    var active = false
    var paused = false
    var once = false
    var weight: Float = 0
    var speed: Float = 1

    init(_ clip: GLTFClip) { self.clip = clip }

    var isRunning: Bool { active && !paused }

    @discardableResult func reset() -> ClipAction {
        time = 0
        paused = false
        return self
    }

    func play() { active = true }

    func stop() {
        active = false
        paused = false
        time = 0
        weight = 0
    }

    func advance(_ dt: Float) {
        guard active, !paused else { return }
        time += dt * speed
        let d = clip.duration
        if once {
            if time >= d {
                time = d
                paused = true
            }
        } else if d > 0 {
            time = time.truncatingRemainder(dividingBy: d)
        }
    }
}

final class Mixer {
    private struct Binding {
        let node: SCNNode
        let path: GLTFTrack.Path
        let rest: SIMD4<Float>
    }

    let actions: [ClipAction]
    private var bindings: [Int: Binding] = [:]
    private var accum: [Int: (value: SIMD4<Float>, weight: Float)] = [:]

    init(nodes: [SCNNode], actions: [ClipAction]) {
        self.actions = actions
        for action in actions {
            for track in action.clip.tracks where track.node < nodes.count {
                let key = track.node * 3 + track.path.rawValue
                if bindings[key] != nil { continue }
                let node = nodes[track.node]
                let rest: SIMD4<Float>
                switch track.path {
                case .translation: rest = SIMD4(node.simdPosition, 0)
                case .scale: rest = SIMD4(node.simdScale, 0)
                case .rotation: rest = node.simdOrientation.vector
                }
                bindings[key] = Binding(node: node, path: track.path, rest: rest)
            }
        }
    }

    private static func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float, rotation: Bool) -> SIMD4<Float> {
        rotation ? slerp(a, b, t) : a + (b - a) * t
    }

    func update(_ dt: Float) {
        for a in actions { a.advance(dt) }
        accum.removeAll(keepingCapacity: true)
        for a in actions where a.active && a.weight > 0 {
            for track in a.clip.tracks {
                let key = track.node * 3 + track.path.rawValue
                let v = track.sample(at: a.time)
                if var e = accum[key] {
                    e.weight += a.weight
                    e.value = Mixer.mix(e.value, v, a.weight / e.weight, rotation: track.path == .rotation)
                    accum[key] = e
                } else {
                    accum[key] = (v, a.weight)
                }
            }
        }
        for (key, b) in bindings {
            var v = b.rest
            if let e = accum[key] {
                v = e.weight < 1 ? Mixer.mix(e.value, b.rest, 1 - e.weight, rotation: b.path == .rotation) : e.value
            }
            switch b.path {
            case .translation: b.node.simdPosition = SIMD3(v.x, v.y, v.z)
            case .scale: b.node.simdScale = SIMD3(v.x, v.y, v.z)
            case .rotation: b.node.simdOrientation = simd_quatf(vector: v).normalized
            }
        }
    }
}
