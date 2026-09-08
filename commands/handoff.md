---
description: Run the completion protocol — write the handoff and update shared memory if the work meets the threshold
---

Run the shared-project-memory completion protocol for the work done in this session.

**First, check the update threshold.** Update memory only if ANY of these is true:
- Source, tests, config, scripts, or meaningful docs changed.
- Work is incomplete and another agent could continue it.
- Test results, environment assumptions, dependencies, or known risks changed.
- The user made a decision affecting future work.

If none apply (read-only question, trivial explanation, no-change review, or exploration that
produced nothing reusable), say so and **stop — do not write anything**. Needless churn is a cost,
not diligence.

If the threshold is met:

1. Rewrite `.project-memory/handoff.md` with the real state — Agent, Branch, Commit (use
   `git rev-parse --short HEAD`, or `Uncommitted`), Done, Not done, Next agent should, Tests,
   Warnings. "Next agent should" must be concrete enough to execute without this conversation.
2. Update `.project-memory/STATE.md` **only** if a milestone, macro status, major blocker, or
   cross-module plan changed.
3. Append to `.project-memory/DECISIONS.md` **only** for a durable architectural decision — add a
   row to the Quick Index and a new section below. Never rewrite an existing decision; supersede it.
4. Run the relevant tests or validation and record the actual command and result. If tests failed
   or you did not run them, write that — never record an unverified pass.
5. Show `git diff --stat` and state any remaining risk.
6. **Commit the memory yourself** so other agents and other machines actually receive it:

```bash
bash .project-memory/commit-handoff.sh "docs(memory): <one-line summary of this session>"
```

   This commits ONLY `.project-memory/` and the generated entry-file blocks — pathspec-limited, so
   any source changes you or the user have staged stay staged and uncommitted. It also regenerates
   the block that Codex and Antigravity auto-load, so they get this handoff on their next session.

   It pushes only when `MEM_AUTOPUSH=1`; otherwise the commit stays local and the script says so.
   Tell the user if the handoff has not been pushed yet — until it is, other machines won't see it.

Do not pull, rebase, merge, reset, or force-push. Committing the memory is fine and reversible
(`git reset --soft HEAD~1`); committing the user's source code is not yours to decide — leave that
to them.
