(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const isWindows = /Windows/i.test(navigator.userAgent);

  /* Platform-aware labels and header button */
  if (isWindows) {
    $$('.mod-label').forEach((el) => { el.textContent = 'Ctrl'; });
    const mod = $('#key-mod');
    if (mod) mod.textContent = 'Ctrl';
    const link = $('[data-platform-link]');
    const img = $('[data-platform-img]');
    if (link && img) {
      link.href = 'https://github.com/misanode/lil-agent/releases/latest/download/Lil-Agent-Windows-Setup.exe';
      img.src = 'assets/get-for-windows.svg';
      img.alt = 'Get for Windows';
      img.width = 288;
    }
  }

  /* Floating download button: shows once the hero buttons scroll out of view */
  const floatGet = $('.float-get');
  const heroGet = $('#hero-get');
  if (floatGet && heroGet && 'IntersectionObserver' in window) {
    new IntersectionObserver(([entry]) => {
      const past = !entry.isIntersecting && entry.boundingClientRect.top < 0;
      floatGet.classList.toggle('is-shown', past);
      floatGet.tabIndex = past ? 0 : -1;
      floatGet.setAttribute('aria-hidden', String(!past));
    }).observe(heroGet);
  }

  /* Scroll reveal */
  const revealables = $$('[data-reveal]');
  if ('IntersectionObserver' in window && !reduceMotion) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -10% 0px' });
    revealables.forEach((el) => io.observe(el));
  } else {
    revealables.forEach((el) => el.classList.add('is-in'));
  }

  /* Stage tilt: starts slightly tilted back, flattens as you scroll */
  const stage = $('#desktop-demo');
  if (stage && !reduceMotion) {
    let ticking = false;
    const update = () => {
      const r = stage.getBoundingClientRect();
      const p = Math.min(Math.max(1 - (r.top - 80) / (innerHeight * .7), 0), 1);
      stage.style.setProperty('--tilt', `${(1 - p) * 12}deg`);
      stage.style.setProperty('--scale', String(.95 + p * .05));
      ticking = false;
    };
    addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    update();
  }

  /* Menubar clock */
  const clock = $('#clock');
  const tick = () => { if (clock) { const d = new Date(); clock.textContent = `${d.toLocaleDateString([], { weekday: 'short' })} ${d.toLocaleDateString([], { month: 'short', day: 'numeric' })}  ${d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`; } };
  tick(); setInterval(tick, 15000);

  /* Streaming text: reveal word by word */
  const stream = (el, text, gap = 55) => {
    clearTimeout(el._t);
    if (reduceMotion) { el.textContent = text; return; }
    el.replaceChildren(...text.split(' ').map((w, i, a) => {
      const s = document.createElement('span');
      s.className = 'sw';
      s.textContent = w + (i < a.length - 1 ? ' ' : '');
      return s;
    }));
    const words = [...el.children];
    let i = 0;
    const step = () => { if (i < words.length) { words[i++].classList.add('on'); el._t = setTimeout(step, gap); } };
    el._t = setTimeout(step, 120);
  };

  /* Demo statuses + fake terminal */
  const statuses = {
    working: {
      bubble: 'Thinking things through…', status: 'Your agent is working.', title: '<span class="spin">✳</span> Dark mode toggle',
      lines: [
        '<span class="g">●</span> <span class="b">Read</span>(src/settings.tsx)',
        '  <span class="dim">⎿  Read 142 lines</span>',
        '<span class="g">●</span> <span class="b">Update</span>(src/settings.tsx)',
        '  <span class="dim">⎿  Updated with 18 additions</span>',
        '<span class="o"><span class="spin">✳</span> Thinking…</span> <span class="dim">(12s · esc to interrupt)</span>',
      ],
    },
    attention: {
      bubble: 'A little help, please?', status: 'Your agent needs you.', title: 'Dark mode toggle',
      lines: [
        '<span class="g">●</span> <span class="b">Bash</span>(npm run migrate)',
        '  <span class="dim">⎿  Waiting…</span>',
        '<span class="o b">Do you want to proceed?</span>',
        '<span class="sel">❯ 1. Yes</span>',
        '<span class="dim">  2. No, and tell Claude what to do differently</span>',
      ],
    },
    done: {
      bubble: 'All done. Your turn!', status: 'Your agent has finished.', title: 'Dark mode toggle',
      lines: [
        '<span class="g">●</span> <span class="b">Bash</span>(npm test)',
        '  <span class="dim">⎿  42 passing</span>',
        '● Added a dark mode toggle to Settings. Tests pass.',
        '<span class="dim">✻ Worked for 42s · done</span>',
      ],
    },
  };
  const bubble = $('#bubble-text');
  const statusText = $('#status-text');
  const term = $('#term');
  const statusButtons = $$('[data-status]');
  const thumb = $('.seg-thumb');
  const moveThumb = () => {
    const active = statusButtons.find((b) => b.getAttribute('aria-pressed') === 'true');
    if (!thumb || !active) return;
    thumb.style.width = `${active.offsetWidth}px`;
    thumb.style.transform = `translateX(${active.offsetLeft}px)`;
  };
  moveThumb();
  addEventListener('resize', moveThumb);
  document.fonts?.ready.then(moveThumb);
  let termTimer;

  const prompt = '<span class="user">&gt; add a dark mode toggle to settings</span>';
  const termTitle = $('#term-title');
  const printLines = (body) => {
    const lines = [prompt, ...body];
    clearTimeout(termTimer);
    term.replaceChildren();
    let i = 0;
    const next = () => {
      if (i >= lines.length) return;
      const div = document.createElement('div');
      div.className = 'term-line';
      div.innerHTML = lines[i++];
      term.append(div);
      termTimer = setTimeout(next, reduceMotion ? 0 : 420);
    };
    next();
  };

  const live = {};
  const stageTimers = [];
  const playStageAnimation = (key) => {
    stageTimers.splice(0).forEach(clearTimeout);
    const m = live.stage;
    if (!m) return;
    if (key === 'working') {
      // Matches the terminal: Read → Update → Thinking
      m.setState('reading');
      stageTimers.push(setTimeout(() => m.setState('typing'), 1250));
      stageTimers.push(setTimeout(() => m.setState('thinking'), 2100));
    } else if (key === 'attention') {
      m.setState('permission');
    } else if (key === 'done') {
      m.setState('done', { then: 'idle' });
    }
  };
  let currentStatus = 'working';

  const setStatus = (key) => {
    const s = statuses[key];
    if (!s) return;
    currentStatus = key;
    playStageAnimation(key);
    statusButtons.forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.status === key)));
    moveThumb();
    stage.dataset.state = key;
    stream(bubble, s.bubble);
    statusText.textContent = s.status;
    if (termTitle) termTitle.innerHTML = `lil-agent — ${s.title} — claude — 80×24`;
    printLines(s.lines);
  };

  // Autoplay through statuses while visible, until the visitor takes over
  const order = ['working', 'attention', 'done'];
  let autoIndex = 0;
  let autoTimer = null;
  let userTookOver = false;
  const startAuto = () => {
    if (userTookOver || reduceMotion || autoTimer) return;
    autoTimer = setInterval(() => { autoIndex = (autoIndex + 1) % order.length; setStatus(order[autoIndex]); }, 4200);
  };
  const stopAuto = () => { clearInterval(autoTimer); autoTimer = null; };
  statusButtons.forEach((b) => b.addEventListener('click', () => { userTookOver = true; stopAuto(); setStatus(b.dataset.status); }));
  if (stage) {
    setTimeout(() => setStatus('working'), reduceMotion ? 0 : 1900);
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(([e]) => (e.isIntersecting ? startAuto() : stopAuto()), { threshold: .4 }).observe(stage);
    }
  }

  /* Compare slider */
  const compare = $('#compare');
  const range = compare && $('.compare-range', compare);
  if (range) range.addEventListener('input', () => compare.style.setProperty('--x', `${range.value}%`));

  /* Pet & play: drag with spring-back, tap to hop */
  const playPet = $('#play-pet');
  if (playPet) {
    let sx = 0, sy = 0, moved = false, dragging = false;
    playPet.addEventListener('pointerdown', (e) => {
      dragging = true; moved = false; sx = e.clientX; sy = e.clientY;
      playPet.setPointerCapture(e.pointerId);
      playPet.classList.add('dragging');
    });
    playPet.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      const dx = e.clientX - sx, dy = e.clientY - sy;
      if (Math.abs(dx) + Math.abs(dy) > 4) moved = true;
      playPet.style.transform = `translate(${dx}px, ${dy}px) rotate(${dx * .08}deg)`;
    });
    const release = () => {
      if (!dragging) return;
      dragging = false;
      playPet.classList.remove('dragging');
      playPet.style.transform = '';
      if (!moved) { playPet.classList.remove('hop'); void playPet.offsetWidth; playPet.classList.add('hop'); }
    };
    playPet.addEventListener('pointerup', release);
    playPet.addEventListener('pointercancel', release);
  }

  /* Pet & play: cycle through the app's moods (same list as its Moods settings) */
  const MOODS = [
    ['Coffee break', 'coffee'], ['Workout', 'workout'], ['Meditate', 'meditate'], ['Bright idea', 'idea'],
    ['Happy', 'happy'], ['Excited', 'excited'], ['Curious', 'curious'], ['Sad', 'sad'],
    ['Dance', 'dance'], ['Wave', 'wave'], ['Annoyed', 'annoyed'], ['Dizzy', 'dizzy'],
  ];
  const moodName = $('#mood-name');
  let moodIndex = -1;
  $$('[data-mood-step]').forEach((b) => b.addEventListener('click', () => {
    moodIndex = (moodIndex + Number(b.dataset.moodStep) + MOODS.length) % MOODS.length;
    const [label, state] = MOODS[moodIndex];
    moodName.textContent = label;
    live.play?.setState(state, { then: 'idle' });
  }));

  /* Make it yours: size */
  const sizeRange = $('#size-range');
  const sizePet = $('#size-pet');
  if (sizeRange && sizePet) sizeRange.addEventListener('input', () => {
    sizePet.style.transform = `scale(${sizeRange.value / 100})`;
    live.size?.setSize(.6 * sizeRange.value / 100);
  });

  /* Show or hide: keycaps + the real shortcut */
  const keysArea = $('.keys-area');
  const keyMod = $('#key-mod');
  const keySlash = $('#key-slash');
  const toggleKeysPet = () => {
    [keyMod, keySlash].forEach((k) => k.classList.add('pressed'));
    setTimeout(() => [keyMod, keySlash].forEach((k) => k.classList.remove('pressed')), 140);
    const hidden = keysArea.classList.toggle('hidden-pet');
    if (!hidden) live.keys?.setState('wave', { then: 'idle' });
  };
  [keyMod, keySlash].forEach((k) => k && k.addEventListener('click', toggleKeysPet));
  addEventListener('keydown', (e) => {
    if (e.key === '\\' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); toggleKeysPet(); }
  });

  /* CTA keycaps press loop */
  const bigMod = $('.bigkey-mod');
  const bigSlash = $('.bigkey-slash');
  if (bigMod && !reduceMotion) {
    setInterval(() => {
      bigMod.classList.add('pressed');
      setTimeout(() => bigSlash.classList.add('pressed'), 160);
      setTimeout(() => { bigMod.classList.remove('pressed'); bigSlash.classList.remove('pressed'); }, 620);
    }, 2600);
  }

  /* Live 3D mascots: the app's real models, states and animation clips.
     Needs http(s) — when opened from file:// the PNG fallbacks stay. */
  const mountLive = async () => {
    if (location.protocol === 'file:') return;
    let mod;
    try { mod = await import('./vendor/mascot-preview.js'); } catch (err) { console.warn('Live mascots unavailable', err); return; }
    const spots = [
      { key: 'stage', character: 'clawd', size: .4, state: 'reading', statusText: true },
      { key: 'play', character: 'clawd', size: .5, state: 'idle', interactive: true },
      { key: 'size', character: 'codex', size: .6, state: 'idle' },
      { key: 'keys', character: 'clawd', size: .62, state: 'idle' },
      { key: 'compare-clawd', character: 'clawd', size: .58, state: 'idle' },
      { key: 'compare-codex', character: 'codex', size: .62, state: 'idle' },
    ];
    for (const spot of spots) {
      const el = $(`[data-live="${spot.key}"]`);
      if (!el) continue;
      const host = el.parentElement;
      const start = () => mod.mountMascot(el, { ...spot, onReady: () => host.classList.add('is-live') })
        .then((m) => {
          live[spot.key] = m;
          if (spot.key === 'stage') playStageAnimation(currentStatus);
          if (spot.key === 'size' && sizeRange) m.setSize(.6 * sizeRange.value / 100);
        })
        .catch((err) => console.warn(`Live mascot (${spot.key}) failed`, err));
      // Mount each one when it first comes near the viewport
      const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) { io.disconnect(); start(); } }, { rootMargin: '300px' });
      io.observe(host);
    }
  };
  mountLive();

  /* FAQ: smooth height animation */
  $$('.faq-list details').forEach((d) => {
    const summary = $('summary', d);
    const body = $('.faq-answer', d);
    summary.addEventListener('click', (e) => {
      if (reduceMotion || !body.animate) return;
      e.preventDefault();
      if (d.open) {
        const a = body.animate([{ height: `${body.offsetHeight}px`, opacity: 1 }, { height: '0px', opacity: 0 }], { duration: 260, easing: 'cubic-bezier(.22,1,.36,1)' });
        d.classList.add('closing');
        a.onfinish = () => { d.open = false; d.classList.remove('closing'); };
      } else {
        d.open = true;
        body.animate([{ height: '0px', opacity: 0 }, { height: `${body.offsetHeight}px`, opacity: 1 }], { duration: 320, easing: 'cubic-bezier(.22,1,.36,1)' });
      }
    });
  });
})();
