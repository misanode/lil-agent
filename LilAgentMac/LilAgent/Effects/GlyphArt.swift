import AppKit
import CoreText

enum GlyphArt {
    static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func line(_ text: String, font: NSFont, fill: CGColor? = nil, stroke: (CGColor, CGFloat)? = nil) -> CTLine {
        var attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font]
        if let fill { attrs[.init(kCTForegroundColorAttributeName as String)] = fill }
        if let (color, width) = stroke {
            attrs[.init(kCTStrokeColorAttributeName as String)] = color
            attrs[.init(kCTStrokeWidthAttributeName as String)] = width
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    static func advance(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

    static func baseline(font: NSFont, centerY: CGFloat) -> CGFloat {
        centerY - (font.ascender + font.descender) / 2
    }

    static func neutralToneMap(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let start = 0.8 - 0.04
        let desaturation = 0.15
        var color = c
        let x = min(color.x, min(color.y, color.z))
        let offset = x < 0.08 ? x - 6.25 * x * x : 0.04
        color -= SIMD3(repeating: offset)
        let peak = max(color.x, max(color.y, color.z))
        if peak < start { return color }
        let d = 1 - start
        let newPeak = 1 - d * d / (peak + d - start)
        color *= newPeak / peak
        let g = 1 - 1 / (desaturation * (peak - newPeak) + 1)
        return color * (1 - g) + SIMD3(repeating: newPeak) * g
    }

    static func srgb(_ linear: SIMD3<Double>) -> CGColor {
        func enc(_ v: Double) -> CGFloat {
            let x = clamp01(v)
            return CGFloat(x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055)
        }
        return CGColor(srgbRed: enc(linear.x), green: enc(linear.y), blue: enc(linear.z), alpha: 1)
    }
}
