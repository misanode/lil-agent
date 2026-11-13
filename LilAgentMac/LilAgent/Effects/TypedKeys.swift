import AppKit
import SceneKit

/// Type-along keycaps: every key you press pops a matching keycap out of the pet's laptop,
/// launched from a random spot on the lid in a random direction, then floats away and fades.
final class TypedKeys {
    /// Keycap edge length in pet-scale units, so caps grow and shrink with the pet size setting.
    private static let size = 0.24
    private static let popS = 0.3
    private static let holdS = 0.42
    private static let fadeS = 0.34
    private static let stagger = 0.05
    private static let maxAlive = 24
    /// Widest launch angle either side of straight up.
    private static let spread = 1.3
    private static let candidates = 5
    private static let textureSize = 192

    private static let names: [Character: String] = [
        "&": "ampersand", "*": "asterisk", "@": "at", "\\": "backslash", "`": "backtick", "}": "brace-close", "{": "brace-open",
        "]": "bracket-close", "[": "bracket-open", "^": "caret", ":": "colon", ",": "comma", "$": "dollar", "\"": "double-quote",
        "=": "equals", "!": "exclamation", ">": "greater-than", "#": "hash", "<": "less-than", "-": "minus", "(": "paren-open",
        ")": "paren-close", "%": "percent", ".": "period", "|": "pipe", "+": "plus", "?": "question", "'": "quote",
        ";": "semicolon", "/": "slash", "~": "tilde", "_": "underscore",
    ]

    private struct Cap {
        let node: SCNNode
        let born: Double
        /// Launch point across the laptop: u in -1...1 (left to right), v in 0...1 (bottom to top).
        let u: Double
        let v: Double
        let angle: Double
        let distance: Double
        let roll: (from: Double, to: Double)
        let tilt: SIMD2<Double>
        let wobble: Double
    }

    private let group = SCNNode()
    private var caps: [Cap] = []
    private var images: [String: CGImage] = [:]
    private var time = 0.0
    private var lastBirth = -Double.infinity
    var cameraDistance = 10.0

    /// Accent colour as #RRGGBB; changing it recolours keys typed from then on.
    var accentHex = KeyColors.defaultColor {
        didSet {
            guard accentHex != oldValue else { return }
            accent = KeyColors.rgb(accentHex) ?? KeyColors.rgb(KeyColors.defaultColor)!
            images.removeAll()
        }
    }
    private var accent = KeyColors.rgb(KeyColors.defaultColor)!

    init(scene: SCNScene) {
        scene.rootNode.addChildNode(group)
    }

    func input(_ ch: String) {
        guard let image = image(for: ch) else { return }
        if caps.count >= Self.maxAlive { caps.removeFirst().node.removeFromParentNode() }
        let born = max(time, lastBirth + Self.stagger)
        lastBirth = born

        // Best of a few random angles: whichever is furthest from the keys still in the air.
        var angle = 0.0, gap = -1.0
        for _ in 0..<Self.candidates {
            let a = rnd(-Self.spread, Self.spread)
            let g = caps.map { abs($0.angle - a) }.min() ?? .infinity
            if g > gap { (angle, gap) = (a, g) }
        }
        let u = clamp(sin(angle) / sin(Self.spread) * 0.7 + rnd(-0.15, 0.15), -0.9, 0.9)
        let roll0 = rnd(-0.9, 0.9)
        caps.append(Cap(node: node(image), born: born, u: u, v: rnd(0.55, 0.85), angle: angle, distance: rnd(0.8, 1.25),
                        roll: (roll0, -angle * 0.25 + rnd(-0.2, 0.2)), tilt: [rnd(-0.35, 0.35), rnd(-0.4, 0.4)],
                        wobble: rnd(0, 2 * .pi)))
    }

    /// - Parameters:
    ///   - laptop: world-space bounds of the laptop, or nil when it isn't out; caps then spring from `fallback`.
    ///   - bounds: half extents of the visible stage, used to keep caps on screen.
    func update(_ dt: Double, laptop: (lo: Vec3, hi: Vec3)?, fallback: Vec3, scale: Double, bounds: (x: Double, y: Double)) {
        time += dt
        let side = Self.size * scale
        let margin = side * 0.6
        let lo = laptop?.lo ?? Vec3(fallback.x - 0.25 * scale, fallback.y - 0.2 * scale, fallback.z)
        let hi = laptop?.hi ?? Vec3(fallback.x + 0.25 * scale, fallback.y, fallback.z)
        let center = (lo + hi) / 2
        let half = (hi - lo) / 2

        var i = caps.count - 1
        while i >= 0 {
            let c = caps[i]
            let age = time - c.born
            if age >= Self.popS + Self.holdS + Self.fadeS {
                c.node.removeFromParentNode()
                caps.remove(at: i)
                i -= 1
                continue
            }
            i -= 1
            if age < 0 {
                c.node.isHidden = true
                continue
            }
            c.node.isHidden = false

            let start = Vec3(center.x + c.u * half.x * 0.8, lo.y + c.v * (hi.y - lo.y), center.z)
            let reach = c.distance * scale
            var end = Vec3(start.x + sin(c.angle) * reach, max(hi.y + side * 0.4, start.y + cos(c.angle) * reach), hi.z + side * 0.3)
            end.x = clamp(end.x, -bounds.x + margin, bounds.x - margin)
            end.y = min(end.y, bounds.y - margin)

            let pop = clamp01(age / Self.popS)
            let fly = clamp01(age / (Self.popS * 1.4))
            let fade = clamp01((age - Self.popS - Self.holdS) / Self.fadeS)
            let travel = 0.88 * easeOutCubic(fly) + 0.12 * clamp01((age - Self.popS) / (Self.holdS + Self.fadeS))
            var p = start + (end - start) * travel
            p.y += sin(age * 7 + c.wobble) * 0.02 * scale * pop + fade * 0.12 * scale
            c.node.simdPosition = SIMD3(Float(p.x), Float(p.y), Float(p.z))

            let grow = easeOutBack(pop) * (1 - 0.3 * fade)
            c.node.simdScale = SIMD3(repeating: Float(max(side * grow, 0.0001)))
            let settle = easeOutCubic(pop)
            let roll = lerp(c.roll.from, c.roll.to, settle) + sin(age * 5 + c.wobble) * 0.05
            c.node.simdOrientation = quatXYZ(c.tilt.x * (1 - 0.6 * settle), c.tilt.y * (1 - 0.6 * settle), roll)
            c.node.opacity = CGFloat(1 - fade * fade)
        }
    }

    // MARK: - Textures

    private func node(_ image: CGImage) -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.diffuse.mipFilter = .linear
        m.readsFromDepthBuffer = true
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        m.blendMode = .alpha
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.castsShadow = false
        n.renderingOrder = 10
        n.isHidden = true
        n.simdScale = SIMD3(repeating: 0.0001)
        group.addChildNode(n)
        return n
    }

    private func image(for ch: String) -> CGImage? {
        guard ch.count == 1, let c = ch.first, !c.isWhitespace,
              let u = c.unicodeScalars.first, u.value >= 0x20, u.value != 0x7f, !(0xF700...0xF8FF).contains(u.value) else { return nil }
        let name: String
        if c.isASCII, c.isLetter { name = c.uppercased() } else if let n = Self.names[c] { name = n } else { name = "" }
        if !name.isEmpty, let art = cached(name, { load(name) }) { return art }
        return cached("blank+" + ch) { lettered(ch) }
    }

    private func cached(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        if let img = images[key] { return img }
        guard let img = make() else { return nil }
        images[key] = img
        return img
    }

    private func load(_ name: String) -> CGImage? {
        guard let pair = Self.pair(name) else { return nil }
        return Self.tint(pair, accent)
    }

    /// The two renders of a key: its accent painted black and painted white (see Art/Keys/export.sh),
    /// as premultiplied RGBA bytes at `textureSize`.
    private static var pairs: [String: (lo: [UInt8], hi: [UInt8])] = [:]

    private static func pair(_ name: String) -> (lo: [UInt8], hi: [UInt8])? {
        if let p = pairs[name] { return p }
        guard let lo = pixels("key-\(name)-0"), let hi = pixels("key-\(name)-1") else { return nil }
        pairs[name] = (lo, hi)
        return (lo, hi)
    }

    private static func pixels(_ file: String) -> [UInt8]? {
        let url = Bundle.main.url(forResource: file, withExtension: "png")
            ?? Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "Keys")
        guard let url, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let ctx = GlyphArt.context(width: textureSize, height: textureSize)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: textureSize, height: textureSize))
        guard let data = ctx.data else { return nil }
        let count = ctx.bytesPerRow * textureSize
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
    }

    /// Every gradient, blur and blend in the key art is linear in the accent colour, so mixing the
    /// black- and white-accent renders by the accent rebuilds the key exactly in that colour.
    private static func tint(_ pair: (lo: [UInt8], hi: [UInt8]), _ accent: SIMD3<Double>) -> CGImage? {
        let ctx = GlyphArt.context(width: textureSize, height: textureSize)
        guard let data = ctx.data, ctx.bytesPerRow * textureSize == pair.lo.count else { return nil }
        let out = data.assumingMemoryBound(to: UInt8.self)
        let k = [accent.x, accent.y, accent.z].map { Float(clamp01($0)) }
        pair.lo.withUnsafeBufferPointer { lo in
            pair.hi.withUnsafeBufferPointer { hi in
                for i in stride(from: 0, to: lo.count, by: 4) {
                    for c in 0..<3 {
                        let a = Float(lo[i + c]), b = Float(hi[i + c])
                        out[i + c] = UInt8(min(255, max(0, (a + (b - a) * k[c]).rounded())))
                    }
                    out[i + 3] = lo[i + 3]
                }
            }
        }
        return ctx.makeImage()
    }

    /// Keys without their own art (digits, accented letters…) get the blank cap with the character drawn on.
    private func lettered(_ ch: String) -> CGImage? {
        guard let blank = load("blank") else { return nil }
        let s = CGFloat(Self.textureSize)
        let ctx = GlyphArt.context(width: Self.textureSize, height: Self.textureSize)
        ctx.draw(blank, in: CGRect(x: 0, y: 0, width: s, height: s))
        let font = GlyphArt.roundedFont(size: (s * 0.6).rounded(), weight: .heavy)
        let line = GlyphArt.line(ch, font: font, fill: CGColor(gray: 1, alpha: 1))
        let w = GlyphArt.advance(line)
        ctx.saveGState()
        ctx.translateBy(x: s * 0.514, y: s * 0.495)
        ctx.rotate(by: 5.13 * .pi / 180)
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.05,
                      color: CGColor(srgbRed: accent.x, green: accent.y, blue: accent.z, alpha: 0.9))
        ctx.textPosition = CGPoint(x: -w / 2, y: GlyphArt.baseline(font: font, centerY: 0))
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return ctx.makeImage()
    }
}
