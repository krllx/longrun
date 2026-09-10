/* Scenario data: what each command prints, on a toy project "shop" with sessions aaaaaaaa and bbbbbbbb. */
window.COURSE = (function () {
  const FOOT = 'Write: `longrun add -t dead|decision|fact|ctx|todo|pin "<one line>"` (own), `--shared` for what other sessions need, `longrun log "<milestone>"`. Lost detail: `longrun recall <term>`. ...';
  /* actors shared by all scenarios */
  const N = {
    U: { id: 'U', kind: 'human', x: 10, y: 10, w: 150, h: 44, title: 'Человек', sub: ['терминал, чат, диалог'] },
    A: { id: 'A', kind: 'session', x: 10, y: 90, w: 150, h: 60, title: 'Сессия A', sub: ['Claude Code', 'хуки longrun'] },
    B: { id: 'B', kind: 'session', x: 10, y: 200, w: 150, h: 60, title: 'Сессия B', sub: ['Claude Code', 'хуки longrun'] },
    P: { id: 'P', kind: 'project', x: 230, y: 110, w: 170, h: 96, title: 'Проект shop/.longrun', sub: ['NOTES.md  общие', 'inbox/  board.json', 'archive/'] },
    SA: { id: 'SA', kind: 'own', x: 440, y: 90, w: 110, h: 60, title: 'своё A', sub: ['notes.md', 'journal, meta'] },
    SB: { id: 'SB', kind: 'own', x: 440, y: 200, w: 110, h: 60, title: 'своё B', sub: ['notes.md', 'journal, meta'] },
    L: { id: 'L', kind: 'timer', x: 230, y: 250, w: 170, h: 50, title: 'таймер, раз в 5 мин', sub: ['watch, смотритель, бюджет'] },
    G: { id: 'G', kind: 'global', x: 432, y: 10, w: 124, h: 44, title: '~/.claude/longrun', sub: ['watch/, halt.json'] },
    D: { id: 'D', kind: 'human', x: 230, y: 10, w: 150, h: 44, title: 'Диалог osascript', sub: ['поверх всех окон'] },
  };
  const E = [
    { id: 'AP', from: 'A', to: 'P', off: 5 }, { id: 'PA', from: 'P', to: 'A', off: 5 },
    { id: 'BP', from: 'B', to: 'P', off: 5 }, { id: 'PB', from: 'P', to: 'B', off: 5 },
    { id: 'ASA', from: 'A', to: 'SA', off: 4 }, { id: 'SAA', from: 'SA', to: 'A', off: 4 },
    { id: 'BSB', from: 'B', to: 'SB', off: 4 }, { id: 'SBB', from: 'SB', to: 'B', off: 4 },
    { id: 'AB', from: 'A', to: 'B', off: 6 }, { id: 'LP', from: 'L', to: 'P' }, { id: 'LA', from: 'L', to: 'A' }, { id: 'LB', from: 'L', to: 'B' },
    { id: 'AG', from: 'A', to: 'G', off: 4 }, { id: 'GB', from: 'G', to: 'B' }, { id: 'LG', from: 'L', to: 'G' },
    { id: 'BD', from: 'B', to: 'D', off: 5 }, { id: 'DB', from: 'D', to: 'B', off: 5 }, { id: 'DU', from: 'D', to: 'U', off: 4 }, { id: 'UD', from: 'U', to: 'D', off: 4 }, { id: 'UA', from: 'U', to: 'A' }, { id: 'LD', from: 'L', to: 'D' },
  ];
  function pick(nodeIds, edgeIds) { return { nodes: nodeIds.map(i => N[i]), edges: E.filter(e => edgeIds.includes(e.id)) }; }

  const PROJ = { label: 'shop/.longrun/  (общее, в проекте)', prefix: 'shop/.longrun/', files: [
    { path: 'NOTES.md', what: 'Общие заметки [n1], [n2]... одной строкой, с автором. Бюджет 5000 байт.', who: 'Пишет агент: add --shared, rm, replace, prune --shared' },
    { path: 'config.json', what: 'Настройки проекта: режим hq, бюджеты, пороги.', who: 'init; правится руками' },
    { path: 'state.json', what: 'Счетчики id заметок и задач.', who: 'CLI' },
    { path: 'inbox/<msg>.md', what: 'Сообщение сессии, которая сейчас не работает. Доставленное уходит в inbox/.archive/.', who: 'send, watch, board, ask; читают хуки адресата' },
    { path: 'archive/precompact/<sid>-<time>.md', what: 'Снимок перед компакцией: последние просьбы человека, правленые файлы, недавние FAIL. Из него собирается блок HANDOFF (передача самому себе после компакции) в следующем дайджесте.', who: 'хук PreCompact' },
    { path: 'archive/compact/<sid>-<time>.md', what: 'Резюме компакции дословно. Их находит longrun recall.', who: 'хук PostCompact' },
    { path: 'board.json', what: 'Доска оркестратора: цель, задачи T<n>, факты F<n>.', who: 'board, fact' },
    { path: 'orchestrator.json', what: 'Кто держит роль оркестратора и с какой целью.', who: 'orchestrate start/stop' },
  ] };
  const OWN = { label: '~/.claude/longrun/sessions/shop/<сессия>/  (свое, вне репозитория)', prefix: '~/.claude/longrun/sessions/shop/', files: [
    { path: 'aaaaaaaa/meta.json', what: 'Счетчики ходов и вызовов, cwd, последний ответ, что из общего уже показано, телеметрия (идущий инструмент, ожидание).', who: 'хуки на каждом событии' },
    { path: 'aaaaaaaa/journal.md', what: 'Вехи (longrun log) и механические строки: старт, конец, FAIL, компакция, отправки.', who: 'хуки и longrun log' },
    { path: 'aaaaaaaa/notes.md', what: 'Свои заметки [s1], [s2]... Бюджет 3000 байт.', who: 'агент: add, rm, replace, prune' },
    { path: 'aaaaaaaa/asks.json', what: 'Вопросы этой сессии человеку: Q<n>, состояние, ответ.', who: 'longrun ask' },
    { path: 'bbbbbbbb/meta.json', what: 'То же для сессии B.', who: 'хуки' },
    { path: 'bbbbbbbb/journal.md', what: 'Журнал сессии B.', who: 'хуки, longrun log' },
    { path: '_index/<cli sid>.json', what: 'CLI id -> проект и ключ сессии. Так resume под новым id находит старый каталог.', who: 'хук SessionStart' },
  ] };
  const GLOB = { label: '~/.claude/longrun/  (глобальное)', prefix: '~/.claude/longrun/', files: [
    { path: 'watch/w1.json', what: 'Одна отложенная проверка: что проверять, кому и что сказать, когда истекает.', who: 'watch add; тик таймера обновляет' },
    { path: 'halt.json', what: 'Стоп для всех сессий всех проектов: кто, когда, почему.', who: 'halt / resume, смотритель бюджета' },
    { path: 'budget.json', what: 'Замеры 5-часового окна и план (20% в час).', who: 'смотритель раз в 5 минут' },
  ] };

  /* ---------- Scenario 1: one session survives compaction ---------- */
  const s1 = Object.assign(pick(['U', 'A', 'P', 'SA'], ['AP', 'PA', 'ASA', 'SAA', 'UA']), { size: [560, 215], roots: [PROJ, OWN], steps: [
    { title: 'Папка становится проектом', who: 'человек или агент', nodes: ['U', 'A', 'P'], edges: ['UA', 'AP'],
      caption: 'Один раз в папке проекта, той, что открыта в Claude Code. Появляется <b>.longrun/</b>: это и есть "проект", общая память всех сессий в этой папке.',
      term: [{ who: 'shop', cmd: 'longrun init' }, { out: 'project shop: /Users/me/shop/.longrun\nsessions: ~/.claude/longrun/sessions/shop\nmode: notes only (`longrun init --hq` adds the shared ledger/inbox layer)\ntip: add `.longrun/` to the repo ignore file, or use `longrun init --external` to keep it out of the tree' }],
      files: [['NOTES.md', 'new'], ['config.json', 'new'], ['state.json', 'new']] },
    { title: 'Сессия A стартует: хук SessionStart печатает дайджест', who: 'хук', nodes: ['A', 'P', 'SA'], edges: ['PA', 'SAA'],
      caption: 'Хук находит проект (вверх по дереву до .longrun/), заводит каталог сессии вне репозитория и печатает в контекст модели дайджест. Пока он пуст.',
      term: [{ dim: '# SessionStart (source=startup) -> в контекст модели:' }, { out: '<longrun v0.4.0 project=shop session=aaaaaaaa [aaaaaaaa] source=startup>\nSHARED notes (project shop) 0 entries 0/5000 B (~0 tok)\nOWN notes (this session) 0 entries 0/3000 B (~0 tok)\n' + FOOT + '\n</longrun>' }],
      files: [['NOTES.md', 'rd'], ['aaaaaaaa/meta.json', 'new'], ['aaaaaaaa/journal.md', 'new'], ['_index/<cli sid>.json', 'new']] },
    { title: 'Тупик: агент записывает его себе', who: 'агент', nodes: ['A', 'SA'], edges: ['ASA'],
      caption: 'Тест повис, причина найдена. Это первое, что теряет компакция, поэтому одна строка на диск сразу. Без <code>--shared</code> заметка своя: <b>[s1]</b>.',
      term: [{ who: 'A', cmd: 'longrun add -t dead "pytest -x hangs on test_checkout: it waits for a real Redis; run with REDIS_URL=fake://"' }, { out: 'added s1 (own, 107/3000 bytes, ~26 tokens)' }],
      files: [['aaaaaaaa/notes.md', 'new']] },
    { title: 'Факт для всех: в общие заметки', who: 'агент', nodes: ['A', 'P'], edges: ['AP'],
      caption: 'Номер PR и решение о типе нужны любой сессии проекта. <code>--shared</code> кладет их в NOTES.md проекта: <b>[n1]</b>, <b>[n2]</b>, с меткой автора.',
      term: [{ who: 'A', cmd: 'longrun add --shared -t pin "PR 42 = feature/cart-total, branch cart-total"' }, { out: 'added n1 (shared, 71/5000 bytes, ~17 tokens)' }, { who: 'A', cmd: 'longrun add --shared -t decision "Round prices with Decimal, not float: float gave 19.999999 in the cart"' }, { out: 'added n2 (shared, 172/5000 bytes, ~43 tokens)' }, { who: 'A', cmd: 'cat .longrun/NOTES.md' }, { out: '# longrun notes (one line per entry; edit with `longrun add|rm|replace|prune`)\n- [n1] 09-10 pin (shop): PR 42 = feature/cart-total, branch cart-total\n- [n2] 09-10 decision (shop): Round prices with Decimal, not float: float gave 19.999999 in the cart' }],
      files: [['NOTES.md', 'chg']] },
    { title: 'Веха: в журнал, не в заметки', who: 'агент', nodes: ['A', 'SA'], edges: ['ASA'],
      caption: 'Прогресс ("тесты зеленые", "PR открыт") идет в журнал сессии. Заметки для того, что нельзя вывести заново; журнал для хронологии.',
      term: [{ who: 'A', cmd: 'longrun log "tests green, PR 42 opened"' }, { out: 'logged to sessions/aaaaaaaa/journal.md' }],
      files: [['aaaaaaaa/journal.md', 'chg']] },
    { title: 'Компакция: механика снимает и архивирует', who: 'хуки', nodes: ['A', 'P', 'SA'], edges: ['AP', 'ASA'],
      caption: 'Контекст переполнился, Claude Code сжимает историю в резюме. <b>PreCompact</b> сохраняет снимок (последние просьбы человека, правленые файлы, FAIL), <b>PostCompact</b> кладет резюме дословно в архив. Модель тут ничего не делает.',
      term: [{ dim: '# PreCompact (trigger=auto), PostCompact -> файлы, вывода в контекст нет' }, { who: 'A', cmd: 'tail -3 ~/.claude/longrun/sessions/shop/aaaaaaaa/journal.md' }, { out: '09-10 11:03 * tests green, PR 42 opened\n09-10 11:03 compaction auto | snapshot archive/precompact/aaaaaaaa-20260910-110357.md\n09-10 11:03 session compact ()' }],
      files: [['archive/precompact/<sid>-<time>.md', 'new'], ['archive/compact/<sid>-<time>.md', 'new'], ['aaaaaaaa/journal.md', 'chg']] },
    { title: 'После компакции: заметки возвращаются в контекст', who: 'хук', nodes: ['A', 'P', 'SA'], edges: ['PA', 'SAA'],
      caption: 'Снова SessionStart, теперь с <code>source=compact</code>. Дайджест печатает общие и свои заметки и хвост журнала. Тупик с Redis <b>опять в контексте</b>, хотя резюме могло его выбросить.',
      term: [{ dim: '# SessionStart (source=compact) -> в контекст модели:' }, { out: '<longrun v0.4.0 project=shop session=aaaaaaaa [aaaaaaaa] source=compact>\nSHARED notes (project shop) 2 entries 172/5000 B (~43 tok)\n- [n1] 09-10 pin (shop): PR 42 = feature/cart-total, branch cart-total\n- [n2] 09-10 decision (shop): Round prices with Decimal, not float: float gave 19.999999 in the cart\nOWN notes (this session) 1 entries 107/3000 B (~26 tok)\n[[- [s1] 09-10 dead: pytest -x hangs on test_checkout: it waits for a real Redis; run with REDIS_URL=fake://]]\nSESSION journal tail (sessions/aaaaaaaa/journal.md):\n09-10 11:03 session startup ()\n09-10 11:03 * tests green, PR 42 opened\n09-10 11:03 compaction auto | snapshot archive/precompact/aaaaaaaa-20260910-110357.md\n09-10 11:03 session compact ()\nCompaction summaries are archived verbatim in archive/compact/ (1 kept): `longrun recall <term>` finds what this one dropped.\n' + FOOT + '\n</longrun>' }],
      files: [['NOTES.md', 'rd'], ['aaaaaaaa/notes.md', 'rd'], ['aaaaaaaa/journal.md', 'rd']] },
    { title: 'Потерялась деталь: recall, а не повторное исследование', who: 'агент', nodes: ['A', 'P', 'SA'], edges: ['ASA', 'AP'],
      caption: 'Поиск идет по общим и своим заметкам всех сессий, журналам, архивным резюме и транскриптам проекта. Сначала это, и только потом перечитывать код.',
      term: [{ who: 'A', cmd: 'longrun recall Redis' }, { out: 'sessions/aaaaaaaa/notes.md:2: - [s1] 09-10 dead: pytest -x hangs on test_checkout: it waits for a real Redis; run with REDIS_URL=fake://\ntranscript(tool_result): ...run with REDIS_URL=fake:// ...\n(1 file hits, 2 hits in 6 transcript(s); showing 1+2, -n to widen)' }],
      files: [['aaaaaaaa/notes.md', 'rd'], ['archive/compact/<sid>-<time>.md', 'rd']] },
  ] });
  return { N, E, pick, PROJ, OWN, GLOB, FOOT, s1 };
})();
