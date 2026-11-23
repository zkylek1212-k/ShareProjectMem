---
description: Share this project's memory between computers — link .project-memory to a cloud folder or a private GitHub repo, sync it, or show its status
argument-hint: "[link <folder | owner/repo> [--prefer local|shared] | sync | status]"
---

Run the plugin's sync script from the project root with the user's arguments (default: `status`).
On Windows run it with Git Bash, not WSL bash.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-sync.sh" $ARGUMENTS
```

- `link <store>`: `<store>` is a OneDrive / Google Drive / Dropbox folder, or the user's PRIVATE
  GitHub repository as `owner/repo` (cloned for them; created private with `gh` if it is missing).
  A public repository is refused. The store is remembered on this machine, so other projects need
  only `link`. If `.project-memory` has never been set up, run `/memory-init` first.
- If it says the memory differs, show the user both sides (`.project-memory/handoff.md` vs the
  store's copy) and ask which to keep, then rerun with `--prefer local` or `--prefer shared`. Both
  are backed up under `<store>/.local-backups/` first.
- If it says the project repository tracks `.project-memory`, ask before running
  `git rm -r --cached .project-memory` and committing.
- Report exactly what it printed. Never commit memory to the project repository.
