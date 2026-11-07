import Foundation

enum ClaudeHooks {
    static let settingsFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    private static let marker = "# lil-agent"
    private static let legacyMarker = "# clawd-pet"
    private static let command = "curl -s -m 2 -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:\(AgentBridge.port)/claude || true \(marker)"
    private static let toolEvents = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"]
    private static let otherEvents = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "StopFailure", "PreCompact", "SessionEnd"]

    private static func ours(_ entry: JSON) -> Bool {
        guard case .array(let hooks)? = entry["hooks"] else { return false }
        return hooks.contains { h in
            if case .string(let c)? = h["command"] { return c.contains(marker) || c.contains(legacyMarker) }
            return false
        }
    }

    private static func read() throws -> JSON {
        guard let data = try? Data(contentsOf: settingsFile) else { return .object([]) }
        do {
            return try JSON.parse(String(decoding: data, as: UTF8.self))
        } catch {
            throw NSError(domain: "ClaudeHooks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't read \(settingsFile.path): \(error.localizedDescription)"])
        }
    }

    private static func write(_ settings: JSON) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = settingsFile.path + ".lil-agent-backup"
        if fm.fileExists(atPath: settingsFile.path) && !fm.fileExists(atPath: backup) {
            try fm.copyItem(atPath: settingsFile.path, toPath: backup)
        }
        try Data((settings.stringify() + "\n").utf8).write(to: settingsFile, options: .atomic)
    }

    static func installed() -> Bool {
        guard let s = try? read(), case .object(let hooks)? = s["hooks"] else { return false }
        return (toolEvents + otherEvents).allSatisfy { event in
            guard let (_, entries) = hooks.first(where: { $0.0 == event }), case .array(let list) = entries else { return false }
            return list.contains(where: ours)
        }
    }

    static func uninstall() throws {
        var s = try read()
        guard case .object(var hooks)? = s["hooks"] else { return }
        hooks = hooks.compactMap { event, entries in
            guard case .array(let list) = entries else { return (event, entries) }
            let kept = list.filter { !ours($0) }
            return kept.isEmpty ? nil : (event, .array(kept))
        }
        s["hooks"] = hooks.isEmpty ? nil : .object(hooks)
        try write(s)
    }

    static func install() throws {
        var s = try read()
        var hooks: [(String, JSON)] = []
        if case .object(let h)? = s["hooks"] { hooks = h }
        let hook = JSON.object([("type", .string("command")), ("command", .string(command)), ("timeout", .number("5"))])
        for event in toolEvents + otherEvents {
            var entries: [JSON] = []
            if let i = hooks.firstIndex(where: { $0.0 == event }), case .array(let list) = hooks[i].1 { entries = list.filter { !ours($0) } }
            entries.append(toolEvents.contains(event)
                ? .object([("matcher", .string("*")), ("hooks", .array([hook]))])
                : .object([("hooks", .array([hook]))]))
            if let i = hooks.firstIndex(where: { $0.0 == event }) { hooks[i].1 = .array(entries) } else { hooks.append((event, .array(entries))) }
        }
        s["hooks"] = .object(hooks)
        try write(s)
    }
}

indirect enum JSON {
    case object([(String, JSON)])
    case array([JSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    subscript(key: String) -> JSON? {
        get {
            guard case .object(let pairs) = self else { return nil }
            return pairs.first { $0.0 == key }?.1
        }
        set {
            guard case .object(var pairs) = self else { return }
            if let i = pairs.firstIndex(where: { $0.0 == key }) {
                if let newValue { pairs[i].1 = newValue } else { pairs.remove(at: i) }
            } else if let newValue {
                pairs.append((key, newValue))
            }
            self = .object(pairs)
        }
    }

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ text: String) throws -> JSON {
        var p = Parser(Array(text.unicodeScalars))
        p.skip()
        if p.i >= p.s.count { return .object([]) }
        let v = try p.value()
        p.skip()
        if p.i < p.s.count { throw ParseError(message: "Unexpected text after JSON") }
        return v
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func skip() {
            while i < s.count, [" ", "\n", "\r", "\t"].contains(s[i]) { i += 1 }
        }

        mutating func expect(_ c: Unicode.Scalar) throws {
            skip()
            guard i < s.count, s[i] == c else { throw ParseError(message: "Expected \"\(c)\" at \(i)") }
            i += 1
        }

        mutating func value() throws -> JSON {
            skip()
            guard i < s.count else { throw ParseError(message: "Unexpected end of JSON") }
            switch s[i] {
            case "{":
                i += 1
                var pairs: [(String, JSON)] = []
                skip()
                if i < s.count, s[i] == "}" { i += 1; return .object(pairs) }
                while true {
                    skip()
                    let k = try string()
                    try expect(":")
                    pairs.append((k, try value()))
                    skip()
                    guard i < s.count else { throw ParseError(message: "Unterminated object") }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "}" { i += 1; return .object(pairs) }
                    throw ParseError(message: "Expected , or } at \(i)")
                }
            case "[":
                i += 1
                var items: [JSON] = []
                skip()
                if i < s.count, s[i] == "]" { i += 1; return .array(items) }
                while true {
                    items.append(try value())
                    skip()
                    guard i < s.count else { throw ParseError(message: "Unterminated array") }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "]" { i += 1; return .array(items) }
                    throw ParseError(message: "Expected , or ] at \(i)")
                }
            case "\"": return .string(try string())
            case "t": try word("true"); return .bool(true)
            case "f": try word("false"); return .bool(false)
            case "n": try word("null"); return .null
            default:
                let start = i
                while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
                guard i > start else { throw ParseError(message: "Unexpected character at \(i)") }
                return .number(String(String.UnicodeScalarView(s[start..<i])))
            }
        }

        mutating func word(_ w: String) throws {
            for c in w.unicodeScalars {
                guard i < s.count, s[i] == c else { throw ParseError(message: "Bad literal at \(i)") }
                i += 1
            }
        }

        mutating func string() throws -> String {
            guard i < s.count, s[i] == "\"" else { throw ParseError(message: "Expected string at \(i)") }
            i += 1
            var out = String.UnicodeScalarView()
            var pendingHigh: UInt32?
            while i < s.count {
                let c = s[i]
                i += 1
                if c == "\"" { return String(out) }
                if c != "\\" {
                    out.append(c)
                    continue
                }
                guard i < s.count else { break }
                let e = s[i]
                i += 1
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{8}")
                case "f": out.append("\u{c}")
                case "u":
                    guard i + 4 <= s.count, let v = UInt32(String(String.UnicodeScalarView(s[i..<i + 4])), radix: 16) else {
                        throw ParseError(message: "Bad \\u escape at \(i)")
                    }
                    i += 4
                    if (0xD800...0xDBFF).contains(v) {
                        pendingHigh = v
                    } else if (0xDC00...0xDFFF).contains(v), let hi = pendingHigh {
                        pendingHigh = nil
                        if let u = Unicode.Scalar(0x10000 + ((hi - 0xD800) << 10) + (v - 0xDC00)) { out.append(u) }
                    } else if let u = Unicode.Scalar(v) {
                        out.append(u)
                    }
                default: out.append(e)
                }
            }
            throw ParseError(message: "Unterminated string")
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{c}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    func stringify(_ indent: String = "") -> String {
        let inner = indent + "  "
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            return "{\n" + pairs.map { inner + JSON.quote($0.0) + ": " + $0.1.stringify(inner) }.joined(separator: ",\n") + "\n" + indent + "}"
        case .array(let items):
            if items.isEmpty { return "[]" }
            return "[\n" + items.map { inner + $0.stringify(inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .string(let s): return JSON.quote(s)
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }
}
