import AppKit
import SceneKit

final class TypedLetters {
    private static let rim = CGColor(srgbRed: 201 / 255, green: 96 / 255, blue: 58 / 255, alpha: 1)
    private static let fill = CGColor(srgbRed: 1, green: 250 / 255, blue: 245 / 255, alpha: 1)
    private static let dropShadow = CGColor(srgbRed: 70 / 255, green: 25 / 255, blue: 10 / 255, alpha: 0.45)
    private static let tracking = 0.045
    private static let em = 0.6875
    private static let boxH = 1.35
    private static let size = 0.24
    private static let clipFeather = 0.12
    private static let clipShader = """
    #pragma arguments
    float clipMin;
    float clipMax;
    float clipFeather;
    #pragma body
    float clipS = _surface.position.x / max(-_surface.position.z, 0.0001);
    float clipA = smoothstep(clipMin, clipMin + clipFeather, clipS) * (1.0 - smoothstep(clipMax - clipFeather, clipMax, clipS));
    _output.color *= clipA;
    """
    private static let pauseS = 1.5
    private static let sendS = 0.9
    private static let popS = 0.24
    private static let stagger = 0.045
    private static let pixelsPerUnit = 100.0

    final class GlyphImage {
        let image: CGImage
        let w: Double
        let h: Double
        let advance: Double
        init(image: CGImage, w: Double, h: Double, advance: Double) {
            self.image = image
            self.w = w
            self.h = h
            self.advance = advance
        }
    }

    private struct Letter {
        let ch: String?
        let node: SCNNode?
        let glyph: GlyphImage?
        let lead: Double
        let advance: Double
        let born: Double
    }

    private struct Sent {
        let nodes: [SCNNode]
        let base: [SIMD3<Float>]
        var t: Double
    }

    private let group = SCNNode()
    private var glyphs: [String: GlyphImage] = [:]
    private var line: [Letter] = []
    private var sent: [Sent] = []
    private var removed: [(node: SCNNode, glyph: GlyphImage, t: Double)] = []
    private var lastKey = -Double.infinity
    private var lastBirth = -Double.infinity
    private var warmQueue: [String] = []
    private var time = 0.0
    private var scroll = 0.0
    private var origin = Vec3(0, 0, 0)
    private var scale = 1.0
    private var res = 0
    private var font = GlyphArt.roundedFont(size: 12, weight: .bold)
    var backingScale: Double = 2

    struct Palette {
        var rim: CGColor
        var fill: CGColor
        var shadow: CGColor
        static let clawd = Palette(rim: TypedLetters.rim, fill: TypedLetters.fill, shadow: TypedLetters.dropShadow)
        static let codex = Palette(rim: CGColor(srgbRed: 64 / 255, green: 98 / 255, blue: 224 / 255, alpha: 1),
                                   fill: CGColor(srgbRed: 236 / 255, green: 252 / 255, blue: 1, alpha: 1),
                                   shadow: CGColor(srgbRed: 14 / 255, green: 20 / 255, blue: 60 / 255, alpha: 0.45))
    }

    var palette = Palette.clawd {
        didSet {
            glyphs.removeAll()
            warmQueue = (32...126).compactMap { Unicode.Scalar($0).map { String(Character($0)) } }.filter { $0 != " " }
        }
    }

    init(scene: SCNScene) {
        scene.rootNode.addChildNode(group)
    }

    private func setResolution(_ scale: Double) {
        let r = max(24, Int((Self.size * scale * Self.pixelsPerUnit * backingScale).rounded()))
        if abs(r - res) <= 1 { return }
        res = r
        font = GlyphArt.roundedFont(size: (CGFloat(r) * CGFloat(Self.em)).rounded(), weight: .bold)
        glyphs.removeAll()
        warmQueue = (32...126).compactMap { Unicode.Scalar($0).map { String(Character($0)) } }.filter { $0 != " " }
    }

    private func glyph(_ ch: String) -> GlyphImage {
        if let g = glyphs[ch] { return g }
        let r = CGFloat(res)
        let px = font.pointSize
        let pad = (r * 0.28).rounded(.up)
        let face = GlyphArt.line(ch, font: font, fill: palette.fill)
        let edge = GlyphArt.line(ch, font: font, fill: palette.rim, stroke: (palette.rim, -8))
        let advance = GlyphArt.advance(face)
        let ink = CTLineGetBoundsWithOptions(face, .useGlyphPathBounds)
        let inkW = max(advance, ink.width)
        let width = Int((inkW + pad * 2).rounded(.up))
        let height = Int((r * CGFloat(Self.boxH)).rounded(.up))
        let ctx = GlyphArt.context(width: width, height: height)
        let at = CGPoint(x: CGFloat(width) / 2 - advance / 2, y: GlyphArt.baseline(font: font, centerY: CGFloat(height) / 2 - px * 0.05))
        func draw(_ line: CTLine) {
            ctx.textPosition = at
            CTLineDraw(line, ctx)
        }
        ctx.setShadow(offset: CGSize(width: 0, height: -px * 0.05), blur: px * 0.1, color: palette.shadow)
        draw(edge)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        draw(edge)
        draw(face)
        let g = GlyphImage(image: ctx.makeImage()!, w: Double(width) / Double(res), h: Double(height) / Double(res),
                           advance: Double(advance) / Double(res) + Self.tracking)
        glyphs[ch] = g
        return g
    }

    private func width(_ text: String) -> Double {
        Double(GlyphArt.advance(GlyphArt.line(text, font: font))) / Double(res)
    }

    private func kern(_ a: String?, _ b: String) -> Double {
        guard let a else { return 0 }
        return width(a + b) - width(a) - width(b)
    }

    private func node(_ g: GlyphImage) -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = g.image
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.diffuse.mipFilter = .none
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        m.blendMode = .alpha
        m.shaderModifiers = [.fragment: Self.clipShader]
        applyClip(m)
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.castsShadow = false
        n.renderingOrder = 10
        size(n, g, 0.0001)
        group.addChildNode(n)
        return n
    }

    private var clip: (min: Float, max: Float, feather: Float) = (-10, 10, 0.01)
    var cameraDistance = 10.0

    private func applyClip(_ m: SCNMaterial) {
        m.setValue(NSNumber(value: clip.min), forKey: "clipMin")
        m.setValue(NSNumber(value: clip.max), forKey: "clipMax")
        m.setValue(NSNumber(value: clip.feather), forKey: "clipFeather")
    }

    private func applyClip(_ n: SCNNode) {
        if let m = n.geometry?.firstMaterial { applyClip(m) }
    }

    private func size(_ n: SCNNode, _ g: GlyphImage, _ s: Double) {
        n.simdScale = SIMD3(Float(s * g.w), Float(s * g.h), 1)
    }

    func input(_ ch: String) {
        lastKey = time
        if ch == "\r" || ch == "\n" { return send() }
        if ch == "\u{7f}" || ch == "\u{8}" {
            if let last = line.popLast(), let n = last.node, let g = last.glyph { removed.append((n, g, 0)) }
            return
        }
        setResolution(scale)
        if ch == " " || ch == "\t" {
            line.append(Letter(ch: nil, node: nil, glyph: nil, lead: 0, advance: width(" ") * 1.15 + Self.tracking, born: nextBirth()))
            return
        }
        if isControl(ch) { return }
        let g = glyph(ch)
        line.append(Letter(ch: ch, node: node(g), glyph: g, lead: kern(line.last?.ch, ch), advance: g.advance, born: nextBirth()))
    }

    private func nextBirth() -> Double {
        let born = max(time, lastBirth + Self.stagger)
        lastBirth = born
        return born
    }

    private func isControl(_ ch: String) -> Bool {
        guard let u = ch.unicodeScalars.first else { return true }
        return u.value < 0x20 || (0xF700...0xF8FF).contains(u.value)
    }

    private func send() {
        let nodes = line.compactMap { $0.node }
        if !nodes.isEmpty { sent.append(Sent(nodes: nodes, base: nodes.map { $0.simdPosition }, t: 0)) }
        line = []
        scroll = 0
    }

    func update(_ dt: Double, origin: Vec3, scale: Double, lineY: Double, clipCenter: Double, clipHalf: Double, clipDepth: Double) {
        time += dt
        self.origin = origin
        self.scale = scale
        setResolution(scale)
        for _ in 0..<3 {
            guard let ch = warmQueue.popLast() else { break }
            _ = glyph(ch)
        }
        if !line.isEmpty && time - lastKey > Self.pauseS { send() }

        let unit = Self.size * scale
        let letterZ = origin.z + 0.1 * scale
        let toFront = max(cameraDistance - clipDepth, 0.001)
        let toLetter = max(cameraDistance - letterZ, 0.001)
        let toLetters = toLetter / toFront
        clip = (Float((clipCenter - clipHalf) / toFront), Float((clipCenter + clipHalf) / toFront), Float(Self.clipFeather * unit / toLetter))
        let lineCenter = clipCenter * toLetters
        let width = line.reduce(0) { $0 + $1.lead + $1.advance }
        let maxW = max(unit, 2 * clipHalf * toLetters - 2 * Self.clipFeather * unit - 0.1 * unit)
        let targetScroll = max(0, width * unit - maxW)
        scroll = damp(scroll, targetScroll, 22, dt)
        let left = -min(width * unit, maxW) / 2 - scroll
        var cursor = 0.0
        for l in line {
            cursor += l.lead
            let slot = left + (cursor + l.advance / 2) * unit
            cursor += l.advance
            guard let n = l.node, let g = l.glyph else { continue }
            let k = clamp((time - l.born) / Self.popS, 0, 1)
            let fly = easeOutCubic(k)
            n.simdPosition = SIMD3(Float(lerp(origin.x, lineCenter + slot, fly)), Float(lerp(origin.y, lineY, fly)), Float(letterZ))
            size(n, g, unit * easeOutBack(k))
            applyClip(n)
        }

        var i = sent.count - 1
        while i >= 0 {
            sent[i].t += dt
            let s = sent[i]
            let k = s.t / Self.sendS
            if k >= 1 {
                s.nodes.forEach { $0.removeFromParentNode() }
                sent.remove(at: i)
                i -= 1
                continue
            }
            for (j, n) in s.nodes.enumerated() {
                n.simdPosition = SIMD3(s.base[j].x, s.base[j].y + Float(0.5 * scale * easeOutCubic(k)), s.base[j].z)
                n.opacity = CGFloat(1 - k)
                applyClip(n)
            }
            i -= 1
        }

        i = removed.count - 1
        while i >= 0 {
            removed[i].t += dt
            let r = removed[i]
            let k = r.t / 0.2
            if k >= 1 {
                r.node.removeFromParentNode()
                removed.remove(at: i)
                i -= 1
                continue
            }
            size(r.node, r.glyph, unit * (1 - k))
            applyClip(r.node)
            r.node.opacity = CGFloat(1 - k)
            i -= 1
        }
    }
}
