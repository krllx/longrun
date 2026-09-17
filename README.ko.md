[English](README.md) | [Русский](README.ru.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | 한국어

<p align="center">
  <img src="assets/hero.jpg" alt="longrun: Claude Code 세션을 위한 기억과 협력" width="820">
</p>

<h1 align="center">longrun</h1>

<p align="center">
  Claude Code 세션을 위한 기억과 협력.<br>
  프로젝트는 자기 상태를 디스크에 두고, 에이전트가 직접 그 상태를 적고 정리합니다.<br>
  모든 세션이 프로젝트에 쌓인 내용과 지금 누가 함께 일하고 있는지를 봅니다.<br>
  작업은 컨텍스트가 있는 세션으로 갑니다. 기다림은 확실하고 비용이 들지 않습니다.<br>
  한 세션이 나머지를 이끌 수 있고, 사람만 결정할 수 있는 일에서는 사람에게 연락합니다.
</p>

<p align="center">
  <a href="#빠른-시작">빠른 시작</a> ·
  <a href="#세션이-협력하는-네-가지-방법">네 가지 협력 방법</a> ·
  <a href="#동작-방식">동작 방식</a> ·
  <a href="#명령어">명령어</a> ·
  <a href="docs/REFERENCE.md">레퍼런스</a> ·
  <a href="https://krllx.github.io/longrun/course/">강의</a>
</p>

<p align="center">
  <img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-skill-d97757">
  <img alt="Python" src="https://img.shields.io/badge/python-3.9%2B%2C_no_deps-3776ab">
  <img alt="macOS and Linux" src="https://img.shields.io/badge/macOS-launchd-000000">
  <img alt="Linux" src="https://img.shields.io/badge/Linux-systemd_%2F_cron-e95420">
  <img alt="Tests" src="https://img.shields.io/badge/tests-326_checks%2C_no_API_calls-2ea44f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p align="center">
  <a href="https://krllx.github.io/longrun/course/"><img src="assets/course-banner.svg" alt="The course: how longrun works inside - eleven short parts, about 15 minutes" width="820"></a>
</p>

---

> 영어판이 원본이며, 이 페이지보다 최신일 수 있습니다. 수정 제안은 언제든 환영합니다. [docs/TRANSLATION.md](docs/TRANSLATION.md)를 참고하십시오.

## 빠른 시작

```bash
curl -fsSL https://krllx.github.io/longrun/install.sh | bash
```

> [!NOTE]
> 설치 스크립트는 터미널용 `longrun` 명령이 포함된 skill, `~/.claude/settings.json`의 hook, 그리고 백그라운드에서 5분마다 실행되는 타이머를 설치합니다. 데스크톱 알림은 설정할지 먼저 묻습니다. `install.sh --uninstall`로 전부 되돌립니다.

<details>
<summary>이 컴퓨터에서 실제로 바뀌는 것</summary>

- `~/.claude/settings.json` - hook 항목 11개와, 에이전트가 `longrun`을 호출하도록 허용하는 권한 규칙 2개. 파일은 먼저 `~/.claude/backups/`로 복사하고, longrun이 아닌 다른 hook은 건드리지 않습니다.
- `~/.claude/skills/longrun/` 디렉터리와 심볼릭 링크 `~/.local/bin/longrun`.
- 사용자 스코프의 MCP 서버 `longrun`(`claude mcp add`). `ask`와 `notify` 도구가 여기에서 나옵니다.
- **백그라운드 타이머**, 5분마다: macOS에서는 launchd agent, Linux에서는 systemd user timer나 cron 한 줄. 등록해 둔 워치를 확인하고 세션 상태를 살펴봅니다. 셸 검사 몇 번이 전부이므로 모델도 token도 쓰지 않으며, 걸어 둔 조건 중 하나가 성립했을 때만 세션을 깨웁니다. `--no-timer`로 건너뜁니다.
- **데스크톱 알림**, 설치 중 질문에 예라고 답했을 때: macOS에서는 `terminal-notifier`가 없으면 `brew install terminal-notifier`, 그리고 macOS가 권한 요청 창을 띄우도록 하는 테스트 알림 하나. Linux에서는 `notify-send`가 있는지만 확인합니다. `--notify`와 `--no-notify`는 이 질문에 미리 답해 두는 옵션입니다.

macOS 또는 Linux, Claude Code, python3 3.9 이상이 필요합니다. 리포지터리를 clone해서 설치할 때도 같은 [`install.sh`](install.sh)를 씁니다.

</details>

그다음 Claude Code에서 프로젝트를 열고(이미 열려 있어도 괜찮습니다) "**set up longrun**"이라고 말하면 됩니다. 터미널에서 한다면:

```bash
cd ~/my-project && longrun init && claude "set up longrun"
```

여기서부터는 따로 실행할 명령이 없습니다. "*기록해 둬*", "*지금까지 뭘 시도했지*", "*PR 머지되면 알려줘*"라고 말하면 됩니다.

> **내부가 어떻게 돌아가는지, 예제와 함께**: [강의](https://krllx.github.io/longrun/course/) - 짧은 장 11개, 약 15분(영어).

<details>
<summary><b>데스크톱 알림</b> - 무엇에 쓰는 것이고, 설치 스크립트는 무엇을 묻는지</summary>

- **왜 필요한가**: 전체 중단, 발동한 워치, 끝난 턴은 알림이 없어도 세션에 전달됩니다. 배너는 다른 창을 보고 있을 때 그 사실을 알아차리게 해 주는 수단입니다. longrun이 알림에 의존하는 일은 없습니다.
- **macOS**: Homebrew로 설치하는 `terminal-notifier`(OS 기본 기능으로는 배너가 뜨지 않습니다)와 권한 확인 한 번. 설치할 때 아니라고 답했다면 나중에 `brew install terminal-notifier`를 실행하면 됩니다.
- **Linux**: `notify-send`(`libnotify`). 대부분의 데스크톱 환경에는 이미 들어 있습니다.

`longrun notify --test`는 알림이 실제로 화면까지 도달하는지 확인합니다. 눈여겨볼 설정이 두 가지 있습니다. `notify_turn_end unfocused`(Claude 창이 앞에 없을 때 세션이 턴을 마치면 배너를 띄웁니다)와, 절대 놓치면 안 되는 세션 하나를 지정하는 `longrun important on|next`입니다. 에이전트가 호출하는 `notify` 도구는 설치 스크립트가 등록하는 `longrun` MCP 서버에서 옵니다. macOS 특유의 까다로운 부분까지 포함한 자세한 설명은 [docs/REFERENCE.md](docs/REFERENCE.md)에 있습니다.

</details>

## 한마디로

**아무것도 하지 않아도, 첫 세션부터**: 프로젝트는 디스크에 메모를 모아 둡니다. 막다른 길, 결정, 사실을 에이전트가 직접 적고, 다시 읽고, 정리합니다. 모든 세션은 그 메모의 내용과, 지금 어떤 세션이 함께 열려 있고 각 세션이 마지막으로 무엇을 했는지를 알고 시작합니다. 매 턴에는 그 뒤로 다른 세션이 무엇을 바꿨는지 longrun이 보여 줍니다.

**요청했을 때, 또는 에이전트가 필요하다고 판단했을 때**: 작업은 이미 컨텍스트가 있는 세션에 넘어갑니다. "PR 머지되면 알려줘"는 기다리는 동안 token을 쓰지 않고 때를 놓치지도 않는 워치가 됩니다. 놓치면 안 되는 세션이 있으면 알림이 사람에게 도착합니다. 한 세션이 정해진 목표를 향해 나머지 세션을 조율하고, 사람만 풀 수 있는 일에서는 사람 앞에 대화 상자를 띄웁니다.

**그리고 그 과정에서**: 디스크 위의 메모는 시간이 지나도 내용이 깎이지 않습니다. 그래서 hook은 compaction(대화 기록이 자동으로 요약되는 동작), `/clear`, resume 뒤에 그 메모를 그대로 다시 불러옵니다. 이 부분은 예전만큼 중요하지 않습니다. 같은 hook이 요약하는 모델에게 무엇을 남길지도 알려 주기 때문에, 평범한 compaction도 예전보다 덜 잃습니다.

## 왜 필요한가

| longrun이 없을 때 | longrun이 있을 때 |
|---|---|
| 세션이 알아낸 내용은 전부 그 대화 하나 안에만 남습니다. 다음 세션은 내일 여는 세션이든 옆 창의 세션이든 아무것도 없는 상태에서 시작해, 사람에게 지금 무슨 상황이냐고 묻습니다. | **기억하는 프로젝트**. 프로젝트마다 `.longrun/` 하나. 에이전트가 직접 적고, 다시 읽고, 정리하는 메모가 거기에 들어 있습니다. 모든 세션은 그 메모와 함께, 지금 또 누가 일하고 있고 각자 마지막으로 무엇을 했는지를 알고 시작합니다. |
| 두 번째 세션은 첫 번째 세션이 있다는 것조차 모릅니다. 한쪽은 PR을 만들었는데 다른 쪽은 "PR은 아직 만들어지지 않았다"고 말합니다. | **메시지와 작업**. 작업은 이미 컨텍스트가 있는 세션으로 가고, 그 세션에는 사용자 턴으로 도착합니다. 멈춰 있는 세션에도 보낼 수 있습니다. 메시지는 프로젝트 수신함에서 기다립니다. |
| "PR 머지되면 알려줘"는 token을 소모하는 폴링 루프가 되거나, 정해진 시간만 기다리는 sleep이 됩니다. sleep이 끝났을 때는 이벤트가 이미 한참 지났거나, 아직 오지 않았습니다. | **워치**. 백그라운드 타이머가 5분마다 모델 없이 조건을 확인하고, 성립하면 세션을 깨웁니다. 확실하고, 반응이 빠르고, 비용이 들지 않습니다. |
| 프로젝트 하나에 세션이 다섯 개. 무엇이 끝났고 무엇이 막혔고 다음이 무엇인지는 사람만 알고, 그중 한 세션이 사람의 대답을 기다리고 있다는 사실도 사람만 알아챕니다. | **오케스트레이터**. 한 세션이 나머지 세션을 위해 보드를 맡고, 정체된 세션을 알아채고, 사람만 결정할 수 있는 일에서는 모든 창 앞에 대화 상자를 띄웁니다. |
| compaction은 대화 기록을 요약으로 압축하는데, 결정의 이유가 가장 먼저 사라집니다. 왜 그 방법을 버렸는지, 왜 이 길을 택했는지가 남지 않습니다. | **디스크 위의 메모는 깎이지 않고**, hook이 compaction 뒤에 그 메모를 다시 넣어 줍니다. 같은 hook이 요약하는 모델에게 무엇을 남길지도 알려 주므로, compaction 자체도 덜 잃습니다. |

python 파일 하나, 의존성 없음.

## 이 중 일부는 Claude Code가 이미 합니다

longrun은 한 턴과 한 세션보다 오래 남는 것을 다룹니다. 기본으로 들어 있는 기능을 먼저 쓰십시오.

- **한 세션이 확인 가능한 조건 하나를 향해 일할 때** -> `/goal`. 별도의 평가자가 그 조건이 성립했다고 확인할 때까지 그 세션을 계속 돌립니다. longrun에는 보드와 설득이 있을 뿐 평가자는 없습니다.
- **한 턴 안에서 일을 쪼갤 때** -> 서브에이전트와 워크플로. 병렬로 돌고, 한데 모이고, 턴이 끝나면 사라집니다.
- **작업 자체보다 오래 남는 정보** - 사용자가 누구인지, 어떻게 일하는지, 늘 지키는 규칙 -> Claude Code의 자동 메모리.
- **지금 돌아가고 있는 세션에 메시지를 보낼 때** -> 기본 제공되는 `SendMessage`. 무엇이 돌아가고 있는지는 `ListAgents`가 보여 줍니다.
- **창 여러 개로 몇 시간, 며칠에 걸쳐 일할 때** -> longrun. 매 턴보다 오래 남는 상태, 멈춰 있어도 글을 보낼 수 있는 세션, token을 쓰지 않는 대기, 그리고 나머지를 조율하는 한 세션.

## 세션이 협력하는 네 가지 방법

> [!NOTE]
> 아래 명령은 에이전트가 스스로 실행합니다. 언제 메모를 쓰고, 언제 메시지를 보내고, 언제 워치를 걸지는 skill이 알려 줍니다. 여기에 외워야 할 명령은 하나도 없습니다. "*기록해 둬*"나 "*PR 머지되면 알려줘*"라고 말하면 되고, 아무 말도 하지 않아도 됩니다. 그래도 여기에 적어 둔 이유는, 손으로 실행하고 싶을 때 언제든 그렇게 할 수 있기 때문입니다.

### 1. 디스크 위의 공유 문서

프로젝트마다 하나씩 있는 `.longrun/` 디렉터리에 모든 세션이 보는 메모가 들어 있고, 메모는 기본적으로 이 디렉터리에 저장됩니다. 세션이 혼자만 두고 싶은 내용은 `--own`을 붙여 리포지터리 트리 바깥에 따로 저장합니다. hook은 compaction, `/clear`, resume 때마다 공유 메모와 자체 메모를 모두 되살리고, 매 턴 다른 세션이 무엇을 바꿨는지 보여 줍니다.

```bash
longrun add -t pin "PR 42 = branch feature/checkout"           # shared: every session sees it
longrun add --own -t ctx "only the checkout drawer, not the cart"  # this conversation only
longrun doc add research/plan.md "the rollout plan and what is open"
longrun recall 429                                             # notes, those files, journals, transcripts
```

### 2. 컨텍스트가 있는 세션에 위임

다른 세션으로 보낸 메시지는 그쪽에서 사용자 턴으로 도착합니다. 돌아가고 있는 세션은 socket으로 바로 받고, 멈춰 있는 세션은 다음 턴에 프로젝트 수신함에서 받습니다. `--resume`을 붙였을 때만 그 자리에서 깨어나는데, 이 경우 백그라운드에서 `claude -p`가 실행되므로 token을 씁니다. 세션 이름은 사이드바에 보이는 제목 그대로입니다.

세션 사이에 메시지를 보내는 일 자체는 Claude Code도 스스로 합니다. `SendMessage`는 **돌아가고 있는** 세션에 글을 보내고, `ListAgents`는 돌아가고 있는 세션을 나열합니다. `longrun send`는 거기에 나머지를 더합니다. 멈춰 있는 세션에도 보낼 수 있고(메시지는 수신함에서 기다립니다), 세션 id가 아니라 사이드바 제목으로 상대를 지정하고, `--resume`으로 헤드리스로 깨울 수 있으며, 발동한 워치와 보드도 같은 경로를 씁니다. 워치와 보드에는 대신 도구를 호출해 줄 모델이 없습니다.

```bash
longrun send "PR 43: payments" "PR 42 merged, rebase onto main"
longrun board assign T8 "PR 43: payments"      # a task instead of a message
```

### 3. 이벤트 기반: token을 쓰지 않는 대기

워치는 정해진 규칙대로만 판정하는 검사로, 타이머(macOS에서는 launchd agent, Linux에서는 systemd user timer나 cron 작업)가 5분마다 모델 없이 실행합니다. 조건이 성립하면 세션은 `--then`에 적은 문구를 메시지로 받습니다. 노트북이 잠들어 있으면 검사가 미뤄질 뿐입니다.

```bash
longrun watch add --to "PR 43: payments" --then "rebase onto main" -- pr-merged 42
longrun watch add --then "check the deploy" -- at 10:00
```

검사 종류: `pr-merged`(`gh`로 GitHub 확인), `pr-status`, `at`, `file`, `http`, `cmd`.

### 4. 한 세션이 나머지를 조율합니다 - 그리고 필요할 때는 사람에게 연락합니다

한 세션이 오케스트레이터 역할을 맡아 보드를 유지합니다. 보드에는 목표, 작업, 바깥에서 들어온 사실이 담깁니다. 작업 세션은 작업을 가져가서 끝내고, 진행이 막히면 그 작업에 막힘 표시를 합니다. 보드가 바뀔 때마다 오케스트레이터가 깨어나 다음 작업을 나눠 주고, 막힌 것을 풀거나, 모든 창 앞에 뜨는 대화 상자로 사람에게 묻습니다. 폴링도 하지 않고, 세션을 직접 띄우지도 않습니다. 데스크톱 앱에서는 클릭하면 세션이 열리는 칩(버튼)을 남기고, 터미널에서는 직접 붙여 넣을 첫 줄을 건네줍니다.

오케스트레이터는 사람 없이 알아서 진행하지 않습니다. 창 여러 개를 조율하고, 사람에게 연락할 길을 열어 둘 뿐입니다. 세션 **하나**를 평가자가 확인할 수 있는 상태까지 끌고 가는 일은 `/goal`이 맡습니다.

```bash
longrun orchestrate start --goal "ship the checkout drawer"    # in the coordinating session
longrun board take T7; longrun board done T7 "PR 42 merged"    # in a worker
longrun board add --fact "reviewer wants the field renamed"    # something learned outside
longrun ask "Merge PR 42?" --options "Yes,No"                  # a dialog, answered inline
```

제어권은 사람이 쥐고 있습니다. 오케스트레이터와 감시자는 제안만 합니다. 세션에 메시지를 보내고, 사람 앞에 질문을 띄우고, `longrun halt`로 모든 세션을 한 번에 멈출 수 있지만, 그 정지는 사람만 풀 수 있습니다. 실행 중인 도구를 강제로 끝내는 기능은 없습니다. 정체된 창은 사람이 Esc로 직접 멈춥니다.

## 동작 방식

```mermaid
sequenceDiagram
    participant S as Claude Code 세션
    participant L as longrun (hooks)
    participant D as 디스크 위의 메모
    S->>L: 세션 시작
    L->>D: 프로젝트의 공유 메모와 이 세션의 자체 메모 읽기
    L-->>S: 다이제스트: 무엇이 알려져 있고, 누가 일하고 있고, 무엇이 대기 중인지
    Note over S: 에이전트가 작업하며 막다른 길과 결정을 한 줄씩 기록
    S->>D: longrun add ...
    S->>L: 매 턴
    L-->>S: 다른 세션이 바꾼 것, 나에게 온 메시지
    S->>L: compaction 임박
    L->>D: 스냅샷, 그리고 요약하는 모델에게 무엇을 남길지 지시
    S->>L: 세션 재시작 (compaction, /clear, resume 후)
    L-->>S: 같은 다이제스트, 그리고 어디서 멈췄는지
```

**시작**. hook은 디렉터리로 프로젝트를 찾아 다이제스트를 출력합니다. 다이제스트에는 공유 메모, 자체 메모, 다른 세션(살아 있는지, 각자 마지막으로 무엇을 했는지), 대기 중인 워치, 아직 전달되지 않은 메시지가 들어 있습니다.

**작업**. 에이전트는 막다른 길, 결정, 어렵게 얻은 사실을 한 줄씩 적습니다. hook은 편집 횟수를 세고 실패한 명령을 기록합니다. 메모 없이 편집만 길게 이어지면 에이전트에게 메모를 남기라고 한 번 알려 줍니다.

**매 턴**. 수신함의 메시지가 전달됩니다. 다른 세션이 공유 메모를 바꾼 내용은 변경분으로 표시됩니다. `+`는 추가, `~`는 수정, `-`는 삭제입니다.

**compaction**. compaction 직전에 최근 요청, 편집한 파일, 최근 실패의 스냅샷을 남기고, 요약하는 모델에게 줄 지시도 함께 넘깁니다. 막다른 길은 이유까지 남기고, 정확한 문자열은 남기고, 파일을 한 번 읽으면 되찾을 수 있는 것은 버리라는 내용입니다. Claude Code는 자동 compaction에서도 `/compact <text>`와 똑같은 요약 prompt를 만듭니다. 그래서 longrun은 같은 방식으로 요약을 유도하며, 사용자가 시점을 맞추는 수고만 덜어 줍니다. compaction이 끝나면 요약은 그대로 아카이브됩니다. 다음 시작 때는 다이제스트에 더해 HANDOFF 블록이 출력되어, 세션은 같은 자리에서 이어집니다. resume과 `/clear`는 같은 메모를 그대로 이어받고, fork는 사본을 받습니다.

**정리**. 한 시간에 한 번, 오래된 항목은 아카이브로 보내고(`pin`은 제외), 저널은 잘라 내고, 조용해진 세션도 아카이브로 보냅니다. 메모 한도에 이르면 `add` 명령은 저장을 거부하고 무엇을 덜어 내면 되는지 알려 줍니다. 소리 없이 버려지는 것은 없습니다.

## 세 가지 구성 요소

| 구성 요소 | 무엇인지 | 저장하는 것 |
|---|---|---|
| **프로젝트** | `.longrun/` 디렉터리 하나. 프로젝트 폴더 안에 두거나 트리 바깥에 둡니다(`--external`) | 공유 메모, 수신함, 보드, 아카이브 |
| **세션** | Claude Code 대화 하나. 앱에서는 사이드바의 한 줄. resume하면 id가 새로 생기고, longrun이 옛 id와 새 id를 이어 줍니다 | 자체 메모, 저널, 카운터, 마지막 상태 |
| **디렉터리** | 세션이 시작된 폴더. 리포지터리 루트, worktree, 하위 디렉터리 | 아무것도 저장하지 않습니다. 그 세션이 어느 프로젝트에 속하는지만 알려 줍니다 |

worktree는 `longrun link <project>`로 프로젝트에 붙이며, worktree 자체의 메모는 따로 없습니다.

## 무엇을 기록하는가

기준은 하나입니다. **명령 한 번, 파일 읽기 한 번, grep 한 번으로 되찾을 수 있는가**? 그렇다면 적지 않습니다. 한 줄에 담기에 너무 길면 파일로 두고, 메모에는 그 파일을 가리키는 한 줄만 남깁니다: `longrun doc add research/plan.md "the rollout plan and what is still open"`. 모든 세션이 시작할 때마다 그 한 줄을 보고, 파일은 필요할 때만 엽니다.

| 태그 | 무엇을 | 어디에 |
|---|---|---|
| `dead` | 실패한 접근과 그 이유 | 자체 메모. 다른 세션도 같은 막다른 길에 들어설 수 있으면 공유 |
| `decision` | 선택과 그 이유 | 다른 세션과 관계있으면 공유 |
| `fact` | 어렵게 알아낸 환경 정보 | 공유 |
| `pin` | 만료가 없는 사실. PR 번호, 브랜치, 호스트 | 공유 |
| `ctx` | 사람이 준 작업의 배경과 조건 | 자체 메모 |
| `doc` | 메모 한 줄에 담기에는 너무 긴 파일을 가리키는 한 줄: `longrun doc add <path> "what is in it"` | 공유 |

더 이상 사실이 아닌 메모는 아무도 모르게 지우지 않습니다. `longrun stale n12 "staging moved to vla-07"`로 표시해 두면 모든 세션이 그 표시를 보고, 다음 정리 때 표시된 항목부터 치웁니다. `longrun mute n12`는 그 메모를 *내* 다이제스트에서만 감출 뿐, 다른 누구에게도 아무 영향을 주지 않습니다.

저널은 기계적인 기록을 알아서 남깁니다. 무엇을 편집했는지, 무엇이 실패했는지, compaction이 언제 일어났는지가 저널에 쌓이므로, 진행 상황을 따로 적어 둘 필요는 없습니다. 작업보다 오래 남는 정보(사용자가 누구인지, 어떻게 일하는지)는 longrun이 아니라 Claude Code의 자동 메모리에 넣습니다.

## 명령어

```bash
longrun init [--external] | link <project> | where | onboard | config
longrun add [--own] -t TAG "..." | rm | replace | stale | mute | notes | prune | recall <term>
longrun doc add <path> "what is in it" | doc ls | doc touch n12 "..." 
longrun status | send [--list] [--resume] WHO "..."
longrun watch add --to WHO --then "..." -- pr-merged 42 | at 10:00 | cmd '...' | file /path | http URL
longrun orchestrate start --goal "..." | board [add --fact|ack] | ask | halt | resume
```

전체 플래그, 파일 형식, Claude Code에 대해 검증한 사실은 [docs/REFERENCE.md](docs/REFERENCE.md)에 있습니다. 오케스트레이터의 설계와 남은 과제는 [docs/ORCHESTRATOR.md](docs/ORCHESTRATOR.md)에 있습니다.

<!-- site: nuances, limits and edge cases move to the site; add the link here -->

<details>
<summary><b>자주 묻는 질문</b></summary>

**PR이 있는데도 에이전트가 "PR은 아직 만들어지지 않았다"고 말합니다**. 그 사실이 공유 메모에 없기 때문입니다. 이렇게 적어 둡니다: `longrun add -t pin "PR 42 = branch feature/checkout"`.

**worktree의 세션이 프로젝트 메모를 보지 못합니다**. `longrun where`의 출력에 프로젝트가 나와야 합니다. "not initialised"라고 나오면 그 worktree에서 `longrun link <project>`를 실행합니다.

**메시지를 보냈는데 세션이 조용합니다**. `longrun send --list`로 확인합니다. 받는 쪽이 "stopped"면 메시지는 수신함에 있고 다음 턴에 받습니다. 지금 당장 필요하면 `--resume`을 붙입니다.

**워치가 발동하지 않습니다**. `longrun watch status`, `longrun watch ls --all`, `longrun watch test -- <the same check>`. 흔한 원인은 `cmd` 안의 상대 경로나 셸 alias입니다.
</details>

## 개발

```bash
bash tests/run.sh            # 211 regression checks, no API calls
bash tests/scenarios.sh      # 37 scenarios, one per goal
bash tests/orchestrator.sh   # 51: the orchestrator layer
bash tests/ask.sh            # 27: the dialog and the MCP server
```

설치 스크립트는 파일을 `~/.claude/skills/longrun/`로 복사하며, checkout한 디렉터리에서 직접 읽어 들이는 것은 없습니다. hook은 이벤트마다 별도 프로세스로 실행되기 때문에, 돌아가고 있는 세션도 재시작 없이 업데이트를 받습니다.

## 라이선스

[MIT](LICENSE)
