export const UPDATE_INTERVAL_MS = 24 * 60 * 60 * 1000;

export function compareVersions(a, b) {
  const parts = (v) => String(v).split('-')[0].split('.').map((n) => Number.parseInt(n, 10) || 0);
  const x = parts(a), y = parts(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const l = x[i] ?? 0, r = y[i] ?? 0;
    if (l !== r) return l < r ? -1 : 1;
  }
  return 0;
}

export function evaluateRelease({ statusCode, body, current, repo }) {
  if (statusCode === 404) return { status: 'current' };
  if (statusCode !== 200 || typeof body?.tag_name !== 'string') return { status: 'failed' };
  const latest = body.tag_name.replace(/^v/i, '');
  if (compareVersions(latest, current) <= 0) return { status: 'current' };
  const prefix = `https://github.com/${repo}/`;
  const page = typeof body.html_url === 'string' && body.html_url.startsWith(prefix) ? body.html_url : `${prefix}releases/latest`;
  return { status: 'available', latest, page };
}

export function createUpdateChecker({ current, repo, userAgent, fetch, onChange = () => {} }) {
  let state = { status: 'idle' };
  let timer = null;
  const set = (next) => {
    if (JSON.stringify(next) === JSON.stringify(state)) return;
    state = next;
    onChange(state);
  };
  async function check({ quiet = false } = {}) {
    if (state.status === 'checking') return;
    const previous = state;
    if (!quiet) set({ status: 'checking' });
    let result;
    try {
      const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
        headers: { Accept: 'application/vnd.github+json', 'User-Agent': userAgent },
      });
      const body = res.status === 200 ? await res.json().catch(() => null) : null;
      result = evaluateRelease({ statusCode: res.status, body, current, repo });
    } catch {
      result = { status: 'failed' };
    }
    if (result.status === 'failed' && quiet) set(previous.status === 'checking' ? { status: 'idle' } : previous);
    else set(result);
  }
  return {
    get state() { return state; },
    check,
    start() {
      check({ quiet: true });
      timer = setInterval(() => check({ quiet: true }), UPDATE_INTERVAL_MS);
    },
    stop() { clearInterval(timer); },
  };
}
