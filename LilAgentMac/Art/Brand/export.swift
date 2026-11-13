import AppKit

let brand = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let mac = brand.appendingPathComponent("../..").standardizedFileURL
let electron = mac.appendingPathComponent("../LilAgentWindows").standardizedFileURL
let resources = mac.appendingPathComponent("LilAgent/Resources")
let appIcon = mac.appendingPathComponent("LilAgent/AppIcon.icon")
let electronAssets = electron.appendingPathComponent("assets")
let fm = FileManager.default

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func source(_ name: String) -> URL { brand.appendingPathComponent(name) }

func svg(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: source(name)) else { fail("Can't read \(name)") }
    return image
}

func pathData(_ url: URL) -> [String] {
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let regex = try! NSRegularExpression(pattern: #"\bd="([^"]+)""#)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range(at: 1), in: text)!]) }
}

let splashCanvas = CGSize(width: 1000, height: 598)

func checkProvenance() {
    let splash = Set(pathData(source("Source/splash.svg")))
    let background = Set(pathData(source("Source/splash-bg.svg")))
    let logo = Set(pathData(source("Source/lil-agent-logo.svg")))
    if !Set(pathData(source("splash-wordmark.svg"))).isSubset(of: splash) {
        fail("splash-wordmark.svg no longer matches Source/splash.svg")
    }
    if !Set(pathData(source("splash-card.svg"))).isSubset(of: background) {
        fail("splash-card.svg no longer matches Source/splash-bg.svg")
    }
    for name in ["splash-card.svg", "splash-wordmark.svg"] {
        let size = svg(name).size
        if abs(size.width / size.height - splashCanvas.width / splashCanvas.height) > 0.01 {
            fail("\(name) isn't \(Int(splashCanvas.width))×\(Int(splashCanvas.height)) like the splash card")
        }
    }
    for name in ["menu-bar-mascot.svg"] where !Set(pathData(source(name))).isSubset(of: logo) {
        fail("\(name) no longer matches Source/lil-agent-logo.svg")
    }
}

func bitmap(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("Can't encode \(url.lastPathComponent)") }
    do { try png.write(to: url) } catch { fail("Can't write \(url.path): \(error)") }
}

func copy(_ name: String, to url: URL) {
    try? fm.removeItem(at: url)
    do { try fm.copyItem(at: source(name), to: url) } catch { fail("Can't copy \(name): \(error)") }
}

// The app icon master is the supplied raster plate. Drop its faint baked-in shadow (the Mac icon draws its own) and crop
// away the transparent margin so the plate fills the draw rect.
let master: CGImage = {
    guard let data = try? Data(contentsOf: source("Source/app-icon.png")), let rep = NSBitmapImageRep(data: data) else {
        fail("Can't read Source/app-icon.png")
    }
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
    var pixel = [Int](repeating: 0, count: 4)
    var clear = [Int](repeating: 0, count: rep.samplesPerPixel)
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            rep.getPixel(&pixel, atX: x, y: y)
            if pixel[3] < 64 { rep.setPixel(&clear, atX: x, y: y); continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, let image = rep.cgImage,
          let plate = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else {
        fail("Source/app-icon.png is empty")
    }
    return plate
}()

func windowsIcon(_ px: Int) -> NSBitmapImageRep {
    bitmap(px, px) { ctx in
        ctx.interpolationQuality = .high
        ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    }
}

func mascot(width: Int, height: Int, ink: NSColor = .black) -> NSBitmapImageRep {
    let image = svg("menu-bar-mascot.svg")
    return bitmap(width, height) { ctx in
        let aspect = image.size.width / image.size.height
        let w = min(CGFloat(width), CGFloat(height) * aspect)
        let h = w / aspect
        image.draw(in: NSRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(ink.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

func ico(_ sizes: [Int], _ url: URL) {
    let images = sizes.map { windowsIcon($0).representation(using: .png, properties: [:])! }
    var data = Data()
    func le16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func le32(_ v: Int) { le16(v & 0xFFFF); le16(v >> 16 & 0xFFFF) }
    le16(0); le16(1); le16(sizes.count)
    var offset = 6 + 16 * sizes.count
    for (size, png) in zip(sizes, images) {
        data.append(contentsOf: [UInt8(size >= 256 ? 0 : size), UInt8(size >= 256 ? 0 : size), 0, 0])
        le16(1); le16(32); le32(png.count); le32(offset)
        offset += png.count
    }
    images.forEach { data.append($0) }
    do { try data.write(to: url) } catch { fail("Can't write \(url.path): \(error)") }
}

func splashBadge(width: Int) -> NSBitmapImageRep {
    guard let data = try? Data(contentsOf: source("Source/lil-agent-glass.png")), let badge = NSBitmapImageRep(data: data)?.cgImage else {
        fail("Can't read Source/lil-agent-glass.png")
    }
    let unit = CGFloat(width) / splashCanvas.width
    let height = Int((splashCanvas.height * unit).rounded())
    let h = 377 * unit
    let w = h * CGFloat(badge.width) / CGFloat(badge.height)
    return bitmap(width, height) { ctx in
        ctx.interpolationQuality = .high
        ctx.draw(badge, in: CGRect(x: 500 * unit - w / 2, y: CGFloat(height) - 270 * unit - h / 2, width: w, height: h))
    }
}

checkProvenance()

for name in ["splash-card", "splash-wordmark"] {
    copy("\(name).svg", to: resources.appendingPathComponent("\(name).svg"))
}
write(splashBadge(width: 1400), resources.appendingPathComponent("splash-logo.png"))

write(mascot(width: 23, height: 16), resources.appendingPathComponent("trayTemplate.png"))
write(mascot(width: 46, height: 32), resources.appendingPathComponent("trayTemplate@2x.png"))
for (name, ink) in [("trayWindowsWhite", NSColor.white), ("trayWindowsBlack", NSColor.black)] {
    for (suffix, px) in [("", 16), ("@1.5x", 24), ("@2x", 32)] {
        write(mascot(width: px, height: px, ink: ink), electronAssets.appendingPathComponent("\(name)\(suffix).png"))
    }
}

let iconBuild = fm.temporaryDirectory.appendingPathComponent("LilAgent-\(UUID().uuidString)")
try? fm.createDirectory(at: iconBuild, withIntermediateDirectories: true)
let actool = Process()
actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
actool.arguments = ["actool", "--compile", iconBuild.path, "--platform", "macosx", "--minimum-deployment-target", "14.0",
                    "--app-icon", "AppIcon", "--output-partial-info-plist", iconBuild.appendingPathComponent("partial.plist").path,
                    appIcon.path]
actool.standardOutput = FileHandle.nullDevice
try! actool.run()
actool.waitUntilExit()
if actool.terminationStatus != 0 { fail("actool couldn't compile LilAgent/AppIcon.icon") }
try? fm.removeItem(at: electronAssets.appendingPathComponent("icon.icns"))
do { try fm.copyItem(at: iconBuild.appendingPathComponent("AppIcon.icns"), to: electronAssets.appendingPathComponent("icon.icns")) }
catch { fail("Can't copy the compiled AppIcon.icns: \(error)") }
try? fm.removeItem(at: iconBuild)

ico([16, 20, 24, 32, 40, 48, 64, 256], electronAssets.appendingPathComponent("icon.ico"))
write(windowsIcon(1024), electronAssets.appendingPathComponent("icon.png"))

print("brand assets exported")
