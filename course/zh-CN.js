/* Simplified Chinese strings for the scenario data: overrides titles, captions, node labels and file descriptions of window.COURSE. Terminal output is shared. */
(function (C) {
  const N = C.N;
  Object.assign(N.U, { title: '人', sub: ['终端、聊天、对话框'] });
  Object.assign(N.A, { title: '会话 A', sub: ['Claude Code', 'longrun hooks'] });
  Object.assign(N.B, { title: '会话 B', sub: ['Claude Code', 'longrun hooks'] });
  Object.assign(N.P, { title: '项目 shop/.longrun', sub: ['NOTES.md  共享', 'inbox/  board.json', 'archive/'] });
  Object.assign(N.SA, { title: 'A 的自有目录', sub: ['notes.md', 'journal, meta'] });
  Object.assign(N.SB, { title: 'B 的自有目录', sub: ['notes.md', 'journal, meta'] });
  Object.assign(N.L, { title: '定时器，每 5 分钟', sub: ['watch, watcher, budget'] });
  Object.assign(N.G, { title: '~/.claude/longrun', sub: ['watch/, halt.json'] });
  Object.assign(N.D, { title: 'osascript 对话框', sub: ['盖在所有窗口之上'] });

  C.PROJ.label = 'shop/.longrun/  （共享，在项目里）';
  const PF = {
    'NOTES.md': ['共享笔记 [n1]、[n2]…… 每条一行，带作者。预算 5000 字节。', '由 agent 写：add --shared, rm, replace, prune --shared'],
    'config.json': ['项目设置：hq 模式（台账和收件箱那一层，`longrun init --hq`）、预算、阈值。', 'init; longrun config set'],
    'state.json': ['笔记 id 和任务 id 的计数器。', 'CLI'],
    'inbox/<msg>.md': ['给当前没在运行的会话的消息。送达后移到 inbox/.archive/。', 'send, watch, board, ask；由收件会话的 hook 读取'],
    'archive/precompact/<sid>-<time>.md': ['compaction 之前的快照：用户最近的几个请求、编辑过的文件、最近的 FAIL。HANDOFF 区块（compaction 之后留给自己的交接说明）就是用它拼出来的。', 'PreCompact hook'],
    'archive/compact/<sid>-<time>.md': ['compaction 总结的原文。longrun recall 能搜到这些文件。', 'PostCompact hook'],
    'board.json': ['编排器的任务板：目标、任务 T<n>、事实 F<n>。', 'board, fact'],
    'orchestrator.json': ['谁拿着编排器的角色，目标是什么。', 'orchestrate start/stop'],
  };
  C.OWN.label = '~/.claude/longrun/sessions/shop/<session>/  （自有，在仓库之外）';
  const OF = {
    'aaaaaaaa/meta.json': ['轮次和调用计数、cwd、最后一次回答、共享笔记里哪些已经给它看过、遥测（正在跑的工具、是否在等人）。', '每个事件的 hook'],
    'aaaaaaaa/journal.md': ['里程碑 (longrun log) 和机械层写的记录：启动、结束、失败的命令、compaction、发送。', 'hook 和 longrun log'],
    'aaaaaaaa/notes.md': ['自有笔记 [s1]、[s2]…… 预算 3000 字节。', 'agent：add, rm, replace, prune'],
    'aaaaaaaa/asks.json': ['这个会话问过人的问题：Q<n>、状态、回答。', 'longrun ask'],
    'bbbbbbbb/meta.json': ['会话 B 的对应文件。', 'hook'],
    'bbbbbbbb/journal.md': ['会话 B 的日志。', 'hook, longrun log'],
    '_index/<cli sid>.json': ['CLI id -> 项目和会话 key。resume 用新 id 启动时就是这样找回旧目录的。', 'SessionStart hook'],
  };
  C.GLOB.label = '~/.claude/longrun/  （全局）';
  const GF = {
    'watch/w1.json': ['一项延迟检查：查什么、通知谁、说什么、什么时候过期。', 'watch add；定时器每次 tick 都会更新'],
    'halt.json': ['全部停止的记录，对所有项目的所有会话生效：谁停的、什么时候、为什么。', 'halt / resume，预算监视器'],
    'budget.json': ['5 小时窗口的采样和计划（每小时 20%）。', '监视器每 5 分钟一次'],
  };
  [[C.PROJ, PF], [C.OWN, OF], [C.GLOB, GF]].forEach(([r, m]) => r.files.forEach(f => { if (m[f.path]) { f.what = m[f.path][0]; f.who = m[f.path][1]; } }));

  function steps(sc, list) { list.forEach((t, i) => { const s = sc.steps[i]; if (!s) return; s.title = t[0]; s.who = t[1]; s.caption = t[2]; }); }
  steps(C.s1, [
    ['文件夹变成项目', '人或 agent', '在项目文件夹（也就是 Claude Code 打开的那个）里只做一次。多出一个 <b>.longrun/</b> 目录：这就是“项目”，是这个文件夹下所有会话的共享记忆。'],
    ['会话 A 启动：SessionStart hook 打印摘要', 'hook', 'hook 沿目录树向上找到项目（找 .longrun/），在仓库之外建好会话目录，再把摘要打印进模型的上下文。摘要现在还是空的。'],
    ['一条死胡同：agent 给自己记下来', 'agent', '测试挂住了，原因找到了。compaction 最先丢的就是这个，所以马上写一行到磁盘上。不加 <code>--shared</code> 的笔记是自有的：<b>[s1]</b>。'],
    ['一条大家都要的事实：写进共享笔记', 'agent', 'PR 号和选用哪种类型的决定，项目里任何一个会话都用得上。<code>--shared</code> 把它们写进项目的 NOTES.md：<b>[n1]</b>、<b>[n2]</b>，带上作者标记。'],
    ['里程碑：进日志，不进笔记', 'agent', '进展（“测试绿了”、“PR 开了”）写进会话日志。笔记留给推导不出来的东西；日志是时间线。'],
    ['compaction：机械层做快照和归档', 'hook', '上下文满了，Claude Code 把历史压成一段总结。<b>PreCompact</b> 存下快照（用户最近的几个请求、编辑过的文件、FAIL），<b>PostCompact</b> 把总结原样归档。模型在这一步什么都不做。'],
    ['compaction 之后：笔记回到上下文里', 'hook', '又一次 SessionStart，这回是 <code>source=compact</code>。摘要打印共享笔记、自有笔记和日志的尾巴。Redis 那条死胡同<b>又回到上下文里</b>了，哪怕总结把它丢了。'],
    ['少了一个细节：用 recall，别重新查一遍', 'agent', '搜索覆盖所有会话的共享笔记和自有笔记、各份日志、归档的总结，以及项目的 transcript。先搜这些，之后才是重读代码。'],
  ]);
  steps(C.s2, [
    ['会话 B 在同一个文件夹里打开', 'hook', 'B 还什么都没做，但已经知道了 PR 号、用 Decimal 的决定，以及 A 正在旁边干活。这就是 <b>SESSIONS</b> 区块：都有谁、是否还活着、各有多少自有笔记、各自最后干了什么。'],
    ['B 弄清了一条环境事实并分享出去', 'agent B', 'Stripe key 不在 env 文件说的那个地方。这是花了力气才弄清的，而且谁都用得上：<code>--shared -t fact</code>。'],
    ['A 的下一轮：只有差异会送过来', 'hook', '<b>UserPromptSubmit</b> hook 把 NOTES.md 和 A 已经看过的内容比一比，只打印差异：<code>+</code> 新增、<code>~</code> 改写、<code>-</code> 删除。一个会话自己写的行，永远不会再回显给它。'],
    ['谁在干什么：status', 'agent', '全部来自状态文件，不读 transcript：名字、是否还活着、自有笔记、调用次数、compaction 次数、失败次数、最后一次回答。'],
    ['预算是硬上限：add 会拒绝，prune 来清理', 'agent', '共享笔记 5000 字节，自有笔记 3000。文件满了不会悄悄挤掉旧行：<code>add</code> 直接拒绝，并指出删掉哪几条最划算。习惯是：做完的用 <code>rm</code> 删掉，用 <code>replace</code> 而不是再加一行，摘要里出现 PRUNE NEEDED 就 <code>prune</code>。'],
  ]);
  steps(C.s3, [
    ['A 把活交给 B：收件方已经停了', 'agent A', '收件方按人看到的名字来指定：侧边栏标题、登记表里的名字，或者 id 前缀。B 现在没在运行，所以这段文字以文件形式落进项目的 <b>inbox</b>。'],
    ['B 醒来：消息作为一轮用户输入送到', 'hook', 'B 的第一个 hook（一轮输入、一次工具调用或一次启动）把文件从收件箱取走，打印进上下文。对模型来说这是同伴发来的请求，不是人下的指令：B 的权限还是 B 自己的，不因此改变。'],
    ['如果 B 此刻正在运行：走 socket', 'CLI', '正在运行的会话监听一个 unix socket。文字直接送到那里，在两次工具调用之间作为一轮用户输入出现在 B 里，不经过收件箱。<code>--resume</code> 通过 <code>claude -p --resume</code> 叫醒已经停了的会话。'],
    ['等一个事件：用 watch，不要轮询', 'agent A', '“两小时后看一下”、“PR 合了以后”：不用 sleep 循环，也不用提醒人。注册的是一项确定性的检查。<code>add</code> 会立刻先试一次：已经成立就什么都不注册，直接去做。'],
    ['定时器每 5 分钟检查一次，不调用模型', '定时器', '一次 tick 不花 token。条件不成立就更新记录，仅此而已。笔记本电脑休眠了，醒来会补上。连着三次检查本身出错或者过了截止时间，会发来一条 "broken" 或 "expired"。'],
    ['条件成立：给收件方发消息', '定时器', 'tick 把 <code>--then</code> 里的文字用和 <code>send</code> 一样的方式送出去：进正在运行的会话的 socket，或者进收件箱。会话读到 "From longrun watch w1" 就照着做。那段文字是它自己写的，也许还是在某次 compaction 之前写的。'],
  ]);
  steps(C.s4, [
    ['A 接过编排器的角色', 'agent A，按人的吩咐', '每个项目只有一个会话带着它走向既定目标。它拿到一份职责清单，而且<b>什么都不轮询</b>：事件会叫醒它。第二个会话想接会被拒绝，并看到现在是谁拿着。'],
    ['任务板：任务和派发', '编排器', '任务 T<n>，状态有 todo / doing / blocked / done / dropped。<code>assign</code> 把任务送进活着的会话的 socket，或者送进已停会话的收件箱。'],
    ['B 把任务当作一轮用户输入收下', 'hook', '干活的会话只需要三条命令：<code>take</code>、<code>done</code>、<code>block</code>。别的什么都不用学。'],
    ['B 干完活并关掉任务；一条来自外部的事实', 'agent B', '<code>done</code> 和 <code>block</code> 会叫醒编排器。评审要求改一个字段名：这是<b>来自外部的事实</b>。规矩是：先记下来 (<code>fact</code>)，再做决定。这条事实也会送到编排器那儿。'],
    ['编排器醒来并处置', '编排器', '它读任务板和事实，不读 transcript：自己的上下文必须保持精简。每一条事实都要明确收尾：转达出去、重新规划，或者去问人。'],
    ['不花 token 的遥测：SESSIONS 里的标记', 'hook 和监视器', 'PreToolUse、PostToolUse、Stop、PermissionRequest 和 Notification 这几个 hook 把工具何时开始、何时结束、会话是否在等权限写进 meta.json。监视器（定时器）每 5 分钟把这些记录和阈值比一次，每一次卡住只向编排器报一次。'],
    ['全部停止：halt', '编排器，按人的吩咐', 'halt.json 文件是全局的。每个会话的 <b>PreToolUse</b> hook 都会拒绝执行并附上原因；模型看得到，会告诉人它本来打算做什么。只有人能解除，而且要在对话里明说：<code>longrun resume</code>。'],
    ['盖在所有窗口之上问人一个问题', 'agent B', '只用于等不了的事：一次确认、一个权限、一件只有人能做的事。对话框由 osascript 在一个单独的进程里画出来：盖在所有窗口之上，带提示音，不需要任何权限。90 秒之内的回答会直接返回。'],
    ['人不在：回答稍后作为一轮用户输入送到', '等待', '90 秒之后命令返回 PENDING，会话继续往下走。对话框还开着（默认 6 小时）；点击的结果会进会话的 socket 或收件箱。Cancel、Esc 或过期：CANCELLED / EXPIRED，问题不再重复问，而是挂到任务板上。'],
    ['5 小时窗口的预算', '监视器', '监视器每 5 分钟读一次窗口用量（用 Claude Code 的登录凭证调 usage 接口），并和计划比一比：每小时 20%。超出 1.5 倍：所有项目全部停止、向编排器汇报，并给人弹一个 Keep stopped / Resume all 对话框。'],
  ]);
  /* Russian comment lines inside terminal panels */
  const TERM = {
    '# SessionStart (source=startup) -> в контекст модели:': '# SessionStart (source=startup) -> 进入模型上下文：',
    '# PreCompact (trigger=auto), PostCompact -> файлы, вывода в контекст нет': '# PreCompact (trigger=auto), PostCompact -> 写文件，不往上下文里打印任何东西',
    '# SessionStart (source=compact) -> в контекст модели:': '# SessionStart (source=compact) -> 进入模型上下文：',
    '# SessionStart в сессии B:': '# SessionStart，在会话 B 里：',
    '# UserPromptSubmit в сессии A -> в контекст:': '# UserPromptSubmit，在会话 A 里 -> 进入上下文：',
    '# UserPromptSubmit в сессии B -> в контекст:': '# UserPromptSubmit，在会话 B 里 -> 进入上下文：',
    '# у адресата это выглядит так:': '# 收件方看到的是这样：',
    '# другие проверки: pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'': '# 其他检查：pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'',
    '# 13:05, в контексте сессии A:': '# 13:05，在会话 A 的上下文里：',
    '# UserPromptSubmit в B:': '# UserPromptSubmit，在 B 里：',
    '# строки SESSIONS в дайджесте оркестратора (пример):': '# 编排器摘要里的 SESSIONS 行（示例）：',
    '# что делает оркестратор: longrun send сессии, или предлагает человеку interrupt': '# 编排器会做什么：longrun send 给那个会话，或者向人提议 interrupt',
    '# PreToolUse в сессии B (Bash "pytest") -> Claude Code:': '# PreToolUse，在会话 B 里 (Bash "pytest") -> Claude Code:',
    '# ... на экране диалог с кнопками Да / Нет, человек нажимает Да': '# ... 屏幕上是带 Yes / No 两个按钮的对话框，人点了 Yes',
    '# то же самое из MCP: тул mcp__longrun__ask (сервер `longrun`, регистрирует install.sh)': '# 用 MCP 也一样：工具 mcp__longrun__ask（服务器 `longrun`，由 install.sh 注册）',
    '# ... позже, в контексте B:': '# ... 稍后，在 B 的上下文里：',
    '# при стопе: HALT + уведомление macOS + диалог Keep stopped / Resume all; `longrun resume` снимает и усыпляет правило до сброса окна': '# 停止时：HALT + macOS 通知 + Keep stopped / Resume all 对话框；`longrun resume` 解除停止，并让预算规则休眠，直到窗口重置',
  };
  [C.s1, C.s2, C.s3, C.s4].forEach(sc => sc.steps.forEach(s => (s.term || []).forEach(t => { if (t.dim && TERM[t.dim]) t.dim = TERM[t.dim]; })));
  /* the ask dialog buttons in scenario 4 */
  C.s4.steps.forEach(s => (s.term || []).forEach(t => ['cmd', 'dim', 'out'].forEach(f => {
    if (typeof t[f] === 'string') t[f] = t[f].replace(/Да,Нет/g, 'Yes,No').replace(/Да \/ Нет/g, 'Yes / No').replace(/Да/g, 'Yes').replace(/Нет/g, 'No');
  })));
})(window.COURSE);
