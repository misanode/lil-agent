import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { AGENT_PORT } from './agentBridge.js';

const WIN = process.platform === 'win32';
const CURL = WIN ? 'curl' : '/usr/bin/curl';


const CLAUDE_FILE = path.join(os.homedir(), '.claude', 'settings.json');
const CLAUDE_MARKER = '# lil-agent';
const LEGACY_CLAUDE_MARKER = '# clawd-pet';
export const CLAUDE_COMMAND = `curl -s -m 2 -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:${AGENT_PORT}/claude || true ${CLAUDE_MARKER}`;
const TOOL_EVENTS = ['PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest'];
const OTHER_EVENTS = ['SessionStart', 'UserPromptSubmit', 'Notification', 'Stop', 'StopFailure', 'PreCompact', 'SessionEnd'];

const claudeOurs = (entry) => Array.isArray(entry?.hooks) && entry.hooks.some((h) => typeof h?.command === 'string'
  && (h.command.includes(CLAUDE_MARKER) || h.command.includes(LEGACY_CLAUDE_MARKER)));

function readJSON(file, { strict = false } = {}) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return {};
  }
  if (!text.trim()) return {};
  try {
    const v = JSON.parse(text);
    if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error('not a JSON object');
    return v;
  } catch (err) {
    throw new Error(strict ? `${file} must contain a JSON object. No changes were made.` : `Couldn't read ${file}: ${err.message}`);
  }
}

function writeJSON(file, value, backupName) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const backup = backupName(file);
  if (fs.existsSync(file) && !fs.existsSync(backup)) fs.copyFileSync(file, backup);
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n');
  fs.renameSync(tmp, file);
}

export const claudeHooks = {
  file: CLAUDE_FILE,
  installed() {
    try {
      const hooks = readJSON(CLAUDE_FILE).hooks;
      return !!hooks && [...TOOL_EVENTS, ...OTHER_EVENTS].every((e) => Array.isArray(hooks[e]) && hooks[e].some(claudeOurs));
    } catch {
      return false;
    }
  },
  install() {
    const s = readJSON(CLAUDE_FILE);
    const hooks = s.hooks && typeof s.hooks === 'object' ? s.hooks : {};
    const hook = { type: 'command', command: CLAUDE_COMMAND, timeout: 5 };
    for (const event of [...TOOL_EVENTS, ...OTHER_EVENTS]) {
      const entries = Array.isArray(hooks[event]) ? hooks[event].filter((e) => !claudeOurs(e)) : [];
      entries.push(TOOL_EVENTS.includes(event) ? { matcher: '*', hooks: [hook] } : { hooks: [hook] });
      hooks[event] = entries;
    }
    s.hooks = hooks;
    writeJSON(CLAUDE_FILE, s, (f) => `${f}.lil-agent-backup`);
  },
  uninstall() {
    const s = readJSON(CLAUDE_FILE);
    if (!s.hooks || typeof s.hooks !== 'object') return;
    for (const [event, entries] of Object.entries(s.hooks)) {
      if (!Array.isArray(entries)) continue;
      const kept = entries.filter((e) => !claudeOurs(e));
      if (kept.length) s.hooks[event] = kept;
      else delete s.hooks[event];
    }
    if (!Object.keys(s.hooks).length) delete s.hooks;
    writeJSON(CLAUDE_FILE, s, (f) => `${f}.lil-agent-backup`);
  },
};


const CODEX_MARKER = '# lil-agent-codex';
const LEGACY_CODEX_MARKER = '# clawd-pet-codex';
export const CODEX_COMMAND = `(${CURL} -s --connect-timeout 0.2 -m 0.5 -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:${AGENT_PORT}/codex || true); printf '%s\\n' '{}' ${CODEX_MARKER}`;
const CODEX_EVENTS = ['SessionStart', 'SessionEnd', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PermissionRequest', 'PreCompact',
  'PostCompact', 'PreModelRequest', 'PostModelRequest', 'SubagentStart', 'SubagentStop', 'Stop', 'Interrupt'];

const codexFile = () => {
  const env = process.env.CODEX_HOME;
  return path.join(env ? env : path.join(os.homedir(), '.codex'), 'hooks.json');
};
const codexOurs = (h) => typeof h?.command === 'string' && (h.command.endsWith(CODEX_MARKER) || h.command.endsWith(LEGACY_CODEX_MARKER));
const LEGACY_CODEX_COMMAND = () => CODEX_COMMAND.replace(CODEX_MARKER, LEGACY_CODEX_MARKER);

function readCodex(file) {
  const root = readJSON(file, { strict: true });
  if (root.hooks !== undefined) {
    if (!root.hooks || typeof root.hooks !== 'object' || Array.isArray(root.hooks)) throw new Error('Expected a hooks object. No changes were made.');
    for (const [event, groups] of Object.entries(root.hooks)) {
      if (!Array.isArray(groups) || !groups.every((g) => g && Array.isArray(g.hooks))) throw new Error(`Invalid hook groups for ${event}. No changes were made.`);
    }
  }
  return root;
}

function removingOurs(hooks) {
  const result = { ...hooks };
  for (const [event, groups] of Object.entries(hooks)) {
    if (!Array.isArray(groups)) continue;
    const kept = groups.flatMap((g) => {
      if (!Array.isArray(g.hooks) || !g.hooks.some(codexOurs)) return [g];
      const remaining = g.hooks.filter((h) => !codexOurs(h));
      return remaining.length ? [{ ...g, hooks: remaining }] : [];
    });
    if (kept.length) result[event] = kept;
    else delete result[event];
  }
  return result;
}

export const codexHooks = {
  get file() { return codexFile(); },
  installed() {
    try {
      const hooks = readCodex(codexFile()).hooks;
      return !!hooks && CODEX_EVENTS.every((e) => Array.isArray(hooks[e]) && hooks[e].some((g) =>
        g.matcher === undefined && Array.isArray(g.hooks) && g.hooks.some((h) => (h.command === CODEX_COMMAND || h.command === LEGACY_CODEX_COMMAND()) && h.type === 'command')));
    } catch {
      return false;
    }
  },
  install() {
    const file = codexFile();
    const root = readCodex(file);
    const hooks = removingOurs(root.hooks ?? {});
    for (const event of CODEX_EVENTS) {
      const groups = Array.isArray(hooks[event]) ? hooks[event] : [];
      groups.push({ hooks: [{ type: 'command', command: CODEX_COMMAND, timeout: 2 }] });
      hooks[event] = groups;
    }
    root.hooks = hooks;
    writeJSON(file, root, (f) => `${f}.lil-agent-backup`);
  },
  uninstall() {
    const file = codexFile();
    if (!fs.existsSync(file)) return;
    const root = readCodex(file);
    const hooks = removingOurs(root.hooks ?? {});
    if (Object.keys(hooks).length) root.hooks = hooks;
    else delete root.hooks;
    writeJSON(file, root, (f) => `${f}.lil-agent-backup`);
  },
};
