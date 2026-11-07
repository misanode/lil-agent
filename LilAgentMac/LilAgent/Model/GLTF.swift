import AppKit
import SceneKit
import simd

struct GLTFTrack {
    enum Path: Int { case translation, rotation, scale }
    let node: Int
    let path: Path
    let times: [Float]
    let values: [Float]
    let step: Bool

    private func key(_ i: Int) -> SIMD4<Float> {
        if path == .rotation { return SIMD4(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3]) }
        return SIMD4(values[i * 3], values[i * 3 + 1], values[i * 3 + 2], 0)
    }

    func sample(at t: Float) -> SIMD4<Float> {
        let count = times.count
        if count == 0 { return .zero }
        if t <= times[0] { return key(0) }
        if t >= times[count - 1] { return key(count - 1) }
        var lo = 0, hi = count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid } else { hi = mid }
        }
        if step { return key(lo) }
        let f = (t - times[lo]) / max(times[hi] - times[lo], 1e-6)
        if path == .rotation { return slerp(key(lo), key(hi), f) }
        return key(lo) + (key(hi) - key(lo)) * f
    }
}

struct GLTFClip {
    let name: String
    let tracks: [GLTFTrack]
    let duration: Float
}

struct GLTFError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func slerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    let qa = simd_quatf(vector: a)
    var qb = simd_quatf(vector: b)
    if simd_dot(qa.vector, qb.vector) < 0 { qb = simd_quatf(vector: -qb.vector) }
    return simd_slerp(qa, qb, t).vector
}

let neutralToneMapping = """
#pragma body
float3 tm = _output.color.rgb;
float tmX = min(tm.r, min(tm.g, tm.b));
tm -= (tmX < 0.08) ? (tmX - 6.25 * tmX * tmX) : 0.04;
float tmPeak = max(tm.r, max(tm.g, tm.b));
if (tmPeak >= 0.76) {
    float tmD = 0.24;
    float tmNewPeak = 1.0 - tmD * tmD / (tmPeak + tmD - 0.76);
    tm *= tmNewPeak / tmPeak;
    float tmG = 1.0 - 1.0 / (0.15 * (tmPeak - tmNewPeak) + 1.0);
    tm = mix(tm, float3(tmNewPeak), tmG);
}
_output.color.rgb = tm;
"""

func linearColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    let space = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
    return NSColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)], count: 4)
}

final class GLTFAsset {
    let sceneRoot = SCNNode()
    private(set) var nodes: [SCNNode] = []
    private(set) var clips: [GLTFClip] = []
    private(set) var meshNodes = Set<Int>()

    private let json: [String: Any]
    private let bin: Data
    private var materials: [Int: SCNMaterial] = [:]
    private var lists: [String: [[String: Any]]] = [:]

    init(data: Data) throws {
        guard data.count >= 20, data.u32(0) == 0x4654_6C67 else { throw GLTFError(message: "Not a .glb file") }
        var offset = 12
        var json: [String: Any]?
        var bin = Data()
        while offset + 8 <= data.count {
            let length = Int(data.u32(offset))
            let type = data.u32(offset + 4)
            guard offset + 8 + length <= data.count else { break }
            let chunk = data.subdata(in: (offset + 8)..<(offset + 8 + length))
            if type == 0x4E4F_534A { json = try JSONSerialization.jsonObject(with: chunk) as? [String: Any] }
            if type == 0x004E_4942 { bin = chunk }
            offset += 8 + length
        }
        guard let json else { throw GLTFError(message: "The .glb has no JSON chunk") }
        self.json = json
        self.bin = bin
        for key in ["accessors", "bufferViews", "materials", "meshes", "nodes", "scenes", "animations"] {
            lists[key] = json[key] as? [[String: Any]] ?? []
        }
        build()
    }

    private func list(_ key: String) -> [[String: Any]] { lists[key] ?? (json[key] as? [[String: Any]] ?? []) }

    private func layout(_ index: Int) -> (acc: [String: Any], count: Int, comps: Int, ctype: Int, csize: Int, base: Int, stride: Int)? {
        let acc = list("accessors")[index]
        guard let count = acc["count"] as? Int, let ctype = acc["componentType"] as? Int,
              let bvIndex = acc["bufferView"] as? Int else { return nil }
        let comps = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16][acc["type"] as? String ?? ""] ?? 1
        let csize = [5126: 4, 5125: 4, 5123: 2, 5122: 2, 5121: 1, 5120: 1][ctype] ?? 4
        let bv = list("bufferViews")[bvIndex]
        let base = (bv["byteOffset"] as? Int ?? 0) + (acc["byteOffset"] as? Int ?? 0)
        let stride = bv["byteStride"] as? Int ?? comps * csize
        return (acc, count, comps, ctype, csize, base, stride)
    }

    func floats(_ index: Int) -> (values: [Float], count: Int, comps: Int) {
        guard let l = layout(index) else { return ([], 0, 1) }
        let normalized = l.acc["normalized"] as? Bool ?? false
        var out = [Float](repeating: 0, count: l.count * l.comps)
        bin.withUnsafeBytes { raw in
            for i in 0..<l.count {
                for c in 0..<l.comps {
                    let o = l.base + i * l.stride + c * l.csize
                    guard o + l.csize <= raw.count else { continue }
                    let v: Float
                    switch l.ctype {
                    case 5126: v = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                    case 5125: v = Float(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                    case 5123:
                        let u = raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)
                        v = normalized ? Float(u) / 65535 : Float(u)
                    case 5122:
                        let s = raw.loadUnaligned(fromByteOffset: o, as: Int16.self)
                        v = normalized ? max(Float(s) / 32767, -1) : Float(s)
                    case 5121:
                        let u = raw.load(fromByteOffset: o, as: UInt8.self)
                        v = normalized ? Float(u) / 255 : Float(u)
                    case 5120:
                        let s = raw.load(fromByteOffset: o, as: Int8.self)
                        v = normalized ? max(Float(s) / 127, -1) : Float(s)
                    default: v = 0
                    }
                    out[i * l.comps + c] = v
                }
            }
        }
        return (out, l.count, l.comps)
    }

    private func indices(_ index: Int) -> [UInt32] {
        guard let l = layout(index) else { return [] }
        var out = [UInt32](repeating: 0, count: l.count)
        bin.withUnsafeBytes { raw in
            for i in 0..<l.count {
                let o = l.base + i * l.stride
                switch l.ctype {
                case 5125: out[i] = raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)
                case 5123: out[i] = UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))
                default: out[i] = UInt32(raw.load(fromByteOffset: o, as: UInt8.self))
                }
            }
        }
        return out
    }

    private func source(_ values: [Float], count: Int, comps: Int, semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: count, usesFloatComponents: true,
                                 componentsPerVector: comps, bytesPerComponent: 4, dataOffset: 0, dataStride: comps * 4)
    }

    private func material(_ index: Int?) -> SCNMaterial {
        let key = index ?? -1
        if let m = materials[key] { return m }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        let def = index.map { list("materials")[$0] } ?? [:]
        m.name = def["name"] as? String
        let pbr = def["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let bc = (pbr["baseColorFactor"] as? [Double]) ?? [1, 1, 1, 1]
        m.diffuse.contents = linearColor(bc[0], bc[1], bc[2], 1)
        m.metalness.contents = NSNumber(value: pbr["metallicFactor"] as? Double ?? 1)
        m.roughness.contents = NSNumber(value: pbr["roughnessFactor"] as? Double ?? 1)
        let ext = def["extensions"] as? [String: Any] ?? [:]
        if let e = def["emissiveFactor"] as? [Double], e.count >= 3 {
            let s = (ext["KHR_materials_emissive_strength"] as? [String: Any])?["emissiveStrength"] as? Double ?? 1
            m.emission.contents = linearColor(e[0] * s, e[1] * s, e[2] * s)
        }
        if let cc = ext["KHR_materials_clearcoat"] as? [String: Any] {
            m.clearCoat.contents = NSNumber(value: cc["clearcoatFactor"] as? Double ?? 0)
            m.clearCoatRoughness.contents = NSNumber(value: cc["clearcoatRoughnessFactor"] as? Double ?? 0)
        }
        m.isDoubleSided = def["doubleSided"] as? Bool ?? false
        if bc[3] < 1 || (def["alphaMode"] as? String) == "BLEND" {
            m.transparency = CGFloat(bc[3])
            m.blendMode = .alpha
        }
        m.shaderModifiers = [.fragment: neutralToneMapping]
        materials[key] = m
        return m
    }

    private func geometry(_ primitive: [String: Any]) -> SCNGeometry? {
        guard let attrs = primitive["attributes"] as? [String: Int], let posIndex = attrs["POSITION"] else { return nil }
        if let mode = primitive["mode"] as? Int, mode != 4 { return nil }
        let pos = floats(posIndex)
        var sources = [source(pos.values, count: pos.count, comps: 3, semantic: .vertex)]
        if let n = attrs["NORMAL"] {
            let a = floats(n)
            sources.append(source(a.values, count: a.count, comps: 3, semantic: .normal))
        }
        if let t = attrs["TEXCOORD_0"] {
            let a = floats(t)
            sources.append(source(a.values, count: a.count, comps: 2, semantic: .texcoord))
        }
        let idx = (primitive["indices"] as? Int).map { indices($0) } ?? (0..<UInt32(pos.count)).map { $0 }
        let data = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: idx.count / 3, bytesPerIndex: 4)
        let g = SCNGeometry(sources: sources, elements: [element])
        g.materials = [material(primitive["material"] as? Int)]
        return g
    }

    private func build() {
        let defs = list("nodes")
        let meshes = list("meshes")
        nodes = defs.enumerated().map { i, n in
            let node = SCNNode()
            node.name = n["name"] as? String ?? "node\(i)"
            if let m = n["matrix"] as? [Double], m.count == 16 {
                let f = m.map { Float($0) }
                node.simdTransform = simd_float4x4(SIMD4(f[0], f[1], f[2], f[3]), SIMD4(f[4], f[5], f[6], f[7]),
                                                   SIMD4(f[8], f[9], f[10], f[11]), SIMD4(f[12], f[13], f[14], f[15]))
            } else {
                if let t = n["translation"] as? [Double] { node.simdPosition = SIMD3(Float(t[0]), Float(t[1]), Float(t[2])) }
                if let r = n["rotation"] as? [Double] {
                    node.simdOrientation = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3]))
                }
                if let s = n["scale"] as? [Double] { node.simdScale = SIMD3(Float(s[0]), Float(s[1]), Float(s[2])) }
            }
            if let mi = n["mesh"] as? Int, mi < meshes.count {
                meshNodes.insert(i)
                let prims = (meshes[mi]["primitives"] as? [[String: Any]] ?? []).compactMap { geometry($0) }
                if prims.count == 1 {
                    node.geometry = prims[0]
                } else {
                    for (k, g) in prims.enumerated() {
                        let child = SCNNode(geometry: g)
                        child.name = "\(node.name ?? "mesh")_\(k)"
                        node.addChildNode(child)
                    }
                }
            }
            return node
        }
        for (i, n) in defs.enumerated() {
            for c in n["children"] as? [Int] ?? [] where c < nodes.count { nodes[i].addChildNode(nodes[c]) }
        }
        let scenes = list("scenes")
        let sceneIndex = json["scene"] as? Int ?? 0
        if sceneIndex < scenes.count {
            for r in scenes[sceneIndex]["nodes"] as? [Int] ?? [] where r < nodes.count { sceneRoot.addChildNode(nodes[r]) }
        }

                                                                                 
                                                                               
        var animationAccessors: [Int: (values: [Float], count: Int, comps: Int)] = [:]
        func animationFloats(_ index: Int) -> (values: [Float], count: Int, comps: Int) {
            if let cached = animationAccessors[index] { return cached }
            let decoded = floats(index)
            animationAccessors[index] = decoded
            return decoded
        }

        for (ai, a) in list("animations").enumerated() {
            let samplers = a["samplers"] as? [[String: Any]] ?? []
            var tracks: [GLTFTrack] = []
            var duration: Float = 0
            for ch in a["channels"] as? [[String: Any]] ?? [] {
                guard let target = ch["target"] as? [String: Any], let node = target["node"] as? Int,
                      let si = ch["sampler"] as? Int, si < samplers.count,
                      let input = samplers[si]["input"] as? Int, let output = samplers[si]["output"] as? Int else { continue }
                let path: GLTFTrack.Path
                switch target["path"] as? String {
                case "translation": path = .translation
                case "rotation": path = .rotation
                case "scale": path = .scale
                default: continue
                }
                let times = animationFloats(input).values
                let out = animationFloats(output)
                var values = out.values
                let interpolation = samplers[si]["interpolation"] as? String ?? "LINEAR"
                if interpolation == "CUBICSPLINE" {
                    let n = out.comps
                    values = (0..<times.count).flatMap { k in Array(out.values[(k * 3 + 1) * n..<(k * 3 + 2) * n]) }
                }
                tracks.append(GLTFTrack(node: node, path: path, times: times, values: values, step: interpolation == "STEP"))
                duration = max(duration, times.last ?? 0)
            }
            clips.append(GLTFClip(name: a["name"] as? String ?? "clip\(ai)", tracks: tracks, duration: duration))
        }
    }
}

extension Data {
    func u32(_ offset: Int) -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }
}
