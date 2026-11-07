import Foundation

func now() -> Double { ProcessInfo.processInfo.systemUptime }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

if CommandLine.arguments.contains("--install-hooks") {
    try CodexHooks.install()
    print("Installed Lil Agent hooks at \(CodexHooks.settingsFile.path). Review and trust them using /hooks in Codex.")
    exit(0)
}

let bridge = AgentBridge { _ in }
func send(_ name: String, _ provider: String = "codex", tool: String? = nil, agent: String? = nil, status: String? = nil) {
    var e: [String: Any] = ["hook_event_name": name, "session_id": "shared-id", "cwd": "/tmp/ClawdProject"]
    e["tool_name"] = tool
    e["agent_id"] = agent
    e["status"] = status
    bridge.handle(e, provider: provider)
}

send("UserPromptSubmit", "claude")
send("UserPromptSubmit")
check(bridge.current.sessions == 2, "Provider session IDs collided")
send("PreToolUse", tool: "Bash")
check(bridge.current.activity == "command" && bridge.current.provider == "codex", "Codex Bash not mapped")
send("PermissionRequest", "claude")
send("PreToolUse", tool: "apply_patch")
check(bridge.current.activity == "permission" && bridge.current.provider == "claude", "Permission priority lost")
send("SessionEnd", "claude")
check(bridge.current.activity == "typing" && bridge.current.sessions == 1, "Claude closing removed Codex")
send("PreToolUse", tool: "functions.update_plan")
check(bridge.current.activity == "planning", "Planning not mapped")
send("PreToolUse", tool: "request_user_input")
check(bridge.current.activity == "question", "Questions not mapped")
send("PostToolUse")
send("SubagentStart", agent: "child")
check(bridge.current.sessions == 2, "Child overwrote parent")
send("SubagentStop", agent: "child")
check(bridge.current.sessions == 1 && bridge.current.activity == "thinking" && bridge.current.reason == nil, "Child stop finished parent")
send("Stop")
check(bridge.current.activity == "waiting" && bridge.current.reason == "done", "Completion did not celebrate")
send("UserPromptSubmit")
send("SubagentStart", agent: "child")
send("Interrupt")
check(bridge.current.activity == "idle" && bridge.current.sessions == 0 && bridge.current.reason == nil, "Interrupt left work or celebrated")
send("UserPromptSubmit")
send("PostModelRequest", status: "failed")
check(bridge.current.activity == "error", "Model failure not shown")
send("PreModelRequest")
check(bridge.current.activity == "thinking", "Model retry did not clear failure")
send("PreCompact")
check(bridge.current.activity == "compacting", "Compaction not shown")
send("PostCompact")
check(bridge.current.activity == "thinking", "Compaction not cleared")
send("SessionEnd")
check(bridge.current.provider == nil && bridge.current.activity == "idle", "Closed session remained")
send("UserPromptSubmit")
send("SubagentStart", agent: "child")
send("PostModelRequest", status: "cancelled")
check(bridge.current.activity == "idle" && bridge.current.sessions == 0, "Cancelled model left children active")
send("PreToolUse", "claude", tool: "Read")
check(bridge.current.activity == "reading", "Claude Read regressed")
send("PostToolUseFailure", "claude")
check(bridge.current.activity == "error", "Claude failure regressed")
send("Stop", "claude")
check(bridge.current.reason == "done", "Claude completion regressed")

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lil-agent-hooks-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
let file = temp.appendingPathComponent("hooks.json")
let foreign: [String: Any] = ["type": "command", "command": "echo unrelated"]
let original: [String: Any] = ["description": "Keep me", "hooks": ["Stop": [["matcher": "keep", "hooks": [foreign]]]]]
let originalData = try JSONSerialization.data(withJSONObject: original)
try originalData.write(to: file)
try CodexHooks.install(at: file)
check(CodexHooks.installed(at: file), "Install not detected")
let once = try Data(contentsOf: file)
try CodexHooks.install(at: file)
let twice = try Data(contentsOf: file)
check(once == twice, "Install not idempotent")
let backup = try Data(contentsOf: file.appendingPathExtension("lil-agent-backup"))
check(backup == originalData, "Original backup changed")
var root = try JSONSerialization.jsonObject(with: twice) as! [String: Any]
var hooks = root["hooks"] as! [String: Any]
var stops = hooks["Stop"] as! [[String: Any]]
var handlers = stops[1]["hooks"] as! [[String: Any]]
handlers.append(foreign)
stops[1]["hooks"] = handlers
hooks["Stop"] = stops
root["hooks"] = hooks
try JSONSerialization.data(withJSONObject: root).write(to: file)
try CodexHooks.uninstall(at: file)
let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
let remaining = removed["hooks"] as! [String: Any]
let remainingStops = remaining["Stop"] as! [[String: Any]]
check(removed["description"] as? String == "Keep me" && remainingStops.count == 2, "Uninstall deleted other settings or handlers")
check(!CodexHooks.installed(at: file), "Uninstall left installed state")
for invalid in ["{broken", "[]", "{\"hooks\": []}", "{\"hooks\": {\"Stop\": 3}}"] {
    let data = Data(invalid.utf8)
    try data.write(to: file)
    do { try CodexHooks.install(at: file); fatalError("Accepted malformed configuration") } catch {}
    let after = try Data(contentsOf: file)
    check(after == data, "Changed invalid configuration")
}
try FileManager.default.removeItem(at: file)
try CodexHooks.install(at: file)
check(CodexHooks.installed(at: file), "Fresh install failed")
try CodexHooks.uninstall(at: file)
check(!CodexHooks.installed(at: file), "Fresh uninstall failed")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", CodexHooks.command.replacingOccurrences(of: ":47613/codex", with: ":9/codex")]
let input = Pipe(), output = Pipe()
process.standardInput = input
process.standardOutput = output
let started = now()
try process.run()
input.fileHandleForWriting.write(Data("{\"hook_event_name\":\"Stop\"}".utf8))
try input.fileHandleForWriting.close()
process.waitUntilExit()
let reply = output.fileHandleForReading.readDataToEndOfFile()
let response = try JSONSerialization.jsonObject(with: reply) as? [String: Any]
check(process.terminationStatus == 0 && response?.isEmpty == true && now() - started < 2, "Missing pet blocked or influenced Codex")
print("PASS: mixed providers, tool mapping, priority, child lifecycle, completion, interruption, Claude regression, safe hook merge/backup/uninstall, invalid-config protection")
