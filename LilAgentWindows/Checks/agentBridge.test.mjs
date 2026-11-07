import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import http from 'node:http';
import test from 'node:test';
import { startAgentBridge } from '../electron/agentBridge.js';

function harness(t) {
  let clock = 1_700_000_000_000;
  let poll;
  const published = [];
  t.mock.method(Date, 'now', () => clock);
  t.mock.method(http, 'createServer', () => Object.assign(new EventEmitter(), {
    listen() {},
    close() {},
  }));
  t.mock.method(globalThis, 'setInterval', (fn, delay) => {
    assert.equal(delay, 60_000);
    poll = fn;
    return 1;
  });
  t.mock.method(globalThis, 'clearInterval', () => {});
  const bridge = startAgentBridge({ onActivity: (value) => published.push(value) });
  return {
    bridge,
    published,
    event(provider, session, name, extra = {}) {
      bridge.handle({ session_id: session, hook_event_name: name, ...extra }, provider);
    },
    advance(seconds) { clock += seconds * 1000; },
    poll() { poll(); },
  };
}

test('summary ranks both providers and counts only working sessions', (t) => {
  const h = harness(t);
  h.event('claude', 'one', 'PreToolUse', { tool_name: 'Read', cwd: '/work/first' });
  h.advance(1);
  h.event('codex', 'two', 'PreToolUse', { tool_name: 'Bash', cwd: '/work/second' });
  assert.deepEqual(h.bridge.current, {
    activity: 'command', project: 'second', sessions: 2, reason: null, provider: 'codex',
  });
  h.event('claude', 'permission', 'PermissionRequest', { cwd: '/work/approval' });
  h.event('claude', 'idle', 'SessionStart', { cwd: '/work/idle' });
  assert.deepEqual(h.bridge.current, {
    activity: 'permission', project: 'approval', sessions: 2, reason: null, provider: 'claude',
  });
});

test('expiry removes stale working sessions before counting and preserves idle sessions', (t) => {
  const h = harness(t);
  h.event('claude', 'idle', 'SessionStart', { cwd: '/work/idle' });
  h.event('claude', 'reading', 'PreToolUse', { tool_name: 'Read', cwd: '/work/read' });
  h.event('codex', 'command', 'PreToolUse', { tool_name: 'Bash', cwd: '/work/run' });
  h.advance(900);
  h.poll();
  assert.equal(h.bridge.current.sessions, 2);
  h.advance(1);
  h.poll();
  assert.deepEqual(h.bridge.current, {
    activity: 'command', project: 'run', sessions: 1, reason: null, provider: 'codex',
  });
  h.advance(900);
  h.poll();
  assert.deepEqual(h.bridge.current, {
    activity: 'idle', project: 'idle', sessions: 0, reason: null, provider: 'claude',
  });
});

test('closing a Codex parent deletes adjacent helper entries only within that parent', (t) => {
  const h = harness(t);
  h.event('codex', 'root', 'PreToolUse', { tool_name: 'Bash', cwd: '/work/root' });
  for (const agent of ['a', 'b', 'c']) {
    h.event('codex', 'root', 'SubagentStart', { agent_id: agent, cwd: '/work/root' });
  }
  h.event('codex', 'root-other', 'SubagentStart', { agent_id: 'a', cwd: '/work/other' });
  h.event('claude', 'root', 'PreToolUse', { tool_name: 'Read', cwd: '/work/claude' });
  assert.equal(h.bridge.current.sessions, 6);
  h.advance(1);
  h.event('codex', 'root', 'Stop');
  assert.deepEqual(h.bridge.current, {
    activity: 'subagents', project: 'other', sessions: 2, reason: 'done', provider: 'codex',
  });
  h.event('codex', 'root-other', 'Interrupt');
  assert.deepEqual(h.bridge.current, {
    activity: 'reading', project: 'claude', sessions: 1, reason: null, provider: 'claude',
  });
});

test('unchanged polling stays silent and completion reasons publish once', (t) => {
  const h = harness(t);
  h.event('codex', 'one', 'UserPromptSubmit', { cwd: '/work/first' });
  h.poll();
  h.event('codex', 'one', 'PostModelRequest', { status: 'success' });
  h.event('codex', 'one', 'PostToolUse');
  assert.equal(h.published.length, 1);
  h.event('codex', 'one', 'Stop');
  assert.equal(h.published.length, 2);
  assert.deepEqual(h.published.at(-1), {
    activity: 'waiting', project: 'first', sessions: 0, reason: 'done', provider: 'codex',
  });
  h.poll();
  assert.equal(h.published.length, 2);
});
