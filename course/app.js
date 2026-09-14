/* longrun course: diagram + scenario player + small interactive bits. No dependencies. */
(function () {
  'use strict';
  const SVGNS = 'http://www.w3.org/2000/svg';
  const I = Object.assign({ step: 'Шаг', of: 'из', prev: 'Назад', next: 'Дальше',
    fileHint: 'Нажмите на файл, чтобы узнать, что в нем и кто его пишет. + создан на этом шаге, ~ изменен, (read) прочитан.',
    quiz: ['Свои заметки', 'Общие', 'Журнал', 'Не писать'],
    diagHead: 'Кто с кем говорит на этом шаге', termHead: 'Агент вызывает команды скилла в нужные моменты: команда и что она печатает',
    loop: ['старт сессии', 'ход: запрос человека', 'вызов инструмента', 'сессия закончилась', 'ответ модели', 'компакция', 'после компакции снова SessionStart'] }, window.LR_I18N || {});
  function el(tag, attrs, children) {
    const e = document.createElement(tag);
    if (attrs) for (const k in attrs) { if (k === 'html') e.innerHTML = attrs[k]; else if (k === 'text') e.textContent = attrs[k]; else e.setAttribute(k, attrs[k]); }
    (children || []).forEach(c => e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c));
    return e;
  }
  function svgEl(tag, attrs) { const e = document.createElementNS(SVGNS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); return e; }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  /* ---------- Language bar ----------
     The one list of locales the course has. The bar is built here instead of being written
     into every locale's HTML, because that edit - adding the new language to the pages that
     already exist - is the one everyone forgets. Adding a language is one line below.
     English lives at course/, every other locale one level down at course/<code>/.
     The static link already in .lang stays as the no-JS fallback until this replaces it.
     A locale goes in here only once its page is published, or the bar links to a 404. */
  const LOCALES = [
    { code: 'en', name: 'English', dir: '' },
    { code: 'ru', name: 'Русский', dir: 'ru' },
    { code: 'zh-CN', name: '简体中文', dir: 'zh-CN' },
    { code: 'ja', name: '日本語', dir: 'ja' },
  ];
  function LangBar() {
    const box = document.querySelector('nav.side .lang');
    if (!box) return;
    const cur = document.documentElement.lang || 'en';
    const up = cur === 'en' ? '' : '../';
    const links = LOCALES.filter(l => l.code !== cur)
      .map(l => el('a', { href: up + (l.dir ? l.dir + '/' : ''), hreflang: l.code, lang: l.code, text: l.name }));
    if (!links.length) return;
    box.textContent = '';
    links.forEach((a, i) => { if (i) box.appendChild(document.createTextNode(' · ')); box.appendChild(a); });
  }

  /* ---------- Diagram: boxes + arrows, highlightable ---------- */
  function Diagram(container, nodes, edges, size) {
    const W = size[0], H = size[1];
    const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}` });
    const defs = svgEl('defs', {});
    for (const [id, cls] of [['arr', ''], ['arr-on', 'on']]) {
      const m = svgEl('marker', { id: id + '-' + container.id, markerWidth: 8, markerHeight: 8, refX: 7, refY: 4, orient: 'auto', markerUnits: 'strokeWidth', class: cls });
      m.appendChild(svgEl('path', { d: 'M0,0 L8,4 L0,8 z' })); defs.appendChild(m);
    }
    svg.appendChild(defs);
    const byId = {}; nodes.forEach(n => byId[n.id] = n);
    function anchor(n, tx, ty, off) {
      const cx = n.x + n.w / 2, cy = n.y + n.h / 2, dx = tx - cx, dy = ty - cy;
      const sx = dx === 0 ? Infinity : (n.w / 2) / Math.abs(dx), sy = dy === 0 ? Infinity : (n.h / 2) / Math.abs(dy);
      const s = Math.min(sx, sy);
      const px = cx + dx * s, py = cy + dy * s;
      const len = Math.hypot(dx, dy) || 1, nx = -dy / len * off, ny = dx / len * off;
      return [px + nx, py + ny];
    }
    const edgeEls = {};
    edges.forEach(e => {
      const a = byId[e.from], b = byId[e.to], off = e.off || 0;
      const [x1, y1] = anchor(a, b.x + b.w / 2, b.y + b.h / 2, off);
      const [x2, y2] = anchor(b, a.x + a.w / 2, a.y + a.h / 2, -off);
      const p = svgEl('path', { d: `M${x1},${y1} L${x2},${y2}`, class: 'edge', 'marker-end': `url(#arr-${container.id})` });
      svg.appendChild(p); edgeEls[e.id] = p;
    });
    const nodeEls = {};
    nodes.forEach(n => {
      const g = svgEl('g', { class: 'node kind-' + n.kind });
      g.appendChild(svgEl('rect', { x: n.x, y: n.y, width: n.w, height: n.h, rx: 8 }));
      const t = svgEl('text', { x: n.x + 10, y: n.y + 18, 'font-weight': 600 }); t.textContent = n.title; g.appendChild(t);
      (n.sub || []).forEach((s, i) => { const st = svgEl('text', { x: n.x + 10, y: n.y + 34 + i * 13, class: 'sub' }); st.textContent = s; g.appendChild(st); });
      svg.appendChild(g); nodeEls[n.id] = g;
    });
    container.appendChild(svg);
    this.highlight = function (onNodes, onEdges, dimOthers) {
      for (const id in nodeEls) { nodeEls[id].classList.toggle('on', onNodes.includes(id)); nodeEls[id].classList.toggle('dim', !!dimOthers && !onNodes.includes(id)); }
      for (const id in edgeEls) { const on = onEdges.includes(id); edgeEls[id].classList.toggle('on', on); edgeEls[id].setAttribute('marker-end', `url(#${on ? 'arr-on' : 'arr'}-${container.id})`); }
    };
  }

  /* ---------- File tree with cumulative state ---------- */
  function renderTree(container, roots, state, info) {
    container.innerHTML = '';
    roots.forEach(r => {
      container.appendChild(el('div', { class: 'root', text: r.label }));
      r.files.forEach(f => {
        const st = state[f.path]; if (!st && !f.always) return;
        const d = el('div', { class: 'f ' + (st === 'new' ? 'new' : st === 'chg' ? 'chg' : st === 'rd' ? 'rd' : ''), text: '  ' + f.path });
        d.addEventListener('click', () => { container.querySelectorAll('.f').forEach(x => x.classList.remove('on')); d.classList.add('on'); if (info) info.innerHTML = `<b>${esc(r.prefix + f.path)}</b><div>${f.what}</div>${f.who ? `<div class="who">${f.who}</div>` : ''}`; });
        container.appendChild(d);
      });
    });
  }

  /* ---------- Scenario player ---------- */
  function Player(root, sc) {
    root.classList.add('player');
    const stepname = el('div', { class: 'stepname' });
    const diagramBox = el('div', { class: 'diagram', id: root.id + '-d' });
    const caption = el('div', { class: 'caption' });
    const term = el('div', { class: 'term' });
    const left = el('div', {}, [el('div', { class: 'phead', text: I.diagHead }), diagramBox, caption]);
    const right = el('div', {}, [el('div', { class: 'phead', text: I.termHead }), term]);
    const top = el('div', { class: 'top' }, [left, right]);
    const tree = el('div', { class: 'tree' });
    const finfo = el('div', { class: 'fileinfo', html: '<span style="color:var(--muted)">' + esc(I.fileHint) + '</span>' });
    const bottom = el('div', { class: 'bottom' }, [tree, finfo]);
    const prev = el('button', { text: I.prev }), next = el('button', { class: 'primary', text: I.next });
    const dots = el('div', { class: 'steps' });
    const ctrls = el('div', { class: 'ctrls' }, [prev, next, dots]);
    root.append(stepname, top, bottom, ctrls);
    const dg = new Diagram(diagramBox, sc.nodes, sc.edges, sc.size || [560, 330]);
    sc.steps.forEach((_, i) => { const d = el('i', {}); d.addEventListener('click', () => go(i)); dots.appendChild(d); });
    let cur = 0;
    function fileState(upto) {
      const st = {};
      for (let i = 0; i <= upto; i++) {
        const prevKeys = Object.keys(st); prevKeys.forEach(k => { if (st[k] !== 'gone') st[k] = 'keep'; });
        (sc.steps[i].files || []).forEach(f => { st[f[0]] = f[1]; });
      }
      return st;
    }
    function go(i) {
      cur = Math.max(0, Math.min(sc.steps.length - 1, i));
      const s = sc.steps[cur];
      stepname.innerHTML = `${I.step} ${cur + 1} ${I.of} ${sc.steps.length}: ${esc(s.title)}${s.who ? `<small>${esc(s.who)}</small>` : ''}`;
      dg.highlight(s.nodes || [], s.edges || [], true);
      caption.innerHTML = s.caption || '';
      term.innerHTML = (s.term || []).map(t => {
        if (t.cmd) return `<span class="who">${esc(t.who || '')}$</span> <span class="cmd">${esc(t.cmd)}</span>\n`;
        if (t.out) return `<span class="out">${esc(t.out).replace(/\[\[(.+?)\]\]/g, '<span class="hi">$1</span>')}</span>\n`;
        if (t.dim) return `<span class="dim">${esc(t.dim)}</span>\n`;
        return '';
      }).join('');
      term.scrollTop = 0;
      renderTree(tree, sc.roots, fileState(cur), finfo);
      prev.disabled = cur === 0; next.disabled = cur === sc.steps.length - 1;
      dots.querySelectorAll('i').forEach((d, j) => { d.classList.toggle('on', j === cur); d.classList.toggle('done', j < cur); });
    }
    prev.addEventListener('click', () => go(cur - 1)); next.addEventListener('click', () => go(cur + 1));
    root.addEventListener('keydown', e => { if (e.key === 'ArrowRight') { go(cur + 1); e.preventDefault(); } if (e.key === 'ArrowLeft') { go(cur - 1); e.preventDefault(); } });
    root.tabIndex = 0;
    go(0);
  }

  /* ---------- Hook loop figure ---------- */
  function HookLoop(container, infoBox, hooks) {
    const W = 620, H = 330;
    const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}` });
    // main loop: a rounded rectangle path
    svg.appendChild(svgEl('path', { class: 'loop', d: 'M90,60 H530 a12,12 0 0 1 12,12 V170 a12,12 0 0 1 -12,12 H90 a12,12 0 0 1 -12,-12 V72 a12,12 0 0 1 12,-12 z' }));
    svg.appendChild(svgEl('path', { class: 'loop', d: 'M310,182 V250', 'stroke-dasharray': '4 4' }));
    const labels = [[95, 50, I.loop[0]], [250, 50, I.loop[1]], [420, 50, I.loop[2]], [95, 210, I.loop[3]], [250, 210, I.loop[4]], [400, 210, I.loop[5]], [315, 262, I.loop[6]]];
    labels.forEach(([x, y, t]) => { const l = svgEl('text', { x, y, class: 'lbl' }); l.textContent = t; svg.appendChild(l); });
    const pos = { SessionStart: [40, 100], UserPromptSubmit: [190, 100], PreToolUse: [360, 80], PostToolUse: [360, 120], PostToolUseFailure: [468, 100], PermissionRequest: [468, 140], Notification: [190, 140], Stop: [190, 225], SessionEnd: [40, 225], PreCompact: [360, 225], PostCompact: [480, 225] };
    let active = null;
    hooks.forEach(h => {
      const [x, y] = pos[h.name]; const g = svgEl('g', { class: 'hk' });
      const w = h.name.length * 6.8 + 16;
      g.appendChild(svgEl('rect', { x, y, width: w, height: 24, rx: 6 }));
      const t = svgEl('text', { x: x + 8, y: y + 16 }); t.textContent = h.name; g.appendChild(t);
      g.addEventListener('click', () => { if (active) active.classList.remove('on'); active = g; g.classList.add('on'); infoBox.innerHTML = `<h4>${esc(h.name)}</h4><div>${h.what}</div>`; });
      svg.appendChild(g);
    });
    container.appendChild(svg);
  }

  /* ---------- Quiz ---------- */
  function Quiz(container, items) {
    items.forEach(it => {
      const q = el('div', { class: 'q' });
      q.appendChild(el('div', { class: 'stmt', html: it.stmt }));
      const btns = el('div', {});
      [['own', I.quiz[0]], ['shared', I.quiz[1]], ['log', I.quiz[2]], ['no', I.quiz[3]]].forEach(([k, label]) => {
        const b = el('button', { text: label });
        b.addEventListener('click', () => { if (q.classList.contains('done')) return; q.classList.add('done'); b.classList.add(k === it.ans ? 'right' : 'wrong'); btns.querySelectorAll('button').forEach(x => { if (x.textContent === label) return; if ([...btns.children].indexOf(x) === ['own', 'shared', 'log', 'no'].indexOf(it.ans)) x.classList.add('right'); }); });
        btns.appendChild(b);
      });
      q.appendChild(btns); q.appendChild(el('div', { class: 'why', html: it.why }));
      container.appendChild(q);
    });
  }

  /* ---------- Nav progress ---------- */
  function Nav() {
    const links = [...document.querySelectorAll('nav.side a[href^="#"]')];
    const secs = links.map(a => document.querySelector(a.getAttribute('href')));
    const bar = document.querySelector('nav.side .progress i');
    function upd() {
      let idx = 0; secs.forEach((s, i) => { if (s && s.getBoundingClientRect().top < window.innerHeight * 0.35) idx = i; });
      links.forEach((a, i) => a.classList.toggle('active', i === idx));
      if (bar) bar.style.width = Math.round((idx + 1) / links.length * 100) + '%';
    }
    window.addEventListener('scroll', upd, { passive: true }); upd();
  }

  window.LR = { Diagram, Player, HookLoop, Quiz, Nav, LangBar, LOCALES, renderTree, el };
  /* self-starting: a locale page needs no extra call, and none of the existing pages change */
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', LangBar);
  else LangBar();
})();
