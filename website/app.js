(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const root = document.documentElement;
  const wideMQ = matchMedia("(min-width: 992px)");
  const narrowMQ = matchMedia("(max-width: 991px)");
  const phoneMQ = matchMedia("(max-width: 767px)");
  const tinyMQ = matchMedia("(max-width: 480px)");
  const reduceMQ = matchMedia("(prefers-reduced-motion: reduce)");
  const hoverMQ = matchMedia("(hover: hover)");
  const SVGNS = "http://www.w3.org/2000/svg";
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const span = (v, a, b) => (b > a ? clamp((v - a) / (b - a), 0, 1) : v >= b ? 1 : 0);
  const smooth = (t) => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
  const phaseT = (p, a, b) => smooth(span(p, a, b));
  // GSAP's curves, so timings read the same as the reference
  const quadInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
  const quartOut = (t) => 1 - Math.pow(1 - t, 4);
  const backOut2 = (t) => 1 + 3 * Math.pow(t - 1, 3) + 2 * Math.pow(t - 1, 2);
  const follow = (cur, tgt, amount, dr) => { const v = cur + (tgt - cur) * (1 - Math.pow(1 - amount, dr)); return Math.abs(tgt - v) < 0.0004 ? tgt : v; };
  const reduced = () => reduceMQ.matches;

  // ---- One frame loop for everything that moves ---------------------------------------------------------------------
  const tasks = new Set();
  let rafId = 0, lastT = 0;
  const loop = (t) => {
    const dt = lastT ? Math.min(100, t - lastT) : 1000 / 60;
    lastT = t;
    tasks.forEach((fn) => fn(t, dt, dt / (1000 / 60)));
    rafId = tasks.size ? requestAnimationFrame(loop) : 0;
    if (!rafId) lastT = 0;
  };
  const addTask = (fn) => { tasks.add(fn); if (!rafId) { lastT = 0; rafId = requestAnimationFrame(loop); } };
  const removeTask = (fn) => tasks.delete(fn);

  // Runs start/stop as el enters and leaves the screen (and the tab is visible).
  function whileVisible(el, start, stop, margin = "80px 0px") {
    let on = false, seen = false;
    const sync = () => { const want = seen && !document.hidden; if (want !== on) { on = want; (on ? start : stop)(); } };
    new IntersectionObserver((es) => { seen = es[es.length - 1].isIntersecting; sync(); }, { rootMargin: margin }).observe(el);
    document.addEventListener("visibilitychange", sync);
  }
  // CSS animations hold still while their section is off screen.
  $$(".strip, .hero, .story, .feats, .ex, .foot").forEach((el) => whileVisible(el, () => el.classList.remove("paused"), () => el.classList.add("paused")));

  // ---- Copy ---------------------------------------------------------------------------------------------------------
  const liveRegion = $("[data-live-region]");
  $$("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.getAttribute("data-copy");
      let ok = false;
      try { await navigator.clipboard.writeText(text); ok = true; } catch (_) {
        const ta = document.createElement("textarea");
        ta.value = text; ta.setAttribute("readonly", ""); ta.style.cssText = "position:fixed;top:0;left:0;opacity:0";
        document.body.appendChild(ta); ta.select();
        try { ok = document.execCommand("copy"); } catch (_) { ok = false; }
        ta.remove();
      }
      if (!btn.dataset.label) btn.dataset.label = btn.textContent;
      btn.textContent = ok ? "Copied" : "Press ⌘C";
      liveRegion.textContent = ok ? "Install command copied" : "";
      clearTimeout(btn._t);
      btn._t = setTimeout(() => { btn.textContent = btn.dataset.label; }, 1600);
    });
  });

  // ---- Letters ripple on hover: each one rises, dips and settles over 1 s, 60 ms after the one before -------------------
  const WAVE_KF = [{ transform: "translateY(0) rotate(0deg)" }, { transform: "translateY(-20%) rotate(-5deg)" }, { transform: "translateY(20%) rotate(5deg)" }, { transform: "translateY(0) rotate(0deg)" }];
  function splitLetters(host) {
    const chars = [];
    [...host.childNodes].forEach((node) => {
      if (node.nodeType !== 3 || !node.textContent.trim()) return;
      // one box for the whole label (so flex gaps don't land between words), words inside it, letters inside those
      const box = document.createElement("span");
      box.className = "wave"; box.setAttribute("aria-hidden", "true");
      node.textContent.trim().split(/(\s+)/).forEach((part) => {
        if (!part) return;
        if (/^\s+$/.test(part)) { box.append(" "); return; }
        const w = document.createElement("span"); w.className = "wave-w";
        [...part].forEach((ch) => { const c = document.createElement("span"); c.className = "wave-l"; c.textContent = ch; w.append(c); chars.push(c); });
        box.append(w);
      });
      const sr = document.createElement("span"); sr.className = "sr-only"; sr.textContent = node.textContent.trim();
      const frag = document.createDocumentFragment();
      frag.append(sr, box);
      node.replaceWith(frag);
    });
    return chars;
  }
  function ripple(el, hosts) {
    const chars = hosts.flatMap(splitLetters);
    if (!chars.length) return;
    let anims = [];
    el.addEventListener("mouseenter", () => {
      if (!hoverMQ.matches || reduced()) return;
      anims.forEach((a) => a.cancel());
      anims = chars.map((c, i) => c.animate(WAVE_KF, { duration: 1000, delay: i * 60, easing: "linear" }));
    });
    el.addEventListener("mouseleave", () => {
      if (!anims.length) return;
      const now = chars.map((c) => getComputedStyle(c).transform);
      anims.forEach((a) => a.cancel());
      anims = chars.map((c, i) => (now[i] === "none" ? null : c.animate([{ transform: now[i] }, { transform: "none" }], { duration: 200, easing: "linear" }))).filter(Boolean);
    });
  }
  $$(".btn").forEach((btn) => { const lg = $(".lg", btn); ripple(btn, lg ? [lg, $(".sm", btn)] : [btn]); });
  $$(".nav-links a, .seg a, .banner a, .more").forEach((a) => ripple(a, [a]));
  $$(".prod-cta").forEach((cta) => ripple(cta, [cta]));

  // ---- Nav: menu, scroll hide on narrow screens, bottom bar -----------------------------------------------------------
  const nav = $("[data-nav]"), burger = $("[data-burger]"), menu = $("[data-menu]");
  const MENU_KF = [{ transform: "translateY(-100%)", clipPath: "inset(100% 0 0 0)" }, { transform: "none", clipPath: "inset(0 0 0 0)" }];
  let menuAnim = null;
  const setMenu = (open) => {
    burger.setAttribute("aria-expanded", String(open));
    nav.classList.toggle("is-open", open);
    if (menuAnim) { menuAnim.cancel(); menuAnim = null; }
    if (open) {
      menu.hidden = false;
      if (!reduced()) menuAnim = menu.animate(MENU_KF, { duration: 400, easing: "ease" });
    } else if (!menu.hidden && !reduced() && phoneMQ.matches) {
      menuAnim = menu.animate(MENU_KF, { duration: 400, easing: "ease", direction: "reverse" });
      menuAnim.onfinish = () => { menu.hidden = true; menuAnim = null; };
    } else menu.hidden = true;
  };
  burger.addEventListener("click", () => setMenu(burger.getAttribute("aria-expanded") !== "true"));
  menu.addEventListener("click", (e) => { if (e.target.closest("a")) setMenu(false); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && burger.getAttribute("aria-expanded") === "true") { setMenu(false); burger.focus(); } });
  phoneMQ.addEventListener("change", () => setMenu(false));
  const segs = $$("[data-seg]");
  const setSeg = (name) => segs.forEach((a) => {
    const on = a.dataset.seg === name;
    a.classList.toggle("seg-on", on);
    if (on) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current");
  });

  const bbar = $("[data-bbar]"), foot = $(".foot");
  const setBar = (up) => { bbar.classList.toggle("is-up", up); bbar.inert = !up; };
  setBar(false);
  $("[data-bbar-close]").addEventListener("click", () => { bbar.hidden = true; });
  let navLastY = scrollY;
  function navScroll() {
    const y = scrollY;
    if (!narrowMQ.matches) { nav.classList.remove("is-hidden"); navLastY = y; return; }
    // Down past 50 px hides the nav and brings up the bar; any move up reverses both.
    if (y > navLastY && y > 50) { if (burger.getAttribute("aria-expanded") !== "true") nav.classList.add("is-hidden"); setBar(true); }
    else if (y < navLastY) { nav.classList.remove("is-hidden"); setBar(false); }
    navLastY = y;
    bbar.classList.toggle("is-gone", foot.getBoundingClientRect().top < innerHeight * 0.8);
  }
  nav.addEventListener("focusin", () => nav.classList.remove("is-hidden"));

  // ---- Rounded section corners square off as a section fills the screen ------------------------------------------------
  const cornerEls = $$(".speed, .ex").map((el) => ({ el, t: -1, b: -1, wt: -1, wb: -1 }));
  function cornersTick(t, dt, dr) {
    const vh = innerHeight, max = innerWidth > 991 ? 80 : 40, k = 1 - Math.pow(1 - 0.16, dr);
    cornerEls.forEach((s) => {
      const r = s.el.getBoundingClientRect();
      if (r.bottom < -100 || r.top > vh + 100) return;
      const tT = clamp(r.top, 0, max), tB = clamp(vh - r.bottom, 0, max);
      if (s.t < 0) { s.t = tT; s.b = tB; } else {
        s.t += (tT - s.t) * k; if (Math.abs(tT - s.t) < 0.1) s.t = tT;
        s.b += (tB - s.b) * k; if (Math.abs(tB - s.b) < 0.1) s.b = tB;
      }
      if (s.t === s.wt && s.b === s.wb) return;
      s.wt = s.t; s.wb = s.b;
      s.el.style.borderRadius = `${s.t.toFixed(1)}px ${s.t.toFixed(1)}px ${s.b.toFixed(1)}px ${s.b.toFixed(1)}px`;
    });
  }
  const cornersOn = () => { if (!reduced()) addTask(cornersTick); };
  cornerEls.forEach((s) => whileVisible(s.el, cornersOn, () => { if (cornerEls.every((c) => { const r = c.el.getBoundingClientRect(); return r.bottom < -80 || r.top > innerHeight + 80; })) removeTask(cornersTick); }));

  // ---- Hero ribbon --------------------------------------------------------------------------------------------------
  const ribbon = $("[data-ribbon]");
  const heroAPI = (() => {
    const svg = $("svg", ribbon);
    const raw = $("#rb-raw"), clean = $("#rb-clean");
    const rawTP = $("[data-raw]", ribbon), cleanTP = $("[data-clean]", ribbon);
    const PATHS = {
      wide: {
        raw: "M -760 300 C -320 292 60 266 205 250 C 300 222 362 160 342 100 C 322 40 232 22 186 60 C 140 98 150 180 200 232 C 262 300 420 425 700 455",
        clean: "M 720 455 C 960 445 1180 392 1500 300 S 1980 160 2300 110",
      },
      phone: {
        raw: "M -400 330 C 120 334 330 336 446 322 C 518 312 560 248 546 196 C 532 146 470 134 449 176 C 428 218 456 282 506 334 C 548 378 610 440 700 455",
        clean: "M 720 455 C 900 448 1060 400 1300 330 S 1700 200 2000 140",
      },
    };
    const baseRaw = rawTP.textContent, baseClean = cleanTP.textContent;
    rawTP.textContent = baseRaw.repeat(4);
    cleanTP.textContent = baseClean.repeat(4);
    // The pill's waveform: bars that jitter on a 167 ms beat while a quiet stretch drifts through as dots.
    const bars = $("[data-bars]", ribbon);
    const N = 17, bw = 3.6, gap = 2.3, x0 = 720 - (N * bw + (N - 1) * gap) / 2, HMAX = 44, HMIN = 3.6;
    const barEls = [], barSeed = [];
    for (let i = 0; i < N; i++) {
      const r = document.createElementNS(SVGNS, "rect");
      r.setAttribute("x", (x0 + i * (bw + gap)).toFixed(1)); r.setAttribute("width", bw); r.setAttribute("rx", bw / 2);
      bars.appendChild(r); barEls.push(r);
      barSeed.push({ a: Math.random(), b: Math.random(), ph: Math.random() * 6.28 });
    }
    const drawBars = (t) => {
      const beat = t / 167, k = beat - Math.floor(beat), e = k * k * (3 - 2 * k);
      for (let i = 0; i < N; i++) {
        const s = barSeed[i], n0 = Math.floor(beat), x = i / (N - 1);
        const r1 = Math.abs(Math.sin((n0 + 1) * 12.9898 * (s.a + 0.31) + s.ph) * 43758.5453) % 1;
        const r0 = Math.abs(Math.sin(n0 * 12.9898 * (s.a + 0.31) + s.ph) * 43758.5453) % 1;
        const jag = lerp(r0, r1, e);
        const env = 0.55 + 0.45 * Math.sin(Math.PI * x);
        // the quiet band travels left to right across the pill every 2.4 s
        const q = ((t / 2400) % 1) * 1.6 - 0.3, d = Math.abs(x - q);
        const quiet = d < 0.16 ? 1 : d < 0.24 ? 1 - (d - 0.16) / 0.08 : 0;
        const h = lerp(HMIN + (HMAX - HMIN) * (0.18 + 0.82 * jag) * env, HMIN, quiet);
        barEls[i].setAttribute("y", (455 - h / 2).toFixed(1));
        barEls[i].setAttribute("height", h.toFixed(1));
      }
    };
    // Toasts: a spoken word floats over the pill, gets fixed, folds into a dot, and the dot opens into a toast.
    const TOASTS = [
      { word: "um", toast: "Filler removed", kind: "strike" },
      { word: "no wait", toast: "Correction applied", kind: "strike" },
      { word: "five five five", to: "555", toast: "Number formatted", kind: "swap" },
      { word: "the the", to: "the", toast: "Repeat removed", kind: "swap" },
    ];
    const wordEl = $("[data-word]", ribbon), strike = $("[data-strike]", ribbon);
    const toast = $("[data-toast]", ribbon), tBg = $("[data-toast-bg]", ribbon), tTick = $("[data-toast-tick]", ribbon), tText = $("[data-toast-text]", ribbon);
    const CY = 383, PERIOD = 5200, WORD_MS = 1750;
    let item = -1, wordChars = [], toastChars = [], toastW = 34, swapped = false;
    const ezOut = (t) => 1 - Math.pow(1 - t, 3);
    const bez = (x1, y1, x2, y2) => (x) => { // cubic-bezier solver for timing curves
      let t = x; for (let i = 0; i < 6; i++) { const cx = 3 * x1 * t * (1 - t) ** 2 + 3 * x2 * t * t * (1 - t) + t ** 3 - x; const d = 3 * x1 * (1 - t) ** 2 + 6 * (x2 - x1) * t * (1 - t) + 3 * (1 - x2) * t * t; if (Math.abs(d) < 1e-6) break; t = clamp(t - cx / d, 0, 1); }
      return 3 * y1 * t * (1 - t) ** 2 + 3 * y2 * t * t * (1 - t) + t ** 3;
    };
    const growEase = bez(0.562, 0, 0, 1), shrinkEase = bez(1, 0, 0.438, 1);
    const setChars = (el, text) => {
      el.textContent = "";
      return [...text].map((ch) => { const s = document.createElementNS(SVGNS, "tspan"); s.textContent = ch; el.appendChild(s); return s; });
    };
    // tspans can't take transforms, so each letter's lift is written as a dy relative to the letter before it
    const placeChars = (chars, ys, alphas) => {
      let prev = 0;
      chars.forEach((c, j) => { c.setAttribute("dy", (ys[j] - prev).toFixed(2)); prev = ys[j]; c.style.fillOpacity = alphas[j].toFixed(3); });
    };
    const startItem = (i) => {
      item = i; swapped = false;
      const it = TOASTS[i];
      wordChars = setChars(wordEl, it.word);
      wordEl.removeAttribute("transform"); wordEl.style.opacity = "";
      strike.removeAttribute("transform");
      toastChars = setChars(tText, it.toast);
      const tw = tText.getComputedTextLength();
      toastW = Math.round(tw + 70);
      tText.setAttribute("x", (-toastW / 2 + 40).toFixed(1));
      tTick.setAttribute("transform", `translate(${(-toastW / 2 + 21).toFixed(1)} 0)`);
      const ww = wordEl.getComputedTextLength();
      strike.setAttribute("x1", (720 - ww / 2 - 4).toFixed(1)); strike.setAttribute("x2", (720 + ww / 2 + 4).toFixed(1));
      strike.style.strokeDasharray = ww + 8; strike.style.strokeDashoffset = ww + 8; strike.style.opacity = "0";
    };
    const drawToast = (t) => {
      const i = Math.floor(t / PERIOD) % TOASTS.length, local = t % PERIOD;
      if (i !== item) startItem(i);
      const it = TOASTS[i];
      // word: letters rise in one by one, ripple, then sit still
      if (local < WORD_MS + 200) {
        const amp = 1 - span(local, 500, 1200);
        const ys = [], al = [];
        wordChars.forEach((c, j) => {
          const a = span(local, j * 40, j * 40 + 300);
          ys.push((1 - ezOut(a)) * 10 + amp * 4 * Math.sin(local / 140 - j * 0.7)); al.push(a);
        });
        placeChars(wordChars, ys, al);
        const fix = span(local, 1150, 1450);
        if (it.kind === "strike") { strike.style.opacity = fix > 0 ? "1" : "0"; strike.style.strokeDashoffset = ((1 - fix) * parseFloat(strike.style.strokeDasharray)).toFixed(1); }
        else if (fix >= 0.5 && !swapped) { swapped = true; wordChars = setChars(wordEl, it.to); }
        const fold = span(local, 1550, 1750);
        const sc = 1 - ezOut(fold);
        wordEl.setAttribute("transform", `translate(720 ${CY}) scale(${sc.toFixed(3)}) translate(-720 ${-CY})`);
        strike.setAttribute("transform", wordEl.getAttribute("transform"));
        wordEl.style.opacity = local > WORD_MS ? "0" : "1";
        if (local > WORD_MS) strike.style.opacity = "0";
      } else { wordEl.style.opacity = "0"; strike.style.opacity = "0"; }
      // toast
      const T = local - WORD_MS;
      if (T < 0 || T > 2040) { toast.style.opacity = "0"; return; }
      toast.style.opacity = "1";
      let w = 34;
      if (T < 133) w = 34;
      else if (T < 533) w = lerp(34, toastW, growEase((T - 133) / 400));
      else if (T < 1700) w = toastW;
      else w = lerp(toastW, 34, shrinkEase(span(T, 1700, 1950)));
      const pop = T < 133 ? ezOut(T / 133) : 1;
      const out = 1 - span(T, 1900, 2033);
      tBg.setAttribute("x", (-w / 2).toFixed(1)); tBg.setAttribute("width", w.toFixed(1));
      toast.setAttribute("transform", `translate(720 ${CY}) scale(${(pop * out).toFixed(3)})`);
      const textOut = 1 - span(T, 1650, 1800), n = toastChars.length;
      placeChars(toastChars, toastChars.map((c, j) => 2.5 * Math.sin(T / 95 - j * 0.5)), toastChars.map((c, j) => span(T, 100 + j * (600 / n), 400 + j * (600 / n)) * textOut));
      const tick = T < 767 ? 0 : T < 867 ? 0.28 * span(T, 767, 867) : T < 1000 ? 0.28 : 0.28 + 0.72 * ezOut(span(T, 1000, 1167));
      tTick.style.strokeDashoffset = ((1 - tick * textOut) * 18).toFixed(2);
    };
    let rawLen = 0, cleanLen = 0, off = 0, offC = 0, raf = 0, last = 0, t0 = 0, scale = 1;
    const layout = () => {
      const p = phoneMQ.matches ? PATHS.phone : PATHS.wide;
      raw.setAttribute("d", p.raw); clean.setAttribute("d", p.clean);
      rawLen = rawTP.parentNode.getComputedTextLength() / 4;
      cleanLen = cleanTP.parentNode.getComputedTextLength() / 4;
      const b = svg.getBoundingClientRect();
      scale = Math.max(b.width / 1440, b.height / 540) || 1;
      draw();
    };
    const draw = () => {
      const pr = raw.getTotalLength();
      // Raw words travel toward the pill; clean words leave it.
      rawTP.setAttribute("startOffset", (pr - rawLen * 3 + (off % rawLen)).toFixed(1));
      cleanTP.setAttribute("startOffset", ((offC % cleanLen) - cleanLen).toFixed(1));
    };
    const frame = (t) => {
      const dt = last ? Math.min(0.05, (t - last) / 1000) : 0; last = t;
      if (!t0) t0 = t;
      // 86 px/s on screen above 480 px, 53–55 px/s below (35 s / 50 s and 15 s / 20 s loops in the reference)
      const pxs = tinyMQ.matches ? [53, 55] : [87, 85];
      off += dt * pxs[0] / scale; offC += dt * pxs[1] / scale;
      draw(); drawBars(t); drawToast(t - t0);
      raf = requestAnimationFrame(frame);
    };
    const start = () => { if (reduced()) return; last = 0; raf = requestAnimationFrame(frame); };
    const stop = () => cancelAnimationFrame(raf);
    const still = () => { drawBars(800); startItem(0); wordEl.style.opacity = "0"; toast.style.opacity = "0"; };
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => {
      layout(); still();
      whileVisible(ribbon, start, stop);
    });
    return { layout, reduceChanged: () => { stop(); if (!reduced()) start(); else still(); } };
  })();

  // ---- Logo strip: 36 px/s, 25 px/s on small phones ------------------------------------------------------------------
  const mqTrack = $(".marquee-track");
  const setMarquee = () => {
    const gapPx = parseFloat(getComputedStyle(mqTrack).columnGap) || 0;
    const dist = mqTrack.scrollWidth / 2 + gapPx / 2;
    mqTrack.style.setProperty("--mq-dur", (dist / (tinyMQ.matches ? 24.8 : 36.3)).toFixed(2) + "s");
  };

  // ---- Arc text ------------------------------------------------------------------------------------------------------
  // Moves the text along its path toward the path's end. `pace` gives on-screen px per second for a given svg width.
  function arcRunner(textPath, pace, copies = 3) {
    let off = 0, last = 0, raf = 0, len = 0, speed = 0;
    textPath.textContent = textPath.textContent.repeat(copies);
    const svg = textPath.closest("svg"), vb = svg.viewBox.baseVal;
    const measure = () => {
      len = textPath.parentNode.getComputedTextLength() / copies;
      const r = svg.getBoundingClientRect(), sc = Math.max(r.width / vb.width, r.height / vb.height) || 1;
      speed = pace(r.width) / sc;
    };
    const place = () => { if (!len) measure(); if (len) textPath.setAttribute("startOffset", ((off % len) - len).toFixed(1)); };
    const frame = (t) => {
      const dt = last ? Math.min(0.05, (t - last) / 1000) : 0; last = t;
      off += dt * speed; place();
      raf = requestAnimationFrame(frame);
    };
    return {
      start() { measure(); if (reduced()) { place(); return; } last = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(frame); },
      stop() { cancelAnimationFrame(raf); },
      measure,
    };
  }

  // ---- The story card: one scene that plays the three chapters ---------------------------------------------------------
  const CH_MS = [9500, 6200, 6800];          // desktop autoplay per chapter
  const MOBILE_CH_MS = [4000, 5200, 6800];   // each stacked chapter plays once when it scrolls in
  const BAR_SHAPE = [0.16, 0.42, 0.7, 0.92, 1, 0.88, 0.66, 0.46, 0.28, 0.14];
  const GRAD_CSS = "linear-gradient(100deg,#F0D7FF 0%,#FFA946 23%,#FF6C4C 39%,#FFBCF2 67%,#7232A6 91%)";
  function wrapWords(el, cls) {
    const out = [];
    const walk = (node, cat) => {
      [...node.childNodes].forEach((n) => {
        if (n.nodeType === 3) {
          const frag = document.createDocumentFragment();
          n.textContent.split(/(\s+)/).forEach((part) => {
            if (!part) return;
            if (/^\s+$/.test(part)) { frag.append(part); return; }
            const w = document.createElement("span"); w.className = cls; w.textContent = part;
            frag.append(w); out.push({ el: w, cat });
          });
          n.replaceWith(frag);
        } else if (n.nodeType === 1 && n.tagName !== "BR") walk(n, n.dataset.cat || cat);
      });
    };
    walk(el, null);
    return out;
  }
  function Scene(card, desktop) {
    const S = { card, desktop };
    S.bgs = $$("[data-bg]", card); S.art = $("[data-art]", card);
    S.intro = $("[data-intro]", card);
    S.screen = $("[data-screen]", card);
    S.tr = $("[data-tr]", card); S.rawWrap = $("[data-raw-wrap]", card);
    S.words = wrapWords(S.tr, "w");
    S.polished = $("[data-polished]", card);
    S.pwords = wrapWords(S.polished, "pw").map((w) => w.el);
    S.msg = $("[data-msg]", card); S.ph = $(".cm-ph", S.msg);
    S.cmCard = $("[data-cm-card]", card); S.cmClip = $("[data-cm-clip]", card);
    S.composer = $("[data-composer]", card);
    S.fanCards = $$(".fan-card", card);
    S.destRow = $("[data-dest-row]", card); S.dests = $$(".dest-i", card);
    S.pills = {}; $$("[data-pill]", card).forEach((p) => { S.pills[p.dataset.pill] = p; });
    Object.values(S.pills).forEach((p) => {
      const t = $(".pill-t", p), s = t.textContent; t.textContent = "";
      [...s].forEach((ch, i) => { const c = document.createElement("span"); c.className = "ch"; c.textContent = ch; c.style.transitionDelay = (0.16 + i * 0.018).toFixed(3) + "s"; t.append(c); });
    });
    S.pol = S.pills.polishing;
    S.dots = $$(".pp-dots i", S.pol);
    S.dots.forEach((d, i) => { d.style.setProperty("--h", (3 + BAR_SHAPE[i] * 11).toFixed(1) + "px"); d.style.transitionDelay = i * 0.03 + "s"; });
    S.audio = $("[data-audio]", card);
    S.bars = $$(".fw i", S.audio);
    S.barSeed = S.bars.map(() => ({ ceil: 0.24 + 0.74 * (0.82 + 0.18 * Math.random()), f1: 0.8 + Math.random() * 1.5, f2: 2 + Math.random() * 3, p1: Math.random() * 6.28, p2: Math.random() * 6.28 }));
    S.env = [Math.random() * 6.28, Math.random() * 6.28];
    S.extras = $$("[data-extra]", S.audio);
    S.caps = $$("[data-cap]", S.audio); S.mid = $("[data-mid]", S.audio); S.wave = $(".fw", S.audio);
    S.chapter = -2; S.wordsShown = -1; S.pillShown = undefined; S.bgShown = 0;
    S.polishColored = false; S.gradReady = false; S.fanCur = 0; S.liftCur = 1; S.fanTgt = 0; S.liftTgt = 1;
    S.polishCur = 0; S.wiggle = 0; S.pillT = []; S.voiceLive = false;
    return S;
  }
  // the message box's visible height, drawn without moving anything in layout
  function setMsg(S, h) {
    S.msgH = h;
    if (!S.msgMax) return;
    S.cmCard.style.transform = `scaleY(${((h + S.toolsH) / (S.msgMax + S.toolsH)).toFixed(4)})`;
    S.cmClip.style.clipPath = `inset(${(S.msgMax - h).toFixed(1)}px 0 0 0)`;
  }
  function sceneMeasure(S) {
    const sc = S.screen;
    S.msgCollapsed = S.ph.offsetHeight || 44;
    S.msgExpanded = S.polished.offsetHeight + 20;
    S.msgMax = S.msgExpanded + 6;
    S.msg.style.height = S.msgMax + "px";
    S.toolsH = S.composer.offsetHeight - S.msgMax;
    setMsg(S, S.msgH || S.msgCollapsed);
    // the composer lifts to the middle of the screen in chapter three
    const scH = sc.offsetHeight || 467;
    const cTop = S.composer.offsetTop + S.composer.parentNode.offsetTop, cH = S.composer.offsetHeight;
    S.fanCY = Math.round(scH / 2 - (cTop + cH / 2));
    S.fanCards.forEach((c) => { c._cy = Math.round(scH / 2 - (c.offsetTop + S.composer.parentNode.offsetTop + c.offsetHeight / 2)) - 30; });
    // each raw word's place along a diagonal sweep (top-left to bottom-right)
    const W = S.tr.offsetWidth || 1, H = S.tr.offsetHeight || 1;
    let mn = Infinity, mx = -Infinity;
    S.words.forEach((w) => {
      const x = w.el.offsetLeft + w.el.offsetWidth / 2, y = w.el.offsetTop + w.el.offsetHeight / 2;
      w._v = y / H + (x / W) * 0.35; mn = Math.min(mn, w._v); mx = Math.max(mx, w._v);
      w._gx = w.el.offsetLeft;
    });
    S.words.forEach((w) => { w.diag = (w._v - mn) / ((mx - mn) || 1); });
    S.trW = W; S.gradReady = false;
  }
  // The audio pill's bars: a travelling wave mixed with jagged noise, like a voice.
  function sceneAudio(S, clock) {
    const TP = Math.PI * 2, t = clock * 2.4, n = S.bars.length;
    const e = (0.5 + 0.5 * Math.sin(t * TP * 0.9 + S.env[0])) * (0.5 + 0.5 * Math.sin(t * TP * 2.3 + S.env[1]));
    for (let i = 0; i < n; i++) {
      const b = S.barSeed[i], xi = i / (n - 1);
      const v = 0.55 * Math.sin(t * TP * b.f1 + b.p1) + 0.45 * Math.sin(t * TP * b.f2 + b.p2);
      const jag = (0.5 + 0.5 * v) * (0.22 * e + 0.78);
      const wave = 0.6 * Math.sin((xi * 1.7 - t) * TP) + 0.4 * Math.sin((xi * 0.85 - t * 0.6) * TP + 1.7);
      const sw = (0.5 + 0.5 * wave) * (0.7 + 0.3 * Math.sin(xi * Math.PI));
      const s = 0.72 * sw + 0.28 * jag;
      S.bars[i].style.transform = `scaleY(${(0.24 + (b.ceil - 0.24) * s).toFixed(3)})`;
    }
    if (S.voiceLive) {
      const N = S.dots.length;
      for (let i = 0; i < N; i++) {
        const xi = i / (N - 1);
        const wave = 0.6 * Math.sin((xi * 1.7 - t) * TP) + 0.4 * Math.sin((xi * 0.85 - t * 0.6) * TP + 1.7);
        S.dots[i].style.height = (3 + (0.5 + 0.5 * wave) * (0.7 + 0.3 * Math.sin(xi * Math.PI)) * 11).toFixed(1) + "px";
      }
    }
  }
  function setBg(S, idx) {
    const want = idx < 1 ? 0 : Math.min(idx, 2);
    if (want === S.bgShown) return;
    S.bgShown = want;
    S.bgs.forEach((b) => { b.style.opacity = +b.dataset.bg === want ? "1" : "0"; });
  }
  // The backdrop goes out of focus as the story moves on: a blur and a slight push-in on the art's own layer.
  const ART_BLUR = 26, ART_ZOOM = 0.06;
  function artDepth(S, t, base = "", max = ART_BLUR) {
    const b = (max * t).toFixed(1), tf = `${base} scale(${(1 + ART_ZOOM * t).toFixed(4)})`;
    if (b !== S.artBlur) { S.artBlur = b; S.art.style.filter = `blur(${b}px)`; }
    if (tf !== S.artTf) { S.artTf = tf; S.art.style.transform = tf; }
  }
  function artReset(S) { S.artBlur = S.artTf = null; S.art.style.filter = ""; S.art.style.transform = ""; }
  // The pill opens from push-to-talk (73 wide) to hands-free (102 wide): the end caps part over a middle that stretches
  // (76 wide in the stylesheet, 2 px under each cap), the bars shift 2 px left and the buttons grow in with the caps.
  const PILL_IN = 14.5, PILL_MID = 76;
  function pillOpen(S, e) {
    const k = e.toFixed(3);
    if (k === S.pillOpenK) return;
    S.pillOpenK = k;
    const a = PILL_IN * (1 - e);
    S.caps[0].style.transform = `translateX(${a.toFixed(2)}px)`;
    S.caps[1].style.transform = `translateX(${(-a).toFixed(2)}px) scaleX(-1)`;
    S.mid.style.transform = `scaleX(${((PILL_MID - 2 * a) / PILL_MID).toFixed(4)})`;
    S.wave.style.transform = `translateX(${(2 * (1 - e)).toFixed(2)}px)`;
    S.extras[0].style.transform = `translateX(${a.toFixed(2)}px) scale(${k})`;
    S.extras[1].style.transform = `translateX(${(-a).toFixed(2)}px) scale(${k})`;
    S.extras.forEach((x) => { x.style.opacity = k; });
  }
  // The "Cleaning up…" pill: spinner, then dots, then (chapter three) a live voice wave.
  function pillCalls(S) { S.pillT.forEach(clearTimeout); S.pillT = []; }
  function pillDotsIn(S) { S.pol.classList.add("is-in"); }
  function setVoice(S, on) {
    S.voiceLive = on;
    S.pol.classList.toggle("is-live", on);
    if (!on) S.dots.forEach((d) => { d.style.height = ""; });
  }
  function setPillDone(S, on, wave) {
    const P = S.pol;
    if (on) {
      clearTimeout(S.pillOff); S.pillOff = 0;
      if (S.pillDone && S.pillWave === wave) return;
      if (S.pillDone && wave && !S.pillWave) { S.pillWave = true; pillCalls(S); pillDotsIn(S); P.classList.add("is-wave"); S.pillT.push(setTimeout(() => setVoice(S, true), 500)); return; }
      if (S.pillDone && !wave && S.pillWave) { S.pillWave = false; pillCalls(S); setVoice(S, false); P.classList.remove("is-wave"); return; }
      S.pillDone = true; S.pillWave = wave; pillCalls(S);
      P.classList.add("is-done");
      S.pillT.push(setTimeout(() => pillDotsIn(S), 240));
      if (wave) {
        S.pillT.push(setTimeout(() => P.classList.add("is-wave"), 540));
        S.pillT.push(setTimeout(() => setVoice(S, true), 1040));
      }
    } else {
      if (!S.pillDone || S.pillOff) return;
      S.pillOff = setTimeout(() => {
        S.pillOff = 0; S.pillDone = false; S.pillWave = false; pillCalls(S); setVoice(S, false);
        P.classList.remove("is-wave", "is-in", "is-done");
      }, 200);
    }
  }
  function setPill(S, name) {
    if (name === S.pillShown) return;
    S.pillShown = name;
    Object.entries(S.pills).forEach(([k, p]) => p.classList.toggle("is-on", k === name));
  }
  function resetPolish(S) {
    if (!S.polishColored) return;
    S.words.forEach((w) => { const s = w.el.style; s.color = ""; s.textShadow = ""; s.transform = ""; s.backgroundImage = ""; });
    S.tr.classList.remove("is-polish");
    S.rawWrap.style.webkitMaskImage = ""; S.rawWrap.style.maskImage = ""; S.rawWrap.style.transform = "";
    S.polishColored = false; S.gradReady = false;
  }
  const crestAt = (front, ph) => { const d = front - ph; return d <= 0 || d >= 0.18 ? 0 : Math.sin(Math.PI * (d / 0.18)); };
  const crestCSS = (w, extraY) => { const y = (extraY || 0) - 7 * w; let t = ""; if (y) t += `translateY(${y.toFixed(2)}px)`; if (w) t += ` scale(${(1 + 0.05 * w).toFixed(4)})`; return t; };
  const outPow = (t) => 1 - Math.pow(1 - clamp(t, 0, 1), 4);
  const wiggleAt = (tp) => { const t = phaseT(tp, 0.53, 0.72); return t <= 0 || t >= 1 ? 0 : Math.sin(t * Math.PI * 2 * 2.2) * (1 - t) * (1 - t); };
  // chapter two: the raw words take a colour sweep, glow and ripple, wipe away and drop, and the clean text grows into the box
  function renderPolish(S, tp, fast) {
    if (!S.gradReady) {
      S.words.forEach((w) => { const s = w.el.style; s.backgroundImage = GRAD_CSS; s.backgroundRepeat = "no-repeat"; s.webkitBackgroundClip = "text"; s.backgroundClip = "text"; });
      S.gradReady = true;
    }
    const spanW = S.trW * 2.2, tt = (performance.now() / 3200) % 2, slide = (tt > 1 ? 2 - tt : tt) * (spanW - S.trW);
    const Fg = phaseT(tp, 0, 0.46) * 1.08, Fglow = phaseT(tp, 0, 0.46) * 1.19;
    S.words.forEach((w) => {
      const s = w.el.style, ph = w.diag;
      s.backgroundSize = spanW.toFixed(1) + "px 100%";
      s.backgroundPosition = (-w._gx - slide).toFixed(1) + "px 0";
      s.color = Fg > ph ? "transparent" : "";
      const df = Fglow - ph, g = df >= 0 && df < 0.14 ? 1 - df / 0.14 : 0;
      s.textShadow = g > 0.02 ? `0 0 ${(12 * g).toFixed(1)}px rgba(255,255,240,${(0.9 * g).toFixed(2)})` : "";
      const cw = crestAt(Fglow, ph);
      s.transform = cw > 0.002 ? crestCSS(cw, 0) : "";
    });
    const rawT = smooth(phaseT(tp, 0.46, 0.55));
    const wipe = fast ? Math.min(1, rawT * 1.12) : rawT;
    const m = `linear-gradient(164.25deg, transparent ${(wipe * 160 - 30).toFixed(1)}%, #000 ${(wipe * 160).toFixed(1)}%)`;
    S.rawWrap.style.webkitMaskImage = m; S.rawWrap.style.maskImage = m;
    S.rawWrap.style.transform = fast && rawT > 0.0005 ? `translateY(${(90 * rawT).toFixed(2)}px)` : "";
    const F = outPow(phaseT(tp, 0.52, 0.66)) * (fast ? 1.7 : 1) * 1.34;
    const np = S.pwords.length;
    S.pwords.forEach((w, j) => {
      const pph = np > 1 ? j / (np - 1) : 0, o = smooth((F - pph - 0.12) / 0.22);
      w.style.opacity = o.toFixed(3);
      w.style.transform = crestCSS(crestAt(F, pph) * 0.6, 12 * (1 - o));
    });
    let grow = outPow(phaseT(tp, 0.52, 0.66));
    if (fast) grow = Math.pow(grow, 1 / 2.6);
    setMsg(S, S.msgCollapsed + (S.msgExpanded - S.msgCollapsed) * grow);
    S.ph.style.opacity = (1 - smooth(Math.min(1, grow * 6))).toFixed(3);
    S.wiggle = fast ? wiggleAt(tp) : 0;
  }
  const fanStep = (t, n) => {
    const wH = 0.6 / n, wT = 0.4 / (n - 1); let x = 0;
    for (let i = 0; i < n; i++) {
      if (t <= x + wH) return i;
      x += wH;
      if (i < n - 1) { if (t <= x + wT) return i + smooth((t - x) / wT); x += wT; }
    }
    return n - 1;
  };
  // chapter three: the message lifts to the middle, then swings away as the same words land in mail and a terminal
  function fanTargets(S, tp, exitOn) {
    const n = 1 + S.fanCards.length;
    S.liftTgt = smooth(Math.min(1, tp / 0.15));
    const sw = Math.max(0, (tp - 0.15) / 0.85);
    if (exitOn && sw > 0.78) S.fanTgt = n - 1 + 2 * smooth(clamp((sw - 0.78) / 0.22, 0, 1));
    else S.fanTgt = fanStep(exitOn ? Math.min(1, sw / 0.78) : sw, n);
    S.fanAlpha = smooth(Math.min(1, tp / 0.1));
  }
  function fanRender(S, show) {
    const f = S.fanCur, lift = S.liftCur, tx = innerWidth < 992 ? 460 : 300;
    const all = [S.composer, ...S.fanCards];
    all.forEach((el, i) => {
      if (!show) { el.style.transform = ""; el.style.opacity = i ? "0" : ""; el.style.zIndex = ""; return; }
      const rel = i - f, ar = Math.abs(rel);
      const op = (1 - clamp((ar - 1) / 0.6, 0, 1)) * (S.fanAlpha ?? 1);
      const cy = (i ? el._cy : S.fanCY) * lift;
      el.style.transformOrigin = "50% 100%";
      el.style.transform = `translate(${(tx * rel).toFixed(1)}px, ${cy.toFixed(1)}px) rotate(${(45 * rel).toFixed(2)}deg)`;
      el.style.opacity = Math.max(0, op).toFixed(3);
      el.style.zIndex = String(100 - Math.round(ar * 10));
    });
    S.destRow.style.opacity = show ? "1" : "0";
    S.dests.forEach((d, i) => {
      const lrel = i === 0 ? i - f + (1 - lift) : i - f, lar = Math.abs(lrel);
      d.style.opacity = show ? (Math.max(0, 1 - lar) * (S.fanAlpha ?? 1)).toFixed(3) : "0";
      d.style.transform = `rotate(${(90 * lrel).toFixed(1)}deg) scale(${(1 - 0.4 * Math.min(1, lar)).toFixed(3)})`;
    });
  }
  // Paints one chapter at progress tp (0–1). `idx` -1 = before the chapters (desktop intro).
  function sceneUpdate(S, idx, tp, opts = {}) {
    const n = S.words.length;
    if (idx !== S.chapter) {
      if (S.chapter === 1) resetPolish(S);
      S.chapter = idx; S.wordsShown = -1;
      if (idx === 1) S.polishCur = tp;
      if (idx === 2) { S.fanCur = S.fanTgt; S.liftCur = 0; }
    }
    setBg(S, idx);
    S.audio.style.opacity = idx >= 1 ? "0" : "1";
    const count = idx < 0 ? 0 : idx === 0 ? Math.round(Math.min(1, tp / 0.9) * n) : n;
    if (idx !== 1 && count !== S.wordsShown) { S.words.forEach((w, i) => { w.el.style.opacity = i < count ? "1" : "0"; }); S.wordsShown = count; }
    if (idx === 1) {
      if (!S.polishColored) { S.words.forEach((w) => { w.el.style.opacity = "1"; }); S.tr.classList.add("is-polish"); S.polishColored = true; }
      S.tr.style.opacity = "";
      S.polishTgt = tp;
      if (!S.desktop) { S.polishCur = tp; renderPolish(S, tp, false); }
    } else if (idx >= 2) {
      resetPolish(S);
      S.tr.style.opacity = "0";
      S.pwords.forEach((w) => { w.style.opacity = "1"; w.style.transform = ""; });
      setMsg(S, S.msgExpanded + 6 * smooth(Math.min(1, tp / 0.15)));
      S.ph.style.opacity = "0";
      S.wiggle = 0;
    } else {
      resetPolish(S);
      S.tr.style.opacity = "";
      S.pwords.forEach((w) => { w.style.opacity = "0"; w.style.transform = ""; });
      setMsg(S, S.msgCollapsed);
      S.ph.style.opacity = "";
      S.wiggle = 0;
    }
    // which pill: the category of the last word typed, then "Cleaning up…"
    let pill = null;
    if (idx === 0) { for (let j = count - 1; j >= 0; j--) if (S.words[j].cat) { pill = S.words[j].cat; break; } }
    else if (idx >= 1) pill = (opts.pillAt ?? 0) <= tp || idx >= 2 ? "polishing" : null;
    setPill(S, pill);
    const voice = idx >= 2;
    setPillDone(S, voice || (idx === 1 && tp >= 0.46), voice);
    if (idx >= 2) { fanTargets(S, tp, opts.exit !== false); if (!S.desktop) { S.fanCur = S.fanTgt; S.liftCur = S.liftTgt; } }
    else { S.fanTgt = 0; S.liftTgt = 1; }
    if (!S.desktop) fanRender(S, idx >= 2);
  }
  // per-frame easing for the desktop card (the reference eases these toward their targets every frame)
  function sceneTick(S, dr) {
    if (S.chapter === 1) {
      S.polishCur = follow(S.polishCur, S.polishTgt, 0.32, dr);
      renderPolish(S, S.polishCur, true);
    }
    if (S.chapter >= 2) {
      S.fanCur = follow(S.fanCur, S.fanTgt, 0.12, dr);
      S.liftCur = follow(S.liftCur, S.liftTgt, 0.12, dr);
      fanRender(S, true);
    } else if (S.fanShown !== false) { fanRender(S, false); }
    S.fanShown = S.chapter >= 2;
  }

  // ---- The scroll story (wide screens): speed cards → full card → portrait card → three chapters ------------------------
  const story = $("[data-story]");
  const stage = $("[data-stage]");
  const outCard = $("[data-out]");
  const card = $("[data-card]");
  const ci = $("[data-ci]", card), cs = $("[data-cs]", card);
  const speed = $("[data-speed]");
  const howTrack = $("[data-how]");
  const howPin = $(".how-pin", howTrack);
  const tabsEl = $("[data-tabs]");
  const tabs = $$("[data-step-tab]");
  const steps = $$("[data-step]");
  const bgPaths = $$("[data-tab-bg]");
  const speedSlot = $('[data-slot="speed"]');
  const coTick = $(".co-tick span", outCard), coIn = $("[data-co-in]", outCard);
  let cardW = 0, cardH = 0;

  // Clones for the stacked layout (phones, reduced motion): the speed card and one card per chapter.
  let arcSeq = 0;
  const makeClone = (which) => {
    const c = card.cloneNode(true);
    c.removeAttribute("data-card");
    $$("[id]", c).forEach((el) => { const id = el.id + "-c" + ++arcSeq; $$(`[href="#${el.id}"]`, c).forEach((u) => u.setAttribute("href", "#" + id)); el.id = id; });
    if (which === "speed") $(".cs", c).remove(); else $(".ci", c).remove();
    return c;
  };
  const clones = { speed: makeClone("speed"), 1: makeClone("1"), 2: makeClone("2"), 3: makeClone("3") };
  const scene = Scene(card, true);
  const chScenes = ["1", "2", "3"].map((k) => Scene(clones[k], false));
  const speedScene = { audio: $("[data-audio]", clones.speed), bars: $$("[data-audio] .fw i", clones.speed) };
  speedScene.barSeed = speedScene.bars.map(() => ({ ceil: 0.24 + 0.74 * (0.82 + 0.18 * Math.random()), f1: 0.8 + Math.random() * 1.5, f2: 2 + Math.random() * 3, p1: Math.random() * 6.28, p2: Math.random() * 6.28 }));
  speedScene.env = [Math.random() * 6.28, Math.random() * 6.28]; speedScene.dots = []; speedScene.voiceLive = false;
  // the intro text races along its arc at the reference's 220-wpm pace: 400 units/s of a 928-wide strip, rightward
  const flowPace = (w) => (400 * w) / 928;
  const mainArc = arcRunner($("[data-arc]", card), flowPace);
  const cloneArc = arcRunner($("textPath", clones.speed), flowPace);

  let storyOn = false, geo = null, activeTab = -1, autoTp = 0, autoPlaying = false, autoDone = {}, loopWait = 0;
  let pillCur = 0, pillTgt = 0, sceneP = 0, clock = 0, tabFade = 0, clickLock = null;
  const IN = 0.25, GROW = 0.8, HOLD = 0.25, SHRINK = 0.7, TABS = [1.0, 1.0, 1.2];
  const SPLIT = 0.28, MIN_W = 0.2, FILL_AT = 0.8, FILL_OFF = 0.68;
  const snapEnds = (t) => {
    if (t <= 0) return 0; if (t >= 1) return 1;
    if (t < 0.05) return 0.15 * (t / 0.05);
    if (t > 0.95) return 1 - 0.15 * ((1 - t) / 0.05);
    return 0.15 + ((t - 0.05) / 0.9) * 0.7;
  };
  let fill = 0, fillFrom = 0, fillTo = 0, fillT0 = -1, fillLatched = false;
  const setFill = (on) => { fillFrom = fill; fillTo = on ? 1 : 0; fillT0 = performance.now(); };

  function measureStory() {
    const V = innerHeight, W = root.clientWidth;
    speed.style.height = Math.round(V * 3) + "px";
    const gutter = Math.max(16, W * 0.05);
    const cw = Math.min(1160, W - 2 * gutter), x0 = (W - cw) / 2;
    const cardTop = Math.min(351, Math.max(300, V * 0.39));
    const cardH = Math.max(320, Math.min(501, V - cardTop - 40));
    const ph = Math.min(467, Math.round(V * 0.92));
    const storyTop = story.getBoundingClientRect().top + scrollY;
    const howTop = howTrack.getBoundingClientRect().top + scrollY;
    const y2 = cardTop + (cardH - ph) / 2, y3 = Math.max(16, Math.round((V - ph) / 2));
    geo = {
      V, W, cw, x0, cardTop, cardH, storyTop, howTop, ph,
      dA: IN * V, dB: (IN + GROW) * V, dBh: (IN + GROW + HOLD) * V, dC: (IN + GROW + HOLD + SHRINK) * V,
      dHold: howTop - storyTop, tabEnd: howTop - storyTop + TABS.reduce((a, b) => a + b, 0) * V,
      K1: { x: x0, y: cardTop, w: cw, h: cardH },
      K2: { x: (W - 400) / 2, y: y2, w: 400, h: ph },
      y3, rise: Math.max(0, y2 - y3), pillRec: -Math.min(200, Math.round(cardH * 0.22)),
    };
    howPin.style.setProperty("--card-bottom", y3 + ph + "px");
    tabsEl.style.top = y3 + 8 + "px";
    outCard.style.height = cardH + "px";
    geo.coW = Math.round(cw * SPLIT);
    coIn.style.setProperty("--co-w", geo.coW + "px");
    sceneMeasure(scene);
    moveIndicator(activeTab < 0 ? 0 : activeTab);
    paintBgPaths(activeTab, true);
  }
  const tabStops = () => { const s = [geo.dHold]; let acc = geo.dHold; TABS.forEach((v) => { acc += v * geo.V; s.push(acc); }); return s; };
  function tabAt(d) { const s = tabStops(); for (let i = 0; i < TABS.length; i++) if (d < s[i + 1] || i === TABS.length - 1) return i; return 0; }
  function moveIndicator(n) {
    const b = tabs[Math.max(0, n)];
    tabsEl.style.setProperty("--ind-y", b.parentNode.offsetTop + "px");
    tabsEl.style.setProperty("--ind-h", b.offsetHeight + "px");
  }
  function paintBgPaths(n, instant) {
    bgPaths.forEach((p, i) => {
      const len = p._len || (p._len = p.getTotalLength());
      p.style.strokeDasharray = len;
      if (instant) p.style.transition = "none";
      p.style.strokeDashoffset = i === n ? "0" : String(len);
      if (instant) { void p.getBoundingClientRect(); p.style.transition = ""; }
    });
  }
  function setActiveTab(n) {
    if (n === activeTab) return;
    activeTab = n;
    tabs.forEach((t, j) => { t.classList.toggle("is-on", j === n); if (j === n) t.setAttribute("aria-current", "step"); else t.removeAttribute("aria-current"); });
    steps.forEach((s, j) => s.classList.toggle("is-on", j === n));
    moveIndicator(n < 0 ? 0 : n);
    paintBgPaths(n, false);
    // every chapter replays from the start when it becomes active
    if (n >= 0) { autoTp = 0; autoPlaying = true; loopWait = 0; }
    else autoPlaying = false;
  }
  function renderStory() {
    if (!storyOn || !geo) return;
    const { V, K1, K2 } = geo;
    const d = scrollY - geo.storyTop;
    sceneP = d;
    let x, y, w, h, radius = "", kbW = 0;
    if (d < geo.dB) {
      const gt = span(d, geo.dA, geo.dB);
      if (!fillLatched && gt >= FILL_AT) { fillLatched = true; setFill(true); }
      else if (fillLatched && gt < FILL_OFF) { fillLatched = false; setFill(false); }
      let lp = geo.cw * SPLIT * (1 - snapEnds(gt));
      const frac = lp / geo.cw;
      if (frac < MIN_W) lp *= smooth(frac / MIN_W);
      lp *= 1 - fill;
      x = K1.x + lp; w = K1.w - lp; y = K1.y; h = K1.h;
      kbW = Math.max(0, lp - 12);
    } else if (d < geo.dBh) { x = K1.x; w = K1.w; y = K1.y; h = K1.h; }
    else {
      const t = phaseT(d, geo.dBh, geo.dC);
      w = lerp(K1.w, K2.w, t); h = lerp(K1.h, K2.h, t);
      x = (geo.W - w) / 2; y = K1.y + (K1.h - h) / 2;
      radius = lerp(48, 16, t).toFixed(1) + "px";
      if (d > geo.dC) {
        // the card holds, then rides up to the middle of the screen over the last stretch, dipping on the way
        const S = d - geo.dC, total = geo.dHold - geo.dC;
        const rideT = clamp(S / total, 0, 1);
        y = K2.y - Math.min(geo.rise, Math.max(0, S - (total - geo.rise))) + 70 * Math.sin(Math.PI * rideT);
      }
      if (d >= geo.dHold) y = geo.y3;
    }
    const wig = scene.wiggle || 0;
    card.style.width = w.toFixed(1) + "px";
    card.style.height = h.toFixed(1) + "px";
    card.style.borderRadius = radius;
    card.style.transform = `translate3d(${x.toFixed(1)}px, ${(y + 14 * wig).toFixed(1)}px, 0) rotate(${(0.6 * wig).toFixed(3)}deg)`;
    ci.style.transform = `translate3d(${((w - 1160) / 2).toFixed(1)}px, ${((h - 501) / 2).toFixed(1)}px, 0)`;
    const bgT = `translate3d(${((w - 1240) / 2).toFixed(1)}px, ${((h - 620) / 2).toFixed(1)}px, 0)`;
    scene.bgs.forEach((b) => { b.style.transform = bgT; });
    artDepth(scene, phaseT(d, geo.dBh, geo.dC + 0.8 * (geo.dHold - geo.dC)), bgT);
    cardW = w; cardH = h;
    cs.style.transform = `translate3d(${((w - 400) / 2).toFixed(1)}px, ${((h - 467) / 2).toFixed(1)}px, 0)`;
    outCard.style.width = kbW.toFixed(1) + "px";
    coIn.style.transform = `translate3d(${((kbW - geo.coW) / 2).toFixed(1)}px, 0, 0)`;
    outCard.style.visibility = kbW < 2 ? "hidden" : "";
    outCard.style.transform = `translate3d(${K1.x.toFixed(1)}px, ${K1.y.toFixed(1)}px, 0)`;
    // intro text until the card starts to shrink; the screen once the card has mostly settled
    scene.introOn = d < geo.dBh;
    if (scene.intro._on !== scene.introOn) { scene.intro._on = scene.introOn; scene.intro.style.opacity = scene.introOn ? "1" : "0"; }
    if (!tabFade) scene.screen.style.opacity = d >= geo.dC + 0.8 * (geo.dHold - geo.dC) ? "1" : "0";
    pillTgt = phaseT(d, geo.dBh, geo.dHold);
    if (clickLock == null) setActiveTab(d >= geo.dHold - 0.02 * (geo.tabEnd) ? (d <= geo.dHold ? 0 : tabAt(d)) : -1);
    placePill();
    storyScene();
  }
  // The 102 × 30 pill sits 36 px above the card's bottom, centred, on whole device pixels so it rests crisp. Placed again
  // whenever the card is, so the two never drift a frame apart while scrolling.
  function placePill() {
    if (!geo) return;
    const hp = pillCur, px = devicePixelRatio || 1, snap = (v) => Math.round(v * px) / px;
    const tf = `translate(${snap(cardW / 2 - 51)}px, ${snap(cardH - 36 - 30 + geo.pillRec * (1 - hp))}px) scale(${(1.8 - 0.8 * hp).toFixed(3)})`;
    if (tf !== scene.audioTf) { scene.audioTf = tf; scene.audio.style.transform = tf; }
    pillOpen(scene, smooth((hp - 0.55) / 0.45));
  }
  function storyScene() {
    const idx = activeTab;
    const tp = idx < 0 ? 0 : autoTp;
    sceneUpdate(scene, idx, tp, { exit: true });
  }
  function storyTick(t, dt, dr) {
    clock += dt / 1000;
    if (fillT0 >= 0) {
      const k = clamp((performance.now() - fillT0) / 340, 0, 1);
      fill = lerp(fillFrom, fillTo, quartOut(k));
      if (k >= 1) fillT0 = -1;
      renderStory();
    }
    if (autoPlaying && activeTab >= 0) {
      autoTp += dt / CH_MS[activeTab];
      if (autoTp >= 1) {
        if (activeTab === 2) { // the last chapter loops with a short pause
          autoTp = 1;
          if (!loopWait) loopWait = t + 400;
          else if (t >= loopWait) { loopWait = 0; autoTp = 0; scene.fanCur = 0; scene.liftCur = 0; }
        } else { autoTp = 1; autoPlaying = false; autoDone[activeTab] = true; }
      }
      storyScene();
    }
    pillCur = follow(pillCur, pillTgt, 0.16, dr);
    placePill();
    sceneAudio(scene, clock);
    sceneTick(scene, dr);
    if (scene.wiggle) renderStory();
  }
  // Clicking a tab: fade the screen out, jump to that chapter's middle, replay it, fade back in.
  tabs.forEach((b, i) => b.addEventListener("click", () => {
    if (!storyOn || !geo) return;
    const s = tabStops(), centre = (s[i] + s[i + 1]) / 2;
    clickLock = i; setActiveTab(i);
    clearTimeout(tabFade);
    scene.screen.style.transition = "opacity .22s ease"; scene.screen.style.opacity = "0";
    tabFade = setTimeout(() => {
      scrollTo({ top: geo.storyTop + centre, behavior: "instant" });
      lastSnap = centre; cancelSnap();
      clickLock = null; autoTp = 0; autoPlaying = true; renderStory();
      scene.screen.style.opacity = "1";
      tabFade = setTimeout(() => { tabFade = 0; scene.screen.style.transition = ""; }, 220);
    }, 220);
  }));
  // Inside the chapters a scroll that stops part-way settles on the next chapter in the direction it was heading.
  let snapTimer = 0, lastSnap = null, snapAnim = 0;
  const cancelSnap = () => { cancelAnimationFrame(snapAnim); snapAnim = 0; };
  ["wheel", "touchstart", "keydown", "mousedown"].forEach((ev) => addEventListener(ev, cancelSnap, { passive: true }));
  function snapCheck() {
    clearTimeout(snapTimer);
    if (!storyOn || !geo || snapAnim) return;
    snapTimer = setTimeout(() => {
      const d = scrollY - geo.storyTop, s = tabStops();
      if (d < geo.dHold - 1 || d > geo.tabEnd + 1) { lastSnap = null; return; }
      const pts = TABS.map((_, i) => (s[i] + s[i + 1]) / 2).concat([geo.tabEnd]);
      if (lastSnap == null) lastSnap = pts.reduce((a, p) => (Math.abs(p - d) < Math.abs(a - d) ? p : a), pts[0]);
      let target = lastSnap;
      const eps = 0.004 * (geo.tabEnd - 0);
      if (d > lastSnap + eps) target = pts.find((p) => p > lastSnap + 1) ?? lastSnap;
      else if (d < lastSnap - eps) target = [...pts].reverse().find((p) => p < lastSnap - 1) ?? lastSnap;
      lastSnap = target;
      if (Math.abs(target - d) < 2) return;
      const from = scrollY, to = geo.storyTop + target, t0 = performance.now();
      const step = (now) => {
        const k = clamp((now - t0) / 300, 0, 1);
        scrollTo(0, from + (to - from) * quadInOut(k));
        snapAnim = k < 1 ? requestAnimationFrame(step) : 0;
      };
      snapAnim = requestAnimationFrame(step);
    }, 160);
  }

  // Stacked layout: each chapter plays once when it is 15 % up the screen, and resets when it leaves.
  const chPlay = chScenes.map(() => ({ on: false, tp: 0 }));
  function stackedTick(t, dt) {
    // each chapter's backdrop goes out of focus as its card rises from the bottom of the screen to a little past the middle
    const V = innerHeight, tops = chScenes.map((S) => S.card.getBoundingClientRect().top);
    chScenes.forEach((S, k) => artDepth(S, phaseT(V - tops[k], 0, 0.45 * V), "", ART_BLUR * 0.75));
    chScenes.forEach((S, k) => {
      const st = chPlay[k];
      if (!st.on) return;
      if (st.tp < 1) { st.tp = Math.min(1, st.tp + dt / MOBILE_CH_MS[k]); sceneUpdate(S, k, st.tp, { exit: false, pillAt: 0.06 }); }
      sceneAudio(S, t / 1000);
    });
    sceneAudio(speedScene, t / 1000);
  }
  chScenes.forEach((S, k) => {
    new IntersectionObserver((es) => es.forEach((e) => {
      if (storyOn || reduced()) return;
      const st = chPlay[k];
      if (e.isIntersecting) { st.on = true; st.tp = 0; sceneMeasure(S); sceneUpdate(S, k, 0, { exit: false, pillAt: 0.06 }); }
      else { st.on = false; st.tp = 0; sceneUpdate(S, k, 0, { exit: false, pillAt: 0.06 }); }
    }), { rootMargin: "0px 0px -15% 0px" }).observe(S.card);
  });
  function stackedStill() {
    // reduced motion: each chapter shown as it ends, over the sharp art
    chScenes.forEach(artReset);
    chScenes.forEach((S, k) => { sceneMeasure(S); sceneUpdate(S, k, k === 2 ? 0.15 : 1, { exit: false }); if (k === 2) { S.fanCur = 0; S.liftCur = 1; fanRender(S, true); } });
    sceneUpdate(scene, -1, 0);
  }

  function placeScenes() {
    if (storyOn) {
      stage.prepend(outCard);
      speedSlot.textContent = "";
      $$("[data-slot]").forEach((slot) => { if (slot !== speedSlot) slot.textContent = ""; });
      outCard.style.cssText = ""; card.style.cssText = ""; ci.style.transform = ""; cs.style.transform = "";
    } else {
      outCard.style.cssText = ""; coIn.style.transform = "";
      speedSlot.append(outCard, clones.speed);
      ["1", "2", "3"].forEach((k) => $(`[data-slot="${k}"]`).append(clones[k]));
      steps.forEach((s) => s.classList.add("is-on"));
    }
  }
  // the keyboard card's line crawls at 80 units/s of a 928-wide strip as wide as the stage (100 px/s on a 1160 px stage)
  const tickDur = () => {
    const stageW = storyOn && geo ? geo.cw : outCard.offsetWidth || 343;
    coTick.style.setProperty("--tick-dur", (coTick.scrollWidth / 2 / ((80 * stageW) / 928)).toFixed(2) + "s");
  };
  function setMode() {
    const want = wideMQ.matches && !reduced();
    root.classList.toggle("no-story", !want);
    if (want === storyOn && geo) { if (storyOn) { measureStory(); renderStory(); } return; }
    storyOn = want;
    if (!storyOn) speed.style.height = "";
    placeScenes();
    if (storyOn) {
      activeTab = -2; steps.forEach((s) => s.classList.remove("is-on"));
      measureStory(); setActiveTab(-1); renderStory();
    } else {
      setActiveTab(-1); steps.forEach((s) => s.classList.add("is-on"));
      if (reduced()) stackedStill();
    }
    tickDur();
    storyTasks();
  }
  let storyVisible = false;
  function storyTasks() {
    removeTask(storyTick); removeTask(stackedTick);
    if (!storyVisible || reduced()) return;
    addTask(storyOn ? storyTick : stackedTick);
  }
  whileVisible(story, () => { storyVisible = true; mainArc.start(); cloneArc.start(); storyTasks(); },
    () => { storyVisible = false; mainArc.stop(); cloneArc.stop(); storyTasks(); });

  // ---- Features: the card beside the text nearest the card's own middle is the one that plays ----------------------------
  const featEls = $$("[data-feat]");
  const featCards = featEls.map((f) => $(".feat-card", f));
  const featTexts = featEls.map((f) => $(".feat-text", f));
  const LANGS = [
    ["Deutsch", "de", "Kannst du mir bitte den Bericht bis Freitag schicken?"],
    ["Français", "fr", "Je pense qu'on devrait reporter le lancement à la semaine prochaine."],
    ["Español", "es", "Mañana no puedo ir a la reunión, ¿la podemos mover al jueves?"],
    ["Italiano", "it", "Allora, ci vediamo alle otto davanti al cinema."],
    ["Nederlands", "nl", "Kun je de factuur nog een keer sturen?"],
    ["Português", "pt", "Eu acho que a gente precisa de mais tempo pra testar."],
  ];
  const FEAT_MS = [LANGS.length * 4000, 9000, 4500, 5000, 6000];
  const FEAT_START = [0.3, 0, 0, 0, 0];
  const BACK = "cubic-bezier(.34,1.56,.64,1)", EASE = "cubic-bezier(.4,0,.2,1)";
  // card 0: one line of every language streams along the curve; the label and flag switch as each one reaches the middle
  const langCard = (() => {
    const tp = $("[data-lang-text]"), text = tp.parentNode, path = $("#larc"), name = $("[data-lang-name]"), flag = $("[data-flag]");
    const SEP = "   ";
    let line = LANGS[LANGS.length - 1][2] + SEP;
    const starts = [];
    LANGS.forEach((l, i) => { starts[i] = line.length; line += l[2]; if (i < LANGS.length - 1) line += SEP; });
    line += SEP + LANGS[0][2];
    const mid = LANGS.map((l, i) => (starts[i] + l[2].length / 2) / line.length);
    tp.textContent = line;
    let spanLen = 0, anchor = 0, lastI = -1;
    const measure = () => { spanLen = text.getComputedTextLength(); anchor = 0.5 * path.getTotalLength(); };
    const render = (p) => {
      if (!spanLen) measure();
      const N = LANGS.length, half = ((mid[N - 1] - mid[0]) / (N - 1)) * 0.5;
      const a = mid[0] - half, b = mid[N - 1] + half, ff = a + (b - a) * clamp(p, 0, 1);
      tp.setAttribute("startOffset", (anchor - ff * spanLen).toFixed(1));
      let best = 0; mid.forEach((m, i) => { if (Math.abs(m - ff) < Math.abs(mid[best] - ff)) best = i; });
      if (best !== lastI) { lastI = best; name.textContent = LANGS[best][0]; flag.dataset.flag = LANGS[best][1]; }
    };
    return { render, measure };
  })();
  // card 1: a name is typed, learning switches on, Add is pressed, and the new word joins the list
  const dictCard = (() => {
    const field = $("[data-dict-field]"), add = $("[data-dict-add]"), tg = $("[data-dict-tg]"), chip = $("[data-dict-new]");
    const chipsOld = $$(".dict-chips span:not([data-dict-new])");
    const WORD = "Aoife";
    let timers = [], lastBeat = -1, typeRaf = 0;
    const clear = () => { timers.forEach(clearTimeout); timers = []; cancelAnimationFrame(typeRaf); };
    const at = (ms, fn) => timers.push(setTimeout(fn, ms));
    const type = (ms) => {
      const t0 = performance.now();
      const step = (now) => {
        const k = Math.min(1, (now - t0) / ms);
        field.textContent = WORD.slice(0, Math.round(k * WORD.length)) + (k < 1 ? "|" : "");
        if (k < 1) typeRaf = requestAnimationFrame(step);
      };
      field.classList.add("is-typing"); typeRaf = requestAnimationFrame(step);
    };
    const press = (el, s) => { el.style.transition = "transform 180ms " + EASE; el.style.transform = `scale(${s})`; requestAnimationFrame(() => { el.style.transform = "scale(1)"; }); };
    const click = (el) => { el.style.transition = "transform 90ms " + EASE; el.style.transform = "scale(.85)"; at(120, () => { el.style.transition = "transform 340ms " + BACK; el.style.transform = "scale(1)"; }); };
    const setChip = (on) => {
      if (on) { chip.textContent = WORD; chip.style.display = "inline-block"; chip.style.opacity = "0"; chip.style.transform = "scale(.4) translateY(-6px)"; requestAnimationFrame(() => requestAnimationFrame(() => { chip.style.opacity = "1"; chip.style.transform = "none"; })); }
      else { chip.style.display = "none"; }
    };
    const rest = () => { clear(); field.classList.remove("is-typing"); field.textContent = "Add a word"; tg.classList.remove("tg-on"); setChip(false); chipsOld.forEach((c) => { c.style.opacity = ""; }); };
    const render = (tp) => {
      const beat = (tp >= 0.1) + (tp >= 0.55) + (tp >= 0.85);
      if (beat === lastBeat) return;
      lastBeat = beat;
      if (beat === 0) rest();
      else if (beat === 1) { rest(); press(add, 0.92); at(650, () => type(650)); at(1550, () => tg.classList.add("tg-on")); at(2600, () => click(add)); }
      else if (beat === 2) { clear(); field.classList.remove("is-typing"); field.textContent = "Add a word"; tg.classList.add("tg-on"); setChip(true); }
      else { clear(); chip.style.opacity = "0"; chip.style.transform = "scale(.4) translateY(-6px)"; chipsOld.forEach((c) => { c.style.opacity = "0"; }); }
    };
    return { render, reset: () => { lastBeat = -1; rest(); } };
  })();
  // card 2: the trigger lifts out, the slot widens, the full text rises in, then the row fades and starts over
  const snipCard = (() => {
    const line = $("[data-snip-line]"), slot = $("[data-snip]"), say = $("[data-snip-say]"), out = $("[data-snip-out]");
    let sayW = 0, outW = 0, lastBeat = -1;
    const measure = () => { sayW = say.offsetWidth; outW = out.offsetWidth; if (lastBeat >= 0) slot.style.width = (lastBeat >= 1 ? outW : sayW) + "px"; };
    const resetInstant = () => {
      [say, out, slot].forEach((e) => { e.style.transition = "none"; });
      say.style.transform = "translate(-50%,-50%)"; say.style.opacity = "1";
      out.style.transform = "translate(-50%,-50%) translateY(46px)"; out.style.opacity = "0";
      slot.style.width = sayW + "px"; void slot.offsetWidth;
      [say, out, slot].forEach((e) => { e.style.transition = ""; });
    };
    const render = (tp) => {
      if (!sayW) measure();
      const beat = (tp >= 0.3) + (tp >= 0.58) + (tp >= 0.82), was = lastBeat;
      lastBeat = beat;
      line.style.opacity = beat === 3 ? "0" : "1";
      if (beat === 0 && (was === 3 || was === -1)) resetInstant();
      if (beat === 3) return;
      const urlIn = beat === 2;
      say.style.transform = `translate(-50%,-50%) translateY(${beat === 0 ? 0 : -46}px)`;
      say.style.opacity = urlIn ? "0" : "1";
      out.style.transform = `translate(-50%,-50%) translateY(${urlIn ? 0 : 46}px)`;
      out.style.opacity = beat >= 1 ? "1" : "0";
      slot.style.width = (beat >= 1 ? outW : sayW) + "px";
    };
    return { render, measure, reset: () => { lastBeat = -1; } };
  })();
  // card 3: Formal → Casual → Excited; the old message clears at once, the new one waves in word by word
  const toneCard = (() => {
    const pills = $$("[data-tone-i]"), msgs = $$("[data-tone-msg]").map((p) => wrapWords(p, "tw").map((w) => w.el));
    let last = -1;
    const render = (tp) => {
      const active = clamp(Math.floor(clamp(tp, 0, 0.9999) * 3), 0, 2);
      if (active === last) return;
      const lag = last === -1 ? 0 : 210;
      msgs.forEach((spans, t) => spans.forEach((sp, w) => {
        const on = t === active;
        sp.style.transitionDuration = on ? "320ms, 320ms" : "150ms, 150ms";
        sp.style.transitionDelay = on ? lag + w * 45 + "ms" : "0ms";
        sp.style.opacity = on ? "1" : "0";
        sp.style.transform = on ? "translateY(0)" : "translateY(8px)";
      }));
      pills.forEach((p, i) => p.classList.toggle("is-on", i === active));
      last = active;
    };
    return { render, reset: () => { last = -1; } };
  })();
  // card 4: the call is picked up and the transcript arrives two words at a time, greyed until it settles
  const notesCard = (() => {
    const LIVE = [
      ["You", "Okay, let’s start with the beta. Where are we on the crash fix?"],
      ["Priya", "It’s merged. The build went green this morning, so Thursday works."],
      ["Speaker 2", "Support wants the release notes a day early."],
    ];
    const live = $("[data-live]"), who = live.previousElementSibling, go = $(".mt-go");
    let loopN = -1, shownN = -1, lastLoop = -1;
    const render = (tp, loops) => {
      if (loops !== lastLoop) { lastLoop = loops; loopN = (loopN + 1) % LIVE.length; shownN = -1; if (!reduced()) go.animate([{ transform: "scale(1)" }, { transform: "scale(.92)" }, { transform: "scale(1)" }], { duration: 300, easing: EASE }); }
      const [w, line] = LIVE[loopN], words = line.split(" ");
      const shown = Math.min(words.length, Math.floor(span(tp, 0.1, 0.75) * words.length / 2) * 2 + (tp >= 0.75 ? words.length : 0));
      if (shown === shownN) return;
      shownN = shown;
      who.textContent = w;
      live.textContent = words.slice(0, Math.max(0, shown - 2)).join(" ") + " ";
      const ghost = document.createElement("span"); ghost.className = "ghost"; ghost.textContent = words.slice(Math.max(0, shown - 2), shown).join(" ");
      live.append(ghost);
    };
    return { render };
  })();
  const featRender = [(tp) => langCard.render(tp), (tp) => dictCard.render(tp), (tp) => snipCard.render(tp), (tp) => toneCard.render(tp), (tp, n) => notesCard.render(tp, n)];
  const featReset = [() => {}, () => dictCard.reset(), () => snipCard.reset(), () => toneCard.reset(), () => {}];
  const POP = (() => { const kf = []; for (let i = 0; i <= 12; i++) kf.push({ transform: `scale(${(1.04 - 0.04 * backOut2(i / 12)).toFixed(4)})` }); return kf; })();
  let featOn = -1, featTp = 0, featLoops = 0;
  const featPlay = featEls.map(() => ({ on: false, tp: 0, loops: 0 }));
  function featDesktopTick(t, dt) {
    const vh = innerHeight, cardEl = featCards[featOn >= 0 ? featOn : 0], cr = cardEl.getBoundingClientRect();
    const lineY = cr.top + cr.height / 2 - 0.08 * vh;
    let closest = 0, best = Infinity;
    featTexts.forEach((tx, i) => { const r = tx.getBoundingClientRect(), dd = Math.abs(r.top + r.height / 2 - lineY); if (dd < best) { best = dd; closest = i; } });
    if (closest !== featOn) {
      featEls.forEach((f, i) => f.classList.toggle("is-on", i === closest));
      if (featOn >= 0 && !reduced()) featCards[closest].animate(POP, { duration: 300, easing: "linear" });
      if (!reduced()) featReset.forEach((fn) => fn());
      featOn = closest; featTp = FEAT_START[closest]; featLoops = 0;
    }
    if (reduced()) return;
    featTp += dt / FEAT_MS[featOn];
    if (featTp >= 1) { featTp = FEAT_START[featOn]; featLoops++; featReset[featOn](); }
    featRender[featOn](featTp, featLoops);
  }
  function featStackedTick(t, dt) {
    featPlay.forEach((st, i) => {
      if (!st.on) return;
      st.tp += dt / FEAT_MS[i];
      if (st.tp >= 1) { st.tp = FEAT_START[i]; st.loops++; featReset[i](); }
      featRender[i](st.tp, st.loops);
    });
  }
  featEls.forEach((f, i) => new IntersectionObserver((es) => es.forEach((e) => {
    const st = featPlay[i];
    if (e.isIntersecting) st.on = true;
    else { st.on = false; st.tp = FEAT_START[i]; featReset[i](); if (!wideMQ.matches) featRender[i](st.tp, st.loops); }
  }), { rootMargin: "0px 0px -15% 0px" }).observe($(".feat-card", f)));
  const featsEl = $("[data-feats]");
  let featsVisible = false;
  function featMode() {
    removeTask(featDesktopTick); removeTask(featStackedTick);
    if (!wideMQ.matches) { featEls.forEach((f) => f.classList.add("is-on")); featOn = -1; }
    if (!featsVisible) return;
    if (wideMQ.matches) addTask(featDesktopTick);
    else if (!reduced()) addTask(featStackedTick);
  }
  whileVisible(featsEl, () => { featsVisible = true; langCard.measure(); snipCard.measure(); featMode(); }, () => { featsVisible = false; featMode(); }, "0px");
  // still frames for reduced motion
  const featStill = () => { langCard.render(FEAT_START[0]); dictCard.render(0.6); snipCard.render(0.6); toneCard.render(0); notesCard.render(0.9, 0); };

  // the heading underline draws with scroll as it rises from the bottom of the screen to 30 % from the top, then stays drawn
  const ul = $(".ul path");
  let ulLen = 0, ulDone = false, ulLastP = -1, ulLastY = scrollY;
  function underline() {
    if (!ulLen) { ulLen = ul.getTotalLength(); ul.style.strokeDasharray = ulLen; }
    if (reduced()) { ul.style.strokeDashoffset = "0"; return; }
    const r = ul.getBoundingClientRect(), vh = innerHeight, y = scrollY;
    const p = clamp((vh - r.top) / (vh * 0.7), 0, 1);
    let show;
    if (y >= ulLastY) { show = p; if (p >= 1) ulDone = true; } else show = ulDone ? 1 : p;
    ulLastY = y;
    if (show !== ulLastP) { ulLastP = show; ul.style.strokeDashoffset = (ulLen * (1 - show)).toFixed(1); }
  }
  function isNotetakerOn() {
    const t = featTexts[4].getBoundingClientRect();
    return t.top < innerHeight * 0.7 && t.bottom > innerHeight * 0.15;
  }

  // ---- Examples: cards orbit a drum as you scroll, coming in from the left and leaving to the right ------------------
  const exTrack = $("[data-ex]"), exPin = $(".ex-pin", exTrack), exRow = $("[data-ex-row]"), exCards = $$(".xc", exRow);
  let ex = null;
  function exBuild() {
    const orbit = !reduced();
    root.classList.toggle("no-orbit", !orbit);
    if (!orbit) { ex = null; removeTask(exTick); exTrack.style.height = ""; exPin.style.perspective = ""; exCards.forEach((c) => { c.style.transform = ""; c.style.zIndex = ""; c.style.transformOrigin = ""; }); return; }
    const vw = innerWidth, mobile = vw < 768;
    exCards.forEach((c) => { c.style.transform = "none"; });
    const widths = exCards.map((c) => c.offsetWidth || 1);
    const medW = [...widths].sort((a, b) => a - b)[Math.floor(widths.length / 2)];
    const gap = clamp(medW * (mobile ? 0.22 : 0.14), 32, 160);
    const offsets = [0];
    for (let i = 1; i < exCards.length; i++) offsets[i] = offsets[i - 1] + (widths[i - 1] + widths[i]) / 2 + gap;
    const spanPx = offsets[offsets.length - 1];
    const orbitPx = Math.max(220, medW * 0.65), persp = medW * 2.6, rotHalf = medW * 2.1;
    exPin.style.perspective = persp.toFixed(0) + "px";
    exCards.forEach((c) => { c.style.transformOrigin = `50% 50% -${orbitPx.toFixed(0)}px`; });
    const V = innerHeight;
    exTrack.style.height = Math.round(V + spanPx * 0.85) + "px";
    const top = exTrack.getBoundingClientRect().top + scrollY;
    ex = { offsets, spanPx, orbitPx, persp, rotHalf, top, len: Math.round(spanPx * 0.85), mobile, head: ex ? ex.head : 0, from: 0, to: 0, t0: -1 };
    ex.head = ex.to = clamp(ex.head, 0, spanPx);
    exRender(ex.head);
    if (exVisible) addTask(exTick);
  }
  function exRender(head) {
    const { offsets, orbitPx, persp, rotHalf } = ex;
    const xs = exCards.map((c, j) => {
      const sx = head - offsets[j];
      const p = clamp((sx + rotHalf) / (rotHalf * 2), 0, 1), rot = -50 + 100 * quadInOut(p);
      const f = persp / (persp + orbitPx * (1 - Math.cos((rot * Math.PI) / 180)));
      c.style.transform = `translate(-50%, -50%) translate3d(${(sx / f).toFixed(1)}px, 0, 0) rotateX(${rot.toFixed(2)}deg)`;
      return Math.abs(sx);
    });
    const order = exCards.map((_, i) => i).sort((a, b) => xs[a] - xs[b]);
    order.forEach((ci2, rank) => { exCards[ci2].style.zIndex = String(exCards.length - rank); });
  }
  function exTick(t, dt) {
    if (!ex) return;
    const target = span(scrollY, ex.top, ex.top + ex.len) * ex.spanPx;
    if (ex.mobile) { if (target !== ex.head) { ex.head = target; exRender(target); } return; }
    // scrubbed with a 1.5 s catch-up, like the reference: every scroll restarts the catch-up from where the cards are
    if (Math.abs(target - ex.to) > 0.5) { ex.from = ex.head; ex.to = target; ex.t0 = t - dt; }
    if (ex.t0 >= 0) {
      const k = clamp((t - ex.t0) / 1500, 0, 1);
      ex.head = ex.from + (ex.to - ex.from) * quartOut(k);
      if (k >= 1) ex.t0 = -1;
      exRender(ex.head);
    }
  }
  let exVisible = false;
  whileVisible($(".ex"), () => { exVisible = true; if (ex) addTask(exTick); }, () => { exVisible = false; removeTask(exTick); });

  // ---- FAQ ----------------------------------------------------------------------------------------------------------
  const faq = $("[data-faq]");
  const qButtons = $$(".faq-list button", faq);
  const chat = $("[data-faq-chat]"), ask = $("[data-faq-ask]"), ans = $("[data-faq-ans]");
  const list = $(".faq-list", faq), scrollBox = $(".faq-scroll", faq);
  let swapT = 0;
  // the answer fades up and out, the new one swaps in after 200 ms while the bubble resizes
  const showAnswer = (btn, instant) => {
    const swap = () => { ask.textContent = btn.textContent; ans.innerHTML = $("#" + btn.getAttribute("aria-controls")).innerHTML; };
    clearTimeout(swapT);
    if (instant || reduced()) { swap(); ans.style.height = ""; chat.classList.remove("is-hidden"); return; }
    const h0 = ans.offsetHeight;
    ans.style.height = h0 + "px";
    chat.classList.add("is-hidden");
    swapT = setTimeout(() => {
      swap();
      ans.style.height = "auto"; const h1 = ans.offsetHeight; ans.style.height = h0 + "px"; void ans.offsetHeight;
      ans.style.height = h1 + "px";
      chat.classList.remove("is-hidden");
      swapT = setTimeout(() => { ans.style.height = ""; }, 250);
    }, 200);
  };
  const select = (btn, toggle) => {
    const open = btn.getAttribute("aria-expanded") === "true";
    if (phoneMQ.matches && toggle && open) { btn.setAttribute("aria-expanded", "false"); $("#" + btn.getAttribute("aria-controls")).hidden = true; return; }
    if (!phoneMQ.matches && open) return;
    qButtons.forEach((b) => {
      const on = b === btn;
      b.setAttribute("aria-expanded", String(on));
      $("#" + b.getAttribute("aria-controls")).hidden = !on;
    });
    showAnswer(btn, phoneMQ.matches);
  };
  qButtons.forEach((b) => b.addEventListener("click", () => select(b, true)));
  const fades = () => {
    const max = list.scrollHeight - list.clientHeight, st = list.scrollTop;
    const scrollable = max > 4;
    scrollBox.classList.toggle("fade-top", scrollable && st > 4);
    scrollBox.classList.toggle("fade-bot", scrollable && st < max - 4);
  };
  list.addEventListener("scroll", fades, { passive: true });
  fades();
  $$("[data-faq-open]").forEach((a) => a.addEventListener("click", () => {
    const b = qButtons[+a.dataset.faqOpen - 1];
    if (b) { select(b, false); setTimeout(() => b.focus({ preventScroll: true }), 50); }
  }));

  // ---- Footer: the logo's bars spring up when the footer comes into view -------------------------------------------
  const giant = $("[data-giant]"), giantBars = $$("[data-giant-bars] rect");
  // keyframes per bar as [frame of 68, height as a share of the tallest bar]; the last one is the bar's own height
  const BAR_KEYS = [
    [[5, 0], [18, 0.629], [31, 0.324], [46, 0.466], [64, 1]],
    [[2, 0], [16, 0.826], [28, 0.485], [40, 0.365], [60, 1]],
    [[0, 0], [13, 0.999], [26, 0.829], [37, 0.501], [50, 0.805], [63, 1]],
    [[2, 0], [16, 0.751], [28, 0.437], [40, 0.628], [58, 1]],
    [[5, 0], [18, 0.452], [31, 0.742], [45, 0.497], [67, 1]],
  ];
  let giantAnims = [];
  const giantFinal = giantBars.map((r) => +r.getAttribute("height"));
  const giantMax = Math.max(...giantFinal);
  // at rest each bar is a dot (its own width tall), the way the reference's lines start as round caps
  const giantDot = giantBars.map((r, i) => +r.getAttribute("width") / giantFinal[i]);
  const giantReset = () => { giantAnims.forEach((a) => a.cancel()); giantAnims = []; giantBars.forEach((r, i) => { r.style.transform = reduced() ? "" : `scaleY(${giantDot[i].toFixed(3)})`; }); };
  const giantPlay = () => {
    giantAnims.forEach((a) => a.cancel());
    giantAnims = giantBars.map((r, i) => {
      const keys = BAR_KEYS[i], dot = giantDot[i], kf = [{ offset: 0, transform: `scaleY(${dot.toFixed(3)})` }];
      keys.forEach(([fr, v], k) => {
        const s = k === keys.length - 1 ? 1 : Math.max(dot, (v * giantMax) / giantFinal[i]);
        kf.push({ offset: fr / 68, transform: `scaleY(${s.toFixed(3)})`, easing: k === keys.length - 2 ? "cubic-bezier(.333,0,.19,1)" : "cubic-bezier(.333,0,.667,1)" });
      });
      kf[0].easing = "linear";
      kf.push({ offset: 1, transform: "scaleY(1)" });
      return r.animate(kf, { duration: 1000, fill: "both" });
    });
  };
  new IntersectionObserver((es) => es.forEach((e) => {
    if (reduced()) return;
    if (e.isIntersecting) giantPlay();
  }), { rootMargin: "0px 0px -20% 0px" }).observe(giant);
  new IntersectionObserver((es) => es.forEach((e) => { if (!e.isIntersecting && !reduced()) giantReset(); })).observe(giant);
  giantReset();

  // ---- Scroll + resize ---------------------------------------------------------------------------------------------
  let sTick = false;
  const onScroll = () => {
    if (sTick) return; sTick = true;
    requestAnimationFrame(() => {
      sTick = false;
      renderStory(); underline(); navScroll(); snapCheck();
      setSeg(isNotetakerOn() ? "notetaker" : "dictation");
    });
  };
  addEventListener("scroll", onScroll, { passive: true });
  let rT = 0, lastW = root.clientWidth, lastH = innerHeight;
  const relayout = () => {
    setMode(); if (storyOn) measureStory(); renderStory();
    exBuild(); heroAPI.layout(); setMarquee(); tickDur(); mainArc.measure(); cloneArc.measure(); langCard.measure(); snipCard.measure(); underline();
  };
  addEventListener("resize", () => {
    clearTimeout(rT);
    rT = setTimeout(() => {
      // Phones resize the viewport as the toolbar hides; only re-measure for real changes.
      if (root.clientWidth === lastW && Math.abs(innerHeight - lastH) < 120) return;
      lastW = root.clientWidth; lastH = innerHeight;
      relayout();
    }, 150);
  });
  wideMQ.addEventListener("change", () => { setMode(); featMode(); });
  reduceMQ.addEventListener("change", () => {
    relayout(); featMode(); heroAPI.reduceChanged();
    if (reduced()) { featStill(); giantReset(); removeTask(cornersTick); $$(".speed, .ex").forEach((el) => { el.style.borderRadius = ""; }); }
  });
  setMode();
  exBuild();
  setMarquee();
  underline();
  const featFirst = () => { langCard.measure(); snipCard.measure(); [0, 1, 2, 3].forEach((i) => featRender[i](FEAT_START[i], 0)); if (reduced()) featStill(); };
  featFirst();
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => { relayout(); chScenes.forEach(sceneMeasure); featFirst(); });
  addEventListener("load", () => { relayout(); navScroll(); });
})();
