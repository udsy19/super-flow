(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const root = document.documentElement;
  const wideMQ = matchMedia("(min-width: 992px)");
  const phoneMQ = matchMedia("(max-width: 767px)");
  const reduceMQ = matchMedia("(prefers-reduced-motion: reduce)");
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const span = (v, a, b) => clamp((v - a) / (b - a), 0, 1);
  const SVGNS = "http://www.w3.org/2000/svg";

  // Runs fn while el is on screen and the tab is visible.
  function whileVisible(el, start, stop) {
    let on = false, seen = false;
    const sync = () => { const want = seen && !document.hidden; if (want !== on) { on = want; (on ? start : stop)(); } };
    new IntersectionObserver((es) => { seen = es[es.length - 1].isIntersecting; sync(); }, { rootMargin: "80px 0px" }).observe(el);
    document.addEventListener("visibilitychange", sync);
  }
  // CSS animations pause when their section is off screen.
  $$(".strip, .hero, .story, .feats, .ex, .foot").forEach((el) => whileVisible(el, () => el.classList.remove("paused"), () => el.classList.add("paused")));

  // ---- Copy ---------------------------------------------------------------------------------------------------
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

  // ---- Buttons: the label ripples on hover ---------------------------------------------------------------------
  $$(".btn").forEach((btn) => {
    const label = btn.textContent.replace(/\s+/g, " ").trim();
    btn.setAttribute("aria-label", btn.querySelector(".lg") ? btn.querySelector(".lg").textContent : label);
    const targets = btn.querySelector(".lg") ? [btn.querySelector(".lg"), btn.querySelector(".sm")] : [btn];
    targets.forEach((host) => {
      [...host.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim()).forEach((node) => {
        const frag = document.createElement("span");
        frag.className = "wave";
        [...node.textContent.trim()].forEach((ch, i) => {
          const s = document.createElement("span");
          s.className = "wave-l"; s.textContent = ch; s.setAttribute("aria-hidden", "true");
          s.style.setProperty("--wy", (Math.sin(i * 0.85) * 3.2).toFixed(2) + "px");
          s.style.transitionDelay = i * 12 + "ms";
          frag.appendChild(s);
        });
        node.replaceWith(frag);
      });
    });
  });

  // ---- Nav ----------------------------------------------------------------------------------------------------
  const nav = $("[data-nav]"), burger = $("[data-burger]"), menu = $("[data-menu]");
  const setMenu = (open) => {
    burger.setAttribute("aria-expanded", String(open));
    menu.hidden = !open;
    nav.classList.toggle("is-open", open);
  };
  burger.addEventListener("click", () => setMenu(burger.getAttribute("aria-expanded") !== "true"));
  menu.addEventListener("click", (e) => { if (e.target.closest("a")) setMenu(false); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !menu.hidden) { setMenu(false); burger.focus(); } });
  phoneMQ.addEventListener("change", () => setMenu(false));
  const segs = $$("[data-seg]");
  const setSeg = (name) => segs.forEach((a) => {
    const on = a.dataset.seg === name;
    a.classList.toggle("seg-on", on);
    if (on) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current");
  });

  // ---- Hero ribbon --------------------------------------------------------------------------------------------
  const ribbon = $("[data-ribbon]");
  if (ribbon) {
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
    const bars = $("[data-bars]", ribbon);
    const N = 17, bw = 3.6, gap = 2.3, x0 = 720 - (N * bw + (N - 1) * gap) / 2;
    for (let i = 0; i < N; i++) {
      const r = document.createElementNS(SVGNS, "rect");
      const h = 10 + 30 * Math.pow(Math.sin((i + 1) * 1.7) * 0.5 + 0.5, 1.4);
      r.setAttribute("x", (x0 + i * (bw + gap)).toFixed(1)); r.setAttribute("width", bw);
      r.setAttribute("y", (455 - h / 2).toFixed(1)); r.setAttribute("height", h.toFixed(1)); r.setAttribute("rx", bw / 2);
      bars.appendChild(r);
    }
    const barEls = $$("rect", bars);
    const chip = $("[data-chip]", ribbon), chipText = $("[data-chip-text]", ribbon), chipRect = $("rect", chip);
    const CHIPS = ["Filler removed", "Correction applied", "Number formatted", "Repeat removed"];
    let chipI = 0, rawLen = 0, cleanLen = 0, off = 0, last = 0, raf = 0, chipT = 0;
    const placeChip = () => {
      const w = chipText.getComputedTextLength() + 48;
      chipRect.setAttribute("width", w.toFixed(1));
      chip.setAttribute("transform", `translate(${(720 - w / 2).toFixed(1)} 368) rotate(-3 ${(w / 2).toFixed(1)} 15)`);
    };
    const layout = () => {
      const p = phoneMQ.matches ? PATHS.phone : PATHS.wide;
      raw.setAttribute("d", p.raw); clean.setAttribute("d", p.clean);
      rawLen = rawTP.parentNode.getComputedTextLength() / 4;
      cleanLen = cleanTP.parentNode.getComputedTextLength() / 4;
      placeChip();
      draw();
    };
    const draw = () => {
      const pr = raw.getTotalLength();
      // Raw words travel toward the bar; clean words leave it.
      rawTP.setAttribute("startOffset", (pr - rawLen * 3 + (off % rawLen)).toFixed(1));
      cleanTP.setAttribute("startOffset", ((off % cleanLen) - cleanLen).toFixed(1));
    };
    const frame = (t) => {
      const dt = last ? Math.min(0.05, (t - last) / 1000) : 0; last = t;
      off += dt * 46;
      draw();
      for (let i = 0; i < barEls.length; i++) {
        const v = 0.35 + 0.65 * Math.abs(Math.sin(t / 260 + i * 0.9) * Math.sin(t / 610 + i * 0.37));
        barEls[i].style.transform = `scaleY(${v.toFixed(3)})`;
      }
      chipT += dt;
      if (chipT > 2.6) {
        chipT = 0; chip.classList.remove("is-on");
        setTimeout(() => { chipI = (chipI + 1) % CHIPS.length; chipText.textContent = CHIPS[chipI]; placeChip(); chip.classList.add("is-on"); }, 380);
      }
      raf = requestAnimationFrame(frame);
    };
    const start = () => { if (reduceMQ.matches) return; last = 0; raf = requestAnimationFrame(frame); };
    const stop = () => cancelAnimationFrame(raf);
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => {
      layout();
      chip.classList.add("is-on");
      whileVisible(ribbon, start, stop);
    });
    phoneMQ.addEventListener("change", layout);
    reduceMQ.addEventListener("change", () => { stop(); if (!reduceMQ.matches) start(); });
  }

  // ---- Arc text in the scene cards and the language card -------------------------------------------------------
  function arcRunner(textPath, speed) {
    let off = 0, last = 0, raf = 0, len = 0;
    const base = textPath.textContent;
    textPath.textContent = base.repeat(3);
    const measure = () => { len = textPath.parentNode.getComputedTextLength() / 3; };
    const frame = (t) => {
      const dt = last ? Math.min(0.05, (t - last) / 1000) : 0; last = t;
      off += dt * speed;
      if (!len) measure();
      if (len) textPath.setAttribute("startOffset", (-(off % len)).toFixed(1));
      raf = requestAnimationFrame(frame);
    };
    return {
      start() { if (reduceMQ.matches) return; last = 0; raf = requestAnimationFrame(frame); },
      stop() { cancelAnimationFrame(raf); },
      reset(text) { textPath.textContent = text.repeat(3); len = 0; off = 0; },
    };
  }

  // ---- The scroll story: speed cards → portrait card → how it works -------------------------------------------
  const story = $("[data-story]");
  const stage = $("[data-stage]");
  const outCard = $("[data-out]");
  const card = $("[data-card]");
  const ci = $("[data-ci]", card), cs = $("[data-cs]", card);
  const speed = $("[data-speed]");
  const howTrack = $("[data-how]");
  const howPin = $(".how-pin", howTrack);
  const tabs = $$("[data-step-tab]");
  const steps = $$("[data-step]");
  const speedSlot = $('[data-slot="speed"]');
  // The spoken words in step one arrive one at a time, the way the transcript builds while you talk.
  const tr = $("[data-tr]", card);
  const walker = document.createTreeWalker(tr, NodeFilter.SHOW_TEXT);
  const textNodes = [];
  while (walker.nextNode()) textNodes.push(walker.currentNode);
  textNodes.forEach((node) => {
    const frag = document.createDocumentFragment();
    node.textContent.split(/(\s+)/).forEach((part) => {
      if (!part) return;
      if (/^\s+$/.test(part)) { frag.append(part); return; }
      const w = document.createElement("span"); w.className = "w"; w.textContent = part; frag.append(w);
    });
    node.replaceWith(frag);
  });
  let arcSeq = 0;
  const makeScene = (which) => {
    const c = card.cloneNode(true);
    c.removeAttribute("data-card");
    $$("[data-sc]", c).forEach((sc) => sc.classList.toggle("is-on", sc.dataset.sc === which));
    if (which !== "speed") $$("[data-sc]", c).forEach((sc) => { if (sc.dataset.sc !== which) sc.remove(); });
    c.classList.toggle("is-step", which !== "speed");
    const p = $("path[id]", c);
    if (p) { const id = "arc-c" + ++arcSeq; p.id = id; $("textPath", c).setAttribute("href", "#" + id); }
    return c;
  };
  const clones = { speed: makeScene("speed"), 1: makeScene("1"), 2: makeScene("2"), 3: makeScene("3") };
  const mainArc = arcRunner($("[data-arc]", card), 52);
  const cloneArc = arcRunner($("textPath", clones.speed), 52);

  let storyOn = false, geo = null, lastStep = -1, lastScene = "";
  const setScene = (name) => {
    if (name === lastScene) return; lastScene = name;
    $$("[data-sc]", card).forEach((sc) => sc.classList.toggle("is-on", sc.dataset.sc === name));
    card.classList.toggle("is-step", name !== "speed");
  };
  const setStep = (i) => {
    if (i === lastStep) return; lastStep = i;
    tabs.forEach((t, j) => t.classList.toggle("is-on", j === i));
    steps.forEach((s, j) => s.classList.toggle("is-on", j === i));
  };

  function measureStory() {
    const V = innerHeight, W = root.clientWidth;
    speed.style.height = Math.round(V * 3) + "px";
    const gutter = Math.max(16, W * 0.05);
    const cw = Math.min(1160, W - 2 * gutter);
    const x0 = (W - cw) / 2;
    const cardTop = Math.min(351, Math.max(300, V * 0.39));
    const cardH = Math.max(320, Math.min(501, V - cardTop - 40));
    const leftW = Math.round(cw * 0.263);
    const pw = 405, ph = Math.min(468, V - 160);
    const y2 = Math.min(368, V - ph - 40);
    const y3 = Math.max(96, Math.round((V - 467) / 2));
    const storyTop = story.getBoundingClientRect().top + scrollY;
    const howTop = howTrack.getBoundingClientRect().top + scrollY;
    geo = {
      V, W, storyTop, howTop, howEnd: howTop + howTrack.offsetHeight - V,
      K0: { x: x0 + leftW + 2, y: cardTop, w: cw - leftW - 2, h: cardH, r: 48 },
      L0: { x: x0, y: cardTop, w: leftW, h: cardH },
      K1: { x: x0, y: cardTop, w: cw, h: cardH, r: 48 },
      K2: { x: (W - pw) / 2, y: y2, w: pw, h: ph, r: 16 },
      K3: { x: (W - 400) / 2, y: y3, w: 400, h: 467, r: 16 },
    };
    howPin.style.setProperty("--card-bottom", y3 + 467 + "px");
    $(".how-tabs", howPin).style.top = y3 + 8 + "px";
    outCard.style.width = geo.L0.w + "px"; outCard.style.height = geo.L0.h + "px";
  }
  const mix = (a, b, t) => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t), r: lerp(a.r, b.r, t) });
  function renderStory() {
    if (!storyOn || !geo) return;
    const { V, storyTop, howTop, howEnd } = geo;
    const s = scrollY;
    const d = s - storyTop; // distance scrolled into the story
    let r, outOpacity = 0, outShift = 0, labels = 1;
    const p1 = ease(span(d, 0.35 * V, 1.0 * V));
    const p3 = ease(span(d, 1.3 * V, 2.0 * V));
    if (d < 1.3 * V) {
      r = mix(geo.K0, geo.K1, p1);
      outOpacity = 1 - p1; outShift = -p1 * 220;
    } else if (d < 2.0 * V) {
      r = mix(geo.K1, geo.K2, p3);
      labels = 1 - span(p3, 0, 0.45);
    } else {
      const p4 = ease(span(s, storyTop + 2.0 * V, howTop));
      r = mix(geo.K2, geo.K3, p4);
      labels = 0;
    }
    const inHow = s > storyTop + 2.0 * V + (howTop - storyTop - 2.0 * V) * 0.55;
    if (!inHow) setScene("speed");
    else {
      const sp = span(s, howTop, howEnd);
      const i = Math.min(2, Math.floor(sp * 3));
      setScene(String(i + 1)); setStep(i);
    }
    if (!inHow) setStep(0);
    ci.style.transform = `translate3d(${((r.w - 1160) / 2).toFixed(1)}px, ${((r.h - 501) / 2).toFixed(1)}px, 0)`;
    cs.style.transform = `translate3d(${((r.w - 400) / 2).toFixed(1)}px, ${((r.h - 467) / 2).toFixed(1)}px, 0)`;
    card.style.width = r.w.toFixed(1) + "px";
    card.style.height = r.h.toFixed(1) + "px";
    card.style.borderRadius = r.r.toFixed(1) + "px";
    // Coordinates are relative to the sticky layer, which holds still for the whole story.
    card.style.transform = `translate3d(${r.x.toFixed(1)}px, ${r.y.toFixed(1)}px, 0)`;
    outCard.style.opacity = outOpacity.toFixed(3);
    outCard.style.transform = `translate3d(${(geo.L0.x + outShift).toFixed(1)}px, ${geo.L0.y.toFixed(1)}px, 0)`;
    $$(".sp-label, .sp-num", card).forEach((el) => { el.style.opacity = labels.toFixed(3); });
  }

  function placeScenes() {
    if (storyOn) {
      stage.prepend(outCard);
      speedSlot.textContent = "";
      $$("[data-slot]").forEach((slot) => { if (slot !== speedSlot) slot.textContent = ""; });
      outCard.style.cssText = ""; card.style.cssText = ""; ci.style.transform = ""; cs.style.transform = "";
    } else {
      outCard.style.cssText = "";
      speedSlot.append(outCard, clones.speed);
      ["1", "2", "3"].forEach((k) => $(`[data-slot="${k}"]`).append(clones[k]));
      steps.forEach((s) => s.classList.add("is-on"));
    }
  }
  function setMode() {
    const want = wideMQ.matches && !reduceMQ.matches;
    root.classList.toggle("no-story", !want);
    if (want === storyOn && geo) { if (storyOn) { measureStory(); renderStory(); } return; }
    storyOn = want;
    if (!storyOn) { speed.style.height = ""; }
    placeScenes();
    if (storyOn) { lastStep = -1; lastScene = ""; steps.forEach((s) => s.classList.remove("is-on")); measureStory(); renderStory(); }
    if (storyOn) exMeasure(); else exReset();
  }
  whileVisible(story, () => { mainArc.start(); cloneArc.start(); }, () => { mainArc.stop(); cloneArc.stop(); });

  // ---- Features: the card on the left follows the item in the middle of the screen ------------------------------
  const feats = $$("[data-feat]");
  const featsHead = $(".feats-head");
  new IntersectionObserver((es, ob) => { es.forEach((e) => { if (e.isIntersecting) { featsHead.classList.add("is-in"); ob.disconnect(); } }); }, { threshold: 0.6 }).observe(featsHead);
  let featOn = -1;
  function renderFeats() {
    if (!wideMQ.matches) { feats.forEach((f) => f.classList.add("is-on")); featOn = -2; return; }
    const mid = innerHeight * 0.55;
    let on = 0;
    feats.forEach((f, i) => { const t = $(".feat-text", f).getBoundingClientRect().top; if (t < mid) on = i; });
    if (on !== featOn) { featOn = on; feats.forEach((f, i) => f.classList.toggle("is-on", i === on)); }
  }
  function isNotetakerOn() {
    const t = $(".feat-text", feats[4]).getBoundingClientRect();
    return t.top < innerHeight * 0.7 && t.bottom > innerHeight * 0.15;
  }

  // Feature card loops
  const LANGS = [
    ["Deutsch", "de", "Kannst du mir bitte den Bericht bis Freitag schicken? "],
    ["Français", "fr", "Je pense qu'on devrait reporter le lancement à la semaine prochaine. "],
    ["Español", "es", "Mañana no puedo ir a la reunión, ¿la podemos mover al jueves? "],
    ["Italiano", "it", "Allora, ci vediamo alle otto davanti al cinema. "],
    ["Nederlands", "nl", "Kun je de factuur nog een keer sturen? "],
    ["Português", "pt", "Eu acho que a gente precisa de mais tempo pra testar. "],
  ];
  const langTP = $("[data-lang-text]"), langName = $("[data-lang-name]"), flag = $("[data-flag]");
  langTP.textContent = LANGS[0][2];
  const langArc = arcRunner(langTP, 38);
  const TONES = ["Hey, if you’re free, let’s chat about the great results.", "Hey, if you’re free let’s chat about the great results", "Hey, if you’re free, let’s chat about the great results!"];
  const LIVE = [
    ["You", "Okay, let’s start with the beta. Where are we on the crash fix?"],
    ["Priya", "It’s merged. The build went green this morning, so Thursday works."],
    ["Speaker 2", "Support wants the release notes a day early."],
  ];
  const dictNew = $("[data-dict-new]"), dictField = $("[data-dict-field]");
  const snip = $("[data-snip]");
  const tonePills = $$("[data-tone-i]"), toneMsg = $("[data-tone-msg]");
  const live = $("[data-live]"), liveWho = live.previousElementSibling;
  let loopT = 0, tick = 0, li = 0, ti = 0, lv = 0, dictStep = 0;
  function featTick() {
    tick++;
    // language: every 4 s
    if (tick % 8 === 0) {
      li = (li + 1) % LANGS.length;
      langName.style.opacity = 0; flag.style.opacity = 0;
      setTimeout(() => { langName.textContent = LANGS[li][0]; flag.dataset.flag = LANGS[li][1]; langArc.reset(LANGS[li][2]); langName.style.opacity = 1; flag.style.opacity = 1; }, 300);
    }
    // snippet: flips every 2 s
    if (tick % 4 === 0) snip.classList.toggle("is-out");
    // tone: every 2.5 s
    if (tick % 5 === 0) { ti = (ti + 1) % 3; tonePills.forEach((p, i) => p.classList.toggle("is-on", i === ti)); toneMsg.textContent = TONES[ti]; }
    // dictionary: type a name, add it, clear
    const word = "Aoife";
    dictStep = (dictStep + 1) % 14;
    if (dictStep >= 1 && dictStep <= word.length) { dictField.classList.add("is-typing"); dictField.textContent = word.slice(0, dictStep); }
    else if (dictStep === word.length + 2) { dictNew.textContent = word; dictField.classList.remove("is-typing"); dictField.textContent = "Add a word"; }
    else if (dictStep === 0) dictNew.textContent = "";
    // live transcript: words arrive grey, then settle
    const [who, line] = LIVE[lv];
    const words = line.split(" ");
    const shown = Math.min(words.length, (tick % 12) * 2);
    if (tick % 12 === 0) { lv = (lv + 1) % LIVE.length; }
    liveWho.textContent = who;
    live.innerHTML = "";
    const done = document.createTextNode(words.slice(0, Math.max(0, shown - 2)).join(" ") + " ");
    const ghost = document.createElement("span"); ghost.className = "ghost"; ghost.textContent = words.slice(Math.max(0, shown - 2), shown).join(" ");
    live.append(done, ghost);
  }
  const featsEl = $("[data-feats]");
  whileVisible(featsEl, () => { langArc.start(); if (!reduceMQ.matches) loopT = setInterval(featTick, 500); }, () => { langArc.stop(); clearInterval(loopT); });

  // ---- How-it-works: words arrive, chips cycle ------------------------------------------------------------------
  let wordI = 0, wordTimer = 0;
  const wordTick = () => {
    const all = $$("[data-tr]").map((t) => $$(".w", t));
    const n = all[0].length;
    wordI = (wordI + 1) % (n + 14);
    all.forEach((ws) => ws.forEach((w, i) => w.classList.toggle("in", i < wordI)));
  };
  if (!reduceMQ.matches) root.classList.add("words");
  whileVisible(story, () => { if (!reduceMQ.matches) wordTimer = setInterval(wordTick, 150); }, () => clearInterval(wordTimer));
  // ---- How-it-works chips cycle --------------------------------------------------------------------------------
  const CHIP_STEPS = [["Filler spotted", "chip-amb"], ["Correction spotted", "chip-cor"], ["Repeat spotted", "chip-pink"]];
  let chipStep = 0, chipTimer = 0;
  whileVisible(story, () => {
    if (reduceMQ.matches) return;
    chipTimer = setInterval(() => {
      chipStep = (chipStep + 1) % CHIP_STEPS.length;
      $$("[data-chip-step]").forEach((c) => { c.textContent = CHIP_STEPS[chipStep][0]; c.className = "chip " + CHIP_STEPS[chipStep][1]; c.setAttribute("data-chip-step", ""); });
    }, 1800);
  }, () => clearInterval(chipTimer));

  // ---- Examples: cards travel across on a curve ----------------------------------------------------------------
  const exTrack = $("[data-ex]"), exRow = $("[data-ex-row]"), exCards = $$(".xc", exRow);
  let exGeo = null;
  function exMeasure() {
    if (!storyOn) return;
    exRow.style.transform = "";
    exCards.forEach((c) => { c.style.transform = ""; });
    const W = root.clientWidth;
    exRow.style.paddingLeft = Math.round(W * 0.5 - exCards[0].offsetWidth / 2) + "px";
    const first = exCards[0], lastC = exCards[exCards.length - 1];
    const centers = exCards.map((c) => c.offsetLeft + c.offsetWidth / 2);
    const start = first.offsetLeft + first.offsetWidth / 2 - W / 2;
    const end = lastC.offsetLeft + lastC.offsetWidth / 2 - W / 2;
    const top = exTrack.getBoundingClientRect().top + scrollY;
    exGeo = { W, centers, start, end, top, len: exTrack.offsetHeight - innerHeight };
    renderEx();
  }
  function exReset() { exGeo = null; exRow.style.transform = ""; exRow.style.paddingLeft = ""; exCards.forEach((c) => { c.style.transform = ""; }); }
  function renderEx() {
    if (!storyOn || !exGeo) return;
    const { W, centers, start, end, top, len } = exGeo;
    const p = span(scrollY, top, top + len);
    const shift = lerp(start, end, p);
    exRow.style.transform = `translate3d(${(-shift).toFixed(1)}px,0,0)`;
    exCards.forEach((c, i) => {
      const dd = (centers[i] - shift - W / 2) / (W / 2);
      const a = clamp(dd, -2.2, 2.2);
      c.style.transform = `translate3d(0, ${(Math.abs(a) * 36).toFixed(1)}px, ${(-Math.abs(a) * 120).toFixed(1)}px) rotateY(${(-a * 24).toFixed(2)}deg) rotateZ(${(a * 3).toFixed(2)}deg)`;
    });
  }

  // ---- FAQ ----------------------------------------------------------------------------------------------------
  const faq = $("[data-faq]");
  const qButtons = $$(".faq-list button", faq);
  const chat = $("[data-faq-chat]"), ask = $("[data-faq-ask]"), ans = $("[data-faq-ans]");
  const list = $(".faq-list", faq), scrollBox = $(".faq-scroll", faq);
  const showAnswer = (btn) => {
    ask.textContent = btn.textContent;
    ans.innerHTML = $("#" + btn.getAttribute("aria-controls")).innerHTML;
    chat.classList.remove("is-swap"); void chat.offsetWidth; chat.classList.add("is-swap");
  };
  const select = (btn, toggle) => {
    const open = btn.getAttribute("aria-expanded") === "true";
    if (phoneMQ.matches && toggle && open) { btn.setAttribute("aria-expanded", "false"); $("#" + btn.getAttribute("aria-controls")).hidden = true; return; }
    qButtons.forEach((b) => {
      const on = b === btn;
      b.setAttribute("aria-expanded", String(on));
      $("#" + b.getAttribute("aria-controls")).hidden = !on;
    });
    showAnswer(btn);
  };
  qButtons.forEach((b) => b.addEventListener("click", () => select(b, true)));
  const fades = () => {
    const max = list.scrollHeight - list.clientHeight;
    scrollBox.style.setProperty("--fade-top", clamp(list.scrollTop / 40, 0, 1).toFixed(2));
    scrollBox.style.setProperty("--fade-bot", clamp((max - list.scrollTop) / 40, 0, 1).toFixed(2));
  };
  list.addEventListener("scroll", fades, { passive: true });
  fades();
  $$("[data-faq-open]").forEach((a) => a.addEventListener("click", () => {
    const b = qButtons[+a.dataset.faqOpen - 1];
    if (b) { select(b, false); setTimeout(() => b.focus({ preventScroll: true }), 50); }
  }));

  // ---- Scroll + resize --------------------------------------------------------------------------------------
  let sTick = false;
  const onScroll = () => {
    if (sTick) return; sTick = true;
    requestAnimationFrame(() => {
      sTick = false;
      renderStory(); renderEx(); renderFeats();
      setSeg(isNotetakerOn() ? "notetaker" : "dictation");
    });
  };
  addEventListener("scroll", onScroll, { passive: true });
  let rT = 0, lastW = root.clientWidth, lastH = innerHeight;
  addEventListener("resize", () => {
    clearTimeout(rT);
    rT = setTimeout(() => {
      // Phones resize the viewport as the toolbar hides; only re-measure for real changes.
      if (root.clientWidth === lastW && Math.abs(innerHeight - lastH) < 120 && !storyOn) return;
      lastW = root.clientWidth; lastH = innerHeight;
      setMode(); if (storyOn) { measureStory(); exMeasure(); } renderStory(); renderFeats();
    }, 120);
  });
  wideMQ.addEventListener("change", setMode);
  reduceMQ.addEventListener("change", setMode);
  setMode();
  renderFeats();
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => { if (storyOn) { measureStory(); exMeasure(); renderStory(); } });
  addEventListener("load", () => { if (storyOn) { measureStory(); exMeasure(); renderStory(); } });
})();
