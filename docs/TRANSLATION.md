# Translating longrun

English is the source. Every other language is a translation of it, and may lag behind
a release. This file is the canon for how those translations are made and reviewed, so
that a page translated a year from now reads like the one translated today.

If you are sending a translation PR: read [What never gets translated](#what-never-gets-translated),
the [Glossary](#glossary) and the section for your language. Those three are where
almost every correction comes from.

## 1. Scope

| Surface | Languages |
| --- | --- |
| `README.md` | en, ru, zh-CN, ja, ko |
| `course/` | en, ru, zh-CN, ja |
| `docs/REFERENCE.md`, `docs/ORCHESTRATOR.md` | en, ru only |
| `skill/` (SKILL.md, CLI strings, hook output) | en only |

The reference docs stay at two languages on purpose: they are long, they change with
every release, and they are read by people who have already installed the skill. The
README and the course are the shop window - that is where a translation pays off.

The skill itself is never translated. It talks to a model, not to a person, and the
commands, note types and hook output must match the docs one to one.

### File layout

```
README.md              README.ru.md   README.zh-CN.md   README.ja.md   README.ko.md
course/index.html      course/ru/     course/zh-CN/     course/ja/
course/en.js           (ru is the base)  course/zh-CN.js   course/ja.js
```

Locale codes follow the README suffixes: `ru`, `zh-CN`, `ja`, `ko`. Not `zh_CN`, not `jp`.

### Header on every translated page

First line of a translated README, before anything else - the language bar, with the
current language in plain text and the others as links, English first. The course puts
the same bar in `nav.side .lang`.

Each translation also carries one line near the top:

> English is the source and may be ahead of this page. Corrections welcome - see
> [docs/TRANSLATION.md](docs/TRANSLATION.md).

## 2. What never gets translated

Keep verbatim, in Latin script, spelled exactly as the CLI spells it:

- `Claude Code`, `Claude`, `Anthropic`, `longrun`
- `hook`, `skill`, `compaction`, `prompt`, `token`
- `worktree`, `socket`, `transcript` - the reader meets them in `git`, in the CLI and in
  Claude Code's own output, and every local rendering of them is also an ordinary word
- every command and subcommand: `longrun add`, `longrun status`, `longrun watch add --then`
- every note type: `dead`, `decision`, `fact`, `ctx`, `todo`, `pin`
- every config key: `notify_turn_end`, `compact_hint_max_bytes`, `watch_timer`
- every hook name: `SessionStart`, `UserPromptSubmit`, `PreCompact`, `Stop`
- every path and filename: `.longrun/`, `~/.claude/longrun/sessions/`, `meta.json`
- platform names: `launchd`, `systemd`, `cron`, `osascript`, `zenity`, `notify-send`
- anything inside a code block, a `<code>` span, or terminal output

**Do not transliterate these into the local script either.** `hook` stays `hook`, not
`フック`, not `훅`, not `钩子`. The reader has to be able to match a word in the prose to
what they see in their terminal, and the katakana or hangul form is also an ordinary
word in that language - the reader then cannot tell when we mean Claude Code's feature
and when we mean a hook in general.

The exception is the first occurrence in a page, which may carry a short gloss in
parentheses, in the local language:

- ja: `compaction（会話履歴が自動で要約されること）`
- ko: `compaction(대화 기록이 자동으로 요약되는 동작)`
- zh-CN: `compaction（对话历史被自动摘要）`

One gloss per page, at the first occurrence only. Latin everywhere after.

## 3. Glossary

These are translated, and translated the same way every time.

| English | ru | ja | ko | zh-CN |
| --- | --- | --- | --- | --- |
| session | сессия | セッション | 세션 | 会话 |
| project | проект | プロジェクト | 프로젝트 | 项目 |
| note, notes | заметка, заметки | メモ | 메모 | 笔记 |
| shared notes | общие заметки | 共有メモ | 공유 메모 | 共享笔记 |
| own notes | свои заметки | 自分のメモ | 자체 메모 | 自有笔记 |
| digest | дайджест | ダイジェスト | 다이제스트 | 摘要 |
| ledger | `ledger` (kept Latin) | 台帳 | 원장 | 台账 |
| inbox | `inbox` (kept Latin) | 受信箱 | 수신함 | 收件箱 |
| archive | архив | アーカイブ | 아카이브 | 归档 |
| journal | журнал | ジャーナル | 저널 | 작업 일지 / 日志 |
| watch (event watch) | `watch` (kept Latin) | ウォッチ | 워치 | 事件监听 |
| message | сообщение | メッセージ | 메시지 | 消息 |
| task | задача | タスク | 작업 | 任务 |
| board | борд | ボード | 보드 | 任务板 |
| orchestrator | оркестратор | オーケストレーター | 오케스트레이터 | 编排器 |
| fact | факт | 事実 | 사실 | 事实 |
| halt (stop everything) | остановка всех сессий (`halt`) | 全停止 | 전체 중단 | 全部停止 |
| interrupt | прервать (`interrupt`) | 割り込み | 끼어들기 | 打断 |
| budget (5h usage) | бюджет | 予算 | 예산 | 预算 |
| context window | окно контекста | コンテキストウィンドウ | 컨텍스트 윈도 | 上下文窗口 |
| turn | ход | ターン | 턴 | 轮次 |
| timer | таймер | タイマー | 타이머 | 定时器 |
| milestone | веха | マイルストーン | 마일스톤 | 里程碑 |
| notification | уведомление | 通知 | 알림 | 通知 |
| important session | важная сессия | 重要セッション | 중요 세션 | 重要会话 |
| dialog (the ask popup) | диалог | ダイアログ | 대화 상자 | 对话框 |
| prune | `prune` (kept Latin) | 整理 | 정리 | 清理 |
| stuck (session) | застрявшая | 停滞 | 정체 | 卡住 |
| summary (what compaction leaves) | резюме | 要約 | 요약 | 总结 |
| digest vs summary | дайджест vs резюме - never both резюме | ダイジェスト vs 要約 - never both 要約 | 다이제스트 vs 요약 - never both 요약 | 摘要 vs 总结 - never both 摘要 |
| dead end | тупик | 行き止まり | 막다른 길 | 死胡同 |
| watcher (the one watching sessions) | наблюдатель | 監視役 | 감시자 | 监视器 |
| delta (of the shared notes) | дельта | 差分 | 변경분 | 差异 |
| polling | опрос | ポーリング | 폴링 | 轮询 |
| cheat sheet | шпаргалка | チートシート | - | 速查表 |
| agent | агент | エージェント | 에이전트 | agent (kept Latin) |
| worker (the session taking tasks) | рабочая сессия | 作業役 | 작업 세션 | 干活的会话 |
| summariser (the model compaction uses) | суммаризатор | 要約するモデル | 요약하는 모델 | 做总结的模型 |

A `-` means no translator has needed that term in that language yet. Fill the cell in when
you do, in the PR that needs it - do not leave the row out because one column is empty.

**Concept versus command.** `watch`, `board`, `fact` and `orchestrate` are both ideas
and subcommands. In prose, use the glossary word; when naming the command, Latin and
monospace. First occurrence may pair them: ウォッチ（`longrun watch`）.

Terms not in this table: pick the word an ordinary developer in that language would
use, and add a row here in the same PR. The table is meant to grow.

## 4. Russian (ru)

Russian is the project's second language and the base of the course data, so it is also
where the most native readers will notice a sentence that was born in English. The rules
below came out of a line-by-line review of `README.ru.md`; the tells in section 10 are
the same list seen from the other side.

**Register.** Neutral written Russian; the reader is "вы" (lower case). Developer docs,
not a chat message.

**Verbs are the first tell.** The English README is deliberately casual; the same
casualness in Russian reads as careless. Use the neutral verb: вызывать not звать,
запускать not гонять, тратить not жечь, удалять not снести, приходить or предоставлять
not приезжать, опрашивать not поллить, инструмент not тул.

**Every sentence keeps its subject.** English drops nouns and stays readable; Russian
does not. "Остановленная - из inbox проекта на следующем ходу" has to become
"Остановленная сессия заберет его из inbox проекта на следующем ходу". No dash asides in
the middle of a sentence ("- уже открытый тоже подходит -"): parentheses or a second
sentence. No question-and-answer rhythm ("Ответили нет при установке? Потом - ..."): one
conditional sentence.

**An English image is spelled out, not carried over.** "The reasons go first" is not
"первыми пропадают причины" - the reader asks "причины чего?"; write "первыми пропадают
причины решений: почему подход отбросили, почему выбрали этот путь". "A sleep that
oversleeps" is "пауза на заданное время, после которой событие уже давно произошло или
еще не наступило". If a phrase would make a reader stop and ask what it means, rewrite
it rather than translate it.

**Set phrases the review settled**, beyond the single words in the glossary: "ведет
остальные к заданной цели" for driving the others to a goal; "закончила ход" and "на
каждом ходу" for turns; "фоновый таймер" where the English says `launchd` but means the
timer on any OS - the three platform names are listed once, where the installer is
described.

**Cyrillic forms of the section 2 words.** The Russian pages predate section 2 and use
the established Russian developer words: хук, скилл, компакция, токен, промпт, сокет.
Keep them, consistently, and do not "fix" them back to Latin in a sync. Everything else
in section 2 stays Latin as written there: commands, note types, config keys, hook
names, paths, `worktree`, `inbox`, `watch`, `resume`, platform names. The rule against
transliteration was written for scripts where the katakana or hangul form is also an
ordinary word; хук and скилл have no such collision.

**Typography** matches the rest of the repo's Russian text: no "ё" (все, ведет, еще),
straight quotes "..." only, no dash of any length - a plain minus with spaces is the
only dash - and arrows written as `->`.

**Avoid:**
- звать, гонять, жечь, снести, приезжать, поллить, тул
- a clause with no subject: "Работающая получает его сразу" -> "Работающая сессия получает его сразу"
- a dash aside inside a sentence
- a metaphor carried over whole: "сон, который проспит"
- `launchd` as the timer's name in a sentence that also covers Linux
- «ёлочки», ё, an em dash or an en dash

## 5. Japanese (ja)

**Politeness.** です・ます throughout the body, one register, no drift into だ・である.
Headings, table cells and list labels end in a noun (体言止め) with no です. Instructions
are 〜します / 〜できます; 〜してください only where the reader really must act.

**Script.** Anything in section 2 stays Latin. Everything else that is an ordinary
computing concept takes its established katakana form (セッション, プロジェクト,
コンテキスト). Keep the long-vowel mark in the modern spelling: ユーザー, サーバー,
オーケストレーター - not ユーザ, サーバ.

**Spacing.** No space between Japanese and Latin or digits. Numbers and Latin are
half-width. Punctuation is full-width 、and 。- never ，．

**Parentheses.** Half-width `( )` when the content is Latin only, full-width （） when
it contains Japanese.

**Avoid:**
- 〜することができます -> 〜できます
- long の chains: セッションのメモの一覧の表示 -> セッションのメモを一覧表示
- あなた / 私たち - Japanese drops the subject; so do we
- ！ and ～ as tone markers
- word-for-word English clause order; split a long English sentence into two Japanese ones

## 6. Korean (ko)

**Register.** 합니다체 (하십시오체) throughout. No 해요체, no 반말, no mixing.

**띄어쓰기 - this is where machine translation gives itself away.**
- 조사 attach with no space: 세션이, 프로젝트를, 메모에서
- 의존명사 take a space: 할 수 있습니다, 한 번, 하는 것입니다
- 보조용언 spaced: 저장해 둡니다, 열어 봅니다

**Latin runs** take a space on both sides: `longrun status` 를 실행합니다 -> write it as
`longrun status`를 실행합니다 (the particle attaches, the space goes before the code span).
Choose the particle by how the Latin word is read in Korean: `hook`은 (훅), `skill`을
(스킬), `longrun`은 (롱런). Never write the 은(는) / 을(를) both-options form.

**Loanword spelling** per 외래어 표기법: 세션, 프로젝트, 컨텍스트, 메모, 타이머, 에이전트,
오케스트레이터, 보드.

**Punctuation** is half-width `.` and `,` with a following space, straight quotes.

**Avoid:**
- double passive: 저장되어집니다 -> 저장됩니다
- 가지다 as a calque of "have": 세션은 메모를 가집니다 -> 세션에는 메모가 있습니다
- 들 on every plural - Korean does not need it
- stacked ~에 대한 / ~에 있어서
- 시키다 where 하다 is meant: 실행시킵니다 -> 실행합니다

## 7. Simplified Chinese (zh-CN)

**Characters and vocabulary are mainland only.** 软件 not 軟體, 内存 not 記憶體, 默认 not
預設, 网络 not 網路, 缓存, 提交, 分支, 仓库, 上下文, 令牌, 进程, 终端.

**Punctuation is full-width:** ，。、；：？！ “ ” ‘ ’ （） —— ……
Never a half-width `,` or `.` inside a Chinese sentence. The enumeration comma 、separates
list items, ，separates clauses.

**Spacing.** A space between Chinese and Latin or digits: 每 5 分钟检查一次，运行
`longrun status`。No space between Chinese and full-width punctuation.

**Parentheses:** full-width （） around Chinese content, half-width `( )` around Latin-only
content.

**Second person is 你**, not 您. These are developer docs, not a sales page. Better still,
drop the pronoun where Chinese allows it.

**Avoid:**
- 的 stacked in one clause: 会话的共享的笔记的列表 -> 会话的共享笔记列表
- 被 where Chinese prefers an active verb
- 进行 / 对……进行 padding: 对笔记进行保存 -> 保存笔记
- 一个 as a literal "a"
- English clause order carried over whole - recast long sentences

## 8. The course site

The course is data-driven and Russian is the base: `data.js`, `data2.js`, `data3.js`
hold the scenarios with Russian strings, and `en.js` overrides titles, captions, node
labels and file descriptions with English ones. A new locale is:

1. `course/<locale>/index.html` - a copy of `course/index.html` with the prose translated,
   `<html lang="...">` and `<title>` set, `../style.css` and `../` paths like `course/ru/`.
   The inline `window.LR_I18N` block above the scripts carries the player's own chrome
   (`step`, `of`, `prev`, `next`, `quiz`, `loop`, ...) - same keys as English, translated
   values. Russian is the only locale without it: those are app.js's built-in defaults.
2. `course/<locale>.js` - an override file built exactly like `en.js`, same keys, loaded
   after the data files.
3. One line in the `LOCALES` list at the top of `course/app.js`.

The language bar is rendered from that `LOCALES` list at load time and must not be edited
by hand in the HTML. The static `<a>` sitting in `nav.side .lang` is only the no-JS
fallback. A locale goes into `LOCALES` when its page is published, not before - the bar
would link to a 404.

**Why the override file matters more than it looks.** `data*.js` is Russian. A key your
override forgets does not fall back to English - it falls back to *Russian*, and a
Japanese page quietly grows a Russian sentence. `tests/course.sh` guards exactly this:
it loads the data with your override applied and fails if a single Cyrillic character
survives. Run it before opening the PR:

```bash
bash tests/course.sh
```

**Terminal output inside the scenarios is not translated.** It is real CLI output, and
the CLI is English. Only the titles, captions, `who` lines and node labels around it are.

**Fonts.** `--sans` is Geist, which carries no kana and no Han glyphs. `style.css` already
scopes a system font stack for `ja` and `zh-CN` by `html[lang=...]`, together with the
leading and the letter-spacing, which are set for Geist's Latin and are wrong for CJK. A
new CJK locale needs its own line there; `tests/course.sh` fails if it is missing.

There is no CJK webfont on purpose: a full one runs into megabytes, and every desktop
ships a good one. `--mono` stays as it is - everything in monospace is ASCII.

**Line breaks.** The hero paragraph and card headings use manual `<br>`. CJK has no
spaces between words and breaks anywhere, so a break placed for English lands wrong -
re-place them per language or drop them.

## 9. How a translation is made

One file at a time, whole file in one pass - not chunk by chunk. Terminology and
register drift between chunks, and that drift is the hardest thing to fix afterwards.

1. **Translate.** Glossary and the language section in context. Code blocks, commands,
   links, anchors and badge URLs are copied byte for byte, never retyped.
2. **Review pass A - native reader.** A fresh agent reads only the translation, without
   the English, as a developer who speaks that language. It flags anything that reads
   like a translation: register drift, spacing and punctuation, unnatural phrasing,
   glossary terms used two different ways.
3. **Review pass B - against the source.** A fresh agent diffs translation against
   English: missing or added sections, changed commands or flags, broken anchors,
   altered numbers.
4. **Mechanical check.** `bash tests/course.sh` for a course locale. By hand for a README:
   anchors resolve, relative links resolve from the file's own directory, code blocks are
   identical to the English ones, the language bar lists every locale.

Passes A and B are separate agents on purpose. An agent that has just read the English
will read the translation through it and stop noticing that it sounds like English.

### Bold and italic break in a script that does not use spaces

This one hit zh-CN and ja independently, both times only after the page was live.
CommonMark refuses to close an emphasis run when the closing `**` or `*` is preceded by
punctuation and followed by something that is neither whitespace nor punctuation. The
English pages are safe because a space follows every bold label. A page written in Han or
kana is not: `**笔记在磁盘上。**每条死胡同` never closes, and the reader sees the asterisks
as literal text.

Keep the trailing punctuation outside the emphasis - the rendered line looks the same:

```
**笔记在磁盘上。**每条…     ->  **笔记在磁盘上**。每条…
*"记一下"*或者*"PR 合了"*   ->  two separate spans, or 或者 gets italicised with them
```

Do not eyeball this. Render both the English and the translated file through GitHub's own
renderer and diff the text output - every difference should be an asterisk disappearing:

```bash
gh api -X POST /markdown -f mode=gfm -f text="$(cat README.ja.md)" > /tmp/out.html
```

Korean puts a space after its sentence punctuation, so it is mostly safe - but it is
cheaper to run the check than to assume.

## 10. Review checklist

The tells, per language. If a PR has none of these, it is probably fine.

**Russian** - звать / гонять / жечь / снести / приезжать - a clause without its subject
("Остановленная - из inbox") - a dash aside mid-sentence - ё, «ёлочки» or an em dash -
`launchd` where the sentence also covers Linux - `hook` or `skill` in Latin inside prose
(the Russian pages use хук and скилл).

**Japanese** - です/ます mixed with だ/である - `hook` or `skill` written in katakana -
spaces inserted around Latin words - ユーザ / サーバ without the long-vowel mark -
〜することができます - あなた as the subject.

**Korean** - 띄어쓰기: 할수 있습니다, 하는것 - 저장되어집니다 - 은(는) both-options form -
해요체 mixed into 합니다체 - 들 on every noun - 실행시킵니다.

**Chinese** - half-width `,` or `.` in a Chinese sentence - no space between Chinese and
Latin - 的 three times in one clause - 您 - any Traditional character or Taiwanese term.

**All languages** - a command or flag that differs from the English page - a number that
differs (test counts, sizes, minutes) - a heading anchor that no longer matches a link -
terminal output translated - a visible `**` or `*` on the rendered page (see section 9).
