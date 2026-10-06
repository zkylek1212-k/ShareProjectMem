---
description: Scaffold shared project memory into this repo (.project-memory/, entry files for all three agents, git hooks)
---

Set up cross-tool shared project memory in the current repository.

1. Run the scaffolding script. On Windows, use the bundled PowerShell installer so `bash`
   cannot resolve to WSL:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/install.ps1" "${PWD}"
```

On macOS/Linux, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-memory.sh"
```

2. Report exactly what it created vs skipped (it never overwrites existing files).

3. Then fill in the two placeholder files from what you can actually verify about this repo —
   read the README, package/build files, and recent `git log` first. Do NOT invent status:

   - `.project-memory/STATE.md` — current milestone, macro progress, long-term tasks. Mark
     anything you inferred rather than confirmed as `Unverified`.
   - `.project-memory/handoff.md` — set Agent/Branch/Commit from the real repo state; put the
     genuine next steps under "Next agent should". If there is no work in flight, say so plainly
     rather than fabricating a task.

4. Tell the user the two remaining manual steps:
   - Commit the scaffold: `git add .project-memory .githooks .gitattributes CLAUDE.md AGENTS.md .agents && git commit`
   - On every OTHER machine after cloning: `git config core.hooksPath .githooks`
     (`core.hooksPath` is per-clone local config — committing `.githooks/` does not enable it.)

5. Mention that safe auto-sync is OFF by default, and can be enabled by setting the environment
   variable `MEM_AUTOSYNC=1` (fast-forward only, and only when the tree is clean and has no
   divergent local commits).
