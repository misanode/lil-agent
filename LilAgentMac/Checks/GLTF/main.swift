import Foundation
import SceneKit
import simd

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

func jsonChunk(_ data: Data) throws -> [String: Any] {
    let length = Int(data.u32(12))
    return try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + length))) as! [String: Any]
}

func sameBits(_ a: [Float], _ b: [Float]) -> Bool {
    a.map(\.bitPattern) == b.map(\.bitPattern)
}

@discardableResult
func verify(_ data: Data, name: String, requireSharing: Bool = true) throws -> GLTFAsset {
    let start = ProcessInfo.processInfo.systemUptime
    let asset = try GLTFAsset(data: data)
    let loadMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
    let json = try jsonChunk(data)
    let animations = json["animations"] as? [[String: Any]] ?? []
    require(asset.clips.count == animations.count, "\(name): clip count changed")
    var inputStorage: [Int: UInt] = [:]
    var storage = Set<UInt>()
    var logicalBytes = 0, sharedBytes = 0, trackCount = 0
    func record(_ values: [Float]) {
        logicalBytes += values.count * MemoryLayout<Float>.stride
        values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            if storage.insert(UInt(bitPattern: base)).inserted {
                sharedBytes += buffer.count * MemoryLayout<Float>.stride
            }
        }
    }
    for (ai, animation) in animations.enumerated() {
        let samplers = animation["samplers"] as? [[String: Any]] ?? []
        let clip = asset.clips[ai]
        require(clip.name == (animation["name"] as? String ?? "clip\(ai)"), "Clip name changed")
        var ti = 0
        var duration: Float = 0
        for channel in animation["channels"] as? [[String: Any]] ?? [] {
            guard let target = channel["target"] as? [String: Any], let node = target["node"] as? Int,
                  let si = channel["sampler"] as? Int, si < samplers.count,
                  let input = samplers[si]["input"] as? Int, let output = samplers[si]["output"] as? Int else { continue }
            let path: GLTFTrack.Path
            switch target["path"] as? String {
            case "translation": path = .translation
            case "rotation": path = .rotation
            case "scale": path = .scale
            default: continue
            }
            let times = asset.floats(input).values
            let decoded = asset.floats(output)
            let interpolation = samplers[si]["interpolation"] as? String ?? "LINEAR"
            var values = decoded.values
            if interpolation == "CUBICSPLINE" {
                let n = decoded.comps
                values = (0..<times.count).flatMap { k in Array(decoded.values[(k * 3 + 1) * n..<(k * 3 + 2) * n]) }
            }
            require(ti < clip.tracks.count, "Track missing")
            let actual = clip.tracks[ti]
            let expected = GLTFTrack(node: node, path: path, times: times, values: values, step: interpolation == "STEP")
            require(actual.node == node && actual.path == path && actual.step == expected.step, "Track metadata changed")
            require(sameBits(actual.times, times) && sameBits(actual.values, values), "\(name): decoded float bits changed")
            for t in [Float(-1), 0, (times.last ?? 0) * 0.37, times.last ?? 0, (times.last ?? 0) + 1] {
                require(actual.sample(at: t) == expected.sample(at: t), "\(name): sampled animation changed")
            }
            if requireSharing {
                actual.times.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
                    let address = UInt(bitPattern: base)
                    if let previous = inputStorage[input] {
                        require(address == previous, "\(name): shared input accessor decoded repeatedly")
                    } else { inputStorage[input] = address }
                }
            }
            record(actual.times)
            record(actual.values)
            var copy = actual.times
            if !copy.isEmpty {
                copy[0] += 10
                require(sameBits(actual.times, times), "Copy-on-write isolation changed")
            }
            duration = max(duration, times.last ?? 0)
            ti += 1
        }
        require(ti == clip.tracks.count && clip.duration == duration, "Track order/count or duration changed")
        trackCount += ti
    }
    print("PASS: \(name): \(trackCount) tracks, exact float/sample equivalence; \(logicalBytes) logical / \(sharedBytes) retained animation bytes; load \(String(format: "%.2f", loadMS)) ms")
    return asset
}

func fixture() throws -> Data {
    let floats: [Float] = [0, 1, 1, 2, 3, 4, 5, 6,
                           0, 0, 0, 1, 2, 3, 0, 0, 0, 0, 0, 0, 4, 5, 6, 0, 0, 0,
                           0, 0, 0, 1, 0, 1, 0, 0]
    let binary = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    let json: [String: Any] = [
        "asset": ["version": "2.0"], "nodes": [[:], [:]], "scenes": [["nodes": [0, 1]]],
        "bufferViews": [["byteOffset": 0, "byteLength": binary.count]],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 2, "type": "SCALAR"],
            ["bufferView": 0, "byteOffset": 8, "componentType": 5126, "count": 2, "type": "VEC3"],
            ["bufferView": 0, "byteOffset": 32, "componentType": 5126, "count": 6, "type": "VEC3"],
            ["bufferView": 0, "byteOffset": 104, "componentType": 5126, "count": 2, "type": "VEC4"]
        ],
        "animations": [
            ["name": "shared", "samplers": [
                ["input": 0, "output": 1], ["input": 0, "output": 1, "interpolation": "STEP"],
                ["input": 0, "output": 2, "interpolation": "CUBICSPLINE"], ["input": 0, "output": 3]
            ], "channels": [
                ["sampler": 0, "target": ["node": 0, "path": "translation"]],
                ["sampler": 1, "target": ["node": 1, "path": "scale"]],
                ["sampler": 2, "target": ["node": 1, "path": "translation"]],
                ["sampler": 3, "target": ["node": 0, "path": "rotation"]]
            ]],
            ["name": "other", "samplers": [["input": 0, "output": 1]], "channels": [
                ["sampler": 0, "target": ["node": 1, "path": "translation"]]
            ]]
        ]
    ]
    var text = try JSONSerialization.data(withJSONObject: json)
    while text.count % 4 != 0 { text.append(0x20) }
    var data = Data()
    func word(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
    word(0x4654_6C67); word(2); word(UInt32(12 + 8 + text.count + 8 + binary.count))
    word(UInt32(text.count)); word(0x4E4F_534A); data.append(text)
    word(UInt32(binary.count)); word(0x004E_4942); data.append(binary)
    return data
}

let requireSharing = !CommandLine.arguments.contains("--baseline")
try verify(fixture(), name: "LINEAR/STEP/CUBICSPLINE shared accessor fixture", requireSharing: requireSharing)
let project = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["clawd", "codex", "bed"] {
    try verify(Data(contentsOf: project.appendingPathComponent("LilAgent/Resources/\(name).glb")), name: name, requireSharing: requireSharing)
}
