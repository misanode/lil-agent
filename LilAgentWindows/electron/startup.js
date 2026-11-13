export const SPLASH = { cardWidth: 400, aspect: 598 / 1000, gap: 18, spinner: 20, edge: 2, fadeOutMs: 180, enterLimitMs: 4000 };

export function splashBounds(workArea) {
  const extra = SPLASH.gap + SPLASH.spinner + SPLASH.edge;
  const width = Math.floor(Math.min(SPLASH.cardWidth, workArea.width * 0.8, (workArea.height * 0.8 - extra) / SPLASH.aspect));
  const height = Math.round(width * SPLASH.aspect) + extra;
  return {
    x: Math.round(workArea.x + (workArea.width - width) / 2),
    y: Math.round(workArea.y + (workArea.height - height) / 2),
    width,
    height,
  };
}

export function createStartup({ entered = false, onFinish = () => {}, onFail = () => {} } = {}) {
  let phase = 'starting';
  let isEntered = entered;
  let ready = false;
  const finishIfReady = () => {
    if (!isEntered || !ready) return;
    phase = 'finished';
    onFinish();
  };
  return {
    get phase() { return phase; },
    entranceDone() {
      if (phase !== 'starting') return;
      isEntered = true;
      finishIfReady();
    },
    appReady() {
      if (phase !== 'starting') return;
      ready = true;
      finishIfReady();
    },
    fail(message) {
      if (phase !== 'starting') return;
      phase = 'failed';
      onFail(message);
    },
    cancel() {
      if (phase === 'starting') phase = 'cancelled';
    },
  };
}
