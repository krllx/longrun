/* Scenarios 2 and 3: two sessions share memory; hand work over and wait for events. */
(function (C) {
  const { pick, PROJ, OWN, GLOB, FOOT } = C;

  C.s2 = Object.assign(pick(['A', 'B', 'P', 'SA', 'SB'], ['AP', 'PA', 'BP', 'PB', 'BSB', 'SBB', 'SAA']), { size: [560, 270], roots: [PROJ, OWN], steps: [
    { title: 'Сессия B открывается в той же папке', who: 'хук', nodes: ['B', 'P', 'SB'], edges: ['PB'],
      caption: 'B ничего не делала, но уже знает номер PR, решение про Decimal и что рядом работает A. Это блок <b>SESSIONS</b>: кто есть, жив ли, сколько своих заметок, что делал последним.',
      term: [{ dim: '# SessionStart в сессии B:' }, { out: '<longrun v0.4.0 project=shop session=bbbbbbbb [bbbbbbbb] source=startup>\nSHARED notes (project shop) 2 entries 172/5000 B (~43 tok)\n- [n1] 09-10 pin (shop): PR 42 = feature/cart-total, branch cart-total\n- [n2] 09-10 decision (shop): Round prices with Decimal, not float: float gave 19.999999 in the cart\nOWN notes (this session) 0 entries 0/3000 B (~0 tok)\n[[SESSIONS of project shop (1 other; `longrun status`, `longrun send <name> "..."`):\n  aaaaaaaa [aaaaaaaa] active?, shop, 1 own notes: -]]\n' + FOOT + '\n</longrun>' }],
      files: [['NOTES.md', 'rd'], ['bbbbbbbb/meta.json', 'new'], ['bbbbbbbb/journal.md', 'new']] },
    { title: 'B узнает факт об окружении и делится', who: 'агент B', nodes: ['B', 'P'], edges: ['BP'],
      caption: 'Ключ Stripe лежит не там, где написано в env-файле. Стоило усилий, нужно всем: <code>--shared -t fact</code>.',
      term: [{ who: 'B', cmd: 'longrun add --shared -t fact "Stripe sandbox needs STRIPE_KEY from 1password vault \'shop-dev\', the env file one is stale"' }, { out: 'added n3 (shared, 298/5000 bytes, ~74 tokens)' }],
      files: [['NOTES.md', 'chg']] },
    { title: 'Следующий ход A: приходит только разница', who: 'хук', nodes: ['A', 'P'], edges: ['PA'],
      caption: 'Хук <b>UserPromptSubmit</b> сравнивает NOTES.md с тем, что A уже видела, и печатает дельту: <code>+</code> добавлено, <code>~</code> переписано, <code>-</code> удалено. Свои строки сессии обратно не показываются.',
      term: [{ dim: '# UserPromptSubmit в сессии A -> в контекст:' }, { out: 'SHARED notes of project shop changed since you last saw them:\n  [[+ - [n3] 09-10 fact (bbbbbbbb): Stripe sandbox needs STRIPE_KEY from 1password vault \'shop-dev\', the env file one is stale]]' }],
      files: [['NOTES.md', 'rd'], ['aaaaaaaa/meta.json', 'chg']] },
    { title: 'Кто что делает: status', who: 'агент', nodes: ['B', 'P', 'SA', 'SB'], edges: ['SAA', 'SBB'],
      caption: 'Все из файлов состояния, без чтения транскриптов: имя, жива ли, число своих заметок, вызовов, компакций, падений, последний ответ.',
      term: [{ who: 'B', cmd: 'longrun status' }, { out: 'longrun 0.4.0  project shop  dir=/Users/me/shop/.longrun\nshared notes: 3 entries, 298/5000 B\nledger/inbox: off (notes-only mode; `longrun init --hq` turns the multi-session layer on)\nsessions (* = this one):\n  aaaaaaaa aaaaaaaa      active?   shop   notes=1  tools=0  cmp=1  fails=0  last=2026-09-10 11:03\n      -\n* bbbbbbbb bbbbbbbb      active?   shop   notes=0  tools=0  cmp=0  fails=0  last=2026-09-10 11:04' }],
      files: [['aaaaaaaa/meta.json', 'rd'], ['bbbbbbbb/meta.json', 'rd']] },
    { title: 'Бюджет жесткий: add отказывает, prune чистит', who: 'агент', nodes: ['B', 'P'], edges: ['BP'],
      caption: 'Общие заметки: 5000 байт, свои: 3000. Полный файл не вытесняет старое молча: <code>add</code> отказывает и называет, что дешевле всего убрать. Привычка: <code>rm</code> сделанное, <code>replace</code> вместо второй строки, <code>prune</code> когда дайджест говорит PRUNE NEEDED.',
      term: [{ who: 'B', cmd: 'longrun add --shared -t fact "one more that does not fit"' }, { out: 'longrun: shared notes is at 4961/5000 bytes; the new entry does not fit.\nFree space first: `longrun rm <id>` / `longrun replace <id> <shorter text>` / `longrun prune --auto --shared`.\nCheapest to drop:\n  - [n7] 09-03 todo (shop): re-run the cart fixture\n  - [n9] 09-04 ctx (shop): user wants the discount UI last' }, { who: 'B', cmd: 'longrun prune --auto --shared' }, { out: 'archived 4 entries to archive/notes.md; now 2980/5000 bytes' }, { who: 'B', cmd: 'longrun replace n2 "Prices are Decimal everywhere (cart, checkout, invoices)"' }, { out: 'replaced n2' }],
      files: [['NOTES.md', 'chg']] },
  ] });

  C.s3 = Object.assign(pick(['U', 'A', 'B', 'P', 'L', 'G'], ['AP', 'PB', 'AB', 'AG', 'LG', 'LP', 'PA', 'LA']), { size: [560, 310], roots: [PROJ, GLOB, OWN], steps: [
    { title: 'A передает работу B: адресат остановлен', who: 'агент A', nodes: ['A', 'P'], edges: ['AP'],
      caption: 'Адресата зовут так, как его видит человек: заголовок в сайдбаре, имя из реестра или префикс id. B сейчас не работает, поэтому текст ложится файлом в <b>inbox</b> проекта.',
      term: [{ who: 'A', cmd: 'longrun send bbbbbbbb "PR 42 merged, rebase your branch onto main"' }, { out: 'bbbbbbbb is not running: queued as inbox/20260910-110356-msg-to-bbbbbbbb-from-aaaaaaaa.md; its hooks deliver it at its next tool call, turn or start (`--resume` would wake it now)' }],
      files: [['inbox/<msg>.md', 'new'], ['aaaaaaaa/journal.md', 'chg']] },
    { title: 'B просыпается: сообщение приходит ходом', who: 'хук', nodes: ['B', 'P'], edges: ['PB'],
      caption: 'Первый же хук B (ход, вызов инструмента или старт) забирает файл из inbox и печатает его в контекст. Для модели это просьба от коллеги, не от человека: права остаются свои.',
      term: [{ dim: '# UserPromptSubmit в сессии B -> в контекст:' }, { out: 'MESSAGE to bbbbbbbb from aaaaaaaa (2026-09-10 11:03)\n[[PR 42 merged, rebase your branch onto main]]' }],
      files: [['inbox/<msg>.md', 'gone'], ['bbbbbbbb/meta.json', 'chg']] },
    { title: 'А если B работает прямо сейчас: сокет', who: 'CLI', nodes: ['A', 'B'], edges: ['AB'],
      caption: 'Работающая сессия слушает unix-сокет. Текст уходит туда и появляется у B как ход пользователя между вызовами инструментов, без inbox. <code>--resume</code> будит остановленную сессию через <code>claude -p --resume</code>.',
      term: [{ who: 'A', cmd: 'longrun send "PR C: checkout" "B merged, rebase onto trunk"' }, { out: 'delivered to PR C: checkout (cccccccc) over its inbox socket; it reads it between tool calls or as a new turn' }, { dim: '# у адресата это выглядит так:' }, { out: '<cross-session-message from="uds:/tmp/cc-socks/44777.sock" from-name="longrun send">\nMESSAGE to ... from ...\nB merged, rebase onto trunk\n</cross-session-message>' }],
      files: [] },
    { title: 'Ждать событие: watch вместо опроса', who: 'агент A', nodes: ['A', 'G'], edges: ['AG'],
      caption: '"Проверь через два часа", "когда PR вольется": никаких sleep-циклов и напоминаний человеку. Регистрируется детерминированная проверка. <code>add</code> сразу пробует ее один раз: уже истинна, значит ничего не регистрируется, действуй.',
      term: [{ who: 'A', cmd: 'longrun watch add --then "check the deploy dashboard" -- at "+2h"' }, { out: 'registered w1: time reaches 2026-09-10 13:04\n  to:       aaaaaaaa [aaaaaaaa]  delivery when it fires: inbox file, read at its next tool call, turn or start\n  every:    5m (launchd tick is 5m; a Mac asleep catches up on wake)   expires: 2026-09-17 11:04\n  then:     check the deploy dashboard\n  first run: not yet (now 2026-09-10 11:04, target 2026-09-10 13:04)' }, { dim: '# другие проверки: pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'' }],
      files: [['watch/w1.json', 'new']] },
    { title: 'launchd проверяет раз в 5 минут, без модели', who: 'launchd', nodes: ['L', 'G'], edges: ['LG'],
      caption: 'Тик стоит ноль токенов. Условие не выполнено: запись обновляется и все. Ноутбук спал: проверка догоняет после пробуждения. Три жестких ошибки подряд или истекший срок дают одно сообщение "broken" или "expired".',
      term: [{ who: 'A', cmd: 'longrun watch ls' }, { out: '* w1   pending  -> aaaaaaaa [aaaaaaaa]   time reaches 2026-09-10 13:04 every 5m, next 2026-09-10 11:09, expires 09-17 11:04\n        then: check the deploy dashboard\n        last: 2026-09-10 11:04 rc=1 now 2026-09-10 11:04, target 2026-09-10 13:04\n(* = targets this session)' }],
      files: [['watch/w1.json', 'chg']] },
    { title: 'Условие выполнилось: сообщение адресату', who: 'launchd', nodes: ['L', 'P', 'A'], edges: ['LP', 'PA', 'LA'],
      caption: 'Тик доставляет текст <code>--then</code> теми же путями, что и <code>send</code>: в сокет работающей сессии или в inbox. Сессия читает "From longrun watch w1" и делает, что написано. Написала это она сама, возможно до компакции.',
      term: [{ dim: '# 13:05, в контексте сессии A:' }, { out: 'From longrun watch w1 at 2026-09-10 13:05, for session aaaaaaaa [aaaaaaaa]:\nCONDITION MET: time reaches 2026-09-10 13:04\nRegistered 2026-09-10 11:04 by aaaaaaaa [aaaaaaaa], checked every 5m (25 run(s)).\n\nNow do what was asked when this watch was registered:\n[[check the deploy dashboard]]' }],
      files: [['watch/w1.json', 'chg'], ['inbox/<msg>.md', 'new']] },
  ] });
})(window.COURSE);
