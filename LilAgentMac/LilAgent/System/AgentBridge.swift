import Foundation
import Network

struct AgentActivity: Equatable {
    var activity: String
    var project: String?
    var sessions: Int
    var reason: String?
    var provider: String? = nil
}

final class AgentBridge {
    static let port: UInt16 = 47613
    private static let maxBody = 8 * 1024 * 1024
    private static let minute = 60.0
    private static let stale: [String: Double] = ["attention": 60 * minute, "permission": 60 * minute, "question": 60 * minute,
                                                  "thinking": 15 * minute, "typing": 15 * minute, "reading": 15 * minute,
                                                  "searching": 15 * minute, "command": 30 * minute, "planning": 15 * minute,
                                                  "subagents": 30 * minute, "compacting": 15 * minute, "error": 5 * minute,
                                                  "waiting": 30 * minute, "idle": .infinity]
    private static let rank: [String: Int] = ["permission": 5, "question": 4, "attention": 4, "thinking": 3, "typing": 3,
                                              "reading": 3, "searching": 3, "command": 3, "planning": 3, "subagents": 3,
                                              "compacting": 3, "error": 3, "waiting": 2, "idle": 0]
    static let working: Set<String> = ["thinking", "typing", "reading", "searching", "command", "planning", "subagents",
                                       "compacting", "error"]
    private static let readTools: Set<String> = ["Read", "LS", "NotebookRead"]
    private static let searchTools: Set<String> = ["Grep", "Glob", "WebFetch", "WebSearch", "ToolSearch"]
    private static let commandTools: Set<String> = ["Bash", "BashOutput", "KillShell", "KillBash", "Monitor", "exec_command", "shell_command", "shell", "write_stdin"]
    private static let planTools: Set<String> = ["TodoWrite", "EnterPlanMode", "TaskCreate", "TaskUpdate", "update_plan"]
    private static let agentTools: Set<String> = ["Task", "Agent", "SendMessage", "spawn_agent", "send_input", "wait_agent", "close_agent"]
    private static let askTools: Set<String> = ["AskUserQuestion", "ExitPlanMode", "request_user_input", "request_user_input_async"]

    private(set) var current = AgentActivity(activity: "idle", project: nil, sessions: 0, reason: nil)
    private(set) var listening = false
    private var sessions: [String: (activity: String, at: Double, cwd: String?, provider: String)] = [:]
    private var listener: NWListener?
    private var timer: Timer?
    private let onActivity: (AgentActivity) -> Void

    init(onActivity: @escaping (AgentActivity) -> Void) {
        self.onActivity = onActivity
    }

    private static func activity(forTool tool: String?) -> String {
        guard let rawTool = tool else { return "typing" }
        let tool = rawTool.hasPrefix("functions.") ? String(rawTool.dropFirst("functions.".count)) : rawTool
        if askTools.contains(tool) { return "question" }
        if readTools.contains(tool) { return "reading" }
        if searchTools.contains(tool) { return "searching" }
        if commandTools.contains(tool) { return "command" }
        if planTools.contains(tool) { return "planning" }
        if agentTools.contains(tool) { return "subagents" }
        return "typing"
    }

    static func activity(for e: [String: Any]) -> String?? {
        switch e["hook_event_name"] as? String {
        case "SessionStart": return "idle"
        case "UserPromptSubmit", "PostToolUse", "PostCompact", "PreModelRequest": return "thinking"
        case "PostModelRequest":
            switch e["status"] as? String {
            case "failed": return "error"
            case "cancelled": return .some(nil)
            default: return .none
            }
        case "SubagentStart": return "subagents"
        case "SubagentStop", "Interrupt": return .some(nil)
        case "PostToolUseFailure": return "error"
        case "PreCompact": return "compacting"
        case "PreToolUse": return activity(forTool: e["tool_name"] as? String)
        case "PermissionRequest": return "permission"
        case "Notification":
            let type = e["notification_type"] as? String
            let message = e["message"] as? String ?? ""
            if type == "permission_prompt" || message.range(of: "permission", options: .caseInsensitive) != nil { return "permission" }
            if type == "idle_prompt" || message.range(of: "waiting for your input", options: .caseInsensitive) != nil { return "waiting" }
            return .none
        case "Stop", "StopFailure": return "waiting"
        case "SessionEnd": return .some(nil)
        default: return .none
        }
    }

    private func summarize(_ reason: String?) -> AgentActivity {
        let t = now()
        var best: (activity: String, at: Double, cwd: String?, provider: String)?
        for (id, s) in sessions {
            if t - s.at > Self.stale[s.activity, default: .infinity] {
                sessions[id] = nil
                continue
            }
            let r = Self.rank[s.activity, default: 0]
            if best == nil || r > Self.rank[best!.activity, default: 0] || (r == Self.rank[best!.activity, default: 0] && s.at > best!.at) { best = s }
        }
        let working = sessions.values.filter { Self.working.contains($0.activity) }.count
        let project = best?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        return AgentActivity(activity: best?.activity ?? "idle", project: project, sessions: working, reason: reason, provider: best?.provider)
    }

    private func publish(_ reason: String?) {
        let next = summarize(reason)
        let changed = next.activity != current.activity || next.project != current.project || next.sessions != current.sessions || next.provider != current.provider
        if !changed && reason == nil { return }
        current = next
        onActivity(current)
    }

    func handle(_ e: [String: Any], provider: String = "claude") {
        let provider = provider == "codex" ? "codex" : "claude"
        let session = (e["session_id"] as? String) ?? "default"
        let root = "\(provider):\(session)"
        let agent = provider == "codex" ? e["agent_id"] as? String : nil
        let id = agent.map { root + ":agent:" + $0 } ?? root
        let event = e["hook_event_name"] as? String
        let closing = ["Stop", "Interrupt", "SessionEnd"].contains(event ?? "")
            || (event == "PostModelRequest" && e["status"] as? String == "cancelled")
        if provider == "codex", agent == nil, closing {
            for key in Array(sessions.keys) where key.hasPrefix(root + ":agent:") { sessions[key] = nil }
        }
        guard let activity = Self.activity(for: e) else { return }
        let before = sessions[id]?.activity
        if let activity {
            sessions[id] = (activity, now(), (e["cwd"] as? String) ?? sessions[id]?.cwd, provider)
        } else {
            sessions[id] = nil
        }
        publish(agent == nil && activity == "waiting" && before.map { Self.working.contains($0) } == true ? "done" : nil)
    }


    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.listening = true
                case .failed(let err):
                    self?.listening = false
                    NSLog("Agent listener not started (\(err)). Is another pet (the Electron one?) running?")
                default: break
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("Agent listener not started: \(error)")
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.minute, repeats: true) { [weak self] _ in self?.publish(nil) }
    }

    func stop() {
        listener?.cancel()
        timer?.invalidate()
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        receive(c, Data(), sentContinue: false)
    }

    private func receive(_ c: NWConnection, _ buffer: Data, sentContinue: Bool) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return c.cancel() }
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > Self.maxBody + 64 * 1024 { return self.respond(c, status: "413 Payload Too Large") }
            guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil { c.cancel() } else { self.receive(c, buf, sentContinue: sentContinue) }
                return
            }
            let head = String(decoding: buf[..<headerEnd.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            let request = lines.first?.split(separator: " ") ?? []
            let method = request.first.map(String.init) ?? ""
            let route = request.count > 1 ? String(request[1]) : "/"
            let provider = route == "/codex" ? "codex" : "claude"
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            if method == "GET" { return self.respond(c, status: "200 OK", body: self.currentJSON()) }
            if method != "POST" { return self.respond(c, status: "405 Method Not Allowed") }
            var body = Data(buf[headerEnd.upperBound...])
            let chunked = headers["transfer-encoding"]?.lowercased().contains("chunked") == true
            if !sentContinue, headers["expect"]?.lowercased() == "100-continue", body.isEmpty {
                c.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                return self.receive(c, buf, sentContinue: true)
            }
            if chunked {
                guard let decoded = Self.dechunk(body) else {
                    if complete || error != nil { return c.cancel() }
                    return self.receive(c, buf, sentContinue: true)
                }
                body = decoded
            } else {
                let length = Int(headers["content-length"] ?? "") ?? 0
                if body.count < length && !complete && error == nil { return self.receive(c, buf, sentContinue: true) }
                body = body.prefix(length)
            }
            self.respond(c, status: "204 No Content")
            if body.count <= Self.maxBody, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                self.handle(obj, provider: provider)
            }
        }
    }

    private static func dechunk(_ data: Data) -> Data? {
        var out = Data()
        var i = data.startIndex
        while true {
            guard let lineEnd = data[i...].range(of: Data("\r\n".utf8)) else { return nil }
            let sizeText = String(decoding: data[i..<lineEnd.lowerBound], as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { return nil }
            let start = lineEnd.upperBound
            if size == 0 { return out }
            guard data.distance(from: start, to: data.endIndex) >= size + 2 else { return nil }
            let end = data.index(start, offsetBy: size)
            out.append(data[start..<end])
            i = data.index(end, offsetBy: 2)
        }
    }

    private func currentJSON() -> Data {
        var o: [String: Any] = ["activity": current.activity, "sessions": current.sessions]
        o["project"] = current.project ?? NSNull()
        o["reason"] = current.reason ?? NSNull()
        o["provider"] = current.provider ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    }

    private func respond(_ c: NWConnection, status: String, body: Data = Data()) {
        var head = "HTTP/1.1 \(status)\r\nConnection: close\r\nContent-Length: \(body.count)\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        head += "\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }
}
