/* Japanese strings for the scenario data: overrides titles, captions, node labels and file descriptions of window.COURSE. Terminal output is shared. */
(function (C) {
  const N = C.N;
  Object.assign(N.U, { title: '人間', sub: ['ターミナル、チャット、ダイアログ'] });
  Object.assign(N.A, { title: 'セッションA', sub: ['Claude Code', 'longrun hooks'] });
  Object.assign(N.B, { title: 'セッションB', sub: ['Claude Code', 'longrun hooks'] });
  Object.assign(N.P, { title: 'プロジェクトshop/.longrun', sub: ['NOTES.md  共有', 'inbox/  board.json', 'archive/'] });
  Object.assign(N.SA, { title: 'Aの自分の領域', sub: ['notes.md', 'journal, meta'] });
  Object.assign(N.SB, { title: 'Bの自分の領域', sub: ['notes.md', 'journal, meta'] });
  Object.assign(N.L, { title: 'タイマー、5分ごと', sub: ['watch, watcher'] });
  Object.assign(N.G, { title: '~/.claude/longrun', sub: ['watch/, halt.json'] });
  Object.assign(N.D, { title: 'osascriptダイアログ', sub: ['全ウィンドウの手前に'] });

  C.PROJ.label = 'shop/.longrun/  （共有、プロジェクトの中）';
  const PF = {
    'NOTES.md': ['共有メモ[n1]、[n2]……1件1行、著者つき。予算5000バイト。メモは何も指定しなければここへ入ります。', 'エージェントが書く：add, rm, replace, stale, prune --shared'],
    'config.json': ['プロジェクトの設定：メモとダイジェストの予算、しきい値。', 'init; longrun config set'],
    'state.json': ['メモidとタスクidのカウンター。', 'CLI'],
    'stale.json': ['「古くなった」印：id -> 理由、誰が、いつ。NOTES.mdの中ではなく隣に置くので、メモの形式は変わらずに済みます。', 'longrun stale'],
    'inbox/<msg>.md': ['いま動いていないセッション宛のメッセージ。配送済みのものはinbox/.archive/へ移ります。', 'send, watch, board, ask。受け取る側のhookが読む'],
    'archive/precompact/<sid>-<time>.md': ['compactionの前のスナップショット：ユーザーの直近のリクエスト、編集したファイル、最近のFAIL。HANDOFFブロック（compaction後の自分への引き継ぎ）はこのスナップショットから組み立てられます。', 'PreCompact hook'],
    'archive/compact/<sid>-<time>.md': ['compactionの要約そのまま。longrun recallで見つかります。', 'PostCompact hook'],
    'board.json': ['オーケストレーターのボード：目標、タスクT<n>、事実F<n>。', 'board'],
    'orchestrator.json': ['誰がオーケストレーターの役を持ち、目標は何か。', 'orchestrate start/stop'],
  };
  C.OWN.label = '~/.claude/longrun/sessions/shop/<session>/  （自分の領域、リポジトリの外）';
  const OF = {
    'aaaaaaaa/meta.json': ['ターン数と呼び出し回数、cwd、最後の回答、共有メモのどこまでを見せたか、テレメトリ（実行中のツール、待機）。', '毎イベントのhook'],
    'aaaaaaaa/journal.md': ['機械層が書く行：開始、終了、失敗したコマンド、compaction、送信。書くのはhookで、エージェントではありません。', 'hook'],
    'aaaaaaaa/notes.md': ['自分のメモ[s1]、[s2]……予算3000バイト。', 'エージェント：add, rm, replace, prune'],
    'aaaaaaaa/asks.json': ['このセッションがユーザーに尋ねた質問：Q<n>、状態、回答。', 'longrun ask'],
    'bbbbbbbb/meta.json': ['セッションBの同じファイル。', 'hook'],
    'bbbbbbbb/journal.md': ['セッションBのジャーナル。', 'hook'],
    '_index/<cli sid>.json': ['CLI id -> プロジェクトとセッションkey。新しいidで始まったresumeが古いディレクトリを見つけられるのはこれのおかげです。', 'SessionStart hook'],
  };
  C.GLOB.label = '~/.claude/longrun/  （グローバル）';
  const GF = {
    'watch/w1.json': ['遅延チェック1件：何を確かめ、誰に何を伝え、いつ期限切れになるか。', 'watch add。タイマーのティックが更新する'],
    'halt.json': ['全プロジェクトの全セッションに効く全停止：誰が、いつ、なぜ。解除できるのは人間だけです。', 'halt / resume'],
  };
  [[C.PROJ, PF], [C.OWN, OF], [C.GLOB, GF]].forEach(([r, m]) => r.files.forEach(f => { if (m[f.path]) { f.what = m[f.path][0]; f.who = m[f.path][1]; } }));

  function steps(sc, list) { list.forEach((t, i) => { const s = sc.steps[i]; if (!s) return; s.title = t[0]; s.who = t[1]; s.caption = t[2]; }); }
  steps(C.s1, [
    ['フォルダがプロジェクトになる', '人間またはエージェント', '1度だけ、プロジェクトのフォルダ、つまりClaude Codeで開いているフォルダで実行します。<b>.longrun/</b>ディレクトリができます。これが「プロジェクト」、このフォルダの全セッションの共有記憶です。'],
    ['セッションAが始まり、SessionStart hookがダイジェストを出す', 'hook', 'hookはツリーを上へたどって.longrun/を探し、プロジェクトを見つけます。そしてリポジトリの外にセッションのディレクトリを作り、ダイジェストをモデルのコンテキストへ出力します。いまはまだ空です。'],
    ['行き止まり：エージェントが自分のために書き留める', 'エージェント', 'テストがハングし、原因が分かりました。compactionが真っ先に落とすのはこれなので、すぐ1行をディスクへ書きます。この行き止まりはこのブランチだけの話で、ほかの誰にも必要ありません。だから<code>--own</code>で、メモはこのセッションのもの、<b>[s1]</b>です。'],
    ['全員に必要な事実：共有メモへ', 'エージェント', 'PR番号と型の決定は、このプロジェクトのどのセッションにも必要です。だからフラグは要りません。<code>add</code>は何も指定しなければプロジェクトのNOTES.mdへ書きます。<b>[n1]</b>、<b>[n2]</b>、著者ラベルつきです。'],
    ['1行に収まらないほど長いもの：それはファイル', 'エージェント', 'ロールアウト計画は400文字には収まりません。計画はプロジェクトの中のファイルのままにして、共有メモにはそのパスを書いた1行だけを置きます。<b>[n3]</b>です。どのセッションもこの1行を見て、必要になったときだけファイルを開きます。行を書いた後にファイルが変わっていれば、ダイジェストがこの1行に印を付けます。'],
    ['compaction：機械層がスナップショットとアーカイブを取る', 'hook', 'コンテキストがあふれ、Claude Codeが履歴を要約に圧縮します。<b>PreCompact</b>がスナップショット（ユーザーの直近のリクエスト、編集したファイル、FAIL）を保存し、<b>PostCompact</b>が要約をそのままアーカイブします。モデルはここで何もしません。'],
    ['compactionの後：メモがコンテキストへ戻る', 'hook', '再びSessionStart、今度は<code>source=compact</code>です。ダイジェストは共有メモ、自分のメモ、ジャーナルの末尾を出力します。要約が落としていても、Redisの行き止まりは<b>コンテキストに戻っています</b>。'],
    ['細部が足りない：調べ直さずrecall', 'エージェント', '検索は全セッションの共有メモと自分のメモ、各ジャーナル、アーカイブされた要約、そしてプロジェクトのtranscriptに及びます。まず<code>recall</code>、コードを読み直すのはその後です。'],
  ]);
  steps(C.s2, [
    ['セッションBが同じフォルダで開く', 'hook', 'Bはまだ何もしていませんが、PR番号、Decimalを使う決定、そしてAが隣で作業していることをすでに知っています。これを伝えるのが<b>SESSIONS</b>ブロックです。誰がいるか、動いているかどうか、自分のメモが何件か、それぞれ最後に何をしたか。'],
    ['Bが環境の事実を知り、共有する', 'エージェントB', 'Stripeのkeyはenvファイルが指す場所にありませんでした。手間がかかり、しかも全員に必要です。だから<code>-t fact</code>だけ、フラグは要りません。共有メモがデフォルトの行き先です。'],
    ['Aの次のターン：届くのは差分だけ', 'hook', '<b>UserPromptSubmit</b> hookがNOTES.mdをAがすでに見た内容と比べ、差分を出力します。<code>+</code>が追加、<code>~</code>が書き換え、<code>-</code>が削除です。セッション自身が書いた行が、その本人に返されることはありません。'],
    ['誰が何をしているか：status', 'エージェント', 'すべて状態ファイルからで、transcriptは読みません。名前、動いているかどうか、自分のメモ、呼び出し回数、compaction回数、失敗回数、最後の回答。'],
    ['予算は動かせない：addは拒否し、pruneが整理する', 'エージェント', '共有メモは5000バイト、自分のメモは3000バイト。一杯のファイルが古い行を黙って追い出すことはありません。<code>add</code>は拒否し、削っても影響の小さいエントリを挙げます。習慣は、終わったものは<code>rm</code>、2行目を足す代わりに<code>replace</code>、ダイジェストにPRUNE NEEDEDと出たら<code>prune</code>です。'],
    ['事実でなくなった：黙って消すのではなくstale', 'エージェントB', 'この行は他人のもので、本人に黙って消すのは筋が違います。<code>stale</code>は印を付けます。エントリは理由つきで表示され続け、次の片付けは印のついたものから先に取ります。<code>mute</code>は別のもので、<b>自分の</b>ダイジェストからその行を外すだけです。ほかの誰にとっても何も変わりません。'],
  ]);
  steps(C.s3, [
    ['AがBへ仕事を渡す：宛先は止まっている', 'エージェントA', '宛先の呼び方は人間に見えているとおり、サイドバーのタイトル、レジストリ上の名前、あるいはidの先頭です。Bはいま動いていないので、本文はプロジェクトの<b>受信箱</b>にファイルとして置かれます。'],
    ['Bが目を覚ます：メッセージがターンとして届く', 'hook', 'Bの最初のhook（ターン、ツール呼び出し、開始のいずれか）が受信箱からファイルを取り、コンテキストへ出力します。モデルにとってこれは人間からではなく他のセッションからの依頼で、ツールの権限はB自身の設定のままです。'],
    ['Bがいま動いている場合：socket', 'CLI', '動いているセッションはunix socketを待ち受けています。本文はそこへ送られ、ツール呼び出しの合間にユーザーのターンとしてBに現れます。受信箱は通りません。<code>--resume</code>は<code>claude -p --resume</code>で止まったセッションを起こします。'],
    ['イベントを待つ：ポーリングではなくwatch', 'エージェントA', '「2時間後に見て」「PRがマージされたら」。sleepループも、人間へのリマインドも要りません。登録されるのは決定論的なチェックです。<code>add</code>はその場で1度試します。すでに成立していれば何も登録せず、その場で行動します。'],
    ['タイマーが5分ごとに確認、モデルなし', 'タイマー', '1回のティックはtokenを使いません。条件が成立しなければ記録を更新して終わりです。ノートPCがスリープしていても、起きたときに追いつきます。ハードエラーが3回続くか期限を過ぎると、"broken"か"expired"のメッセージが1通来ます。'],
    ['条件が成立：宛先へメッセージ', 'タイマー', 'ティックは<code>--then</code>の文面を<code>send</code>と同じ経路で送ります。動いているセッションのsocketか、受信箱かです。セッションは"From longrun watch w1"を読み、そのとおりに動きます。その文面を書いたのは自分自身で、しかもcompactionより前かもしれません。'],
  ]);
  steps(C.s4, [
    ['Aがオーケストレーターの役を引き受ける', 'エージェントA、人間の指示で', 'プロジェクトごとに1つのセッションがボードを持ち、人間を呼びます。これは目標へ向かって自律的に走ることではありません。1つのセッションを、確かめられる1つの条件へ向けて動かすのは組み込みの<code>/goal</code>で、あちらには評価役がいます。こちらは別のもので、複数のウィンドウと、その間に置かれたボードと、人間への連絡線です。この役は<b>何もポーリングしません</b>。起こすのはイベントです。2つ目のセッションが引き受けようとすると、いま誰が持っているかを添えて断られます。'],
    ['ボード：タスクと割り当て', 'オーケストレーター', 'タスクT<n>の状態はtodo / doing / blocked / done / dropped。<code>assign</code>はタスクを動いているセッションのsocketへ、止まっているセッションなら受信箱へ入れます。'],
    ['Bがタスクをターンとして受け取る', 'hook', '作業役のセッションに必要なコマンドは3つだけ、<code>take</code>、<code>done</code>、<code>block</code>です。ほかに覚えることはありません。'],
    ['Bが作業してタスクを閉じる。外から来た事実', 'エージェントB', '<code>done</code>と<code>block</code>はオーケストレーターを起こします。レビュアーがフィールド名の変更を求めました。これが<b>外から来た事実</b>です。決まりは、まず記録し、判断はその後です。事実はタスクと同じボードに載る項目なので、<code>board add --fact</code>を使います。この事実はオーケストレーターにも届きます。'],
    ['オーケストレーターが目を覚まし、さばく', 'オーケストレーター', '読むのはボードと事実で、transcriptではありません。自分のコンテキストは小さく保つ必要があります。事実は1件ずつ明示的に片付けます。伝える、計画を立て直す、ユーザーに尋ねる、のいずれかです。'],
    ['tokenを使わないテレメトリ：SESSIONSのフラグ', 'hookと監視役', 'PreToolUse、PostToolUse、Stop、PermissionRequest、Notificationのhookが、ツールがいつ始まりいつ終わったか、セッションが権限を待っているかをmeta.jsonへ書きます。監視役（タイマー）が5分ごとに見るしきい値は2つで、まだ動き続けているツールと、答えのない権限の確認です。そして1つの事象につき1度だけオーケストレーターへ報告します。ほかのフラグ（長いターン、FAILの連続、ウィンドウに迫ったコンテキスト）は表示するだけです。それは普通の作業であって、不具合ではありません。'],
    ['全停止：halt', 'オーケストレーター、人間の指示で', '本当に作業を止められる手段はこれだけで、使うのは人間がそう言ったときだけです。halt.jsonファイルはグローバルです。どのセッションでも<b>PreToolUse</b> hookが理由つきの拒否を返し、モデルはそれを見て、何をしようとしていたかを人間に伝えます。解除できるのは人間だけで、会話の中で言葉にして行います。<code>longrun resume</code>です。'],
    ['全ウィンドウの手前で人間に質問する', 'エージェントB', '待てないことだけに使います。確認、権限、人間にしかできない操作です。ダイアログはosascriptが別プロセスで表示します。全ウィンドウの手前に、音つきで、権限は要りません。90秒以内の回答はその場で返ります。'],
    ['人間が席にいない：回答は後からターンとして届く', '待機', '90秒でコマンドはPENDINGを返し、セッションは先へ進みます。ダイアログは開いたまま（デフォルトで6時間）で、クリックの結果はセッションのsocketか受信箱へ入ります。Cancel、Esc、期限切れならCANCELLED / EXPIRED。質問は繰り返さず、ボードに載せます。'],
  ]);
  /* Russian comment lines inside terminal panels */
  const TERM = {
    '# SessionStart (source=startup) -> в контекст модели:': '# SessionStart (source=startup) -> モデルのコンテキストへ：',
    '# PreCompact (trigger=auto), PostCompact -> файлы, вывода в контекст нет': '# PreCompact (trigger=auto), PostCompact -> ファイルへ書くだけ、コンテキストへの出力はなし',
    '# SessionStart (source=compact) -> в контекст модели:': '# SessionStart (source=compact) -> モデルのコンテキストへ：',
    '# SessionStart в сессии B:': '# セッションBでのSessionStart：',
    '# UserPromptSubmit в сессии A -> в контекст:': '# セッションAでのUserPromptSubmit -> コンテキストへ：',
    '# UserPromptSubmit в сессии B -> в контекст:': '# セッションBでのUserPromptSubmit -> コンテキストへ：',
    '# у адресата это выглядит так:': '# 宛先にはこう見えます：',
    '# другие проверки: pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'': '# 他のチェック：pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'',
    '# 13:05, в контексте сессии A:': '# 13:05、セッションAのコンテキストで：',
    '# UserPromptSubmit в B:': '# BでのUserPromptSubmit：',
    '# строки SESSIONS в дайджесте оркестратора (пример):': '# オーケストレーターのダイジェストのSESSIONS行（例）：',
    '# в дайджесте любой сессии эта строка теперь выглядит так:': '# どのセッションのダイジェストでも、この行はいまこう見えます：',
    '# отчет смотрителя оркестратору, один раз на эпизод:': '# 監視役からオーケストレーターへの報告、1つの事象につき1度：',
    '# ничего не убивается: остановить окно может только человек': '# 何も殺されません。そのウィンドウを止められるのは人間だけです',
    '# PreToolUse в сессии B (Bash "pytest") -> Claude Code:': '# セッションBでのPreToolUse (Bash "pytest") -> Claude Code:',
    '# ... на экране диалог с кнопками Да / Нет, человек нажимает Да': '# ... 画面にはYes / Noのボタンがあるダイアログ、人間がYesを押します',
    '# то же самое из MCP: тул mcp__longrun__ask (сервер `longrun`, регистрирует install.sh)': '# MCPからでも同じ：mcp__longrun__askツール（サーバー`longrun`、install.shが登録）',
    '# ... позже, в контексте B:': '# ... 後ほど、Bのコンテキストで：',
  };
  [C.s1, C.s2, C.s3, C.s4].forEach(sc => sc.steps.forEach(s => (s.term || []).forEach(t => { if (t.dim && TERM[t.dim]) t.dim = TERM[t.dim]; })));
  /* the ask dialog buttons in scenario 4 */
  C.s4.steps.forEach(s => (s.term || []).forEach(t => ['cmd', 'dim', 'out'].forEach(f => {
    if (typeof t[f] === 'string') t[f] = t[f].replace(/Да,Нет/g, 'Yes,No').replace(/Да \/ Нет/g, 'Yes / No').replace(/Да/g, 'Yes').replace(/Нет/g, 'No');
  })));
})(window.COURSE);
