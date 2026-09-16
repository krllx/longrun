[English](README.md) | [Русский](README.ru.md) | [简体中文](README.zh-CN.md) | 日本語 | [한국어](README.ko.md)

<p align="center">
  <img src="assets/hero.jpg" alt="longrun：compactionを生き延びる記憶" width="820">
</p>

<h1 align="center">longrun</h1>

<p align="center">
  Claude Codeセッションのための記憶と協調。<br>
  compaction（会話履歴が自動で要約されること）を生き延びるメモ。メッセージを送り合い、タスクを渡し合うセッション。<br>
  取りこぼしのない待機：ポーリングループはなく、イベントの発火でセッションが目を覚ます。<br>
  決めた目標までほかのセッションを導く1つのセッション。
</p>

<p align="center">
  <a href="#クイックスタート">クイックスタート</a> ·
  <a href="#セッションが協調する4つの方法">4つの協調方法</a> ·
  <a href="#仕組み">仕組み</a> ·
  <a href="#コマンド">コマンド</a> ·
  <a href="docs/REFERENCE.md">リファレンス</a> ·
  <a href="https://krllx.github.io/longrun/course/ja/">コース</a>
</p>

<p align="center">
  <img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-skill-d97757">
  <img alt="Python" src="https://img.shields.io/badge/python-3.9%2B%2C_no_deps-3776ab">
  <img alt="macOS and Linux" src="https://img.shields.io/badge/macOS-launchd-000000">
  <img alt="Linux" src="https://img.shields.io/badge/Linux-systemd_%2F_cron-e95420">
  <img alt="Tests" src="https://img.shields.io/badge/tests-329_checks%2C_no_API_calls-2ea44f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p align="center">
  <a href="https://krllx.github.io/longrun/course/ja/"><img src="assets/course-banner.ja.svg" alt="コース：longrunの中身はどう動いているのか。11の短い章、約15分" width="820"></a>
</p>

---

> 英語版がソースであり、このページより新しい場合があります。修正の指摘は歓迎です。[docs/TRANSLATION.md](docs/TRANSLATION.md)をご覧ください。

## クイックスタート

```bash
curl -fsSL https://krllx.github.io/longrun/install.sh | bash
```

> [!NOTE]
> インストーラーが入れるのは、ターミナル用の`longrun`コマンド付きのskill、`~/.claude/settings.json`のhook、そしてバックグラウンドで5分ごとに動くタイマーです。デスクトップ通知を設定するかどうかを尋ねます。`install.sh --uninstall`ですべて元に戻せます。

<details>
<summary>このマシンで実際に何が変わるか</summary>

- `~/.claude/settings.json`：11個のhookエントリと、エージェントが`longrun`を呼べるようにする2つの権限ルール。インストーラーは先にこのファイルを`~/.claude/backups/`へコピーし、longrun以外のhookには手を触れません。
- `~/.claude/skills/longrun/`と、シンボリックリンク`~/.local/bin/longrun`。
- ユーザースコープのMCPサーバー`longrun`(`claude mcp add`)。`ask`と`notify`のツールはこのサーバーが提供します。
- **バックグラウンドのタイマー**、5分ごと：macOSではlaunchd agent、Linuxではsystemd user timerかcrontabの1行。登録したウォッチを確認し、セッションの様子を見ます。数回のシェルチェックだけで、モデルもtokenも使わず、登録した条件のどれかが成立したときだけセッションを起こします。`--no-timer`で外せます。
- **デスクトップ通知**、インストーラーの質問に「はい」と答えた場合：macOSでは`terminal-notifier`がなければ`brew install terminal-notifier`、`~/.claude/longrun/notifier/`以下に通知を送るためのバンドル、そしてmacOSの権限ダイアログを出すためのテスト通知が1つ。Linuxでは`notify-send`があるかを確認するだけです。`--notify`と`--no-notify`は、この質問にあらかじめ答えておくためのものです。

macOSまたはLinux、Claude Code、python3 3.9以上が必要です。cloneからインストールする場合も同じ[`install.sh`](install.sh)です。

</details>

あとはClaude Codeでプロジェクトを開き（すでに開いているものでかまいません）、「**set up longrun**」と言うだけです。ターミナルからなら：

```bash
cd ~/my-project && longrun init && claude "set up longrun"
```

ここから先は、コマンドを打つ必要はありません。「*記録しておいて*」、「*これまで何を試したか*」、「*PRがマージされたら教えて*」と言うだけです。

> **中身の仕組みを例つきで**：[コース](https://krllx.github.io/longrun/course/ja/)、11の短い章、約15分。

<details>
<summary><b>デスクトップ通知</b>：何のためにあり、インストーラーは何を尋ねるのか</summary>

- **なぜ**：全停止、発火したウォッチ、ターンの終了は、通知がなくてもセッションに届きます。バナーは、別のウィンドウを見ている*人間*が気づくための手段です。longrunが通知に依存することはありません。
- **macOS**：Homebrew経由の`terminal-notifier`（OS標準の手段ではバナーが表示されません）と、権限の確認が1回。インストール時に断った場合は、あとから`longrun notify setup`で設定できます。
- **Linux**：`notify-send`(`libnotify`)。たいていのデスクトップ環境にはすでに入っています。

`longrun notify --test`は、通知が実際に画面へ届くかを確かめます。見ておく価値のある設定が2つあります。`notify_turn_end unfocused`（Claudeのウィンドウが前面にないときにセッションがターンを終えるとバナーを出す）と、絶対に見逃したくない1つのセッションのための`longrun important on|next`です。エージェントが呼ぶ`notify`ツールは、インストーラーが登録する`longrun` MCPサーバーが提供します。macOS特有の癖も含めた全体像は[docs/REFERENCE.md](docs/REFERENCE.md)にあります。

</details>

## ひとことで

**何も言わなくても、最初のセッションから**：エージェントは行き止まり・決定・事実をメモとしてディスクに書き、hookがそれをcompaction、`/clear`、resumeのたびにコンテキストへ戻します。hookは要約するモデルにも何を残すかを伝えます。毎ターン、プロジェクトの他のセッションが何を変えたかが表示されます。

**頼んだとき、またはエージェントが必要だと判断したとき**：「PRがマージされたら教えて」（待つ間tokenを使わないウォッチ）、セッション間のメッセージとタスク、見逃したくないセッションがターンを終えたときの通知、1つのセッションが他のセッションを、決めた目標へ導く動き。

## なぜ

| longrunがない場合 | longrunがある場合 |
|---|---|
| compactionは履歴を要約に圧縮します。真っ先に消えるのは、どのアプローチをなぜ捨て、なぜこの道を選んだのかという決定の理由です。30分後、エージェントは自分がすでに取り消した修正をまた提案します。 | **ディスク上のメモ**。行き止まり・決定・事実を1行ずつ。共有メモは全セッションから見え、自分のメモはcompaction、`/clear`、resumeのたびに戻ってきます。 |
| 2つ目のセッションは1つ目の存在を知りません。片方がPRを作ったのに、もう片方は「PRはまだ作られていない」と言います。 | **メッセージとタスク**。セッションがメッセージを送るかタスクを渡すと、相手のセッションにはユーザーのターンとして届きます。 |
| 「PRがマージされたら教えて」は、tokenを浪費するポーリングループか、決めた時間だけ待つsleepになります。sleepが明けたころには、イベントはとうに過ぎているか、まだ来ていません。 | **ウォッチ**。バックグラウンドのタイマーが5分ごとにモデルなしで条件を確かめ、成立したらセッションを起こします。確実で、反応が速く、コストはゼロです。 |
| 1つのプロジェクトに5つのセッション。何が終わり、何が詰まり、次が何かを知っているのは人間だけです。 | **オーケストレーター**。1つのセッションがボードを持ち、タスクを配り、停滞しているセッションを見つけ、どうしても必要なときだけダイアログで人間に尋ねます。 |

pythonファイル1つ、依存なし。

## セッションが協調する4つの方法

> [!NOTE]
> 以下のコマンドは、エージェントが自分で実行するものです。いつメモを書き、いつメッセージを送り、いつウォッチを仕掛けるかはskillが指示します。ここに覚えるべきコマンドは1つもありません。「*記録しておいて*」や「*PRがマージされたら教えて*」と言うだけ、あるいは何も言わなくてかまいません。並べてあるのは、手で実行したくなったときのためです。

### 1. ディスク上の共有ドキュメント

プロジェクトごとに1つの`.longrun/`が、全セッションから見えるメモを持ちます。各セッションはリポジトリのツリーの外に、自分のメモも持ちます。hookはcompaction、`/clear`、resumeのたびに両方を戻し、毎ターン他のセッションが何を変えたかを表示します。

```bash
longrun add --shared -t pin "PR 42 = branch feature/checkout"     # for every session
longrun add -t dead "retry on 429 does not help, limit is per org"  # for this one
longrun recall 429                                                  # search everything
```

### 2. コンテキストを持っているセッションへの委譲

他のセッションへのメッセージは、相手のセッションにはユーザーのターンとして届きます。動いているセッションはsocket経由ですぐに受け取ります。止まっているセッションは、次のターンでプロジェクトの受信箱から受け取ります。`--resume`を付けたときだけその場で起きますが、バックグラウンドで`claude -p`を実行するためtokenを使います。セッションの名前は、サイドバーに表示されているタイトルです。

```bash
longrun send "PR 43: payments" "PR 42 merged, rebase onto main"
longrun board assign T8 "PR 43: payments"      # a task instead of a message
```

### 3. イベント駆動：tokenを使わずに待つ

ウォッチとは、タイマーが5分ごとにモデルなしで実行する決定論的なチェックです（macOSではlaunchd agent、Linuxではsystemd user timerかcronジョブ）。条件が成立すると、セッションは`--then`で指定した文面をメッセージとして受け取ります。ノートPCがスリープしていても、チェックが遅れるだけです。

```bash
longrun watch add --to "PR 43: payments" --then "rebase onto main" -- pr-merged 42
longrun watch add --then "check the deploy" -- at 10:00
```

チェックの種類：`pr-merged`（`gh`経由のGitHub）、`pr-status`、`at`、`file`、`http`、`cmd`。

### 4. オンにして初めて働く自律：1つのセッションが他を導く

1つのセッションがオーケストレーターの役を引き受け、ボードを持ちます。ボードに載るのは目標、タスク、外から来た事実です。作業役のセッションはタスクを取り、終わらせ、詰まったタスクにはブロックの印を付けます。ボードが変わるたびにオーケストレーターが目を覚まし、次のタスクを配り、詰まりを解消し、あるいは全ウィンドウの手前に出るダイアログで人間に尋ねます。ポーリングはせず、セッションを自分で立ち上げることもしません。デスクトップアプリではクリックすればセッションが開くチップ（ボタン）を残し、ターミナルでは、自分で貼り付けるための最初の1行を渡します。

```bash
longrun orchestrate start --goal "ship the checkout drawer"    # in the driving session
longrun board take T7; longrun board done T7 "PR 42 merged"    # in a worker
longrun ask "Merge PR 42?" --options "Yes,No"                  # a dialog, answered inline
```

詰まったプロセスの強制終了(`longrun interrupt`)、全停止(`longrun halt`)、その解除といった主導権は、人間が握ったままです。監視役とオーケストレーターは提案するだけです。デフォルトではオフで、自分で有効にして初めて働くものもあります。5時間の使用量予算(`longrun budget on`)は、5時間枠の消費が予定より早く進んだときにすべてを止め、どうするかを尋ねます。

## 仕組み

```mermaid
sequenceDiagram
    participant S as Claude Codeセッション
    participant L as longrun (hooks)
    participant D as ディスク上のメモ
    S->>L: セッション開始
    L->>D: プロジェクトの共有メモと、このセッションの自分のメモを読む
    L-->>S: ダイジェスト：何が分かっているか、他に誰が作業中か、何が待機中か
    Note over S: エージェントが作業し、行き止まりや決定を1行ずつ書く
    S->>D: longrun add ...
    S->>L: 毎ターン
    L-->>S: 他のセッションが変えたこと、自分宛のメッセージ
    S->>L: compactionが近い
    L->>D: スナップショット。あわせて要約するモデルに何を残すかを伝える
    S->>L: セッションが再び開始（compaction、/clear、resumeの後）
    L-->>S: 同じダイジェストと、どこで中断したか
```

**開始**。hookはディレクトリからプロジェクトを見つけ、ダイジェストを出力します。中身は共有メモ、自分のメモ、他のセッション（動いているかどうか、それぞれの最後の作業）、待機中のウォッチ、未配送のメッセージです。

**作業**。エージェントは行き止まり・決定・苦労して得た事実を1行ずつ書きます。hookは編集回数を数え、失敗したコマンドを記録します。メモなしの編集が長く続くと、メモを書くよう1度だけ促します。

**毎ターン**。受信箱のメッセージが配送されます。他のセッションが共有メモに加えた変更は差分として現れます。`+`が追加、`~`が書き換え、`-`が削除です。

**compaction**。その前に、直近のリクエスト、編集したファイル、最近の失敗のスナップショットを取り、あわせて要約するモデルへの指示も渡します。行き止まりは理由ごと残す、正確な文字列は残す、ファイルを1回読めば取り戻せるものは捨てる、という指示です。Claude Codeは自動のcompactionでも`/compact <text>`と同じ要約promptを組み立てるので、longrunは同じ指示を、タイミングを見計らう手間なしに代わりに渡しているだけです。compactionの後、要約はそのままアーカイブされます。次の開始ではダイジェストに加えてHANDOFFブロックが出力され、セッションは同じ場所から続きます。resumeと`/clear`は同じメモを引き継ぎ、forkはコピーを受け取ります。

**片付け**。1時間に1度：古いエントリはアーカイブへ（`pin`は除く）、ジャーナルは切り詰め、動きのないセッションはアーカイブへ。メモの容量が上限に達したとき`add`は拒否し、何を削ればよいかを示します。黙って捨てることはありません。

## 3つの実体

| 実体 | 説明 | 何を保存するか |
|---|---|---|
| **プロジェクト** | `.longrun/`ディレクトリ1つ。プロジェクトのフォルダの中か、ツリーの外(`--external`) | 共有メモ、受信箱、ボード、アーカイブ |
| **セッション** | Claude Codeの会話1つ。アプリではサイドバーの1行。resumeでは新しいidになり、longrunが古いidと新しいidを繋ぎます | 自分のメモ、ジャーナル、カウンター、最後の状態 |
| **ディレクトリ** | セッションが始まったフォルダ。リポジトリのルート、worktree、サブディレクトリ | 何も保存しません。そのセッションがどのプロジェクトに属するかを示すだけです |

worktreeは`longrun link <project>`で紐づけます。worktree自体はメモの保存先を持ちません。

## 何を書くか

判断基準は1つ。**コマンド1回、ファイルの読み取り1回、grep1回で取り戻せるか**？取り戻せるなら書きません。

| タグ | 何を | どこへ |
|---|---|---|
| `dead` | 失敗したアプローチと、その理由 | 自分のメモ。他のセッションも同じ行き止まりに突き当たりそうなら共有 |
| `decision` | 選択と、その理由 | 他のセッションに関わるなら共有 |
| `fact` | 手間をかけて分かった環境の事実 | 共有 |
| `pin` | 有効期限のない事実。PR番号、ブランチ、ホスト | 共有 |
| `ctx` | 人間から与えられたタスクの前提 | 自分のメモ |
| `todo` | エージェントが後で済ませるべき短い作業 | 自分のメモ |

マイルストーン（push済み、PR作成、テストが緑）はジャーナルへ：`longrun log "PR opened"`。タスクより長く残るもの（ユーザーが誰か、どう仕事を進めるか）は、longrunではなくClaude Codeの自動メモリへ入れます。

## コマンド

```bash
longrun init [--external] | link <project> | where | onboard | config
longrun add [--shared] -t TAG "..." | rm | replace | notes | prune | log "..." | recall <term>
longrun status | send [--list] [--resume] WHO "..."
longrun watch add --to WHO --then "..." -- pr-merged 42 | at 10:00 | cmd '...' | file /path | http URL
longrun orchestrate start --goal "..." | board | fact | ask | halt | resume | interrupt | budget
```

全フラグ、ファイル形式、Claude Codeについて検証した事実は[docs/REFERENCE.md](docs/REFERENCE.md)。オーケストレーターの設計と残っている課題は[docs/ORCHESTRATOR.md](docs/ORCHESTRATOR.md)。

<!-- site: nuances, limits and edge cases move to the site; add the link here -->

<details>
<summary><b>よくある質問</b></summary>

**PRはあるのに、エージェントが「PRはまだ作られていない」と言う**。その事実が共有メモにありません：`longrun add --shared -t pin "PR 42 = branch feature/checkout"`。

**worktreeのセッションがプロジェクトのメモを見られない**。`longrun where`にプロジェクトが出る必要があります。"not initialised"と出たら、そのworktreeで`longrun link <project>`を実行します。

**メッセージを送ったのにセッションが黙ったまま**。`longrun send --list`で確かめます。宛先が"stopped"ならメッセージは受信箱にあり、次のターンで受け取ります。今すぐ届けたいときは`--resume`です。

**ウォッチが一向に発火しない**。`longrun watch status`、`longrun watch ls --all`、`longrun watch test -- <the same check>`で確かめます。よくある原因は、`cmd`の中の相対パスかシェルのaliasです。
</details>

## 開発

```bash
bash tests/run.sh            # 202 regression checks, no API calls
bash tests/scenarios.sh      # 30 scenarios, one per goal
bash tests/orchestrator.sh   # 67: the orchestrator layer
bash tests/ask.sh            # 30: the dialog and the MCP server
```

インストーラーはファイルを`~/.claude/skills/longrun/`にコピーします。checkoutから読み込まれるものはありません。hookはイベントごとに別プロセスなので、動いているセッションも再起動なしで更新を拾います。

## ライセンス

[MIT](LICENSE)
