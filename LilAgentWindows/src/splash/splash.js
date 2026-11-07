const LOGO_REVEAL = 220;
const WORDMARK_RISE = 420;
const WORDMARK_FADE = 260;
const SPIN_PERIOD = 900;
const RISE = 'cubic-bezier(0.22, 1, 0.36, 1)';

const api = window.splash;
const params = new URLSearchParams(location.search);
const root = document.getElementById('splash');
const $ = (id) => document.getElementById(id);
const card = $('card'), logo = $('logo'), wordmark = $('wordmark');
const spinner = document.querySelector('.spinner');
const arc = document.querySelector('.arc');
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

for (const key of ['gap', 'spinner', 'edge']) {
  const v = Number(params.get(key));
  if (v > 0) document.documentElement.style.setProperty(`--${key}`, `${v}px`);
}
const name = params.get('name');
if (name) {
  document.title = name;
  root.setAttribute('aria-label', `${name} is loading`);
}

const fade = (el, delay, duration) => el.animate([{ opacity: 0 }, { opacity: 1 }], { delay, duration, easing: 'ease-out', fill: 'both' }).finished;

async function enter() {
  await Promise.all([card, logo, wordmark].map((img) => img.decode().catch(() => {})));
  if (reduceMotion) {
    arc.style.strokeDasharray = 'none';
    arc.animate([{ opacity: 1 }, { opacity: 0.45 }], { delay: 250, duration: 800, direction: 'alternate', iterations: Infinity });
    await Promise.all([card, logo, wordmark, spinner].map((el) => fade(el, 0, 250)));
    return;
  }
  spinner.animate([{ transform: 'rotate(0deg)' }, { transform: 'rotate(360deg)' }], { duration: SPIN_PERIOD, iterations: Infinity });
  fade(card, 0, 160);
  fade(logo, 0, LOGO_REVEAL);
  fade(spinner, 0, 200);
  const lift = innerWidth * (Number(params.get('lift')) || 18 / 340);
  await Promise.all([
    fade(wordmark, LOGO_REVEAL, WORDMARK_FADE),
    wordmark.animate([{ transform: `translateY(${lift}px)` }, { transform: 'translateY(0)' }],
      { delay: LOGO_REVEAL, duration: WORDMARK_RISE, easing: RISE, fill: 'both' }).finished,
  ]);
}

api?.onDismiss((ms) => root.animate([{ opacity: 1 }, { opacity: 0 }], { duration: ms, easing: 'ease-in', fill: 'forwards' }));
enter().catch(() => {}).finally(() => api?.entered());
