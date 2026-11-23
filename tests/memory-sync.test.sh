#!/usr/bin/env bash
# End-to-end check of scripts/memory-sync.sh with real git, a folder store and a local bare repo
# as the git store. No network. Run: bash tests/memory-sync.test.sh
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$HERE/scripts/memory-sync.sh"
T="$(mktemp -d)"
trap 'cd /; for l in "$T"/*/.project-memory; do [ -L "$l" ] && rm "$l"; done; rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global init.defaultBranch main
fail() { echo "FAIL: $*"; exit 1; }
clone() {  # $1 = dir: a project clone with origin github.com/me/app
  git init -q "$T/$1"; cd "$T/$1"
  git remote add origin https://github.com/me/app.git
  git commit -q --allow-empty -m init
}

# 1) folder store: first machine moves its memory in
export SPM_CONFIG_DIR="$T/conf-a"
mkdir "$T/drive"
clone a; bash "$HERE/install.sh" >/dev/null
echo "machine A note" >> .project-memory/handoff.md
bash "$SYNC" link "$T/drive" >/dev/null
[ -L .project-memory ] || fail "A not linked"
grep -q "machine A note" "$T/drive/me/app/handoff.md" || fail "memory not moved into store"
[ -f "$T/drive/.workbench-memory.json" ] || fail "no folder marker"
[ -f "$T/drive/me/app/entry/AGENTS.md" ] || fail "entry template not saved"
bash .project-memory/commit-handoff.sh | grep -q "synced folder" || fail "commit-handoff did not see the folder store"
! git status --porcelain | grep -E 'project-memory|AGENTS\.md|\.agents' || fail "memory shows up in the project repo"

# 2) second machine: empty clone gets the shared memory and its entry files
export SPM_CONFIG_DIR="$T/conf-b"
clone b
bash "$SYNC" link "$T/drive" >/dev/null
grep -q "machine A note" .project-memory/handoff.md || fail "B did not get A's memory"
grep -q "AUTO-MEMORY" AGENTS.md || fail "B's AGENTS.md not restored"
bash "$SYNC" link | grep -q "Already linked" || fail "relink not idempotent"

# 3) differing memory is refused until a side is picked
clone c; bash "$HERE/install.sh" >/dev/null; echo "C differs" >> .project-memory/handoff.md
if bash "$SYNC" link 2>/dev/null; then fail "differing memory was linked"; fi
bash "$SYNC" link --prefer shared >/dev/null
grep -q "machine A note" .project-memory/handoff.md || fail "prefer shared"
ls "$T/drive/.local-backups/me__app" | grep -q . || fail "no backup of C's memory"

# 4) git store (bare repo stands in for the private GitHub repo)
git init -q --bare "$T/mem.git"; git clone -q "$T/mem.git" "$T/store-a" 2>/dev/null
export SPM_CONFIG_DIR="$T/conf-ga"
clone ga; bash "$HERE/install.sh" >/dev/null
bash "$SYNC" link "$T/store-a" >/dev/null
git --git-dir="$T/mem.git" log --oneline | grep -q "memory: link me/app" || fail "link not pushed"
echo "handoff from GA" >> .project-memory/handoff.md
bash .project-memory/commit-handoff.sh "handoff GA" | grep -q "Pushed" || fail "commit-handoff did not push"

git clone -q "$T/mem.git" "$T/store-b"
export SPM_CONFIG_DIR="$T/conf-gb"
clone gb; bash "$SYNC" link "$T/store-b" >/dev/null
grep -q "handoff from GA" .project-memory/handoff.md || fail "GB did not get GA's handoff"
echo "edit from GB" >> .project-memory/handoff.md
bash "$SYNC" sync >/dev/null
export SPM_CONFIG_DIR="$T/conf-ga"; cd "$T/ga"; bash "$SYNC" sync >/dev/null
grep -q "edit from GB" .project-memory/handoff.md || fail "sync did not bring GB's edit to GA"

# 5) a project that tracks its memory is refused
clone tr; bash "$HERE/install.sh" >/dev/null; git add -f .project-memory/handoff.md; git commit -q --no-verify -m track
if bash "$SYNC" link 2>/dev/null; then fail "tracked memory was linked"; fi

echo "memory-sync: all checks passed"
