import http from 'node:http';
import path from 'node:path';

export const AGENT_PORT = 47613;
const MAX_BODY = 8 * 1024 * 1024;
const MINUTE = 60;
const STALE = {
  attention: 60 * MINUTE, permission: 60 * MINUTE, question: 60 * MINUTE, thinking: 15 * MINUTE, typing: 15 * MINUTE,
  reading: 15 * MINUTE, searching: 15 * MINUTE, command: 30 * MINUTE, planning: 15 * MINUTE, subagents: 30 * MINUTE,
  compacting: 15 * MINUTE, error: 5 * MINUTE, waiting: 30 * MINUTE, idle: Infinity,
};
const RANK = {
  permission: 5, question: 4, attention: 4, thinking: 3, typing: 3, reading: 3, searching: 3, command: 3, planning: 3,
  subagents: 3, compacting: 3, error: 3, waiting: 2, idle: 0,
};
export const WORKING = new Set(['thinking', 'typing', 'reading', 'searching', 'command', 'planning', 'subagents', 'compacting', 'error']);
const READ_TOOLS = new Set(['Read', 'LS', 'NotebookRead']);
const SEARCH_TOOLS = new Set(['Grep', 'Glob', 'WebFetch', 'WebSearch', 'ToolSearch']);
const COMMAND_TOOLS = new Set(['Bash', 'BashOutput', 'KillShell', 'KillBash', 'Monitor', 'exec_command', 'shell_command', 'shell', 'write_stdin', 'PowerShell']);
const PLAN_TOOLS = new Set(['TodoWrite', 'EnterPlanMode', 'TaskCreate', 'TaskUpdate', 'update_plan']);
const AGENT_TOOLS = new Set(['Task', 'Agent', 'SendMessage', 'spawn_agent', 'send_input', 'wait_agent', 'close_agent']);
const ASK_TOOLS = new Set(['AskUserQuestion', 'ExitPlanMode', 'request_user_input', 'request_user_input_async']);

const now = () => Date.now() / 1000;

function activityForTool(rawTool) {
  if (!rawTool) return 'typing';
  const tool = rawTool.startsWith('functions.') ? rawTool.slice('functions.'.length) : rawTool;
  if (ASK_TOOLS.has(tool)) return 'question';
  if (READ_TOOLS.has(tool)) return 'reading';
  if (SEARCH_TOOLS.has(tool)) return 'searching';
  if (COMMAND_TOOLS.has(tool)) return 'command';
  if (PLAN_TOOLS.has(tool)) return 'planning';
  if (AGENT_TOOLS.has(tool)) return 'subagents';
  return 'typing';
}

export function activityFor(e) {
  switch (e.hook_event_name) {
    case 'SessionStart': return 'idle';
    case 'UserPromptSubmit': case 'PostToolUse': case 'PostCompact': case 'PreModelRequest': return 'thinking';
    case 'PostModelRequest':
      if (e.status === 'failed') return 'error';
      if (e.status === 'cancelled') return null;
      return undefined;
    case 'SubagentStart': return 'subagents';
    case 'SubagentStop': case 'Interrupt': return null;
    case 'PostToolUseFailure': return 'error';
    case 'PreCompact': return 'compacting';
    case 'PreToolUse': return activityForTool(e.tool_name);
    case 'PermissionRequest': return 'permission';
    case 'Notification': {
      const type = e.notification_type;
      const message = String(e.message ?? '');
      if (type === 'permission_prompt' || /permission/i.test(message)) return 'permission';
      if (type === 'idle_prompt' || /waiting for your input/i.test(message)) return 'waiting';
      return undefined;
    }
    case 'Stop': case 'StopFailure': return 'waiting';
    case 'SessionEnd': return null;
    default: return undefined;
  }
}

export function startAgentBridge({ onActivity }) {
  const sessions = new Map();
  const bridge = {
    current: { activity: 'idle', project: null, sessions: 0, reason: null, provider: null },
    listening: false,
    handle,
    stop: () => { server.close(); clearInterval(timer); },
  };

  function summarize(reason) {
    const t = now();
    let best = null;
    let working = 0;
    for (const [id, s] of sessions) {
      if (t - s.at > (STALE[s.activity] ?? Infinity)) {
        sessions.delete(id);
        continue;
      }
      if (WORKING.has(s.activity)) working++;
      const r = RANK[s.activity] ?? 0;
      const br = best ? RANK[best.activity] ?? 0 : -1;
      if (!best || r > br || (r === br && s.at > best.at)) best = s;
    }
    const project = best?.cwd ? path.basename(best.cwd) : null;
    return { activity: best?.activity ?? 'idle', project, sessions: working, reason: reason ?? null, provider: best?.provider ?? null };
  }

  function publish(reason) {
    const next = summarize(reason);
    const c = bridge.current;
    const changed = next.activity !== c.activity || next.project !== c.project || next.sessions !== c.sessions || next.provider !== c.provider;
    if (!changed && reason == null) return;
    bridge.current = next;
    onActivity(next);
  }

  function handle(e, provider = 'claude') {
    provider = provider === 'codex' ? 'codex' : 'claude';
    const root = `${provider}:${e.session_id ?? 'default'}`;
    const agent = provider === 'codex' ? e.agent_id : undefined;
    const id = agent ? `${root}:agent:${agent}` : root;
    const event = e.hook_event_name;
    const closing = ['Stop', 'Interrupt', 'SessionEnd'].includes(event) || (event === 'PostModelRequest' && e.status === 'cancelled');
    if (provider === 'codex' && !agent && closing) {
      for (const key of sessions.keys()) if (key.startsWith(`${root}:agent:`)) sessions.delete(key);
    }
    const activity = activityFor(e);
    if (activity === undefined) return;
    const before = sessions.get(id)?.activity;
    if (activity) sessions.set(id, { activity, at: now(), cwd: e.cwd ?? sessions.get(id)?.cwd ?? null, provider });
    else sessions.delete(id);
    publish(!agent && activity === 'waiting' && before && WORKING.has(before) ? 'done' : null);
  }

  const server = http.createServer((req, res) => {
    if (req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'application/json', Connection: 'close' });
      return res.end(JSON.stringify(bridge.current));
    }
    if (req.method !== 'POST') {
      res.writeHead(405, { Connection: 'close' });
      return res.end();
    }
    const provider = req.url === '/codex' ? 'codex' : 'claude';
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        res.writeHead(413, { Connection: 'close' });
        res.end();
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => {
      if (res.writableEnded) return;
      res.writeHead(204, { Connection: 'close' });
      res.end();
      try {
        const obj = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        if (obj && typeof obj === 'object' && !Array.isArray(obj)) handle(obj, provider);
      } catch {}
    });
  });
  server.on('listening', () => { bridge.listening = true; });
  server.on('error', (err) => {
    bridge.listening = false;
    console.log(`Agent listener not started (${err.code ?? err.message}). Is another pet running?`);
  });
  server.listen(AGENT_PORT, '127.0.0.1');
  const timer = setInterval(() => publish(null), MINUTE * 1000);
  return bridge;
}
