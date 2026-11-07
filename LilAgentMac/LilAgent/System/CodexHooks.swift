import Foundation

enum CodexHooks {
    static var settingsFile: URL {
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let root = env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return root.appendingPathComponent("hooks.json")
    }

    private static let marker = "# lil-agent-codex"
    private static let legacyMarker = "# clawd-pet-codex"
    static let command = "(/usr/bin/curl -s --connect-timeout 0.2 -m 0.5 -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:\(AgentBridge.port)/codex || true); printf '%s\\n' '{}' \(marker)"
    private static var legacyCommand: String { command.replacingOccurrences(of: marker, with: legacyMarker) }
    static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "PermissionRequest", "PreCompact", "PostCompact", "PreModelRequest", "PostModelRequest",
                         "SubagentStart", "SubagentStop", "Stop", "Interrupt"]

    private static func ours(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String).map { $0.hasSuffix(marker) || $0.hasSuffix(legacyMarker) } == true
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "CodexHooks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func read(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw invalid("\(file.path) must contain a JSON object. No changes were made.")
        }
        if let value = root["hooks"] {
            guard let hooks = value as? [String: Any] else { throw invalid("Expected a hooks object. No changes were made.") }
            for (event, value) in hooks {
                guard let groups = value as? [[String: Any]], groups.allSatisfy({ $0["hooks"] is [[String: Any]] }) else {
                    throw invalid("Invalid hook groups for \(event). No changes were made.")
                }
            }
        }
        return root
    }

    private static func removingOurs(_ hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]], handlers.contains(where: ours) else { return group }
                let remaining = handlers.filter { !ours($0) }
                guard !remaining.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            if kept.isEmpty { result.removeValue(forKey: event) } else { result[event] = kept }
        }
        return result
    }

    private static func write(_ root: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = file.appendingPathExtension("lil-agent-backup")
        if fm.fileExists(atPath: file.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: file, to: backup)
        }
        try data.write(to: file, options: .atomic)
    }

    static func installed(at file: URL = settingsFile) -> Bool {
        guard let root = try? read(file), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard group["matcher"] == nil, let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { [command, legacyCommand].contains($0["command"] as? String ?? "") && ($0["type"] as? String) == "command" }
            }
        }
    }

    static func install(at file: URL = settingsFile) throws {
        var root = try read(file)
        var hooks = removingOurs(root["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": 2]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try write(root, to: file)
    }

    static func uninstall(at file: URL = settingsFile) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var root = try read(file)
        let hooks = removingOurs(root["hooks"] as? [String: Any] ?? [:])
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try write(root, to: file)
    }
}
