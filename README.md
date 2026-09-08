# shared-project-memory

跨工具共享專案記憶。讓 **Claude Code / Codex / Antigravity** 在換電腦、換 agent 時讀同一份
Git 版控的記憶,不必重新解釋專案或重掃程式碼。

> **狀態**：機制層已在 Windows／Git Bash 與 Linux／Docker 兩個環境完整實測通過。
> 尚未驗證的一項：Codex 與 Antigravity 是否確實**照著**它們載入的指示做（無 headless CLI 可自動化，
> 需 1 分鐘手測 —— 詳見 [`docs/implement.md`](docs/implement.md) §12）。

📐 **架構總覽（含互動式流程圖）**：[`docs/architecture.html`](docs/architecture.html)
📄 **完整設計、協定與測試紀錄**：[`docs/implement.md`](docs/implement.md)

## 設計核心:單一事實來源,兩條自動化路徑

`.project-memory/handoff.md` 是**唯一**被人／agent 寫入的狀態。三個 agent 開局都能自動拿到它,
但走的機制不同——因為只有 Claude Code 能「自動執行指令並注入輸出」:

```
              .project-memory/handoff.md   ← 唯一事實來源
                          │
        ┌─────────────────┴──────────────────┐
        │                                     │
   status.sh                          sync-entry-files.sh
   (執行時印出 tier-1)                 (生成進靜態 entry 檔)
        │                                     │
   Claude Code                    Codex          Antigravity
   SessionStart hook          AGENTS.md      .agents/rules/
   自動執行 → 注入              自動載入        自動載入
                                    ▲                ▲
                                    └── git hook 自動再生 ──┘
                              pre-commit（改 handoff 即再生+staged）
                              post-merge（pull 後自動刷新）
```

## 各工具支援程度（誠實版）

| 功能 | Claude Code | Codex | Antigravity | 機制 |
|---|:--:|:--:|:--:|---|
| **開局載入記憶** | ✅ **全自動** | ✅ **全自動** | ✅ **全自動** | 見下方「兩條自動化路徑」 |
| 安裝 | `/memory-init` | `install.sh` | `install.sh` | 兩條路都通 |
| 收工寫交接棒 | `/handoff` | entry 檔指示 | entry 檔指示 | `PROTOCOL.md` 門檻 |
| **擋「改碼沒更新記憶」** | ✅ | ✅ | ✅ | **git pre-commit（工具無關）** |
| **擋 secret 進 repo** | ✅ | ✅ | ✅ | **git pre-commit（工具無關）** |
| 跨機同步檢查 | ✅ | ✅ | ✅ | `status.sh` / post-merge |

### 兩條自動化路徑（為什麼三個都能自動）

三個工具**都會自動載入靜態檔案**（CLAUDE.md / AGENTS.md / `.agents/rules/`）；
差別只在**只有 Claude Code 能自動「執行指令並注入輸出」**。所以用兩條路徑補齊：

| | 路徑 | 觸發 |
|---|---|---|
| **Claude Code** | SessionStart hook 執行 `status.sh` → 注入 | 開新 session 自動 |
| **Codex / Antigravity** | git hook 把 handoff **生成**進它們本來就自動讀的 `AGENTS.md` 與 `.agents/rules/shared-memory.md` | `pre-commit`（handoff 一改就再生並自動 staged）＋ `post-merge`（pull 後自動刷新） |

`handoff.md` 仍是**唯一事實來源**；entry 檔裡的 `AUTO-MEMORY` 區塊是**衍生的、機器再生的**，
不是人工複製 —— 標有 do-not-edit 標記，不會 drift。

### Agent 自己提交 handoff（閉環的關鍵）

Agent 收工時自己跑 `bash .project-memory/commit-handoff.sh "<摘要>"`，**不用等使用者 commit**。
這樣「未提交的 handoff 看不到」的時間差就不存在了。

| 動作 | 誰決定 | 為什麼 |
|---|---|---|
| commit **記憶** | ✅ agent 自動 | 本地、可逆（`git reset --soft HEAD~1`），不 commit 就等於沒交接 |
| commit **原始碼** | ❌ 使用者 | 那是你的工作，agent 不該替你決定 |
| **push** | ⚙️ `MEM_AUTOPUSH=1` 才做 | 對外動作；被拒時只回報，**絕不 force** |

commit 是 **pathspec-limited** 的——只含 `.project-memory/` 與生成的 entry 區塊，
**你已 staged 的原始碼原封不動留在暫存區**（已實測）。

> 剩下的唯一限制：hook 能擋「沒更新記憶」，擋不了「更新得爛」——內容品質仍取決於 agent。

## 安裝

**Claude Code（從 GitHub 安裝）:**
```bash
claude plugin marketplace add <你的帳號>/shared-project-memory
claude plugin install shared-project-memory
```
然後在任一專案裡:
```
/memory-init
```

**Codex / Antigravity / 純手動（不需要 Claude Code）:**
```bash
git clone https://github.com/<你的帳號>/shared-project-memory.git
bash shared-project-memory/install.sh            # 裝進目前 repo
bash shared-project-memory/install.sh /my/repo   # 裝進指定 repo
```
Windows PowerShell:
```powershell
.\install.ps1
```

兩條路徑跑的是同一支 `scripts/init-memory.sh`,結果完全相同,且**冪等——不覆蓋任何既有檔案**。

## 安裝後產生什麼

```
.project-memory/
├── INDEX.md         # 純索引,無可變狀態（tier 1）
├── handoff.md       # 交接棒,唯一的狀態寫入處（tier 1）
├── STATE.md         # 宏觀里程碑（tier 2,按需）
├── DECISIONS.md     # 追加式決策 + 頂部索引表（tier 2,按需）
├── PROTOCOL.md      # 完整協定（首次/按需）
├── status.sh        # 開局腳本（Claude hook 執行；任何人可手動跑）
├── sync-entry-files.sh  # 把 handoff 生成進 Codex/Antigravity 的 entry 檔
└── archive/
CLAUDE.md                          # 附加區塊（不覆蓋既有內容）
AGENTS.md                          # Codex entry（含自動再生的 AUTO-MEMORY 區塊）
.agents/rules/shared-memory.md     # Antigravity entry（同上）
.githooks/pre-commit               # 跨工具強制層 + 再生 entry 檔
.githooks/post-merge               # pull 後刷新 entry 檔
.gitattributes                     # 強制 .sh 為 LF
```

## 每天怎麼用

**開工**:三個 agent 都**直接下任務即可**——記憶已在 context 裡(Claude 由 hook 注入,
Codex/Antigravity 由自動載入的 entry 檔帶入)。若想要含未提交狀態的最即時版本,
任何 agent 都可跑 `bash .project-memory/status.sh`。

**收工**:Claude Code 用 `/handoff`;其他 agent 依 `AGENTS.md` 的完成程序。Agent 會寫 handoff
並**自己 commit**(設 `MEM_AUTOPUSH=1` 則連 push 一起)。不符更新門檻(唯讀提問、瑣碎解釋、
無變更 review)時**完全不寫檔**——省下無謂的 churn。

**換電腦**:clone 後跑一次
```bash
git config core.hooksPath .githooks
```
(`core.hooksPath` 是每個 clone 的 local 設定,commit `.githooks/` 不會自動生效。)

## 記憶分層(省 context 但不失真)

| 層 | 檔案 | 何時載入 |
|---|---|---|
| Tier 1 | `INDEX.md`、`handoff.md` | **每次**（自動/一指令） |
| Tier 2 | `STATE.md`、`DECISIONS.md`、`PROTOCOL.md` | **按需** |
| 封存 | `archive/`、`SESSION_LOG.md` | 永不自動載入 |

完整保真度**永遠留在磁碟 + Git**——省 token 靠「不 eager load」,**不是砍內容**。
`INDEX.md` 不放任何可變狀態(commit/日期/進度),避免與 `handoff.md` 雙寫不一致。

估計開銷:唯讀 session ~740、一般開發 ~1,100、架構工作 ~1,620 tokens,平均約 **1,000/session**
——相對於重掃碼的 10k–50k,淨省約 90–98%。

## 兩個開關

```bash
export MEM_AUTOSYNC=1   # 開局自動 fast-forward 同步（預設關,只報告）
export MEM_AUTOPUSH=1   # agent 提交 handoff 後自動 push（預設關,只 commit）
```

跨機工作建議**兩個都開**——這樣「A 機收工 → B 機開局就看得到」全程零手動。

### MEM_AUTOSYNC（拉）

三重守衛缺一不可:**開關開啟 + 工作樹乾淨 + 本地無分岔(ahead=0)**,且只用
`git pull --ff-only`——非快轉直接中止,不可能產生衝突或半 rebase 殘局。
`rebase` / `merge` / `reset` / force-push **永不自動執行**。

### MEM_AUTOPUSH（推）

Agent commit 記憶後嘗試一次普通 `git push`。被拒(分岔)時**只回報,不 force、不 reset**,
留給你手動處理。commit 本身不受這個開關影響——**記憶永遠會被 commit**,差別只在有沒有推上去。

## 已驗證行為

以下皆在拋棄式 repo 實測通過:

- scaffold 冪等(第二次執行全部 skip,不覆蓋)
- 改了 `src/` 但沒 staged 記憶 → **擋 commit**
- 改了碼 + 更新記憶 → 通過
- 記憶新增 `api_key: <長值>` → **擋 commit**
- 移除既有 secret 的 commit → **正常通過**(不誤擋)
- 記憶中出現 "Never store passwords, API keys" 這類**純文字** → 不誤判
- Claude hook 路徑與直接執行 `status.sh` → **輸出完全一致**
- 在沒有 `.project-memory/` 的 repo 執行 hook → **靜默 no-op,exit 0**
- 安裝後 `AGENTS.md` 與 `.agents/rules/` **立即含 AUTO-MEMORY 區塊**（day one 就有記憶）
- 更新 handoff 後 commit → 兩個 entry 檔**自動再生並自動 staged 進同一個 commit**
- `sync-entry-files.sh` **冪等**（重跑不會堆疊出第二個區塊）
- 另一台 clone `git pull` → **post-merge 自動刷新** entry 檔為最新 handoff
- `commit-handoff.sh` 在使用者已 staged `src/app.py` 的情況下提交 → **只提交 3 個記憶檔，
  `src/app.py` 仍 staged 且未被提交**
- 完整跨機閉環：機器A 寫 handoff → 自動 commit+push → 機器B `pull` → **開局即見最新任務，零手動步驟**
- push 遇到分岔被拒 → **回報而已；遠端未被 force 覆蓋，本地 commit 也未被 reset**
- 無記憶變更時執行 → `No memory changes to commit.`（no-op）

## 檔案結構

```
shared-project-memory/
├── .claude-plugin/
│   ├── plugin.json               # 外掛定義
│   └── marketplace.json          # 讓 `claude plugin marketplace add` 可直接指向本 repo
├── docs/
│   ├── implement.md              # 完整設計、協定、測試紀錄、待解決項目
│   └── architecture.html         # 互動式架構總覽
├── hooks/hooks.json              # SessionStart -> scripts/session-start.sh
├── commands/
│   ├── memory-init.md            # /memory-init
│   └── handoff.md                # /handoff
├── scripts/
│   ├── session-start.sh          # 薄包裝 -> repo 的 status.sh
│   └── init-memory.sh            # 冪等 scaffold（兩條安裝路徑共用）
├── install.sh / install.ps1      # 非 Claude Code 的安裝入口
└── templates/
    ├── memory/{INDEX,handoff,STATE,DECISIONS,PROTOCOL}.md
    ├── status.sh                 # Claude 用的共用開局腳本
    ├── sync-entry-files.sh       # 把 handoff 生成進 Codex/Antigravity 的 entry 檔
    ├── post-merge                # pull 後自動刷新 entry 檔
    ├── CLAUDE.md AGENTS.md shared-memory.md
    └── pre-commit
```

## 注意

- `*.sh` 與 `pre-commit` **必須是 LF 換行**;CRLF 會讓 bash 噴 `\r: command not found`。
  scaffold 產生的 `.gitattributes` 已含對應規則。
- Windows 需要 Git Bash(Git for Windows 內建)——hook 本來就依賴它。
- `pre-commit` 的工程檔比對偏嵌入式(含 `firmware|drivers`、`c/cpp/h`)。純軟體專案可自行刪掉。
- 沒有做 Skill:協定放在各專案的 `.project-memory/PROTOCOL.md`(按需讀),不另做第三份副本。
