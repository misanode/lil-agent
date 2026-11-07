import AppKit
import SceneKit
import simd

final class Stage {
    static let cameraFOV = 28.0
    static let pixelsPerUnit = 100.0
    private static func intensity(_ three: Double) -> CGFloat { CGFloat(three / .pi * 1000) }
    private static let floorOpacity = 0.28

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let lightRig = SCNNode()
    private var lights: [(node: SCNNode, offset: SIMD3<Float>)] = []
    private var key: SCNLight!
    private let floor: SCNNode
    private var focusScale = -1.0
    private(set) var width = 1.0
    private(set) var height = 1.0

    init() {
        scene.background.contents = nil

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.cameraFOV)
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 200
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        if let env = Self.roomEnvironment() {
            scene.lightingEnvironment.contents = env
            scene.lightingEnvironment.intensity = 0.75 * CGFloat(Self.envScale)
        }

        let plane = SCNPlane(width: 60, height: 20)
        let m = SCNMaterial()
        m.lightingModel = .shadowOnly
        m.writesToDepthBuffer = false
        plane.materials = [m]
        floor = SCNNode(geometry: plane)
        floor.simdOrientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        floor.castsShadow = false
        floor.opacity = Self.floorOpacity
        floor.renderingOrder = -1
        scene.rootNode.addChildNode(floor)

        scene.rootNode.addChildNode(lightRig)
        key = addLight(color: NSColor.white, intensity: 2.6, at: [-3.5, 6, 6])
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowSampleCount = 32
        key.shadowRadius = 9
        key.shadowMode = .forward
        key.shadowColor = NSColor.black
        key.zNear = 1
        key.zFar = 20
        key.automaticallyAdjustsShadowProjection = false
        addLight(color: NSColor(srgbRed: 0xDF / 255, green: 0xE9 / 255, blue: 1, alpha: 1), intensity: 0.4, at: [5, 2, 4])
        let rim = NSColor(srgbRed: 0x9F / 255, green: 0xE8 / 255, blue: 1, alpha: 1)
        addLight(color: rim, intensity: 1.6, at: [-5, 3, -5])
        addLight(color: rim, intensity: 1.3, at: [5, 4, -5])
        setFocus(x: 0, floorY: 0, scale: 1)
    }

    @discardableResult
    private func addLight(color: NSColor, intensity: Double, at offset: SIMD3<Float>) -> SCNLight {
        let light = SCNLight()
        light.type = .directional
        light.color = color
        light.intensity = Self.intensity(intensity)
        let node = SCNNode()
        node.light = light
        node.simdPosition = offset
        lightRig.addChildNode(node)
        lights.append((node, offset))
        return light
    }

    private static let envScale: Float = 100

    private static func roomEnvironment() -> CGImage? {
        guard let url = Bundle.main.url(forResource: "room_env", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count == 256 * 128 * 16,
              let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        var flipped = Data(count: data.count)
        let row = 256 * 16
        flipped.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                let out = dst.bindMemory(to: Float.self)
                for y in 0..<128 {
                    for i in 0..<(256 * 4) {
                        let v = src.loadUnaligned(fromByteOffset: (127 - y) * row + i * 4, as: Float.self)
                        out[y * 256 * 4 + i] = i % 4 == 3 ? 1 : min(1, v / envScale)
                    }
                }
            }
        }
        guard let flippedProvider = CGDataProvider(data: flipped as CFData) else { return nil }
        _ = provider
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: 256, height: 128, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: row, space: space,
                       bitmapInfo: info, provider: flippedProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func setFocus(x: Double, floorY: Double, scale: Double) {
        let scaleChanged = scale != focusScale
        lightRig.simdPosition = SIMD3(Float(x), Float(floorY), 0)
        if scaleChanged {
            let focus = SIMD3<Float>(0, Float(1.2 * scale), 0)
            for l in lights {
                let dir = simd_normalize(focus - l.offset)
                l.node.simdOrientation = simd_quatf(from: [0, 0, -1], to: dir)
            }
        }
        floor.simdPosition = SIMD3(0, Float(floorY), 0)
        if scaleChanged {
            focusScale = scale
            key.orthographicScale = 2.2 * scale
        }
    }

    func setShadowStrength(_ k: Double) {
        floor.opacity = CGFloat(Self.floorOpacity * clamp01(k))
    }

    func resize(width: Double, height: Double) {
        guard width > 0, height > 0, width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        let halfHeight = height / (2 * Self.pixelsPerUnit)
        cameraNode.simdPosition = SIMD3(0, 0, Float(halfHeight / tan(Self.cameraFOV / 2 * .pi / 180)))
    }
}

final class ScreenSpace {
    static let petHeight = 1.25
    private static let edgeMarginPx = 8.0

    unowned let stage: Stage
    init(stage: Stage) { self.stage = stage }

    var pixelsPerUnit: Double { Stage.pixelsPerUnit }
    var halfHeight: Double { stage.height / (2 * pixelsPerUnit) }
    var halfWidth: Double { stage.width / (2 * pixelsPerUnit) }

    func heightAboveFloor(_ py: Double, floorY: Double) -> Double { toWorldY(py) - floorY }
    func scaleForPixels(_ px: Double) -> Double { px / (Self.petHeight * pixelsPerUnit) }
    func toWorldX(_ px: Double) -> Double { (px / stage.width - 0.5) * 2 * halfWidth }
    func toWorldY(_ py: Double) -> Double { (0.5 - py / stage.height) * 2 * halfHeight }

    func floorY(_ scale: Double, halfWidth: Double, halfDepth: Double, facing: Double) -> Double {
        let d = Double(stage.cameraNode.simdPosition.z)
        let near = (abs(sin(facing)) * halfWidth + abs(cos(facing)) * halfDepth) * scale
        return (-halfHeight + Self.edgeMarginPx / pixelsPerUnit) * ((d - near) / d)
    }

    func movementRange(_ scale: Double, halfWidth: Double, halfDepth: Double, facing: Double) -> (Double, Double) {
        let d = Double(stage.cameraNode.simdPosition.z)
        let edge = max(0, self.halfWidth - Self.edgeMarginPx / pixelsPerUnit)
        let c = cos(facing), s = sin(facing)
        var lo = -Double.infinity
        var hi = Double.infinity
        for x in [-halfWidth, halfWidth] {
            for z in [-halfDepth, halfDepth] {
                let dx = (x * c + z * s) * scale
                let dz = (z * c - x * s) * scale
                let limit = edge * (d - dz) / d
                lo = max(lo, -limit - dx)
                hi = min(hi, limit - dx)
            }
        }
        if lo > hi { lo = 0; hi = 0 }
        return (lo, hi)
    }
}
