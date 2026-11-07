import Foundation
import SceneKit
import simd

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

let project = URL(fileURLWithPath: CommandLine.arguments[1])
func load(_ name: String) throws -> GLTFAsset {
    try GLTFAsset(data: Data(contentsOf: project.appendingPathComponent("LilAgent/Resources/\(name).glb")))
}

                                                                                
                                                                           
let stage = Stage()
let lightRig = stage.scene.rootNode.childNodes.first { node in
    node.childNodes.contains { $0.light?.type == .directional }
}!
let lights = lightRig.childNodes.filter { $0.light?.type == .directional }
let shadowFloor = stage.scene.rootNode.childNodes.first { $0.geometry?.firstMaterial?.lightingModel == .shadowOnly }!
let referenceRig = SCNNode()
let referenceLights = lights.map { light -> SCNNode in
    let reference = SCNNode()
    reference.simdPosition = light.simdPosition
    referenceRig.addChildNode(reference)
    return reference
}
require(lights.count == 4, "Missing directional lights")
for (x, floorY, scale, width, height) in [
    (0.0, 0.0, 1.0, 800.0, 400.0), (3.25, -1.5, 1.0, 1440.0, 900.0),
    (-6.0, -2.75, 0.64, 1440.0, 400.0), (4.0, 0.5, 0.64, 1920.0, 1080.0),
    (2.0, -4.1, 1.68, 1920.0, 1080.0), (-3.0, -2.0, 1.68, 800.0, 600.0),
    (0.0, -3.0, 1.0, 1280.0, 720.0), (7.0, -5.0, 3.2, 2560.0, 1440.0),
] {
    stage.resize(width: width, height: height)
    stage.setFocus(x: x, floorY: floorY, scale: scale)
    referenceRig.simdPosition = SIMD3(Float(x), Float(floorY), 0)
    let focus = SIMD3<Float>(0, Float(1.2 * scale), 0)
    for (light, reference) in zip(lights, referenceLights) {
        let direction = simd_normalize(focus - reference.simdPosition)
        reference.simdOrientation = simd_quatf(from: [0, 0, -1], to: direction)
        require(light.simdOrientation.vector == reference.simdOrientation.vector, "Light orientation changed after focus update")
        for column in 0..<4 {
            require(light.simdTransform[column] == reference.simdTransform[column], "Local light transform changed")
            require(light.simdWorldTransform[column] == reference.simdWorldTransform[column], "World light transform changed")
        }
    }
    require(shadowFloor.simdPosition == SIMD3(0, Float(floorY), 0), "Shadow floor no longer follows focus")
    require(lights.first { $0.light!.castsShadow }!.light!.orthographicScale == 2.2 * scale, "Shadow projection scale changed")
    let cameraZ = Float(height / (2 * Stage.pixelsPerUnit) / tan(Stage.cameraFOV / 2 * .pi / 180))
    require(stage.width == width && stage.height == height && stage.cameraNode.simdPosition == SIMD3(0, 0, cameraZ), "Camera placement changed after resize")
}
print("PASS: lighting orientations, local/world transforms, floor placement, shadow projection, and camera placement exactly match the original across focus changes and resizes")

for name in ["codex", "clawd"] {
    let asset = try load(name)
    let mob = Mascot(asset: asset)
    mob.stateName = "drop"
    let clip = asset.clips.first { $0.name == "drop" }!
    let tracks = clip.tracks.filter { track in
        let node = asset.nodes[track.node]
        return ["body", "hips", "arm_L", "arm_R"].contains(node.name ?? "")
    }
    for frame in 0..<240 {
        mob.animate(1.0 / 60)
        if frame < 40 { continue }
        for track in tracks {
            let expected = track.sample(at: clip.duration)
            let node = asset.nodes[track.node]
            switch track.path {
            case .translation:
                require(simd_length(node.simdPosition - SIMD3(expected.x, expected.y, expected.z)) < 0.0001, "\(name): drop position restarted")
            case .scale:
                require(simd_length(node.simdScale - SIMD3(expected.x, expected.y, expected.z)) < 0.0001, "\(name): drop squash restarted")
            case .rotation:
                require(abs(simd_dot(node.simdOrientation.vector, simd_normalize(expected))) > 0.9999, "\(name): drop rotation restarted")
            }
        }
    }
    print("PASS: \(name) drop finishes once and holds its final pose")
}

let pet = Pet(mob: Mascot(asset: try load("codex")), scene: SCNScene(), settings: PetSettings())
pet.placement = Placement(scale: 1, floorY: -10, minX: -100, maxX: 100, halfWidth: 100, halfHeight: 10, maxLift: 18)
let params = Params(vx: 8, vy: 3)
let daze = 0.2 + 0.3 * min(1, hypot(8, 3) / 10)
var spins: [SIMD2<Double>] = []
for offset in [-0.000001, 0.000001] {
    pet.lift = 8
    pet.target.reset()
    pet.overlay.reset()
    let state = DropState()
    state.enter(pet, params)
    _ = state.update(pet, 0, daze + offset, params)
    spins.append(SIMD2(pet.overlay[.torsoRoll], pet.overlay[.torsoPitch]))
}
require(simd_length(spins[0] - spins[1]) < 0.0001, "Throw wobble snaps at recovery")

let landing = DropState()
pet.lift = 0
landing.enter(pet, Params(vx: 8, vy: -8))
_ = landing.update(pet, 0, 0, Params())
for time in [0.5 - 0.000001, 0.5 + 0.000001, 1.4 - 0.000001, 1.4] {
    pet.target.reset()
    pet.overlay.reset()
    _ = landing.update(pet, 0, time, Params())
    require(abs(pet.overlay[.headRoll]) < 0.0001, "Landing head shake snaps at \(time)")
}
print("PASS: throw recovery and landing head shake are continuous")

let node = SCNNode()
let held = SIMD4<Float>(0, sin(0.3), 0, cos(0.3))
let track = GLTFTrack(node: 0, path: .rotation, times: [0, 1], values: Array(repeating: [held.x, held.y, held.z, held.w], count: 2).flatMap { $0 }, step: true)
let action = ClipAction(GLTFClip(name: "held", tracks: [track], duration: 1))
let mixer = Mixer(nodes: [node], actions: [action])
action.weight = 1
action.play()
for _ in 0..<120 {
    node.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    mixer.update(1.0 / 60)
    require(abs(simd_dot(node.simdOrientation.vector, held)) > 0.9999, "Held pose was lost after procedural reset")
}
print("PASS: native mixer restores held poses every frame")

require(Set(StatusText.phrases.keys) == Set(STATES.keys), "Missing status phrase")
require(StatusText.phrases["done"] == StatusText.phrases["donehold"], "Completion text changes during hold")
for halfWidth in [1.6, 4, 7.2, 19.2] {
    for extent in [0.2, 0.6, 1.2] {
        for x in [0, -halfWidth + extent + 0.08, halfWidth - extent - 0.08] {
            for side in [-1.0, 1.0] {
                for y in [-20.0, 0, 20] {
                    let result = StatusText.layout(x: x, y: y, extent: extent, width: 2.6, height: 0.9, halfWidth: halfWidth, halfHeight: 2, side: side)
                    if result.scale <= 0 { continue }
                    let w = 2.6 * result.scale, h = 0.9 * result.scale
                    require(result.x - w / 2 >= -halfWidth + 0.08 - 1e-8 && result.x + w / 2 <= halfWidth - 0.08 + 1e-8, "Status text crosses horizontal screen edge")
                    require(result.y - h / 2 >= -2 + 0.08 - 1e-8 && result.y + h / 2 <= 2 - 0.08 + 1e-8, "Status text crosses vertical screen edge")
                    require(abs(result.x - x) - w / 2 >= extent + 0.12 - 1e-8, "Status text overlaps mascot")
                    if x == 0 { require(result.side == side, "Status text ignores facing") }
                }
            }
        }
    }
}
let scene = SCNScene()
let captionPet = Pet(mob: Mascot(asset: try load("codex")), scene: scene, settings: PetSettings())
captionPet.placement = Placement(scale: 1.68, floorY: -2, minX: -6, maxX: 6, halfWidth: 7.2, halfHeight: 3, maxLift: 4)
let caption = scene.rootNode.childNode(withName: "statusText", recursively: false)!
captionPet.trigger("dance", Params(loop: true), force: true)
captionPet.loco.facing = 0.4
captionPet.statusText.update(0.2, pet: captionPet)
require(!caption.isHidden && caption.simdPosition.x > 0, "Caption not visible on facing side")
let texture = caption.geometry!.firstMaterial!.diffuse.contents as! CGImage
for _ in 0..<600 { captionPet.statusText.update(1.0 / 60, pet: captionPet) }
require(!caption.isHidden && caption.opacity == 1, "Caption vanished before state ended")
require((caption.geometry!.firstMaterial!.diffuse.contents as! CGImage) === texture, "Unchanged text redrawn each frame")
captionPet.loco.facing = -0.4
captionPet.statusText.update(0.1, pet: captionPet)
require(caption.simdPosition.x < 0, "Caption did not follow facing")
captionPet.settings.showStatusText = false
captionPet.statusText.update(0.1, pet: captionPet)
require(caption.isHidden, "Disabled caption remains visible")
captionPet.trigger("dizzy", force: true)
captionPet.settings.showStatusText = true
captionPet.statusText.update(0.2, pet: captionPet)
require(!caption.isHidden && (caption.geometry!.firstMaterial!.diffuse.contents as! CGImage) !== texture, "Caption did not refresh for new state")
let oldSettings = try JSONDecoder().decode(PetSettings.self, from: Data("{}".utf8))
require(oldSettings.showStatusText, "Status text missing from old settings defaults")
var disabledText = oldSettings
disabledText.showStatusText = false
let decodedText = try JSONDecoder().decode(PetSettings.self, from: JSONEncoder().encode(disabledText))
require(!decodedText.showStatusText, "Status text toggle not persisted")
print("PASS: status text coverage, screen edges, facing, lifetime, texture reuse, toggle, and persistence")
if let preview = ProcessInfo.processInfo.environment["LILAGENT_TEXT_PREVIEW"] {
    let image = NSBitmapImageRep(cgImage: caption.geometry!.firstMaterial!.diffuse.contents as! CGImage)
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}

let sideAnchors = [
    ("command", "prop_command_window"), ("error", "prop_error_alert"),
    ("permission", "prop_permission_lock"), ("planning", "prop_planning_list"),
    ("question", "prop_question_bubble"), ("thinking", "prop_thinking_bubble"),
    ("searching", "prop_searching_glass"),
]
for character in ["codex", "clawd"] {
    let mob = Mascot(asset: try load(character))
    let reference = Mascot(asset: try load(character))
    for (state, anchorName) in sideAnchors {
        mob.stateName = state
        reference.stateName = state
        let anchor = mob.root.childNode(withName: anchorName, recursively: true)!
        let original = reference.root.childNode(withName: anchorName, recursively: true)!
        for facing in [0.6, -0.6, -0.02, 0.6] {
            mob.facing = facing
            reference.facing = 0.6
            let side: Float = facing == -0.02 ? -1 : Float(sgn(facing))
            for _ in 0..<120 {
                mob.animate(1.0 / 60)
                reference.animate(1.0 / 60)
                require(mob.facingSide == side && anchor.simdPosition.x * side > 0, "\(character)/\(state): prop ignored facing")
                require(abs(abs(anchor.simdPosition.x) - abs(original.simdPosition.x)) < 0.0001, "\(character)/\(state): prop drifted")
                var expectedScale = original.simdScale
                if state == "thinking" { expectedScale.x *= side }
                require(simd_length(anchor.simdScale - expectedScale) < 0.0001, "\(character)/\(state): wrong artwork or tail direction")
                require(abs(simd_dot(anchor.simdOrientation.vector, original.simdOrientation.vector)) > 0.9999, "\(character)/\(state): prop artwork rotated")
            }
        }
    }
}
print("PASS: both characters' side props follow facing, hold through neutral, and keep artwork orientation without drift")

for character in ["codex", "clawd"] {
    let mob = Mascot(asset: try load(character))
    for state in ["permission", "error", "command", "question", "thinking", "planning", "searching"] {
        mob.stateName = state
        for _ in 0..<90 { mob.animate(1.0 / 60) }
        for scale in [0.64, 1.68, 3.2] {
            for side in [-1.0, 1.0] {
                mob.root.simdScale = SIMD3(repeating: Float(scale))
                mob.facing = side * 0.6
                mob.root.simdOrientation = quatY(mob.facing)
                mob.root.simdPosition = SIMD3(0, -4.1, 0)
                mob.animate(1.0 / 60)
                let obstacles = mob.sidePropBounds(cameraDistance: 18)
                require(!obstacles.isEmpty, "Missing visible prop bounds")
                let extent = StatusText.extent(x: 0, facing: mob.facing, scale: scale, halfWidth: mob.edgeHalfWidth, halfDepth: mob.edgeHalfDepth, cameraDistance: 18)
                let factor = ["permission", "error"].contains(state) ? 0.2 : state == "command" ? 0.4 : 0.5
                let width = 2.0, height = scale < 1 ? 0.5 : 0.85
                let base = StatusText.layout(x: 0, y: -4.1 + mob.height * scale * factor, extent: extent, width: width, height: height, halfWidth: 7.2, halfHeight: 4.5, side: side)
                let attachBelow = ["command", "permission", "error"].contains(state)
                let result = StatusText.avoidProps(base, width: width, height: height, halfWidth: 7.2, halfHeight: 4.5, obstacles: obstacles, attachBelow: attachBelow)
                require(result.scale > 0, "\(character)/\(state): caption disappeared")
                let w = width * result.scale, h = height * result.scale
                if attachBelow && result.scale == base.scale && result.x == base.x {
                    let below = obstacles.filter { result.x + w / 2 + 0.025 > $0.minX && result.x - w / 2 - 0.025 < $0.maxX }
                    if let propBottom = below.map({ Double($0.minY) }).min() {
                        require(abs(propBottom - (result.y + h / 2) - 0.025) < 0.0001, "\(character)/\(state): caption too far below prop")
                    }
                }
                let box = CGRect(x: result.x - w / 2, y: result.y - h / 2, width: w, height: h)
                require(abs(result.x) + w / 2 <= 7.12 + 1e-6 && abs(result.y) + h / 2 <= 4.42 + 1e-6, "Caption outside screen")
                for obstacle in obstacles { require(!box.intersects(obstacle), "\(character)/\(state)/\(scale): caption overlaps prop") }
            }
        }
    }
}
print("PASS: captions clear real side props for both characters, both directions, and three sizes")
