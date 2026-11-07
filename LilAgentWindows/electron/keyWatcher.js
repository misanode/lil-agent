const US = {
  2: ['1', '!'], 3: ['2', '@'], 4: ['3', '#'], 5: ['4', '$'], 6: ['5', '%'], 7: ['6', '^'], 8: ['7', '&'], 9: ['8', '*'],
  10: ['9', '('], 11: ['0', ')'], 12: ['-', '_'], 13: ['=', '+'], 14: ['\b', '\b'], 15: ['\t', '\t'],
  16: ['q', 'Q'], 17: ['w', 'W'], 18: ['e', 'E'], 19: ['r', 'R'], 20: ['t', 'T'], 21: ['y', 'Y'], 22: ['u', 'U'], 23: ['i', 'I'],
  24: ['o', 'O'], 25: ['p', 'P'], 26: ['[', '{'], 27: [']', '}'], 28: ['\r', '\r'],
  30: ['a', 'A'], 31: ['s', 'S'], 32: ['d', 'D'], 33: ['f', 'F'], 34: ['g', 'G'], 35: ['h', 'H'], 36: ['j', 'J'], 37: ['k', 'K'],
  38: ['l', 'L'], 39: [';', ':'], 40: ["'", '"'], 41: ['`', '~'], 43: ['\\', '|'],
  44: ['z', 'Z'], 45: ['x', 'X'], 46: ['c', 'C'], 47: ['v', 'V'], 48: ['b', 'B'], 49: ['n', 'N'], 50: ['m', 'M'],
  51: [',', '<'], 52: ['.', '>'], 53: ['/', '?'], 57: [' ', ' '],
  3612: ['\r', '\r'], 55: ['*', '*'], 74: ['-', '-'], 78: ['+', '+'], 3637: ['/', '/'], 83: ['.', '.'],
  82: ['0', '0'], 79: ['1', '1'], 80: ['2', '2'], 81: ['3', '3'], 75: ['4', '4'], 76: ['5', '5'], 77: ['6', '6'], 71: ['7', '7'], 72: ['8', '8'], 73: ['9', '9'],
};
const DELETE = 14;

export function startKeyWatcher({ onKey, onKeyUp, onStatus }) {
  let hook = null;
  let running = false;
  let status = 'off';
  const down = new Set();
  let capsLock = false;
  const setStatus = (s) => {
    if (s === status) return;
    status = s;
    onStatus?.(s);
  };

  async function load() {
    if (hook) return hook;
    try {
      ({ uIOhook: hook } = await import('uiohook-napi'));
      hook.on('keydown', (e) => {
        if (e.keycode === 58) capsLock = !capsLock;
        if (down.has(e.keycode)) return;
        down.add(e.keycode);
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        const pair = US[e.keycode];
        if (!pair) return;
        let ch = pair[e.shiftKey ? 1 : 0];
        if (capsLock && /^[a-z]$/i.test(pair[0])) ch = e.shiftKey ? pair[0] : pair[1];
        onKey(e.keycode, e.keycode === DELETE ? '\u007f' : ch);
      });
      hook.on('keyup', (e) => {
        down.delete(e.keycode);
        onKeyUp(e.keycode);
      });
      return hook;
    } catch (err) {
      console.log(`Type along unavailable: ${err.message}`);
      setStatus('unavailable');
      return null;
    }
  }

  return {
    get status() { return status; },
    async sync(enabled) {
      if (enabled && !running) {
        const h = await load();
        if (!h) return;
        try {
          h.start();
          running = true;
          setStatus('ready');
        } catch (err) {
          console.log(`Type along: ${err.message}`);
          setStatus(process.platform === 'darwin' ? 'needs-permission' : 'unavailable');
        }
      } else if (!enabled && running) {
        hook?.stop();
        running = false;
        down.clear();
        setStatus('off');
      }
    },
    stop() {
      if (running) hook?.stop();
      running = false;
    },
  };
}
