# ShareProjectMem（繁體中文）

跨工具共享專案記憶。讓 **Claude Code / Codex / Antigravity** 在換電腦、換 agent 時讀同一份
Git 版控的記憶，不必重新解釋專案或重掃程式碼。

*[English version →](README.md)*

📐 [架構總覽（互動式流程圖）](docs/architecture.html) ·
📄 [完整設計、協定與測試紀錄](docs/implement.md)

> **狀態**：機制層已在 Windows／Git Bash 與 Linux／Docker 兩個環境完整實測通過。
> 尚未驗證的一項：Codex 與 Antigravity 是否確實**照著**它們載入的指示做
> （無 headless CLI 可自動化，需 1 分鐘手測 —— 見 [`docs/implement.md`](docs/implement.md) §12）。

---

## 為什麼需要它

你在多台電腦、多個 agent 之間切換。每次切換，agent 都：

- 不知道上次做到哪、下一步是什麼
- 重新掃描整個 repo 來「理解專案」
- 重做已經完成的工作，或推翻已經做過的決定

這套系統把「下一個 agent 做正確下一步所需的最少可靠資訊」放進 repo，讓每個 agent 開局自動拿到。

**成本**：約 1,000 tokens／session。**省下**：每次 10,000–50,000 tokens 的重複探索。

---

## 設計核心：單一事實來源，兩條自動化路徑

`.project-memory/handoff.md` 是**唯一**被寫入的狀態。三個 agent 開局都自動拿到它，但機制不同 ——
因為只有 Claude Code 能「自動執行指令並注入輸出」：

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

entry 檔裡的 `AUTO-MEMORY` 區塊是**機器衍生**的，標有 do-not-edit，不會 drift。

---

## 各工具支援程度

| 功能 | Claude Code | Codex | Antigravity | 機制 |
|---|:--:|:--:|:--:|---|
| **開局載入記憶** | ✅ 全自動 | ✅ 全自動 | ✅ 全自動 | SessionStart hook／生成區塊 |
| 安裝 | `/memory-init` | `install.sh` | `install.sh` | 兩條路都通 |
| 收工寫交接棒 | `/handoff` | entry 檔指示 | entry 檔指示 | `PROTOCOL.md` 更新門檻 |
| **擋「改碼沒更新記憶」** | ✅ | ✅ | ✅ | **git pre-commit（工具無關）** |
| **擋 secret 進 repo** | ✅ | ✅ | ✅ | **git pre-commit（工具無關）** |
| 跨機同步 | ✅ | ✅ | ✅ | `status.sh`／`post-merge` |

> **誠實的地板**：hook 擋得了「沒更新記憶」，擋不了「更新得敷衍」——
> 內容品質仍取決於 agent，這是 LLM 的本質限制，沒有工具能繞過。

---

## 安裝

### Claude Code

```bash
claude plugin marketplace add zkylek1212-k/ShareProjectMem
claude plugin install shared-project-memory
```

然後在任一專案裡：

```
/memory-init
```

### Codex / Antigravity / 純手動（不需要 Claude Code）

```bash
git clone https://github.com/zkylek1212-k/ShareProjectMem.git
bash ShareProjectMem/install.sh            # 裝進目前 repo
bash ShareProjectMem/install.sh /my/repo   # 裝進指定 repo
```

Windows PowerShell：

```powershell
.\install.ps1
```

兩條路徑跑的是同一支 `scripts/init-memory.sh`，結果完全相同，且**冪等 —— 不覆蓋任何既有檔案**。

**前置條件**：git、bash（Windows 用 Git Bash）、目標資料夾已 `git init`。

### Codex plugin

安裝本 repo 的 marketplace 和 plugin：

```bash
codex plugin marketplace add zkylek1212-k/ShareProjectMem
codex plugin add shared-project-memory@shared-project-memory
```

接著在要初始化的專案中明確呼叫 `$shared-project-memory`。plugin 不會自動初始化專案，也不提供 MCP server；skill 會先檢查 Git repo 和既有記憶檔，再呼叫現有的專案初始化器。

---

## 安裝後產生什麼

```
.project-memory/
├── INDEX.md              # 純索引，無可變狀態（tier 1）
├── handoff.md            # 交接棒，唯一的狀態寫入處（tier 1）
├── STATE.md              # 宏觀里程碑（tier 2，按需）
├── DECISIONS.md          # 追加式決策 + 頂部索引表（tier 2，按需）
├── PROTOCOL.md           # 完整協定（首次/按需）
├── status.sh             # 開局腳本（任何 agent 或人都能跑）
├── sync-entry-files.sh   # 把 handoff 生成進 Codex/Antigravity 的 entry 檔
├── commit-handoff.sh     # agent 自己提交記憶
└── archive/
CLAUDE.md                          # 附加區塊（不覆蓋既有內容）
AGENTS.md                          # Codex entry（含 AUTO-MEMORY 區塊）
.agents/rules/shared-memory.md     # Antigravity entry（同上）
.githooks/pre-commit               # 跨工具強制層
.githooks/post-merge               # pull 後刷新 entry 檔
.gitattributes                     # 強制 .sh 為 LF
```

---

## 每天怎麼用

**開工** — 三個 agent 都直接下任務即可，記憶已在 context 裡。
想要含未提交狀態的最即時版本，任何 agent 都可跑 `bash .project-memory/status.sh`。

**收工** — Claude Code 用 `/handoff`；其他 agent 依 `AGENTS.md` 的完成程序。
Agent 會寫 handoff 並**自己 commit**。不符更新門檻（唯讀提問、瑣碎解釋、無變更 review）時
**完全不寫檔** —— 省下無謂的 churn。

**換電腦** — clone 後跑一次：

```bash
git config core.hooksPath .githooks
```

（`core.hooksPath` 是每個 clone 的 local 設定，commit `.githooks/` 不會自動生效。）

---

## 記憶分層（省 context 但不失真）

| 層 | 檔案 | 何時載入 |
|---|---|---|
| Tier 1 | `INDEX.md`、`handoff.md` | **每次**，自動 |
| Tier 2 | `STATE.md`、`DECISIONS.md`、`PROTOCOL.md` | **按需** |
| 封存 | `archive/`、`SESSION_LOG.md` | 永不自動載入 |

完整保真度**永遠留在磁碟 + Git** —— 省 token 靠「不 eager load」，**不是砍內容**。
`INDEX.md` 不放任何可變狀態（commit／日期／進度），避免與 `handoff.md` 雙寫不一致。

| 情境 | tokens／session |
|---|--:|
| 唯讀提問 | ~740 |
| 一般開發 | ~1,100 |
| 架構工作 | ~1,620 |
| **加權平均** | **~1,000** |

---

## 兩個開關

```bash
export MEM_AUTOSYNC=1   # 開局自動 fast-forward 同步（預設關，只報告）
export MEM_AUTOPUSH=1   # agent 提交 handoff 後自動 push（預設關，只 commit）
```

跨機工作建議**兩個都開** —— 「A 機收工 → B 機開局看得到」全程零手動。

**`MEM_AUTOSYNC`**：三重守衛缺一不可 —— 開關開啟 **+** 工作樹乾淨 **+** 本地無分岔（ahead=0），
且只用 `git pull --ff-only`：非快轉直接中止，不可能產生衝突或半 rebase 殘局。
`rebase` / `merge` / `reset` / force-push **永不自動執行**。

**`MEM_AUTOPUSH`**：被拒（分岔）時**只回報，不 force、不 reset**。commit 本身不受此開關影響 ——
記憶永遠會被 commit，差別只在有沒有推上去。

---

## 同步層：不需要 GitHub

必要的只有本機 `git init`。remote 只有跨機才需要，且不限 GitHub。

| 方案 | 適用 |
|---|---|
| GitHub / GitLab private repo | 個人專案，最省事 |
| NAS／網路磁碟上的 bare repo | 公司 IP 不能上雲 |
| **OneDrive／Google Drive 上的 bare repo** | 只想用現有雲端硬碟 |
| 無 remote | 單機使用，其餘功能全部照常 |

### ⚠️ 絕對不要把整個 repo（含 `.git/`）放進雲端同步資料夾

順序無保證（ref 可能先於 object 抵達 → `bad object`）、沒有 merge（雲端挑贏家，另一台的 commit
無聲消失）、Files On-Demand 佔位符會讓 git 卡住。**失敗是靜默且會丟歷史的。**

### ✅ 正確做法：雲端只放 bare repo 當 remote

bare repo **只在 push/fetch 時被寫入**（短暫離散），雲端有時間收斂，且保留 git 原生的衝突偵測。

```bash
# 第一台，一次
git init --bare "D:/OneDrive/git-remotes/myproj.git"
cd /d/repos/myproj                          # 工作區在雲端資料夾「外」
git remote add origin "D:/OneDrive/git-remotes/myproj.git"
git push -u origin HEAD

# 其他每一台
git clone "D:/OneDrive/git-remotes/myproj.git" D:/repos/myproj
git config core.hooksPath .githooks
```

務必把該資料夾設為「一律保留在此裝置上」（關閉 Files On-Demand）。

---

## 已驗證行為

以拋棄式 repo 實測，Windows／Git Bash 與 Linux／Docker（Alpine + busybox）皆通過：

- scaffold 冪等（第二次執行全部 skip，不覆蓋）
- 改了 `src/` 但沒 staged 記憶 → **擋 commit**
- 改了碼 + 更新記憶 → 通過
- 記憶新增 `api_key: <長值>` → **擋 commit**
- 移除既有 secret 的 commit → **正常通過**（不誤擋）
- 記憶中出現 `Never store passwords, API keys` 這類**純文字** → 不誤判
- Claude hook 路徑與直接執行 `status.sh` → **輸出完全一致**
- 在沒有 `.project-memory/` 的 repo 執行 hook → **靜默 no-op，exit 0**
- 安裝後 entry 檔**立即**含 AUTO-MEMORY 區塊
- 更新 handoff 後 commit → entry 檔**自動再生並自動 staged 進同一個 commit**
- `commit-handoff.sh` 在使用者已 staged `src/app.py` 時提交 → **只提交記憶檔，`src/app.py` 仍 staged**
- 完整跨機閉環：A 寫 handoff → 自動 commit+push → B `pull` → **開局即見最新任務**
- push 遇分岔被拒 → **只回報；遠端未被 force 覆蓋，本地 commit 未被 reset**
- 全新 repo（零 commit）→ 正確提交（早期版本會誤判「無變更」，已修）
- **從 clone 出來的 repo** 安裝並跑完整套測試 → 全數通過，換行為 LF

---

## 已知限制

- **hook 擋不了「寫得爛」** —— 只能擋「沒寫」。內容品質仍靠 agent。
- **Codex／Antigravity 的服從性未經真機驗證** —— 已確認它們**讀取**哪些檔案
  （由 Antigravity 安裝檔實證：`.agents/rules/*.md`、`AGENTS.md`、`GEMINI.md`），
  但「是否照做」需手測。
- **`handoff.md` merge conflict** 跨機同時提交仍會撞；解法有文件，未自動化。
- **Codex／Antigravity 拿到的是 commit／pull 時點的快照**，未提交的在製品要跑 `status.sh` 才看得到。
- **`pre-commit` 的工程檔比對偏嵌入式**（含 `firmware|drivers`、`c/cpp/h`），純軟體專案可自行調整。
- **Antigravity `.agents/rules/` 路徑可能隨版本變** —— 升級後用 grep 重驗（30 秒，方法見文件）。

---

## 文件

| 文件 | 內容 |
|---|---|
| [`docs/architecture.html`](docs/architecture.html) | 互動式架構總覽：資料流、處理管線、分層元件圖、部署 |
| [`docs/implement.md`](docs/implement.md) | 完整設計理由、協定全文、開發歷程、17 項已解決問題、11 項待解決 |

---

## License

[MIT](LICENSE)
