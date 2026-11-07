import { now } from '../core/util.js';
import { allows } from '../character/locomotion.js';

const NEEDS_YOU = new Set(['permission', 'question', 'attention']);
export const WORKING = new Set(['thinking', 'typing', 'reading', 'searching', 'command', 'planning', 'subagents', 'compacting', 'error']);
const AGENT_STATES = new Set([...WORKING, ...NEEDS_YOU, 'waiting', 'done']);
const INTERRUPTIBLE = new Set([...AGENT_STATES, 'idle', 'walk', 'curious', 'dance', 'coffee', 'workout', 'meditate', 'idea', 'donehold']);
const MIN_WORK_HOLD = 1.6;
const MIN_THINK_HOLD = 2.5;
const SLEEPING = new Set(['sleep', 'sleepy']);
const HELD = new Set(['carried', 'drop', 'settle']);
const WAIT_AT_DESK = 20;
const USER_TYPING_HOLD = 1.6;
const PREVIEW_LENGTH = 5;

export class AgentDirector {
  constructor(pet, settings) {
    this.pet = pet;
    this.settings = settings;
    this.activity = null;
    this.music = false;
    this.pendingDone = false;
    this.waitingSince = null;
    this.dozing = false;
    this.idleAsleep = false;
    this.userTypingUntil = 0;
    this.managing = false;
    this.held = new Set();
    this.previewing = null;
  }

  setAgent(a) {
    this.activity = a;
    if (a?.reason === 'done') this.pendingDone = true;
  }

  onKey(ch, code = -1) {
    if (!this.settings.typeAlong) return;
    this.userTypingUntil = now() + USER_TYPING_HOLD;
    if (code >= 0) this.held.add(code);
    this.pet.typeChar(ch, code);
  }

  onKeyUp(code) {
    if (!this.held.delete(code)) return;
    this.userTypingUntil = now() + USER_TYPING_HOLD;
    this.pet.releaseKey(code);
  }

  setMusic(playing) { this.music = playing; }

  get userTyping() { return !!this.settings.typeAlong && (now() < this.userTypingUntil || this.held.size > 0); }

  get desired() {
    const a = this.settings.agentReactions ? this.activity?.activity : null;
    const agent = a && allows(this.settings, a) ? a : null;
    if (agent && NEEDS_YOU.has(agent)) return agent;
    if (this.userTyping) return 'typing';
    if (agent && WORKING.has(agent)) return agent;
    if (this.settings.musicDance && this.music) return 'dance';
    if (agent === 'waiting' && now() - (this.waitingSince ?? now()) < WAIT_AT_DESK) return 'waiting';
    return null;
  }

  setDozing(on) {
    this.dozing = on;
    this.syncAutoWake();
  }

  setIdleAsleep(on) {
    this.idleAsleep = on;
    this.syncAutoWake();
  }

  syncAutoWake() { this.pet.allowAutoWake = !(this.dozing || this.idleAsleep); }

  preview(state) {
    this.previewing = { state, until: now() + PREVIEW_LENGTH };
    this.managing = false;
    this.pendingDone = false;
    this.pet.trigger(state, { then: 'idle' }, true);
  }

  update() {
    const t = now();
    const pet = this.pet;
    const p = this.previewing;
    if (p) {
      if (t < p.until) return;
      this.previewing = null;
      if (pet.stateName === p.state) pet.trigger('idle', {}, true);
    }
    const current = pet.stateName;
    const desired = this.desired;
    const agentWaiting = this.settings.agentReactions && this.activity?.activity === 'waiting';
    this.waitingSince = agentWaiting ? (this.waitingSince ?? t) : null;

    if (!desired) {
      this.pendingDone = false;
      if (this.dozing) this.setDozing(false);
      if (this.managing && (AGENT_STATES.has(current) || current === 'dance')) pet.trigger('idle', {}, true);
      this.managing = false;
      return;
    }

    if (NEEDS_YOU.has(desired)) {
      this.pendingDone = false;
      if (this.dozing) this.setDozing(false);
      if (current === desired || HELD.has(current)) return;
      this.managing = true;
      if (SLEEPING.has(current)) pet.trigger('surprised', { then: desired }, true);
      else pet.trigger(desired, {}, true);
      return;
    }

    if (desired === 'typing' && this.userTyping) {
      this.pendingDone = false;
      if (this.dozing) this.setDozing(false);
      if (HELD.has(current) || (current === 'typing' && this.managing)) return;
      this.managing = true;
      pet.trigger('typing', {}, true);
      return;
    }

    if (this.dozing) {
      if (desired === 'waiting') {
        if (SLEEPING.has(current) || !INTERRUPTIBLE.has(current)) return;
        this.setDozing(false);
        this.waitingSince = t;
      } else {
        this.setDozing(false);
        if (SLEEPING.has(current)) {
          this.managing = true;
          pet.trigger('wake', { then: desired }, true);
          return;
        }
      }
    }

    if (SLEEPING.has(current) || !INTERRUPTIBLE.has(current)) return;

    if (this.pendingDone && !allows(this.settings, 'done')) this.pendingDone = false;
    if (this.pendingDone && !WORKING.has(desired)) {
      this.pendingDone = false;
      this.managing = true;
      pet.trigger('done', { then: 'idle' }, true);
      return;
    }
    if (current === desired && this.managing) return;
    if ((current === 'done' || current === 'donehold') && !WORKING.has(desired)) return;
    if (this.managing && WORKING.has(current) && WORKING.has(desired)
      && pet.fsm.time < (desired === 'thinking' ? MIN_THINK_HOLD : MIN_WORK_HOLD)) return;
    this.managing = true;
    pet.trigger(desired, desired === 'dance' ? { loop: true } : {}, true);
  }
}
