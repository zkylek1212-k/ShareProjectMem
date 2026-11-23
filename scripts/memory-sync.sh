#!/usr/bin/env bash
# Share .project-memory between computers. The memory lives in a store you pick once per machine
# (a OneDrive / Google Drive / Dropbox folder, or your own PRIVATE GitHub repository); each project
# links its .project-memory to <store>/<owner>/<repo> (a junction on Windows, a symlink elsewhere).
# The project repository never receives memory files.
#
#   memory-sync.sh link [<store>] [--prefer local|shared]   # run in a project; <store> is needed once per machine
#   memory-sync.sh sync                                     # git store: commit, pull --rebase, push
#   memory-sync.sh status
#
# <store>: a folder path (cloud-synced folder), owner/repo or a GitHub URL (private repo, cloned for
# you), or a folder that already is a clone of your private memory repo.
# Stores made by the former Agent Workbench memory sync use the same layout and keep working.

set -e
export GIT_TERMINAL_PROMPT=0
PLUGIN="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${SPM_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/shared-project-memory}"
MARKER=".workbench-memory.json"
MEM=".project-memory"

die() { echo "memory-sync: $*" >&2; exit 1; }
real() { (cd "$1" 2>/dev/null && pwd -P); }
same() { [ "$(real "$1" | tr '[:upper:]' '[:lower:]')" = "$(real "$2" | tr '[:upper:]' '[:lower:]')" ]; }
windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0;; esac; return 1; }
is_link() { [ -L "$1" ]; }   # Git Bash reports junctions as links too
make_link() {  # $1=target $2=link
  if windows; then MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -aw "$2")" "$(cygpath -aw "$1")" >/dev/null
  else ln -s "$1" "$2"; fi
}
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^\./_/'; }
gh_repo() {  # owner/repo from a GitHub URL or owner/repo, else empty
  printf '%s' "$1" | sed -nE 's#^(https?://|git@)?(www\.)?(github\.com[/:])?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?$#\4/\5#p' | sed 's/\.git$//'
}
store() { cat "$CONF/store" 2>/dev/null || true; }
is_git_store() { [ -d "$1/.git" ]; }

# Memory is never public: a repo anonymous GitHub can read is refused. 404 = private or missing.
refuse_public() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "https://api.github.com/repos/$1" || echo 000)"
  case "$code" in
    200) die "github.com/$1 is PUBLIC. Memory only goes into a private repository." ;;
    404) ;;
    *) die "could not check github.com/$1 (HTTP $code). Try again when online." ;;
  esac
}

set_store() {  # $1 = folder | owner/repo | URL
  local arg="$1" dir repo
  mkdir -p "$CONF"
  if [ -d "$arg" ]; then
    dir="$(real "$arg")"
    if is_git_store "$dir"; then
      repo="$(gh_repo "$(git -C "$dir" config --get remote.origin.url)")"
      [ -n "$repo" ] && refuse_public "$repo"
    else
      [ -f "$dir/$MARKER" ] || printf '{"provider":"folder"}\n' > "$dir/$MARKER"
    fi
  else
    repo="$(gh_repo "$arg")"
    [ -n "$repo" ] || die "'$arg' is neither an existing folder nor a GitHub repository."
    refuse_public "$repo"
    dir="$CONF/repos/$(safe "${repo#*/}")"
    if [ ! -d "$dir/.git" ]; then
      if ! git ls-remote "https://github.com/$repo.git" >/dev/null 2>&1; then
        command -v gh >/dev/null 2>&1 || die "github.com/$repo not found. Create it as a PRIVATE repository, then run this again."
        gh repo create "$repo" --private >/dev/null || die "could not create github.com/$repo"
      fi
      git clone -q "https://github.com/$repo.git" "$dir"
    fi
  fi
  printf '%s\n' "$dir" > "$CONF/store"
  echo "Memory store: $dir"
}

# Memory content only: no scripts, entry templates, backups or .git
differs() {
  ! diff -rq -x '*.sh' -x entry -x .local-backups -x .git --strip-trailing-cr "$1" "$2" >/dev/null 2>&1
}

project_key() {
  local r; r="$(gh_repo "$(git config --get remote.origin.url 2>/dev/null)")"
  if [ -n "$r" ]; then echo "$(safe "${r%%/*}")/$(safe "${r#*/}")"
  else echo "local/$(safe "$(basename "$PWD")")"; fi
}

# AGENTS.md and the Antigravity rule are not tracked by the project: keep a copy (without the
# generated block) in the store so another machine can recreate them, then regenerate the block.
entry_files() {  # $1 = target
  local pair proj saved
  for pair in "AGENTS.md:AGENTS.md" ".agents/rules/shared-memory.md:shared-memory.md"; do
    proj="${pair%%:*}"; saved="$1/entry/${pair#*:}"
    [ -n "$(git ls-files -- "$proj")" ] && continue
    if [ ! -e "$proj" ] && [ -f "$saved" ]; then mkdir -p "$(dirname "$proj")"; cp "$saved" "$proj"
    elif [ -f "$proj" ] && [ ! -f "$saved" ]; then
      mkdir -p "$1/entry"
      awk '/<!-- BEGIN AUTO-MEMORY/{s=1} !s{print} /<!-- END AUTO-MEMORY -->/{s=0}' "$proj" > "$saved"
    fi
  done
  [ -f "$MEM/sync-entry-files.sh" ] && bash "$MEM/sync-entry-files.sh" >/dev/null 2>&1 || true
}

exclude() {
  local f p; f="$(git rev-parse --git-path info/exclude)"; mkdir -p "$(dirname "$f")"
  for p in /.project-memory /AGENTS.md /.agents/rules/shared-memory.md; do
    grep -qxF "$p" "$f" 2>/dev/null || printf '%s\n' "$p" >> "$f"
  done
}

push_store() {  # $1 = store, $2 = message, $3 = pathspec (optional)
  is_git_store "$1" || return 0
  [ -n "$(git -C "$1" status --porcelain -- ${3:+"$3"})" ] || return 0
  git -C "$1" config user.email >/dev/null || git -C "$1" config user.email "memory@localhost"
  git -C "$1" config user.name >/dev/null || git -C "$1" config user.name "shared-project-memory"
  git -C "$1" add -A -- ${3:+"$3"}
  git -C "$1" diff --cached --quiet && return 0   # only line endings changed
  git -C "$1" commit -q -m "$2" -- ${3:+"$3"}
  git -C "$1" push -q -u origin HEAD 2>/dev/null \
    || { git -C "$1" pull -q --rebase --autostash && git -C "$1" push -q -u origin HEAD; } \
    || echo "Committed in $1 but the push failed; run 'memory-sync.sh sync' later."
}

cmd_link() {
  local prefer="" arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prefer) prefer="$2"; shift 2 ;;
      *) arg="$1"; shift ;;
    esac
  done
  case "$prefer" in ""|local|shared) ;; *) die "--prefer takes local or shared" ;; esac
  cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
  [ -n "$arg" ] && set_store "$arg"
  local S; S="$(store)"
  [ -n "$S" ] && [ -d "$S" ] || die "no memory store on this machine yet: memory-sync.sh link <folder | owner/repo>"
  [ -z "$(git ls-files -- "$MEM")" ] || die "this repository tracks $MEM. Run: git rm -r --cached $MEM && git commit, then link again."

  local key target backup
  key="$(project_key)"; target="$S/$key"
  if is_link "$MEM"; then
    same "$MEM" "$target" || die "$MEM already links to $(real "$MEM" || echo '?'). Remove that link (rm $MEM deletes only the link) and link again."
    echo "Already linked: $MEM -> $target"
  else
    local here=0 there=0
    [ -f "$MEM/handoff.md" ] && here=1
    [ -f "$target/handoff.md" ] && there=1
    [ $here = 1 ] || [ $there = 1 ] || die "no memory here or in the store. Run /memory-init (or install.sh) first."
    if [ $here = 1 ] && [ $there = 1 ] && [ -z "$prefer" ] && differs "$MEM" "$target"; then
      die "this clone's memory differs from the store's copy. Pick one: --prefer local | --prefer shared"
    fi
    if [ $here = 1 ]; then
      backup="$S/.local-backups/${key/\//__}/$(date +%Y-%m-%dT%H-%M-%S)"
      mkdir -p "$backup"; cp -R "$MEM/." "$backup/"
      if [ $there = 0 ] || [ "$prefer" = local ]; then
        [ $there = 1 ] && { mkdir -p "$backup-shared"; cp -R "$target/." "$backup-shared/"; rm -rf "$target"; }
        mkdir -p "$target"; cp -R "$MEM/." "$target/"
      fi
      rm -rf "$MEM"            # a real folder here (links were handled above), now copied and backed up
      echo "Backup of this clone's memory: $backup"
    elif [ -e "$MEM" ]; then
      rmdir "$MEM" 2>/dev/null || die "$MEM exists but has no handoff.md; move it away and link again."
    fi
    mkdir -p "$(dirname "$target")"
    make_link "$target" "$MEM"
    echo "Linked: $MEM -> $target"
  fi

  # The store's scripts follow the plugin (an old commit-handoff.sh may predate today's rules)
  local f
  for f in status.sh sync-entry-files.sh commit-handoff.sh; do
    diff -q --strip-trailing-cr "$PLUGIN/templates/$f" "$target/$f" >/dev/null 2>&1 || cp "$PLUGIN/templates/$f" "$target/$f"
  done
  entry_files "$target"
  exclude
  push_store "$S" "memory: link $key" "$key"
}

cmd_sync() {
  local S; S="$(store)"
  [ -n "$S" ] || die "no memory store on this machine yet: memory-sync.sh link <folder | owner/repo>"
  if is_git_store "$S"; then
    push_store "$S" "memory: sync from $(hostname 2>/dev/null || echo this computer)"
    git -C "$S" pull -q --rebase --autostash || { git -C "$S" rebase --abort 2>/dev/null; die "pull failed; resolve in $S"; }
    [ "$(git -C "$S" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" = 0 ] || git -C "$S" push -q
    echo "Synced: $S"
  else
    echo "Folder store ($S): your cloud client syncs it."
  fi
  if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    cd "$top"; is_link "$MEM" && entry_files "$(real "$MEM")"
  fi
  return 0
}

cmd_status() {
  local S; S="$(store)"
  echo "Store:   ${S:-none (memory-sync.sh link <folder | owner/repo>)}"
  [ -n "$S" ] && { is_git_store "$S" && echo "Kind:    private git repo ($(git -C "$S" config --get remote.origin.url))" || echo "Kind:    synced folder"; }
  if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    cd "$top"
    echo "Project: $(project_key)"
    if is_link "$MEM"; then echo "Memory:  linked -> $(real "$MEM")"
    elif [ -d "$MEM" ]; then echo "Memory:  local only (not shared)"
    else echo "Memory:  none"; fi
  fi
}

case "${1:-}" in
  link) shift; cmd_link "$@" ;;
  sync) cmd_sync ;;
  status) cmd_status ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
