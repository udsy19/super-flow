(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const reduceMQ = matchMedia("(prefers-reduced-motion: reduce)");
  const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  // ---- Copy buttons -------------------------------------------------------------------------------------------
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
      clearTimeout(btn._t);
      btn._t = setTimeout(() => { btn.textContent = btn.dataset.label; }, 1600);
    });
  });

  // ---- The rig: audio → heard → typed ------------------------------------------------------------------------
  // Real cases from docs/specs/cleanup-eval.jsonl with the output and cleanup time Super Flow produced (M4 Pro).
  // In `heard`, a leading ~ marks a filler sound, - a word cleanup removes, * a word cleanup rewrites.
  const EXAMPLES = [
    { name: "Fillers", target: "Any app · Formal", ms: 172,
      heard: "-The, ~uh, the budget for Q3 is, ~um, about *forty *thousand *dollars.",
      typed: "The budget for Q3 is about $40,000." },
    { name: "Correction", target: "Any app · Formal", ms: 73,
      heard: "-Send -it -to -John, -no -wait, send it to Sarah.",
      typed: "Send it to Sarah." },
    { name: "List", target: "Any app · Formal · Medium", ms: 222,
      heard: "*groceries for this week eggs milk ~uh bread -and -like two bags of coffee",
      typed: "Groceries for this week:\n- Eggs\n- Milk\n- Bread\n- Two bags of coffee" },
    { name: "Terminal", target: "Terminal", ms: 96, mono: true,
      heard: "npm install *dash *dash *save *dash *dev typescript",
      typed: "npm install --save-dev typescript" },
    { name: "Numbers", target: "Any app · Formal", ms: 186,
      heard: "Call me at *five *five *five, *one *two *three, *four *five *six *seven.",
      typed: "Call me at 555-123-4567." },
    { name: "French", target: "Any app · Formal", ms: 135, lang: "fr",
      heard: "~euh je pense qu'on devrait ~euh reporter le lancement à la semaine prochaine",
      typed: "Je pense qu'on devrait reporter le lancement à la semaine prochaine." },
  ];

  const IDLE = 0.5;      // before fn goes down
  const LEAD = 0.3;      // fn down → first word
  const POST = 0.15;     // the app's post-roll
  const PROC = 0.65;     // post-roll + this ≈ the measured 0.8 s from key-up to text
  const MARK = 0.12;     // when the cleanup marks start, after processing begins

  for (const ex of EXAMPLES) {
    let t = LEAD;
    ex.tokens = ex.heard.split(" ").map((raw) => {
      const p = raw[0];
      const kind = p === "~" ? "hum" : p === "-" ? "cut" : p === "*" ? "chg" : "";
      const text = kind ? raw.slice(1) : raw;
      const letters = text.replace(/[^\p{L}\p{N}]/gu, "").length;
      const tk = { text, kind, letters, start: t, dur: kind === "hum" ? 0.36 : Math.max(0.17, 0.08 + 0.056 * letters) };
      t += tk.dur + (/[.?!:]$/.test(text) ? 0.24 : /,$/.test(text) ? 0.15 : 0.035);
      return tk;
    });
    ex.keyUp = t;                       // seconds after fn went down
    ex.end = t + POST;                  // mic closes
    ex.typedAt = ex.end + PROC;         // text lands
    ex.hold = Math.min(5.2, 3.4 + ex.typed.length * 0.018);
    ex.total = IDLE + ex.typedAt + ex.hold;
  }

  function hash(a, b) {
    let h = Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  }
  function tokenAt(ex, t) {
    const toks = ex.tokens;
    for (let i = 0; i < toks.length; i++) if (t >= toks[i].start && t < toks[i].start + toks[i].dur) return i;
    return -1;
  }
  function amp(ex, t, i) {
    const n = hash(i + 11, Math.floor(t * 90));
    if (i < 0) return 0.02 + 0.03 * n;
    const tk = ex.tokens[i];
    const u = (t - tk.start) / tk.dur;
    if (tk.kind === "hum") { // a filler is a flat, sustained hum
      const edge = Math.max(0, Math.min(1, u / 0.12, (1 - u) / 0.12));
      return (0.25 + 0.04 * Math.sin(t * 40) + 0.04 * n) * edge;
    }
    const syl = Math.max(1, Math.round(tk.letters / 3));
    const env = Math.pow(Math.sin(Math.PI * u), 0.6);
    const mod = 0.45 + 0.55 * Math.abs(Math.sin(Math.PI * syl * u));
    return (0.5 + 0.42 * hash(i + 3, 7)) * env * mod * (0.78 + 0.38 * n);
  }

  const rig = $("#rig");
  if (rig) {
    const el = {
      key: $("[data-key]", rig), state: $("[data-state]", rig), target: $("[data-target]", rig),
      canvas: $("[data-wave]", rig), ruler: $("[data-ruler]", rig), heard: $("[data-heard]", rig),
      typed: $("[data-typed]", rig), ms: $("[data-ms]", rig), pill: $("[data-pill]", rig),
      bars: $$("[data-pill] .pw i", rig), tabs: $("[data-tabs]", rig), pause: $("[data-pause]", rig),
    };
    const WEIGHTS = Array.from({ length: 10 }, (_, i) => Math.max(0, 1 - Math.pow(4.5 - i, 2) / 48));
    const PHASE = [0, 0.1, 0.2, 0.3, 0.4, -0.5, -0.4, -0.3, -0.2, -0.1];
    let index = 0, elapsed = 0, playing = !reduceMQ.matches, userPaused = false, visible = true, raf = 0, last = 0;
    let shown = { ex: -1 };
    let colors = {};
    const readColors = () => { colors = { ink: css("--ink"), lilac: css("--lilac"), line: css("--line-2"), wash: css("--lilac-wash") }; };
    readColors();

    // Tabs
    const tabButtons = EXAMPLES.map((ex, i) => {
      const b = document.createElement("button");
      b.type = "button"; b.className = "tab"; b.innerHTML = `${esc(ex.name)}<i></i>`;
      b.addEventListener("click", () => select(i));
      el.tabs.appendChild(b);
      return b;
    });

    function setText(node, text) { if (node.textContent !== text) node.textContent = text; }

    function buildExample(i) {
      const ex = EXAMPLES[i];
      el.heard.innerHTML = ex.tokens.map((tk, k) =>
        `<span class="w${tk.kind === "hum" ? " hum" : ""}" data-i="${k}">${esc(tk.text)}</span>`).join(" ");
      el.heard.lang = ex.lang || "en";
      el.typed.lang = ex.lang || "en";
      el.typed.classList.toggle("mono", !!ex.mono);
      el.typed.innerHTML = '<span class="caret"></span>';
      setText(el.target, "→ " + ex.target);
      el.words = $$(".w", el.heard);
      // Ruler: whole seconds, plus the moment fn is released.
      const ticks = [];
      for (let s = 0; s <= ex.end; s += 1) {
        if (s > ex.keyUp - 0.55) break;
        ticks.push(`<span style="left:${(s / ex.end) * 100}%">${s} s</span>`);
      }
      ticks.push(`<span class="k" data-k hidden style="right:${(1 - ex.keyUp / ex.end) * 100}%">let go</span>`);
      el.ruler.innerHTML = ticks.join("");
      el.kmark = $("[data-k]", el.ruler);
      tabButtons.forEach((b, k) => b.setAttribute("aria-current", k === i ? "true" : "false"));
      shown = { ex: i, phase: "", on: -1, marked: false, typed: false };
    }

    function render(t) {
      const ex = EXAMPLES[index];
      if (shown.ex !== index) buildExample(index);
      const r = t - IDLE;                       // time since fn went down
      const held = r >= 0 && r < ex.keyUp;
      const phase = r < 0 ? "idle" : r < ex.keyUp ? "listen" : r < ex.end ? "post" : r < ex.typedAt ? "proc" : "typed";

      el.key.classList.toggle("down", held);
      el.pill.className = "pill " + (phase === "idle" || phase === "typed" ? "is-rest" : phase === "proc" ? "is-proc" : "is-ptt");
      const stateText = phase === "idle" ? "Hold fn to talk"
        : phase === "listen" ? `Listening ${r.toFixed(1)} s`
        : phase === "post" ? "Let go"
        : phase === "proc" ? "Cleaning up"
        : "Typed 0.8 s after let go";
      setText(el.state, stateText);

      // Heard words appear a beat after they are spoken.
      let on = -1;
      ex.tokens.forEach((tk, k) => { if (r >= tk.start + Math.min(0.12, tk.dur * 0.6)) on = k; });
      if (on !== shown.on) { el.words.forEach((w, k) => w.classList.toggle("on", k <= on)); shown.on = on; }

      // Cleanup marks: staggered, while the bar spins.
      const markT = r - (ex.end + MARK);
      if (markT >= 0 || shown.marked) {
        el.words.forEach((w, k) => {
          const due = markT >= k * 0.025;
          const kind = ex.tokens[k].kind;
          w.classList.toggle("cut", due && (kind === "hum" || kind === "cut"));
          w.classList.toggle("chg", due && kind === "chg");
        });
        shown.marked = markT >= 0;
      }
      el.kmark.hidden = r < ex.keyUp;

      // Typed text lands at once: it is pasted, not typed.
      const isTyped = phase === "typed";
      if (isTyped !== shown.typed) {
        if (isTyped) {
          const prompt = ex.mono ? '<span class="tprompt">~ % </span>' : "";
          el.typed.innerHTML = `${prompt}<span class="txt pre">${esc(ex.typed)}</span><span class="caret"></span>`;
          const txt = $(".txt", el.typed);
          requestAnimationFrame(() => txt && txt.classList.remove("pre"));
          setText(el.ms, `${ex.ms} ms`);
        } else {
          el.typed.innerHTML = '<span class="caret"></span>';
          setText(el.ms, "—");
        }
        shown.typed = isTyped;
      }

      // The bar's own waveform follows the audio level.
      if (phase === "listen" || phase === "post" || phase === "proc") {
        const level = phase === "proc" ? 0 : amp(ex, r, tokenAt(ex, r));
        el.bars.forEach((b, k) => {
          const osc = 1 + 0.3 * Math.sin(2 * Math.PI * (t + PHASE[k]));
          const h = Math.min(18, 2 + 14 * WEIGHTS[k] * Math.min(1, level * 1.7) * osc);
          b.style.height = h.toFixed(1) + "px";
          b.style.opacity = level > 0.08 ? "1" : "0.4";
        });
      }

      drawWave(ex, Math.max(0, Math.min(r, ex.end)), r >= ex.end + MARK, r);
      const bar = tabButtons[index].querySelector("i");
      if (bar) bar.style.transform = `scaleX(${playing ? Math.min(1, t / ex.total) : 0})`;
    }

    function drawWave(ex, now, cleaned, r) {
      const c = el.canvas;
      const w = c.clientWidth, h = c.clientHeight, dpr = Math.min(2, window.devicePixelRatio || 1);
      if (!w || !h) return;
      if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) {
        c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
      }
      const ctx = c.getContext("2d");
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      const T = ex.end;
      const xKey = (ex.keyUp / T) * w;
      // Post-roll: the 150 ms the microphone stays open after fn comes up.
      if (r >= ex.keyUp) {
        ctx.globalAlpha = 1; ctx.fillStyle = colors.wash; ctx.fillRect(xKey, 0, w - xKey, h);
      }
      ctx.globalAlpha = 1; ctx.fillStyle = colors.line; ctx.fillRect(0, Math.round(h / 2), Math.min(w, (now / T) * w), 1);
      const pitch = w < 480 ? 3 : 4, bw = 2;
      const n = Math.floor((w + pitch - bw) / pitch);
      for (let k = 0; k < n; k++) {
        const t = ((k * pitch + bw / 2) / w) * T;
        if (t > now) break;
        const i = tokenAt(ex, t);
        const a = amp(ex, t, i);
        const bh = Math.max(2, a * (h - 6));
        const kind = i >= 0 ? ex.tokens[i].kind : "";
        const removed = cleaned && (kind === "hum" || kind === "cut");
        ctx.fillStyle = removed ? colors.lilac : colors.ink;
        ctx.globalAlpha = removed ? 0.7 : t > ex.keyUp ? 0.3 : 0.88;
        const y = (h - bh) / 2;
        if (ctx.roundRect) { ctx.beginPath(); ctx.roundRect(k * pitch, y, bw, bh, 1); ctx.fill(); }
        else ctx.fillRect(k * pitch, y, bw, bh);
      }
      if (r >= ex.keyUp) { // the moment fn came up
        ctx.globalAlpha = 1; ctx.fillStyle = colors.lilac;
        for (let y = 0; y < h; y += 4) ctx.fillRect(Math.round(xKey), y, 1, 2);
      }
      if (now > 0 && now < T) { // recording head
        ctx.globalAlpha = 1; ctx.fillStyle = colors.ink; ctx.fillRect(Math.round((now / T) * w), 0, 1, h);
      }
    }

    // Lanes keep one height for every example, so the page never shifts while the demo plays.
    function fit() {
      const keep = index;
      let hh = 0, th = 0;
      el.heard.style.minHeight = ""; el.typed.style.minHeight = "";
      EXAMPLES.forEach((ex, i) => {
        index = i; buildExample(i);
        el.words.forEach((w) => w.classList.add("on"));
        hh = Math.max(hh, el.heard.offsetHeight);
        el.typed.classList.toggle("mono", !!ex.mono);
        el.typed.innerHTML = `${ex.mono ? '<span class="tprompt">~ % </span>' : ""}<span class="txt">${esc(ex.typed)}</span><span class="caret"></span>`;
        th = Math.max(th, el.typed.offsetHeight);
      });
      el.heard.style.minHeight = hh + "px";
      el.typed.style.minHeight = th + "px";
      index = keep; shown = { ex: -1 };
      render(elapsed);
    }

    function finalTime(ex) { return IDLE + ex.typedAt + 0.01; }

    function select(i) {
      index = i;
      elapsed = playing ? 0 : finalTime(EXAMPLES[i]);
      shown = { ex: -1 };
      tabButtons.forEach((b) => { const bar = b.querySelector("i"); if (bar) bar.style.transform = "scaleX(0)"; });
      render(elapsed);
      if (playing) start();
    }

    function frame(now) {
      raf = 0;
      if (!playing || !visible) return;
      const dt = Math.min(0.1, (now - last) / 1000);
      last = now;
      elapsed += dt;
      const ex = EXAMPLES[index];
      if (elapsed >= ex.total) {
        const bar = tabButtons[index].querySelector("i"); if (bar) bar.style.transform = "scaleX(0)";
        index = (index + 1) % EXAMPLES.length; elapsed = 0; shown = { ex: -1 };
      }
      render(elapsed);
      raf = requestAnimationFrame(frame);
    }
    function start() { if (!raf && playing && visible) { last = performance.now(); raf = requestAnimationFrame(frame); } }
    function stop() { if (raf) cancelAnimationFrame(raf); raf = 0; }

    function setPlaying(p) {
      playing = p;
      el.pause.textContent = p ? "Pause" : "Play";
      el.pause.setAttribute("aria-pressed", p ? "false" : "true");
      if (p) {
        if (elapsed >= finalTime(EXAMPLES[index]) && elapsed >= EXAMPLES[index].total - 0.01) elapsed = 0;
        start();
      } else { stop(); render(elapsed); }
    }
    el.pause.addEventListener("click", () => { userPaused = playing; setPlaying(!playing); });

    function applyMotionPref() {
      if (reduceMQ.matches) {
        el.pause.hidden = true; stop(); playing = false;
        elapsed = finalTime(EXAMPLES[index]); shown = { ex: -1 }; render(elapsed);
      } else {
        el.pause.hidden = false;
        if (!userPaused) setPlaying(true);
      }
    }
    reduceMQ.addEventListener ? reduceMQ.addEventListener("change", applyMotionPref) : reduceMQ.addListener(applyMotionPref);

    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      if (visible) start(); else stop();
    }, { threshold: 0.15 }).observe(rig);
    document.addEventListener("visibilitychange", () => { if (document.hidden) stop(); else start(); });

    let lastWidth = rig.clientWidth, rt = 0;
    window.addEventListener("resize", () => {
      clearTimeout(rt);
      rt = setTimeout(() => { if (rig.clientWidth !== lastWidth) { lastWidth = rig.clientWidth; fit(); } else render(elapsed); }, 120);
    });
    matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", () => { readColors(); render(elapsed); });

    if (reduceMQ.matches) { playing = false; el.pause.hidden = true; elapsed = finalTime(EXAMPLES[0]); }
    fit();
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit);
    start();
  }

  // ---- Command Mode demo ---------------------------------------------------------------------------------------
  const sel = $("[data-cmd-sel]");
  if (sel) {
    const wrap = $("[data-cmd-wrap]"), pill = $("[data-cmd-pill]"), said = $("[data-said]"), live = $("[data-cmd-live]");
    const chips = $$("[data-cmd]");
    const VARIANTS = {
      reset: { said: "", text: sel.textContent },
      short: { said: "make this shorter", text: "Quick update: the beta goes out on Thursday, then we’ll spend two weeks fixing what people report before the public launch." },
      list: { said: "turn it into a list", text: "Quick update on where things stand:\n- The beta goes out on Thursday\n- Then two weeks of fixing what people report\n- Then the public launch" },
      es: { said: "translate to Spanish", text: "Quería daros una actualización rápida de cómo van las cosas. La beta sale el jueves y, después, dedicaremos dos semanas a corregir todo lo que se reporte antes del lanzamiento público." },
    };
    let timers = [];
    const later = (ms, fn) => timers.push(setTimeout(fn, ms));

    function fitCmd() {
      const current = sel.textContent;
      wrap.style.minHeight = "";
      let h = 0;
      Object.values(VARIANTS).forEach((v) => { sel.textContent = v.text; h = Math.max(h, wrap.offsetHeight); });
      sel.textContent = current;
      wrap.style.minHeight = h + "px";
    }
    function run(key) {
      timers.forEach(clearTimeout); timers = [];
      const v = VARIANTS[key];
      chips.forEach((c) => c.setAttribute("aria-pressed", c.dataset.cmd === key && key !== "reset" ? "true" : "false"));
      if (key === "reset" || reduceMQ.matches) {
        sel.textContent = v.text; sel.classList.remove("fade"); said.classList.remove("on");
        pill.className = "pill is-rest is-cmd demo";
        live.textContent = key === "reset" ? "Selection restored." : `Selection replaced: ${v.text}`;
        return;
      }
      said.textContent = `“${v.said}”`; said.classList.add("on");
      pill.className = "pill is-ptt is-cmd demo";
      later(1300, () => { pill.className = "pill is-proc is-cmd demo"; sel.classList.add("fade"); });
      later(2000, () => {
        sel.textContent = v.text; sel.classList.remove("fade");
        pill.className = "pill is-rest is-cmd demo";
        live.textContent = `Selection replaced: ${v.text}`;
      });
      later(3000, () => said.classList.remove("on"));
    }
    chips.forEach((c) => c.addEventListener("click", () => run(c.dataset.cmd)));
    fitCmd();
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitCmd);
    let cw = wrap.clientWidth;
    window.addEventListener("resize", () => { if (wrap.clientWidth !== cw) { cw = wrap.clientWidth; fitCmd(); } });
  }

  // ---- Meeting page tabs ---------------------------------------------------------------------------------------
  const tabs = $$('.mtabs [role="tab"]');
  if (tabs.length) {
    const activate = (tab, focus) => {
      tabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute("aria-selected", on ? "true" : "false");
        t.tabIndex = on ? 0 : -1;
        document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
      });
      if (focus) tab.focus();
    };
    tabs.forEach((t, i) => {
      t.addEventListener("click", () => activate(t, false));
      t.addEventListener("keydown", (e) => {
        const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (d) { e.preventDefault(); activate(tabs[(i + d + tabs.length) % tabs.length], true); }
        else if (e.key === "Home") { e.preventDefault(); activate(tabs[0], true); }
        else if (e.key === "End") { e.preventDefault(); activate(tabs[tabs.length - 1], true); }
      });
    });
  }

  // ---- Two recording tracks: you and them take turns -----------------------------------------------------------
  const turns = [["you", 7], ["them", 8], ["them", 5], ["you", 5], ["them", 4], ["you", 3]];
  const total = turns.reduce((s, x) => s + x[1], 0);
  $$("[data-track]").forEach((track) => {
    const who = track.dataset.track, n = 140;
    let html = "";
    for (let k = 0; k < n; k++) {
      let t = (k / n) * total, owner = turns[turns.length - 1][0];
      for (const [w, d] of turns) { if (t < d) { owner = w; break; } t -= d; }
      const talking = owner === who && hash(k, 5) > 0.12;
      const hgt = talking ? 4 + 24 * Math.pow(hash(k, who === "you" ? 1 : 2), 1.4) * (0.6 + 0.4 * Math.abs(Math.sin(k * 0.7))) : 2 + 2 * hash(k, 9);
      html += `<i class="${talking ? "" : "q"}" style="height:${hgt.toFixed(1)}px"></i>`;
    }
    track.innerHTML = html;
  });
})();
