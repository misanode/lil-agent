import SceneKit
import simd

final class Mascot {
    private static let fitHeight: Float = 1.0
    private static let fitWidth: Float = 1.6
    static let hover = 0.1
    private static let oneShot: Set<String> = ["wake", "surprised", "settle", "drop", "done", "idea"]
    private static let fadeRate = 10.0
    private static let turnNames = ["head", "neck", "trunk", "torso", "chest", "spine", "body"]
    private static let eyeTravelFraction: Float = 0.04
    private static let eyesName = try! NSRegularExpression(pattern: "^eyes?([_.\\s-]?(l|r|left|right))?$", options: .caseInsensitive)

    let root = SCNNode()
    let hips = SCNNode()
    let torso = SCNNode()
    var head: SCNNode { torso }
    let face = FaceDisplay()

    private(set) var height = 1.1
    private(set) var halfWidth = 0.6
    private(set) var halfDepth = 0.3
    private(set) var emoteLift = 1.1
    private static let sidePropGroups = [
        ("prop_command_", "prop_command_window"), ("prop_error_", "prop_error_alert"),
        ("prop_permission_", "prop_permission_lock"), ("prop_planning_", "prop_planning_list"),
        ("prop_question_", "prop_question_bubble"), ("prop_thinking_", "prop_thinking_bubble"),
        ("prop_searching_", "prop_searching_glass"),
    ]

    private var actions: [String: ClipAction] = [:]
    private var weights: [String: Double] = [:]
    private var mixer: Mixer?
    private var idleClip: String?
    private var moveClip: String?
    private var playing: String?
    var stateName = "idle"

    private var eyes: [(node: SCNNode, rest: SIMD3<Float>, restPos: SIMD3<Float>)] = []
    private var faces: [String: SCNNode] = [:]
    private var cursor: SCNNode?
    private var screenFace: Bool { !faces.isEmpty }
    var hasScreenFace: Bool { screenFace }
    private var typingPoses: [(hover: (SIMD3<Float>, simd_quatf), press: (SIMD3<Float>, simd_quatf))] = []
    private var props: [SCNNode] = []
    private var sideProps: [(anchor: SCNNode, nodes: [SCNNode])] = []
    var facing = 0.0
    private(set) var facingSide: Float = 1
    private var screen: (mesh: SCNNode, prop: SCNNode, min: SCNVector3, max: SCNVector3)?
    private var turn: (node: SCNNode, rest: simd_quatf)?
    private var gazeYaw: Float = 0
    private var eyeTravel: Float = 0

    private struct Arm {
        let node: SCNNode
        let side: Float
        var tapStart = -Double.infinity
        var holding: Int64?
        var released = -Double.infinity
        var depth = 1.0
        var press = 0.0
    }
    private var arms: [Arm] = []
    private var nextArm = 0
    private var lastKey: (code: Int64, arm: Int)?
    private var clock = 0.0
    private var keyDriven = 0.0
    private var lastTap = -Double.infinity
    private static let hoverY: Float = 0.93, pressY: Float = 0.78
    private static let hoverTilt: Float = 27, pressTilt: Float = 38
    private static let armX: Float = 1.17, armZ: Float = 0.80
    private static let tapDown = 0.05, tapUp = 0.14, keyHold = 1.2
    private static let maxHold = 10.0

    private static let liftExtra: Float = 0.35, strikeExtra: Float = 0.45
    private static let tapDip: Float = 0.03, tapRoll: Float = 0.032, nodPitch: Float = 0.025, cursorKick: Float = 0.05
    private var bodyRig: (node: SCNNode, pos: SIMD3<Float>, rot: simd_quatf)?
    private var headRig: (node: SCNNode, rot: simd_quatf)?
    private var cursorRest: SIMD3<Float>?
    private var dip = 0.0, rock = 0.0, nod = 0.0, tick = 0.0
    private var autoNext = 0.0
    private var autoWord = 0
    private var autoDeletes = 0
    private var lastRealKey = -Double.infinity
    private static let autoQuiet = 2.0

    private var actingState = ""
    private var actingStart = 0.0
    private var slowBlend: (to: String, start: Double, from: [String: Double])?
    private static let lieDownS = 1.3
    private static let wakeSpeed: Float = 0.5
    private static let shakeAt = 2.05, shakeS = 0.85, shakeYaw = 0.34
    private var mugArm: Int?
    private var mugBase: simd_quatf?
    private var mug: SCNNode?
    private static let mugReach: Float = 0.75, sipTilt: Float = 0.13, sipLean: Float = 0.035
    var mugAmount = 1.0
    private var cap: SCNNode?
    private var permissionLock: SCNNode?
    private var legs: [(node: SCNNode, rot: simd_quatf)] = []
    private var armRest: [simd_quatf] = []
    private var bodyScale = SIMD3<Float>(repeating: 1)
    private static let lyingHips = SIMD3<Float>(0.35, 0.94, 0)
    private static let incline: Float = 0.45
    private static let headRest: Float = 0.72, bodyRest: Float = 0.56
    private var sleepZs: [SCNNode] = []
    private static let zStart = SIMD3<Float>(0, 1.92, 0), zFrom = SIMD3<Float>(-0.6, 2.75, 0.2)
    private static let breathHz = 0.22, breathDepth: Float = 0.03, breathNod: Float = 0.02
    private var bed: SCNNode?
    private var bedRest: SIMD3<Float>?
    private var bedBox: (minX: Double, maxX: Double, top: Double)?
    private var bedHalfDepth = 0.0
    private var blanket: SCNNode?
    private var bedRoot: SCNNode?
    private var dentMaterials: [SCNMaterial] = []
    private var blanketMaterials: [SCNMaterial] = []
    private var rigHips: (node: SCNNode, pos: SIMD3<Float>, rot: simd_quatf)?
    private var bedAmount = 0.0, blanketAmount = 0.0
    private static let mattressTop: Float = 0.62
    private static let bedIn = 0.45, bedOut = 0.35, blanketUp = 0.55, blanketOff = 0.22
    private struct Tears {
        let stream: SCNNode
        let tip: SIMD3<Float>
        let puddle: SCNNode?
        let ripple: SCNNode?
    }
    private var tears: [Tears] = []
    private static let tearSink: Float = 0.03

    private var own = 0.0
    private var bobPhase = rnd(0, 10)
    var lean = 0.0
    var climb = 0.0
    var walkAmount = 0.0
    var walkPhase = 0.0

    init(asset: GLTFAsset) {
        root.name = "mascot"
        hips.position.y = CGFloat(Self.hover)
        root.addChildNode(hips)
        hips.addChildNode(torso)

        let scene = asset.sceneRoot
        let box = Self.measure(scene)
        let size = box.max - box.min
        let center = (box.max + box.min) / 2
        let unit = min(Self.fitHeight / max(size.y, 1e-6), Self.fitWidth / max(max(size.x, size.z), 1e-6))

        let model = SCNNode()
        model.name = "model"
        model.simdScale = SIMD3(repeating: unit)
        model.simdPosition = SIMD3(-center.x * unit, -box.min.y * unit, -center.z * unit)
        model.addChildNode(scene)
        torso.addChildNode(model)

        let h = Double(size.y * unit)
        height = h + Self.hover
        halfWidth = max(0.25, Double(max(size.x, size.z) * unit) / 2)
        halfDepth = Double(size.z * unit) / 2
        emoteLift = h + 0.1

        Self.restyleClay(scene)
        findEyes(scene)
        scene.enumerateHierarchy { node, _ in
            guard let name = node.name?.lowercased(), name.hasPrefix("face_") else { return }
            let face = String(name.dropFirst(5))
            if face == "cursor" { self.cursor = node } else { self.faces[face] = node }
        }
        findProps(scene)
        for (prefix, anchorName) in Self.sidePropGroups {
            if let anchor = props.first(where: { $0.name?.lowercased() == anchorName }) {
                sideProps.append((anchor, props.filter { $0.name?.lowercased().hasPrefix(prefix) == true }))
            }
        }
        for prop in props {
            prop.enumerateHierarchy { node, stop in
                if self.screen == nil, node.geometry != nil, node.name?.range(of: "display|screen", options: [.regularExpression, .caseInsensitive]) != nil {
                    let (a, b) = node.geometry!.boundingBox
                    self.screen = (node, prop, a, b)
                    stop.pointee = true
                }
            }
        }
        eyeTravel = size.y * Self.eyeTravelFraction

        for (name, side) in [("arm_l", Float(-1)), ("arm_r", Float(1))] {
            scene.enumerateHierarchy { node, stop in
                if node.geometry == nil, node.name?.lowercased() == name {
                    self.arms.append(Arm(node: node, side: side))
                    stop.pointee = true
                }
            }
        }

        if screenFace, let typing = asset.clips.first(where: { $0.name.lowercased() == "typing" }) {
            let a: Float = 1.0 / 24, b: Float = 4.0 / 24
            for arm in arms {
                guard let n = asset.nodes.firstIndex(of: arm.node) else { continue }
                func pose(_ t: Float) -> (SIMD3<Float>, simd_quatf) {
                    let tr = typing.tracks.first { $0.node == n && $0.path == .translation }
                    let ro = typing.tracks.first { $0.node == n && $0.path == .rotation }
                    let p = tr.map { track -> SIMD3<Float> in let s = track.sample(at: t); return SIMD3(s.x, s.y, s.z) } ?? arm.node.simdPosition
                    let q = ro.map { simd_quatf(vector: $0.sample(at: t)) } ?? arm.node.simdOrientation
                    return (p, q)
                }
                func handY(_ p: (SIMD3<Float>, simd_quatf)) -> Float { p.0.y + p.1.act(SIMD3(0, -1, 0)).y }
                let (pa, pb) = (pose(a), pose(b))
                let (hover, press) = handY(pa) < handY(pb) ? (pb, pa) : (pa, pb)
                let delta = hover.1.inverse * press.1
                func turned(_ k: Float) -> simd_quatf { hover.1 * simd_quatf(angle: delta.angle * k, axis: delta.axis) }
                typingPoses.append((hover: (hover.0, turned(-Self.liftExtra)), press: (press.0, turned(1 + Self.strikeExtra))))
            }
            if typingPoses.count != arms.count { typingPoses = [] }
            scene.enumerateHierarchy { node, _ in
                guard node.geometry == nil else { return }
                switch node.name?.lowercased() {
                case "body" where self.bodyRig == nil:
                    self.bodyRig = (node, node.simdPosition, node.simdOrientation)
                    self.bodyScale = node.simdScale
                case "leg_l", "leg_r": self.legs.append((node, node.simdOrientation))
                case "head" where self.headRig == nil: self.headRig = (node, node.simdOrientation)
                default: break
                }
            }
            if let cursor { cursorRest = cursor.simdPosition }
            armRest = arms.map { $0.node.simdOrientation }
            if let url = Bundle.main.url(forResource: "bed", withExtension: "glb"),
               let data = try? Data(contentsOf: url), let asset = try? GLTFAsset(data: data) {
                let holder = SCNNode()
                holder.name = "bed"
                holder.simdScale = model.simdScale
                holder.simdPosition = model.simdPosition
                let u = Double(model.simdScale.x), ox = Double(model.simdPosition.x)
                bedBox = (ox - 3.45 * u, ox + 1.9 * u, 3.2 * u)
                let bedBounds = Self.measure(asset.sceneRoot)
                let oz = Double(model.simdPosition.z)
                bedHalfDepth = max(abs(oz + Double(bedBounds.min.z) * u), abs(oz + Double(bedBounds.max.z) * u))
                holder.addChildNode(asset.sceneRoot)
                holder.isHidden = true
                torso.addChildNode(holder)
                bed = holder
                bedRest = holder.simdScale
                blanket = asset.sceneRoot.childNode(withName: "bed_blanket", recursively: true)
                bedRoot = asset.sceneRoot
                func react(_ name: String, _ shader: String, floor: Float, puff: Float, into list: inout [SCNMaterial]) {
                    guard let top = asset.sceneRoot.childNode(withName: name, recursively: true) else { return }
                    top.enumerateHierarchy { n, _ in
                        guard let g = n.geometry?.copy() as? SCNGeometry else { return }
                        let offs = asset.sceneRoot.simdConvertPosition(.zero, from: n)
                        g.materials = g.materials.map { m in
                            let c = m.copy() as! SCNMaterial
                            c.shaderModifiers = [.geometry: shader]
                            c.setValue(NSValue(scnVector3: SCNVector3(offs)), forKey: "offs")
                            c.setValue(NSNumber(value: floor), forKey: "floorY")
                            c.setValue(NSNumber(value: puff), forKey: "puff")
                            c.setValue(NSNumber(value: 0), forKey: "on")
                            c.setValue(NSNumber(value: 0), forKey: "reveal")
                            list.append(c)
                            return c
                        }
                        n.geometry = g
                    }
                }
                react("bed_mattress", Self.dentShader, floor: 0.4, puff: 0.02, into: &dentMaterials)
                react("bed_pillow", Self.dentShader, floor: 0.6, puff: 0.14, into: &dentMaterials)
                react("bed_blanket", Self.blanketShader, floor: 0, puff: 0, into: &blanketMaterials)
            }
            scene.enumerateHierarchy { node, stop in
                if node.geometry == nil, node.name?.lowercased() == "hips" {
                    self.rigHips = (node, node.simdPosition, node.simdOrientation)
                    stop.pointee = true
                }
            }
            for p in props {
                switch p.name?.lowercased() {
                case "prop_coffee_mug": mug = p
                case "prop_sleep_cap": cap = p
                case "prop_permission_lock": permissionLock = p
                case let name? where name.hasPrefix("prop_sleep_z"): sleepZs.append(p)
                default: break
                }
            }
            if let coffee = asset.clips.first(where: { $0.name.lowercased() == "coffee" }),
               let i = arms.firstIndex(where: { $0.side > 0 }), let n = asset.nodes.firstIndex(of: arms[i].node),
               let track = coffee.tracks.first(where: { $0.node == n && $0.path == .rotation }) {
                mugArm = i
                mugBase = simd_quatf(vector: track.sample(at: 1.0 / 24))
            }
        }

        for side in ["l", "r"] {
            var stream: SCNNode?, puddle: SCNNode?, ripple: SCNNode?
            scene.enumerateHierarchy { node, _ in
                switch node.name?.lowercased() {
                case "prop_sad_fountain" + side: stream = node
                case "prop_sad_puddle" + side: puddle = node
                case "prop_sad_ripple" + side: ripple = node
                default: break
                }
            }
            if let stream, let tip = Self.lowestPoint(of: stream) {
                tears.append(Tears(stream: stream, tip: tip, puddle: puddle, ripple: ripple))
            }
        }

        outer: for name in Self.turnNames {
            var found: SCNNode?
            scene.enumerateHierarchy { node, stop in
                if node.name?.lowercased() == name {
                    found = node
                    stop.pointee = true
                }
            }
            if let node = found, node.geometry == nil {
                turn = (node, node.simdOrientation)
                break outer
            }
        }

        var list: [ClipAction] = []
        for clip in asset.clips {
            let key = clip.name.lowercased()
            if actions[key] != nil { continue }
            let action = ClipAction(clip)
            action.once = Self.oneShot.contains(key)
            actions[key] = action
            list.append(action)
        }
        if !list.isEmpty {
            mixer = Mixer(nodes: asset.nodes, actions: list)
            if screenFace { actions["wake"]?.speed = Self.wakeSpeed }
            let names = asset.clips.map { $0.name.lowercased() }
            idleClip = actions["idle"] != nil ? "idle" : (names.first { $0.range(of: "idle|stand|breath|rest", options: .regularExpression) != nil } ?? names.first)
            moveClip = ["walk", "run", "fly", "move", "swim"].first { actions[$0] != nil }
                ?? names.first { $0.range(of: "walk|run|fly|move|swim|hop", options: .regularExpression) != nil }
        }
    }

    private static func lowestPoint(of node: SCNNode) -> SIMD3<Float>? {
        var best: SIMD3<Float>?
        node.enumerateHierarchy { n, _ in
            guard let g = n.geometry, let src = g.sources(for: .vertex).first, src.bytesPerComponent == 4 else { return }
            let m = node.simdConvertTransform(matrix_identity_float4x4, from: n)
            src.data.withUnsafeBytes { raw in
                for i in 0..<src.vectorCount {
                    let o = src.dataOffset + i * src.dataStride
                    let v = SIMD4<Float>(raw.load(fromByteOffset: o, as: Float.self), raw.load(fromByteOffset: o + 4, as: Float.self),
                                         raw.load(fromByteOffset: o + 8, as: Float.self), 1)
                    let p = m * v
                    if best == nil || p.y < best!.y { best = SIMD3(p.x, p.y, p.z) }
                }
            }
        }
        return best
    }

    private static func restyleClay(_ root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] where m.name == "Clay" {
                m.diffuse.contents = linearColor(0.73, 0.165, 0.055)
                m.roughness.contents = NSNumber(value: 0.62)
                m.clearCoat.contents = NSNumber(value: 0.08)
                m.clearCoatRoughness.contents = NSNumber(value: 0.25)
            }
        }
    }

    private static func measure(_ root: SCNNode) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        func visit(_ node: SCNNode, _ parent: simd_float4x4) {
            if node.name?.lowercased().hasPrefix("prop") == true { return }
            let world = parent * node.simdTransform
            if let g = node.geometry {
                let (a, b) = g.boundingBox
                for i in 0..<8 {
                    let p = SIMD3<Float>(Float(i & 1 == 0 ? a.x : b.x), Float(i & 2 == 0 ? a.y : b.y), Float(i & 4 == 0 ? a.z : b.z))
                    let w = world * SIMD4(p, 1)
                    lo = simd_min(lo, SIMD3(w.x, w.y, w.z))
                    hi = simd_max(hi, SIMD3(w.x, w.y, w.z))
                }
            }
            for c in node.childNodes { visit(c, world) }
        }
        visit(root, matrix_identity_float4x4)
        if lo.x > hi.x { return (.zero, SIMD3(1, 1, 1)) }
        return (lo, hi)
    }

    private func findEyes(_ node: SCNNode) {
        let name = node.name ?? ""
        if Self.eyesName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil {
            eyes.append((node, node.simdScale, node.simdPosition))
            return
        }
        node.childNodes.forEach(findEyes)
    }

    private func findProps(_ node: SCNNode) {
        if node.name?.lowercased().hasPrefix("prop") == true {
            props.append(node)
            return
        }
        node.childNodes.forEach(findProps)
    }


    private func targetWeights() -> (state: String, targets: [String: Double])? {
        guard let idle = idleClip else { return nil }
        let state = actions[stateName] != nil ? stateName : idle
        var targets = [state: 1.0]
        if let move = moveClip, move != state, state == idle || stateName == "walk" {
            let w = clamp01(walkAmount)
            targets[state] = 1 - w
            targets[move] = w
        }
        return (state, targets)
    }

    private func updateClips(_ dt: Double) {
        guard let mixer, let (state, targets) = targetWeights() else { return }
        if state != playing {
            actions[state]?.reset().play()
            playing = state
            slowBlend = screenFace && state == "sleep" ? (state, clock, weights) : nil
        }
        let k = 1 - exp(-Self.fadeRate * dt)
        var ease: Double?
        if let b = slowBlend {
            if b.to != state || clock - b.start >= Self.lieDownS { slowBlend = nil }
            else { ease = smooth(0, 1, (clock - b.start) / Self.lieDownS) }
        }
        for (name, action) in actions {
            let target = targets[name] ?? 0
            let prev = weights[name] ?? 0
            var w = prev + (target - prev) * k
            if let e = ease, let b = slowBlend {
                w = (b.from[name] ?? 0) * (1 - e) + (name == b.to ? e : 0)
                if name != b.to { action.paused = true }
            }
            if target == 0 && w < 0.01 {
                if action.active { action.stop() }
                weights[name] = nil
                continue
            }
            if !action.isRunning && !Self.oneShot.contains(name) { action.play() }
            weights[name] = w
        }
        let total = weights.values.reduce(0, +)
        for (name, action) in actions {
            action.weight = Float(total > 0 ? (weights[name] ?? 0) / total : 0)
        }
        mixer.update(Float(dt))
        for node in props { node.isHidden = !(node.simdScale.x > 0.5) }
    }

    private static let faceForState: [String: String] = [
        "typing": "prompt", "command": "prompt", "thinking": "closed", "meditate": "closed", "dizzy": "dizzy",
        "compacting": "squint", "workout": "squint", "sleep": "asleep",
    ]
    private static let openFaces: Set<String> = ["eyes", "wide", "love"]
    private static let promptStates: Set<String> = ["idle", "walk", "waiting", "subagents", "planning", "boot"]
    private static let faceForExpression: [String: String] = [
        "neutral": "eyes", "happy": "happy", "joy": "happy", "uwu": "happy", "excited": "happy", "love": "love",
        "sad": "sad", "crying": "sad", "sleepy": "closed", "asleep": "asleep", "deadpan": "closed", "smug": "wink",
        "curious": "eyes", "surprised": "wide", "nervous": "wide", "angry": "squint", "annoyed": "squint", "pouty": "squint",
    ]

    private func screenFaceName() -> String {
        let expression = face.expression
        var name = Self.faceForState[stateName]
            ?? (expression == "neutral" && Self.promptStates.contains(stateName) ? "prompt" : Self.faceForExpression[expression])
            ?? "eyes"
        if faces[name] == nil { name = faces["eyes"] != nil ? "eyes" : faces.keys.sorted()[0] }
        return name
    }

    private func updateEyes() {
        guard !eyes.isEmpty else { return }
        let f = face
        var blinkFactor = f.blinkFactor
        var eyeOpen = (f.current.eyeOpen[0] + f.current.eyeOpen[1]) / 2
        if screenFace {
            let name = screenFaceName()
            if !Self.openFaces.contains(name) {
                blinkFactor = 1
                eyeOpen = 1
            }
            for (key, node) in faces { node.isHidden = key != name }
            if name == "prompt" {
                blinkFactor = 1
                let lit = stateName == "typing" || clock.truncatingRemainder(dividingBy: 1.06) < 0.53
                cursor?.isHidden = !lit
            } else {
                cursor?.isHidden = true
            }
        }
        let open = clamp(eyeOpen * blinkFactor, 0.06, 1.4)
        let size = (f.current.eyeScale[0] + f.current.eyeScale[1]) / 2
        let dx = Float(f.look.x) * eyeTravel
        let dy = Float(f.look.y) * eyeTravel * 0.6
        for e in eyes {
            e.node.simdScale = SIMD3(e.rest.x, e.rest.y * Float(size * open), e.rest.z)
            e.node.simdPosition.x += dx
            e.node.simdPosition.y += dy
        }
    }

    private func resetGazeTargets() {
        if let turn { turn.node.simdOrientation = turn.rest }
        for e in eyes { e.node.simdPosition = e.restPos }
        if let bodyRig {
            bodyRig.node.simdPosition = bodyRig.pos
            bodyRig.node.simdOrientation = bodyRig.rot
            bodyRig.node.simdScale = bodyScale
        }
        if let headRig, headRig.node !== turn?.node { headRig.node.simdOrientation = headRig.rot }
        if let rigHips {
            rigHips.node.simdPosition = rigHips.pos
            rigHips.node.simdOrientation = rigHips.rot
        }
    }


    func applyPose(_ p: Pose, breath: Double) {
        let sit = clamp01(p[.sit])
        let free = 1 - own
        let tilt = 1 - 0.75 * own
        let bob = sin(bobPhase) * 0.035 * (1 - sit)
        hips.position.y = CGFloat((Self.hover * (1 - sit) + p[.bodyY] + bob - p[.crouch] * 0.5) * free)

        let squash = 1 - p[.crouch] * 1.5 * free
        let b = breath * free
        torso.simdScale = SIMD3(Float(1 / sqrt(squash) + b * 0.004), Float(squash + b * 0.01), Float(1 / sqrt(squash)))

        let wiggle = (p[.armRaiseR] - p[.armRaiseL]) * 0.12 + (p[.armSwingR] - p[.armSwingL]) * 0.05
        let gaze = p[.headYaw] * 0.6
        let routed = turn != nil ? own : 0
        gazeYaw = Float(gaze * routed)
        torso.simdOrientation = quatXYZ(
            ((p[.torsoPitch] * 0.5 + p[.headPitch] * 0.4) * (1 - 0.6 * sit) + lean * 0.6 - climb * 0.15) * tilt,
            p[.torsoYaw] + gaze * (1 - routed),
            (p[.torsoRoll] + p[.headRoll] * 0.7 + wiggle) * tilt
        )
    }

    func pressKey(_ code: Int64 = -1) {
        guard !arms.isEmpty else { return }
        let repeatKey = code >= 0 && lastKey?.code == code
        let i: Int
        if let held = arms.firstIndex(where: { $0.holding == code && code >= 0 }) {
            i = held
        } else if repeatKey, let last = lastKey {
            i = last.arm
        } else {
            i = nextArm
        }
        tap(i, holding: code >= 0 ? code : nil)
        if !repeatKey { nextArm = (i + 1) % arms.count }
        lastKey = (code, i)
        lastRealKey = clock
    }

    private func tap(_ i: Int, holding code: Int64?) {
        arms[i].tapStart = clock
        arms[i].holding = code
        arms[i].released = code != nil ? .infinity : clock
        arms[i].depth = rnd(0.8, 1)
        lastTap = clock
    }

    private func autoType() {
        guard screenFace, stateName == "typing", !arms.isEmpty else {
            autoNext = clock + rnd(0.2, 0.45)
            return
        }
        if arms.contains(where: { $0.holding != nil }) || clock - lastRealKey < Self.autoQuiet {
            autoNext = max(autoNext, clock + rnd(0.3, 0.6))
            return
        }
        guard clock >= autoNext else { return }
        if autoDeletes > 0 {
            autoDeletes -= 1
            tap(lastKey?.arm ?? 0, holding: nil)
            autoNext = clock + (autoDeletes > 0 ? rnd(0.1, 0.13) : rnd(0.25, 0.4))
            return
        }
        let i = Double.random(in: 0..<1) < 0.72 ? nextArm : (nextArm + arms.count - 1) % arms.count
        tap(i, holding: nil)
        nextArm = (i + 1) % arms.count
        lastKey = (-1, i)
        if autoWord > 0 {
            autoWord -= 1
            autoNext = clock + rnd(0.07, 0.15)
            return
        }
        autoWord = Int.random(in: 2...7)
        let roll = Double.random(in: 0..<1)
        if roll < 0.07 {
            autoDeletes = Int.random(in: 2...4)
            autoNext = clock + rnd(0.3, 0.5)
        } else if roll < 0.2 {
            autoNext = clock + rnd(0.5, 1.0)
        } else {
            autoNext = clock + rnd(0.14, 0.26)
        }
    }

    var armHeights: String { arms.map { String(format: "%.2f", $0.node.simdPosition.y) }.joined(separator: " ") }

    func releaseKey(_ code: Int64) {
        for i in arms.indices where arms[i].holding == code {
            arms[i].holding = nil
            arms[i].released = clock
        }
        lastTap = clock
    }

    private func applyKeyTaps(_ dt: Double) {
        for i in arms.indices where arms[i].holding != nil && clock - arms[i].tapStart > Self.maxHold {
            arms[i].holding = nil
            arms[i].released = clock
        }
        let holding = arms.contains { $0.holding != nil }
        let wanted = stateName == "typing" && (holding || clock - lastTap < Self.keyHold) ? 1.0 : 0.0
        keyDriven += (wanted - keyDriven) * (1 - exp(-14 * dt))
        guard keyDriven > 0.001 else { return }
        let w = Float(keyDriven)
        for i in arms.indices {
            let arm = arms[i]
            let t = clock - arm.tapStart
            var press = 0.0
            if t >= 0 {
                let liftStart = max(arm.released, arm.tapStart + Self.tapDown)
                if clock < arm.tapStart + Self.tapDown { press = smooth(0, 1, t / Self.tapDown) }
                else if clock < liftStart { press = 1 }
                else { press = 1 - smooth(0, 1, (clock - liftStart) / Self.tapUp) }
            }
            if !typingPoses.isEmpty { press *= arm.depth }
            arms[i].press = press
            let p = Float(press)
            let keyPos: SIMD3<Float>
            let keyRot: simd_quatf
            if i < typingPoses.count {
                let (hover, down) = typingPoses[i]
                keyPos = hover.0 + (down.0 - hover.0) * p
                keyRot = simd_slerp(hover.1, down.1, p)
            } else {
                let y = Self.hoverY + (Self.pressY - Self.hoverY) * p
                let tilt = (Self.hoverTilt + (Self.pressTilt - Self.hoverTilt) * p) * .pi / 180
                keyPos = SIMD3<Float>(arm.side * Self.armX, y, Self.armZ)
                keyRot = simd_quatf(angle: tilt, axis: [1, 0, 0])
            }
            let n = arm.node
            n.simdPosition = n.simdPosition + (keyPos - n.simdPosition) * w
            n.simdOrientation = simd_slerp(n.simdOrientation, keyRot, w)
        }
    }

    func animate(_ dt: Double) {
        clock += dt
        bobPhase += dt * 3
        own += ((actions[stateName] != nil ? 1 : 0) - own) * (1 - exp(-8 * dt))
        resetGazeTargets()
        updateClips(dt)
        autoType()
        applyKeyTaps(dt)
        if let turn { turn.node.simdOrientation = turn.node.simdOrientation * simd_quatf(angle: gazeYaw, axis: [0, 1, 0]) }
        reactToKeys(dt)
        if screenFace { act(dt) }
        placeSideProps()
        pourTears()
        updateEyes()
    }

    private func placeSideProps() {
        if abs(facing) > 0.12 { facingSide = Float(sgn(facing)) }
        for group in sideProps {
            let thought = group.anchor.name?.lowercased() == "prop_thinking_bubble"
            let inset: Float = thought && screenFace ? 0.45 : 0
            let lowerBy: Float = thought && screenFace ? 0.55 : 0
            let offset = facingSide * max(0, abs(group.anchor.simdPosition.x) - inset) - group.anchor.simdPosition.x
            for node in group.nodes {
                node.simdPosition.x += offset
                node.simdPosition.y -= lowerBy
            }
            if thought { group.anchor.simdScale.x *= facingSide }
        }
    }

    func sidePropBounds(cameraDistance: Double) -> [CGRect] {
        var bounds: [CGRect] = []
        for group in sideProps {
            var minX = Double.infinity, maxX = -Double.infinity
            var minY = Double.infinity, maxY = -Double.infinity
            func visit(_ node: SCNNode) {
                if node.isHidden { return }
                if let geometry = node.geometry {
                    let (a, b) = geometry.boundingBox
                    let transform = node.simdWorldTransform
                    for i in 0..<8 {
                        let point = transform * SIMD4<Float>(Float(i & 1 == 0 ? a.x : b.x), Float(i & 2 == 0 ? a.y : b.y), Float(i & 4 == 0 ? a.z : b.z), 1)
                        let projection = cameraDistance / max(0.001, cameraDistance - Double(point.z))
                        minX = min(minX, Double(point.x) * projection)
                        maxX = max(maxX, Double(point.x) * projection)
                        minY = min(minY, Double(point.y) * projection)
                        maxY = max(maxY, Double(point.y) * projection)
                    }
                }
                node.childNodes.forEach(visit)
            }
            group.nodes.forEach(visit)
            if minX.isFinite { bounds.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) }
        }
        return bounds
    }

    private func pourTears() {
        for t in tears where !t.stream.isHidden {
            guard let floorSpace = t.puddle?.parent ?? t.stream.parent else { continue }
            let floorY = (t.puddle?.simdPosition.y ?? 0) - Self.tearSink
            let eye = floorSpace.simdConvertPosition(.zero, from: t.stream)
            let tip = floorSpace.simdConvertPosition(t.tip, from: t.stream)
            let drop = eye.y - tip.y
            if drop > 0.05 {
                let k = min(max((eye.y - floorY) / drop, 0.6), 1.8)
                t.stream.simdScale.y *= k
            }
            let landed = floorSpace.simdConvertPosition(t.tip, from: t.stream)
            for pool in [t.puddle, t.ripple] {
                guard let pool else { continue }
                pool.simdPosition.x = landed.x
                pool.simdPosition.z = landed.z
            }
        }
    }

    private func act(_ dt: Double) {
        if stateName != actingState {
            actingState = stateName
            actingStart = clock
        }
        let t = clock - actingStart
        let head = headRig?.node

        if let permissionLock { permissionLock.simdPosition.x -= 0.8 * (actions["permission"]?.weight ?? 0) }

        let coffee = Double(actions["coffee"]?.weight ?? 0)
        if let mug {
            if stateName == "coffee" {
                let s = Float(max(0.0001, mugAmount))
                mug.simdScale *= s
                mug.isHidden = s < 0.02
            } else if coffee > 0 {
                mug.isHidden = true
            }
        }
        if coffee > 0.001, let i = mugArm, let base = mugBase {
            let arm = arms[i].node
            let q = arm.simdOrientation
            let w = Float(coffee)
            arm.simdOrientation = simd_slerp(q, simd_slerp(base, q, Self.mugReach), w)
            let sip = Float(clamp01(Double((base.inverse * q).angle) / 0.68)) * w
            head?.simdOrientation *= simd_quatf(angle: -Self.sipTilt * sip, axis: [1, 0, 0])
            if let body = bodyRig?.node { body.simdOrientation *= simd_quatf(angle: -Self.sipLean * sip, axis: [1, 0, 0]) }
        }

        cap?.isHidden = true

        let asleep = Double(actions["sleep"]?.weight ?? 0)
        let rising = stateName == "wake" ? Double(actions["wake"]?.weight ?? 0) * (1 - smooth(0.05, 0.7, t)) : 0
        let curl = Float(min(1, asleep + rising))
        if curl > 0.001 {
            for (i, arm) in arms.enumerated() where i < armRest.count {
                arm.node.simdOrientation = simd_slerp(arm.node.simdOrientation, armRest[i], curl)
            }
            for leg in legs { leg.node.simdOrientation = simd_slerp(leg.node.simdOrientation, leg.rot, curl) }
            if let bodyRig { bodyRig.node.simdOrientation = simd_slerp(bodyRig.node.simdOrientation, bodyRig.rot, curl) }
            head?.simdOrientation = simd_slerp(head?.simdOrientation ?? simd_quatf(), headRig?.rot ?? simd_quatf(), curl)
            let breath = Float(sin(clock * 2 * .pi * Self.breathHz)) * curl * Float(asleep)
            if let body = bodyRig?.node { body.simdScale.z *= 1 + Self.breathDepth * breath }
            head?.simdOrientation *= simd_quatf(angle: Self.breathNod * breath, axis: [1, 0, 0])
        }

        if let bed {
            let wanted = stateName == "sleep" || (stateName == "sleepy" && t > 4.3) || (stateName == "wake" && t < 0.35 && bedAmount > 0)
            bedAmount = wanted ? min(1, bedAmount + dt / Self.bedIn) : max(0, bedAmount - dt / Self.bedOut)
            bed.isHidden = bedAmount <= 0
            let grow = Float(wanted ? easeOutBack(bedAmount) : smooth(0, 1, bedAmount))
            bed.simdScale = (bedRest ?? bed.simdScale) * max(0.001, grow)
            if let rigHips {
                let n = rigHips.node
                n.simdPosition.y += grow * (Self.mattressTop - 0.1)
                let c = Double(curl)
                let tip = Float(smooth(0, 0.6, c)), roll = Float(smooth(0.4, 1, c))
                let lying = simd_quatf(angle: -Self.incline * roll, axis: [0, 0, 1])
                    * simd_quatf(angle: -.pi / 2 * roll, axis: [1, 0, 0]) * simd_quatf(angle: .pi / 2 * tip, axis: [0, 0, 1])
                n.simdOrientation = lying * simd_slerp(n.simdOrientation, rigHips.rot, curl)
                let target = Self.lyingHips * SIMD3(1, grow, 1)
                n.simdPosition += (target - n.simdPosition) * curl
                if grow > 0.9 {
                    let e = bedEllipsoids()
                    let need = max(Self.headRest - (e.head.0.y - e.head.1.y), Self.bodyRest - (e.body.0.y - e.body.1.y),
                                   Self.bodyRest - 0.08 - (e.legs.0.y - e.legs.1.y), 0)
                    n.simdPosition.y += need
                }
                let inv = n.simdOrientation.inverse
                for z in sleepZs {
                    let up = Self.zFrom + (z.simdPosition - Self.zStart)
                    z.simdPosition += (inv.act(up - n.simdPosition) - z.simdPosition) * curl
                    z.simdOrientation = simd_slerp(z.simdOrientation, inv * z.simdOrientation, curl)
                }
            }
            if let blanket {
                let tucked = stateName == "sleep" && t > Self.lieDownS * 0.8
                blanketAmount = tucked ? min(1, blanketAmount + dt / Self.blanketUp) : max(0, blanketAmount - dt / Self.blanketOff)
                blanket.isHidden = blanketAmount <= 0
            }
            shapeBedding(on: Float(smooth(0.85, 1, bedAmount)) * (bed.isHidden ? 0 : 1))
        }

        if stateName == "wake", let head, t > Self.shakeAt, t < Self.shakeAt + Self.shakeS {
            let k = (t - Self.shakeAt) / Self.shakeS
            let yaw = Self.shakeYaw * sin(k * .pi * 4) * (1 - k) * smooth(0, 0.12, k)
            head.simdOrientation *= simd_quatf(angle: Float(yaw), axis: [0, 1, 0])
        }
    }

    private func reactToKeys(_ dt: Double) {
        guard let bodyRig else { return }
        let hit = arms.map(\.press).max() ?? 0
        let side = arms.reduce(0.0) { $0 + Double($1.side) * $1.press }
        dip = damp(dip, hit, 30, dt)
        rock = damp(rock, side, 22, dt)
        nod = damp(nod, dip, 11, dt)
        tick = damp(tick, hit, 45, dt)
        guard keyDriven > 0.001 else { return }
        let w = Float(keyDriven)
        let body = bodyRig.node
        body.simdPosition.y -= Self.tapDip * Float(dip) * w
        body.simdOrientation = body.simdOrientation * simd_quatf(angle: -Self.tapRoll * Float(rock) * w, axis: [0, 0, 1])
        if let head = headRig?.node {
            head.simdOrientation = head.simdOrientation * simd_quatf(angle: Self.nodPitch * Float(nod) * w, axis: [1, 0, 0])
        }
        if let cursor, let rest = cursorRest {
            cursor.simdPosition = rest + SIMD3(Self.cursorKick * Float(tick) * w, 0, 0)
        }
    }

    private func bedEllipsoids() -> (head: (SIMD3<Float>, SIMD3<Float>), body: (SIMD3<Float>, SIMD3<Float>), legs: (SIMD3<Float>, SIMD3<Float>)) {
        let root = bedRoot
        func ellipsoid(_ node: SCNNode?, _ c: SIMD3<Float>, _ r: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
            guard let node, let root else { return (SIMD3(0, 50, 0), SIMD3(repeating: 0.01)) }
            let m = root.simdConvertTransform(matrix_identity_float4x4, from: node)
            let cc = m * SIMD4(c, 1)
            let cols = [m.columns.0, m.columns.1, m.columns.2]
            var half = SIMD3<Float>()
            for i in 0..<3 {
                var sum: Float = 0
                for j in 0..<3 { let v = cols[j][i] * r[j]; sum += v * v }
                half[i] = sqrt(sum)
            }
            return (SIMD3(cc.x, cc.y, cc.z), half)
        }
        let head = ellipsoid(headRig?.node, SIMD3(0, 1.27, -0.02), SIMD3(1.45, 1.22, 0.86))
        let body = ellipsoid(bodyRig?.node, SIMD3(0, 0.24, 0.02), SIMD3(1.18, 0.64, 0.5))
        let legs = ellipsoid(bodyRig?.node.parent, SIMD3(0, -0.3, 0), SIMD3(0.62, 0.32, 0.32))
        return (head, body, legs)
    }

    private func shapeBedding(on: Float) {
        guard bedRoot != nil, !dentMaterials.isEmpty || !blanketMaterials.isEmpty else { return }
        let (head, body, legs) = bedEllipsoids()
        let reveal = Float(easeOutCubic(blanketAmount))
        func v(_ p: SIMD3<Float>) -> NSValue { NSValue(scnVector3: SCNVector3(p)) }
        for m in dentMaterials + blanketMaterials {
            m.setValue(v(head.0), forKey: "hC"); m.setValue(v(head.1), forKey: "hR")
            m.setValue(v(body.0), forKey: "bC"); m.setValue(v(body.1), forKey: "bR")
            m.setValue(v(legs.0), forKey: "lC"); m.setValue(v(legs.1), forKey: "lR")
            m.setValue(NSNumber(value: on), forKey: "on")
            m.setValue(NSNumber(value: reveal), forKey: "reveal")
        }
    }

    private static let dentShader = """
    float3 bedPress(float3 p, float3 c, float3 r, thread float &depth, thread float &rim) {
        float2 q = (p.xz - c.xz) / r.xz;
        float s = 1.0 - dot(q, q);
        float bottom = c.y - r.y * sqrt(max(s, 0.0));
        float d = s > 0.0 ? max(0.0, p.y - bottom) : 0.0;
        float u = sqrt(dot(q, q));
        rim = max(rim, smoothstep(0.95, 1.12, u) * (1.0 - smoothstep(1.12, 1.6, u)) * step(c.y - r.y, p.y + 0.6));
        if (d > depth) { depth = d; return c; }
        return float3(0.0);
    }
    #pragma arguments
    float3 offs;
    float3 hC;
    float3 hR;
    float3 bC;
    float3 bR;
    float3 lC;
    float3 lR;
    float on;
    float floorY;
    float puff;
    float reveal;
    #pragma body
    float3 p = _geometry.position.xyz + offs;
    float depth = 0.0; float rim = 0.0;
    float3 c = float3(0.0);
    float3 k;
    k = bedPress(p, hC, hR, depth, rim); if (depth > 0.0 && k.y != 0.0) c = k;
    float before = depth;
    k = bedPress(p, bC, bR, depth, rim); if (depth > before) c = k;
    before = depth;
    k = bedPress(p, lC, lR, depth, rim); if (depth > before) c = k;
    float up = clamp(_geometry.normal.y, 0.0, 1.0);
    float dy = -min(depth, max(0.0, p.y - floorY)) * on + puff * rim * up * on * step(depth, 0.0001);
    _geometry.position.y += dy;
    if (depth > 0.0 && on > 0.0) {
        float3 inward = normalize(c - float3(p.x, p.y + dy, p.z));
        _geometry.normal = normalize(mix(_geometry.normal, inward, 0.75 * on * up));
    }
    """

    private static let blanketShader = """
    float bedTent(float2 xz, float3 c, float3 r, float spread, float base) {
        float u = length((xz - c.xz) / r.xz);
        if (u < 1.0) return c.y + r.y * sqrt(1.0 - u * u);
        float f = 1.0 - smoothstep(1.0, 1.0 + spread, u);
        return mix(base, c.y, f * f);
    }
    float bedBase(float z) {
        float a = abs(z);
        float top = 0.65;
        if (a <= 1.75) return top;
        float t = min(1.0, (a - 1.75) / 0.3);
        return top - (top - 0.34) * (1.0 - (1.0 - t) * (1.0 - t));
    }
    float bedHeight(float2 xz, float3 hC, float3 hR, float3 bC, float3 bR, float3 lC, float3 lR) {
        float base = bedBase(xz.y);
        float t = max(bedTent(xz, bC, bR, 0.9, base), bedTent(xz, lC, lR, 0.9, base));
        float h = t + 0.07;
        float k = 0.12;
        float m = clamp(0.5 + 0.5 * (h - base) / k, 0.0, 1.0);
        float y = mix(base, h, m) + k * m * (1.0 - m);
        return y + 0.022 * sin(xz.x * 6.0 + xz.y * 1.7);
    }
    #pragma arguments
    float3 offs;
    float3 hC;
    float3 hR;
    float3 bC;
    float3 bR;
    float3 lC;
    float3 lR;
    float on;
    float floorY;
    float puff;
    float reveal;
    #pragma body
    float3 p = _geometry.position.xyz + offs;
    float x = min(p.x + (1.0 - reveal) * 1.41, 1.55);
    float2 xz = float2(x, p.z);
    float e = 0.03;
    float h = bedHeight(xz, hC, hR, bC, bR, lC, lR);
    float hx = bedHeight(xz + float2(e, 0.0), hC, hR, bC, bR, lC, lR) - bedHeight(xz - float2(e, 0.0), hC, hR, bC, bR, lC, lR);
    float hz = bedHeight(xz + float2(0.0, e), hC, hR, bC, bR, lC, lR) - bedHeight(xz - float2(0.0, e), hC, hR, bC, bR, lC, lR);
    float3 n = normalize(float3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
    float3 q = float3(x, h + (p.y - 0.62), p.z);
    _geometry.position.xyz = q - offs;
    float ny = _geometry.normal.y;
    if (ny > 0.4) _geometry.normal = n;
    else if (ny < -0.4) _geometry.normal = -n;
    """

    var edgeHalfWidth: Double {
        guard let bed, !bed.isHidden, let box = bedBox else { return halfWidth }
        return max(halfWidth, max(abs(box.minX), abs(box.maxX)))
    }

    var edgeHalfDepth: Double {
        guard let bed, !bed.isHidden else { return halfDepth }
        return max(halfDepth, bedHalfDepth)
    }

    var hitBox: (minX: Double, maxX: Double, top: Double) {
        var box = (minX: -halfWidth, maxX: halfWidth, top: height)
        if let bed, !bed.isHidden, bedAmount > 0.3, let b = bedBox {
            box = (min(box.minX, b.minX), max(box.maxX, b.maxX), max(box.top, b.top))
        }
        return box
    }

    /// World-space bounds of the laptop prop while it's out, used to launch typed keycaps.
    func laptopBounds() -> (lo: Vec3, hi: Vec3)? {
        guard let screen, !screen.prop.isHidden else { return nil }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        screen.prop.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, !node.isHidden else { return }
            let (a, b) = geometry.boundingBox
            let m = node.simdWorldTransform
            for i in 0..<8 {
                let w = m * SIMD4(Float(i & 1 == 0 ? a.x : b.x), Float(i & 2 == 0 ? a.y : b.y), Float(i & 4 == 0 ? a.z : b.z), 1)
                lo = simd_min(lo, SIMD3(w.x, w.y, w.z))
                hi = simd_max(hi, SIMD3(w.x, w.y, w.z))
            }
        }
        guard lo.x <= hi.x, hi.y - lo.y > 1e-4 else { return nil }
        return (lo.d, hi.d)
    }

    func letterOrigin() -> Vec3? {
        guard let screen, !screen.prop.isHidden else { return nil }
        let (a, b) = (screen.min, screen.max)
        let m = screen.mesh.simdWorldTransform
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for i in 0..<8 {
            let p = SIMD3<Float>(Float(i & 1 == 0 ? a.x : b.x), Float(i & 2 == 0 ? a.y : b.y), Float(i & 4 == 0 ? a.z : b.z))
            let w = m * SIMD4(p, 1)
            lo = simd_min(lo, SIMD3(w.x, w.y, w.z))
            hi = simd_max(hi, SIMD3(w.x, w.y, w.z))
        }
        return Vec3(Double(lo.x + hi.x) / 2, Double(hi.y), Double(lo.z + hi.z) / 2)
    }
}
