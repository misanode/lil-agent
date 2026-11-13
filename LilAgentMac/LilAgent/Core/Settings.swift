import Foundation
import simd

struct PetSettings: Codable, Equatable {
    struct Home: Codable, Equatable {
        var x: Double
        var lift: Double
    }

    var petSize = PetSizes.defaultSize
    var sizes: [String: Int] = [:]
    var disabled: [String] = []

    func allows(_ state: String) -> Bool { !disabled.contains(state) }
    var autoWalk = true
    var lookAtCursor = true
    var walkSpeed = 1.0
    var idleSleepMin = 5.0
    var openAtLogin = false
    var keepOnTop = true
    var showInDock = true
    var showHideShortcut = true
    var showStatusText = true
    var agentReactions = true
    var musicDance = true
    var typeAlong = true
    /// Accent colour of the type-along keycaps, as #RRGGBB.
    var keyColor = KeyColors.defaultColor
    var home: Home?
    var character = PetCharacter.clawd.rawValue

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PetSettings()
        petSize = (try? c.decodeIfPresent(Int.self, forKey: .petSize)) ?? (try? c.decodeIfPresent(Double.self, forKey: .petSize)).flatMap { $0.map { Int($0) } } ?? d.petSize
        autoWalk = (try? c.decodeIfPresent(Bool.self, forKey: .autoWalk)) ?? d.autoWalk
        lookAtCursor = (try? c.decodeIfPresent(Bool.self, forKey: .lookAtCursor)).flatMap { $0 } ?? d.lookAtCursor
        walkSpeed = (try? c.decodeIfPresent(Double.self, forKey: .walkSpeed)) ?? d.walkSpeed
        idleSleepMin = (try? c.decodeIfPresent(Double.self, forKey: .idleSleepMin)) ?? d.idleSleepMin
        openAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .openAtLogin)) ?? d.openAtLogin
        keepOnTop = (try? c.decodeIfPresent(Bool.self, forKey: .keepOnTop)).flatMap { $0 } ?? d.keepOnTop
        showInDock = (try? c.decodeIfPresent(Bool.self, forKey: .showInDock)).flatMap { $0 } ?? d.showInDock
        showHideShortcut = (try? c.decodeIfPresent(Bool.self, forKey: .showHideShortcut)) ?? d.showHideShortcut
        showStatusText = (try? c.decodeIfPresent(Bool.self, forKey: .showStatusText)) ?? d.showStatusText
        agentReactions = (try? c.decodeIfPresent(Bool.self, forKey: .agentReactions)) ?? d.agentReactions
        musicDance = (try? c.decodeIfPresent(Bool.self, forKey: .musicDance)) ?? d.musicDance
        typeAlong = (try? c.decodeIfPresent(Bool.self, forKey: .typeAlong)) ?? d.typeAlong
        keyColor = (try? c.decodeIfPresent(String.self, forKey: .keyColor)).flatMap { $0 }.flatMap(KeyColors.normalize) ?? d.keyColor
        home = (try? c.decodeIfPresent(Home.self, forKey: .home)) ?? nil
        character = (try? c.decodeIfPresent(String.self, forKey: .character)).flatMap { $0 }.flatMap(PetCharacter.init(rawValue:))?.rawValue ?? d.character
        sizes = (try? c.decodeIfPresent([String: Int].self, forKey: .sizes)).flatMap { $0 } ?? d.sizes
        disabled = (try? c.decodeIfPresent([String].self, forKey: .disabled)).flatMap { $0 } ?? d.disabled
    }
}

enum PetCharacter: String, CaseIterable {
    case clawd, codex

    var title: String { self == .clawd ? "Clawd" : "Codex" }

    func loadModel() throws -> GLTFAsset {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "glb") else {
            throw GLTFError(message: "\(rawValue).glb is missing from the app bundle.")
        }
        return try GLTFAsset(data: try Data(contentsOf: url))
    }
}

enum KeyColors {
    static let defaultColor = "#7E6345"
    static let presets: [(name: String, hex: String)] = [
        ("Mocha", "#7E6345"), ("Clay", "#C9603A"), ("Ocean", "#4062E0"), ("Forest", "#3F7D4E"),
        ("Plum", "#7A4A8C"), ("Rose", "#C2556F"), ("Graphite", "#4A4A4F"),
    ]

    /// Parses #RRGGBB (or RRGGBB) into 0...1 components.
    static func rgb(_ hex: String) -> SIMD3<Double>? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return SIMD3(Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)) / 255
    }

    static func hex(_ c: SIMD3<Double>) -> String {
        let v = simd_clamp((c * 255).rounded(.toNearestOrAwayFromZero), SIMD3(repeating: 0), SIMD3(repeating: 255))
        return String(format: "#%02X%02X%02X", Int(v.x), Int(v.y), Int(v.z))
    }

    static func normalize(_ hex: String) -> String? { rgb(hex).map(Self.hex) }
}

enum PetSizes {
    static let presets: [(String, Int)] = [("Tiny", 110), ("Small", 150), ("Medium", 210), ("Large", 290), ("Huge", 400)]
    static let range = 80...520
    static let defaultSize = 290
    static func clampSize(_ px: Double) -> Int {
        Int(min(Double(range.upperBound), max(Double(range.lowerBound), px.isFinite ? px : Double(defaultSize))).rounded())
    }
}

final class SettingsStore {
    private(set) var values: PetSettings
    var onChange: ((PetSettings, PetSettings) -> Void)?
    private let url: URL
    private var saveWork: DispatchWorkItem?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("\(Brand.name)/settings.json")
        let previous = support.appendingPathComponent("Clawd/settings.json")
        let legacy = support.appendingPathComponent("minecraft_pet_v2/settings.json")
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(PetSettings.self, from: data) {
            values = s
        } else if let data = try? Data(contentsOf: previous), let s = try? JSONDecoder().decode(PetSettings.self, from: data) {
            values = s
        } else if let data = try? Data(contentsOf: legacy), let s = try? JSONDecoder().decode(PetSettings.self, from: data) {
            values = s
        } else {
            values = PetSettings()
        }
        values.petSize = PetSizes.clampSize(Double(values.sizes[values.character] ?? values.petSize))
        values.sizes[values.character] = values.petSize
    }

    func update(_ change: (inout PetSettings) -> Void) {
        let old = values
        change(&values)
        if values.character != old.character {
            values.sizes[old.character] = old.petSize
            values.petSize = values.sizes[values.character] ?? PetSizes.defaultSize
        }
        values.petSize = PetSizes.clampSize(Double(values.petSize))
        values.sizes[values.character] = values.petSize
        guard values != old else { return }
        scheduleSave()
        onChange?(old, values)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = values
        let url = url
        let work = DispatchWorkItem {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(snapshot).write(to: url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
