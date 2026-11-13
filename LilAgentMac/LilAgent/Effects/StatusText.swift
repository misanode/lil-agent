import AppKit
import CoreText
import SceneKit

final class StatusText {
    struct Palette {
        var rim: CGColor
        var fill: CGColor
        var shadow: CGColor
        static let clawd = Palette(rim: CGColor(srgbRed: 201 / 255, green: 96 / 255, blue: 58 / 255, alpha: 1),
                                   fill: CGColor(srgbRed: 1, green: 250 / 255, blue: 245 / 255, alpha: 1),
                                   shadow: CGColor(srgbRed: 70 / 255, green: 25 / 255, blue: 10 / 255, alpha: 0.45))
        static let codex = Palette(rim: CGColor(srgbRed: 64 / 255, green: 98 / 255, blue: 224 / 255, alpha: 1),
                                   fill: CGColor(srgbRed: 236 / 255, green: 252 / 255, blue: 1, alpha: 1),
                                   shadow: CGColor(srgbRed: 14 / 255, green: 20 / 255, blue: 60 / 255, alpha: 0.45))
    }

    static let phrases: [String: String] = [
        "boot": "Hello there!", "idle": "Just hanging out.", "walk": "Just stretching my legs.",
        "happy": "Life is good.", "excited": "Ooh, let’s go!", "curious": "What’s that?",
        "sad": "A little blue today.", "coffee": "Tiny coffee break.", "workout": "One more rep!",
        "meditate": "Finding my zen.", "idea": "Oh! I’ve got it!", "dance": "This is my song!",
        "wave": "Hey, you!", "annoyed": "Okay, okay…", "grumpy": "Okay, okay…", "dizzy": "Everything’s spinning…",
        "sleepy": "Getting sleepy…", "sleep": "Zzz…", "wake": "Five more minutes…",
        "thinking": "Hmm…", "reading": "Taking a look.", "searching": "Looking for clues.",
        "typing": "Typing something…", "command": "Running a command…", "planning": "Putting a plan together.",
        "subagents": "Calling in some help!", "permission": "Can I do this?", "question": "Quick question…",
        "attention": "Need your attention.", "compacting": "Compacting", "error": "Oops. Hit a snag.",
        "done": "All done!", "donehold": "All done!", "waiting": "Ready when you are.",
        "pet": "That’s the spot.", "carried": "Where are we going?", "drop": "Whoa!", "settle": "Found my spot.",
        "surprised": "Oh!",
    ]

    struct Layout {
        let x: Double
        let y: Double
        let scale: Double
        let side: Double
    }

    static func extent(x: Double, facing: Double, scale: Double, halfWidth: Double, halfDepth: Double, cameraDistance: Double) -> Double {
        let c = cos(facing), s = sin(facing)
        var extent = 0.0
        for dx in [-halfWidth, halfWidth] {
            for dz in [-halfDepth, halfDepth] {
                let px = (c * dx + s * dz) * scale, pz = (-s * dx + c * dz) * scale
                extent = max(extent, abs((x + px) * cameraDistance / max(0.001, cameraDistance - pz) - x))
            }
        }
        return extent
    }

    static func layout(x: Double, y: Double, extent: Double, width: Double, height: Double,
                       halfWidth: Double, halfHeight: Double, side: Double) -> Layout {
        let margin = 0.08, gap = 0.12
        let right = max(0, halfWidth - margin - (x + extent + gap))
        let left = max(0, x - extent - gap + halfWidth - margin)
        let wanted = side > 0 ? right : left, other = side > 0 ? left : right
        let side = wanted < width && other > wanted + 0.01 ? -side : side
        let available = side > 0 ? right : left
        let scale = min(1, available / max(width, 0.001), max(0, 2 * (halfHeight - margin)) / max(height, 0.001))
        let h = height * scale
        return Layout(x: x + side * (extent + gap + width * scale / 2),
                      y: max(-halfHeight + margin + h / 2, min(halfHeight - margin - h / 2, y)), scale: scale, side: side)
    }

    static func avoidProps(_ layout: Layout, width: Double, height: Double, halfWidth: Double, halfHeight: Double, obstacles: [CGRect], attachBelow: Bool = false) -> Layout {
        let gap = attachBelow ? 0.025 : 0.12, margin = 0.08
        let w = width * layout.scale, h = height * layout.scale
        let horizontal = obstacles.filter { layout.x + w / 2 + gap > $0.minX && layout.x - w / 2 - gap < $0.maxX }
        var y = layout.y
        if attachBelow, let propBottom = horizontal.map({ Double($0.minY) }).min() {
            y = min(halfHeight - margin - h / 2, propBottom - gap - h / 2)
        }
        for _ in horizontal {
            for b in horizontal where y + h / 2 + gap > b.minY && y - h / 2 - gap < b.maxY {
                y = min(y, b.minY - gap - h / 2)
            }
        }
        let bottom = -halfHeight + margin
        if y - h / 2 >= bottom { return Layout(x: layout.x, y: y, scale: layout.scale, side: layout.side) }
        let outerEdge = layout.side > 0 ? obstacles.map { Double($0.maxX) }.max() ?? layout.x : obstacles.map { Double($0.minX) }.min() ?? layout.x
        let outerX = outerEdge + layout.side * (gap + w / 2)
        if abs(outerX) + w / 2 <= halfWidth - margin { return Layout(x: outerX, y: layout.y, scale: layout.scale, side: layout.side) }
        let available = max(0, y + h / 2 - bottom)
        let scale = min(layout.scale, available / height)
        return Layout(x: layout.x, y: bottom + height * scale / 2, scale: scale, side: layout.side)
    }

    private let node: SCNNode
    private let material = SCNMaterial()
    private var key = ""
    private var text = ""
    private var side = 1.0
    private var opacity = 0.0
    private var width = 0.0
    private var height = 0.0
    var backingScale = 2.0

    init(scene: SCNScene) {
        let plane = SCNPlane(width: 1, height: 1)
        material.lightingModel = .constant
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        material.blendMode = .alpha
        plane.materials = [material]
        node = SCNNode(geometry: plane)
        node.name = "statusText"
        node.castsShadow = false
        node.renderingOrder = 11
        node.isHidden = true
        scene.rootNode.addChildNode(node)
    }

    private func draw(_ text: String, px: Double, ratio: Double, codex: Bool) {
        let font = GlyphArt.roundedFont(size: px * ratio, weight: .bold)
        let palette = codex ? Palette.codex : .clawd
        func measure(_ text: String) -> CGFloat { GlyphArt.advance(GlyphArt.line(text, font: font)) }
        var lines: [String] = [], line = ""
        for word in text.split(separator: " ") {
            let next = line.isEmpty ? String(word) : "\(line) \(word)"
            if !line.isEmpty && measure(next) > 180 * ratio {
                lines.append(line)
                line = String(word)
            } else { line = next }
        }
        lines.append(line)
        let pad = ceil(px * ratio * 0.4), step = px * ratio * 1.35
        let w = Int(ceil((lines.map(measure).max() ?? 0) + pad * 2))
        let h = Int(ceil(step * Double(lines.count) + pad * 2))
        let ctx = GlyphArt.context(width: w, height: h)
        for (i, line) in lines.enumerated() {
            let face = GlyphArt.line(line, font: font, fill: palette.fill)
            let edge = GlyphArt.line(line, font: font, fill: palette.rim, stroke: (palette.rim, -8))
            let at = CGPoint(x: Double(w) / 2 - measure(line) / 2,
                             y: GlyphArt.baseline(font: font, centerY: Double(h) - pad - step * (Double(i) + 0.5) - px * ratio * 0.05))
            func paint(_ line: CTLine) {
                ctx.textPosition = at
                CTLineDraw(line, ctx)
            }
            ctx.setShadow(offset: CGSize(width: 0, height: -px * ratio * 0.05), blur: px * ratio * 0.1, color: palette.shadow)
            paint(edge)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            paint(edge)
            paint(face)
        }
        material.diffuse.contents = ctx.makeImage()
        width = Double(w) / ratio / 100
        height = Double(h) / ratio / 100
    }

    func update(_ dt: Double, pet: Pet) {
        let text = pet.settings.showStatusText ? Self.phrases[pet.stateName] ?? "" : ""
        node.isHidden = text.isEmpty
        guard !text.isEmpty else { opacity = 0; self.text = ""; return }
        let p = pet.placement
        let px = max(14, min(24, 0.24 * p.scale * 100 * 0.6875)).rounded()
        let ratio = min(3, max(1, backingScale))
        let key = "\(text)|\(px)|\(ratio)|\(pet.mob.hasScreenFace)"
        if text != self.text { opacity = 0; self.text = text }
        if key != self.key { draw(text, px: px, ratio: ratio, codex: pet.mob.hasScreenFace); self.key = key }
        if abs(pet.loco.facing) > 0.12 { side = sgn(pet.loco.facing) }
        let inset = pet.mob.hasScreenFace ? 0.08 * p.scale : 0
        var textHeight = 0.50 - (pet.stateName == "command" ? 0.10 : 0)
        if pet.stateName == "permission" || pet.stateName == "error" { textHeight = 0.20 }
        let extent = max(0, Self.extent(x: pet.loco.x, facing: pet.loco.facing, scale: p.scale, halfWidth: pet.mob.edgeHalfWidth,
                                      halfDepth: pet.mob.edgeHalfDepth, cameraDistance: pet.keycaps.cameraDistance) - inset)
        let base = Self.layout(x: pet.loco.x, y: Double(pet.mob.root.simdPosition.y) + pet.mob.height * p.scale * textHeight,
                                 extent: extent, width: width, height: height, halfWidth: p.halfWidth, halfHeight: p.halfHeight, side: side)
        let layout = Self.avoidProps(base, width: width, height: height, halfWidth: p.halfWidth, halfHeight: p.halfHeight,
                                     obstacles: pet.mob.sidePropBounds(cameraDistance: pet.keycaps.cameraDistance),
                                     attachBelow: ["command", "permission", "error"].contains(pet.stateName))
        node.isHidden = layout.scale <= 0
        node.simdPosition = SIMD3(Float(layout.x), Float(layout.y), 0)
        node.simdScale = SIMD3(Float(width * layout.scale), Float(height * layout.scale), 1)
        opacity = min(1, opacity + dt / 0.15)
        node.opacity = opacity
    }
}
