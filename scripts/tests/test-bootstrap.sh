#!/usr/bin/env bash
# Run bootstrap.sh and mise against a throwaway HOME and check the result.
# Usage: scripts/tests/test-bootstrap.sh
# Patterns grep for literal shell code ($HOME and all), and messages name paths as ~/...
# shellcheck disable=SC2016,SC2088
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd -P)
# The mise.run install that README.md uses, not whatever is first on PATH.
mise_bin=${MISE_BIN:-$HOME/.local/bin/mise}
work=$(mktemp -d "${TMPDIR:-/tmp}/config-files-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# A fresh HOME whose brew and mise are stubs. brew sits under its prefix but is
# not on PATH, as right after installing it. brew and curl only log, so what
# bootstrap.sh runs shows up in $work/<name>-brew.log and $work/<name>-curl.log.
# $work/<name>-apps stands in for /Applications and starts empty.
new_home() {
  local home=$work/$1
  mkdir -p "$home/.local/bin" "$work/$1-bin" "$work/$1-prefix/bin" "$work/$1-apps"
  printf '#!/bin/sh\necho "brew $*" >>"%s"\n' "$work/$1-brew.log" >"$work/$1-prefix/bin/brew"
  printf '#!/bin/sh\necho "curl $*" >>"%s"\n' "$work/$1-curl.log" >"$work/$1-bin/curl"
  printf '#!/bin/sh\nexit 0\n' >"$home/.local/bin/mise"
  chmod +x "$work/$1-prefix/bin/brew" "$work/$1-bin/curl" "$home/.local/bin/mise"
  echo "$home"
}

run_bootstrap() {
  local home=$1 name
  name=$(basename "$home")
  shift
  HOME=$home HOMEBREW_PREFIX=$work/$name-prefix BOOTSTRAP_APPDIR=$work/$name-apps \
    PATH=$work/$name-bin:/usr/bin:/bin "$repo/scripts/bootstrap.sh" "$@"
}

# make bootstrap PROFILE=..., as README.md runs it on a new Mac.
run_make_bootstrap() {
  local home=$1 name
  name=$(basename "$home")
  shift
  HOME=$home HOMEBREW_PREFIX=$work/$name-prefix BOOTSTRAP_APPDIR=$work/$name-apps \
    PATH=$work/$name-bin:/usr/bin:/bin make -s -C "$repo" bootstrap "$@"
}

# --- bootstrap.sh -----------------------------------------------------------

home=$(new_home personal)
run_bootstrap "$home" personal >/dev/null || fail "bootstrap.sh personal exited with $?"
for f in config.toml config.personal.toml config.work.toml; do
  link=$home/.config/mise/$f
  [[ -L $link && $(readlink "$link") == "$repo/mise/$f" ]] || fail "~/.config/mise/$f is not linked to mise/$f"
done
[[ $(cat "$home/.config/mise/miserc.local.toml" 2>/dev/null) == 'env = ["personal"]' ]] ||
  fail "miserc.local.toml does not select personal"
[[ -s $work/personal-curl.log ]] &&
  fail "bootstrap.sh downloaded although brew and mise exist: $(cat "$work/personal-curl.log")"
# Orca comes from its own tap, which mise can only read with Ruby 3; brew brings its own.
grep -qx 'brew install --cask stablyai/orca/orca' "$work/personal-brew.log" 2>/dev/null ||
  fail "bootstrap.sh does not install Orca with brew"
# An Orca installed by hand (it updates itself) is left alone: brew would refuse to overwrite it.
mkdir -p "$work/personal-apps/Orca.app"
: >"$work/personal-brew.log"
run_bootstrap "$home" personal >/dev/null || fail "bootstrap.sh with Orca already there exited with $?"
grep -q 'orca' "$work/personal-brew.log" && fail "bootstrap.sh reinstalled an Orca that is already there"

mkdir -p "$home/.config/mise"
echo 'env = ["kept"]' >"$home/.config/mise/miserc.local.toml"
run_bootstrap "$home" work >/dev/null || fail "second bootstrap.sh run exited with $?"
[[ $(cat "$home/.config/mise/miserc.local.toml") == 'env = ["kept"]' ]] ||
  fail "bootstrap.sh overwrote an existing miserc.local.toml"

home=$(new_home make)
run_make_bootstrap "$home" PROFILE=work >/dev/null 2>&1 || fail "make bootstrap PROFILE=work failed"
[[ $(cat "$home/.config/mise/miserc.local.toml" 2>/dev/null) == 'env = ["work"]' ]] ||
  fail "make bootstrap PROFILE=work does not select work"

home=$(new_home make-noprofile)
run_make_bootstrap "$home" >/dev/null 2>&1 && fail "make bootstrap without PROFILE succeeded"
[[ -e $home/.config/mise ]] && fail "make bootstrap without PROFILE still touched ~/.config/mise"

home=$(new_home noprofile)
run_bootstrap "$home" >/dev/null 2>&1 && fail "bootstrap.sh without a profile succeeded"
[[ -e $home/.config/mise ]] && fail "bootstrap.sh without a profile still touched ~/.config/mise"

# Anything in ~/.config/mise that is not already our link is left alone, and
# bootstrap.sh stops before changing anything.
home=$(new_home conflict-file)
mkdir -p "$home/.config/mise"
echo mine >"$home/.config/mise/config.toml"
run_bootstrap "$home" personal >/dev/null 2>&1 && fail "bootstrap.sh succeeded over a real config.toml"
[[ ! -L $home/.config/mise/config.toml && $(cat "$home/.config/mise/config.toml") == mine ]] ||
  fail "bootstrap.sh replaced a real config.toml"
[[ -L $home/.config/mise/config.work.toml ]] && fail "bootstrap.sh linked other files before stopping"
[[ -e $home/.config/mise/miserc.local.toml ]] && fail "bootstrap.sh wrote miserc.local.toml before stopping"
[[ -s $work/conflict-file-brew.log ]] && fail "bootstrap.sh ran brew before stopping"

home=$(new_home conflict-link)
mkdir -p "$home/.config/mise"
ln -s /elsewhere/config.work.toml "$home/.config/mise/config.work.toml"
run_bootstrap "$home" personal >/dev/null 2>&1 && fail "bootstrap.sh succeeded over a foreign link"
[[ $(readlink "$home/.config/mise/config.work.toml") == /elsewhere/config.work.toml ]] ||
  fail "bootstrap.sh replaced a link that points elsewhere"

home=$(new_home conflict-dir)
mkdir -p "$home/.config" "$work/conflict-dir-elsewhere"
ln -s "$work/conflict-dir-elsewhere" "$home/.config/mise"
run_bootstrap "$home" personal >/dev/null 2>&1 && fail "bootstrap.sh succeeded with ~/.config/mise as a link"
[[ -z $(ls -A "$work/conflict-dir-elsewhere") ]] || fail "bootstrap.sh wrote through a linked ~/.config/mise"

# --- mise config ------------------------------------------------------------

home=$(new_home mise)
run_bootstrap "$home" personal >/dev/null || true
for env in personal work; do
  other=$([[ $env == personal ]] && echo work || echo personal)
  loaded=$(HOME=$home MISE_DATA_DIR=$work/data MISE_CACHE_DIR=$work/cache MISE_STATE_DIR=$work/state \
    "$mise_bin" -E "$env" config ls 2>&1) || fail "mise -E $env config ls failed: $loaded"
  grep -q "config.$env.toml" <<<"$loaded" || fail "env $env does not load config.$env.toml"
  grep -q "config.$other.toml" <<<"$loaded" && fail "env $env also loads config.$other.toml"
done

# --- dotfiles ---------------------------------------------------------------

# [dotfiles] sources name ~/development/config-files, so put the repo there.
mkdir -p "$home/development"
ln -s "$repo" "$home/development/config-files"
# ~/.claude/settings.json as Claude Code and Orca leave it: a hook Orca added and a
# rule approved with "always allow". The merge must keep both.
mkdir -p "$home/.claude"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"orca-hook"}]}]},' \
  '"permissions":{"allow":["Bash(ls:*)"]}}' >"$home/.claude/settings.json"
# ~/.codex/config.toml as Codex writes it: its own notify hook and MCP server.
mkdir -p "$home/.codex"
printf '%s\n' 'notify = ["codex-notify"]' '' '[mcp_servers.node_repl]' 'command = "node"' >"$home/.codex/config.toml"
applied=$(HOME=$home MISE_DATA_DIR=$work/data MISE_CACHE_DIR=$work/cache MISE_STATE_DIR=$work/state \
  "$mise_bin" bootstrap --only dotfiles --yes 2>&1) || fail "mise bootstrap --only dotfiles failed: $applied"
for pair in .gitconfig:.gitconfig .config/git/ignore:git/ignore \
  .zshrc:.zshrc .config/sheldon/plugins.toml:sheldon/plugins.toml \
  .config/starship.toml:starship/starship.toml \
  .config/ghostty/config:ghostty/config .vimrc:.vimrc \
  .claude/CLAUDE.md:claude/CLAUDE.md .claude/statusline.sh:claude/statusline.sh \
  .codex/AGENTS.md:codex/AGENTS.md .codex/keybindings.json:codex/keybindings.json; do
  target=$home/${pair%%:*} source=$repo/${pair#*:}
  [[ -L $target && $(cd "$(dirname "$target")" && realpath "$(basename "$target")") == "$source" ]] ||
    fail "~/${pair%%:*} is not linked to ${pair#*:}"
done

# .zshrc is shared by every Mac.
zsh -n "$repo/.zshrc" 2>/dev/null || fail ".zshrc has a zsh syntax error"
grep -qE '/Users/|nyagasuki|\.zshrc_project|stree' "$repo/.zshrc" &&
  fail ".zshrc still holds something specific to one Mac"
for sdk in 'Visual Studio Code' google-cloud-sdk DOTNET_ROOT lmstudio unity/env; do
  grep -qF "$sdk" "$repo/.zshrc" || fail ".zshrc lost the $sdk setting shared by every Mac"
done
grep -qx 'export HOMEBREW_NO_INSTALL_UPGRADE=1' "$repo/.zshrc" ||
  fail ".zshrc lets brew install upgrade what is already installed"

# A Mac without some tool must still start a shell cleanly.
unguarded=$(grep -nE '^\s*(\.|source) ' "$repo/.zshrc" || true)
[[ -z $unguarded ]] || fail ".zshrc reads a file without checking it exists: $unguarded"
{ grep -qF 'if [[ -x "${HOME}/.local/bin/mise" ]]; then' "$repo/.zshrc" &&
  grep -qF 'eval "$("${HOME}/.local/bin/mise" activate zsh)"' "$repo/.zshrc"; } ||
  fail ".zshrc does not activate the mise.run install of mise only when it exists"
# cdr writes ~/.cache/chpwd-recent-dirs without creating ~/.cache.
grep -qF 'mkdir -p "${HOME}/.cache"' "$repo/.zshrc" || fail ".zshrc does not create ~/.cache for cdr"
# mise puts go on PATH only once activated, after this section would have run.
grep -qF 'go env GOPATH' "$repo/.zshrc" && fail ".zshrc still has the Go section mise makes dead"

# Order and safety.
# ~/bin and ~/.local/bin are writable by anything I run: they must not shadow system tools.
grep -qE 'PATH="?(\$\{HOME\}|\$HOME|~)/(bin|\.local/bin)' "$repo/.zshrc" &&
  fail ".zshrc puts a home directory first on PATH"
# compinit -C skips compaudit; the cache is rebuilt, and audited, once a day.
grep -qF '(N.mh+24)' "$repo/.zshrc" || fail ".zshrc never rebuilds or audits the completion cache"
grep -qF 'HISTORY_IGNORE=' "$repo/.zshrc" || fail ".zshrc writes commands with secrets to the history file"
# Plugins run in every shell: each is pinned, and syntax highlighting loads last (deferred).
# grep -c exits 1 when it counts 0; the count is still printed.
plugins=$(grep -c '^\[plugins\.' "$repo/sheldon/plugins.toml" || true)
pinned=$(grep -cE '^(tag|rev) = ' "$repo/sheldon/plugins.toml" || true)
[[ $plugins -gt 0 && $plugins == "$pinned" ]] || fail "sheldon pins $pinned of $plugins plugins"
awk '/^\[plugins\.zsh-syntax-highlighting\]/{p=1;next} /^\[/{p=0} p && /^apply = \["defer"\]/{ok=1} END{exit !ok}' \
  "$repo/sheldon/plugins.toml" || fail "zsh-syntax-highlighting is not deferred to load last"

# Claude Code rewrites settings.json, so only the shared keys are merged into a real file.
live=$home/.claude/settings.json
[[ -f $live && ! -L $live ]] || fail "~/.claude/settings.json is not a regular file"
python3 -I - "$live" "$repo/claude/settings.json" <<'PY' || fail "~/.claude/settings.json did not get the shared keys while keeping its own"
import json, sys
live, shared = (json.load(open(p)) for p in sys.argv[1:])
assert live["permissions"]["deny"] == shared["permissions"]["deny"], "shared deny missing"
assert live["permissions"]["allow"] == ["Bash(ls:*)"], "approved rule lost"
assert live["hooks"]["Stop"][0]["hooks"][0]["command"] == "orca-hook", "Orca hook lost"
assert live["statusLine"] == shared["statusLine"], "statusLine missing"
PY
python3 -I - "$repo/claude/settings.json" <<'PY' || fail "claude/settings.json holds keys that belong to one Mac"
import json, sys
s = json.load(open(sys.argv[1]))
# Rules approved on one Mac and hooks installed by Orca stay in that Mac's file.
assert not {"allow", "ask"} & set(s["permissions"]), "allow/ask are per Mac"
assert "orca" not in json.dumps(s.get("hooks", {})).lower(), "Orca installs its own hooks"
PY
python3 -I - "$repo/claude/settings.json" <<'PY' || fail "claude/settings.json lacks \$schema or keeps transcripts only 30 days"
import json, sys
s = json.load(open(sys.argv[1]))
# Editors validate it against the schema, and transcripts are kept instead of cleared after 30 days.
assert s.get("$schema") == "https://json.schemastore.org/claude-code-settings.json", "no $schema"
assert s.get("cleanupPeriodDays", 0) >= 36500, "transcripts are cleared"
PY
python3 -I - "$repo/claude/settings.json" <<'PY' || fail "claude/settings.json has keys Claude Code ignores or that the schema replaced"
import json, sys
s = json.load(open(sys.argv[1]))
# Top-level copies of these are not settings, so the restrictions would silently not apply.
assert not {"disableBypassPermissionsMode", "dangerouslyDisableSandbox", "voiceEnabled"} & set(s), "misplaced or legacy key"
assert s["permissions"].get("disableBypassPermissionsMode") == "disable", "bypass mode allowed"
assert s["sandbox"].get("allowUnsandboxedCommands") is False, "commands can leave the sandbox"
assert s.get("tui") == "fullscreen" and "CLAUDE_CODE_NO_FLICKER" not in s.get("env", {}), "use tui, not the env var"
PY
grep -q '{{' "$repo/claude/CLAUDE.md" && fail "claude/CLAUDE.md has an unfilled template placeholder"
# The global instructions live once, in codex/AGENTS.md; CLAUDE.md imports them and adds
# only what is Claude Code's own, so the two never drift apart.
[[ $(grep -v '^\s*$' "$repo/claude/CLAUDE.md" | head -1) == '@~/.codex/AGENTS.md' ]] ||
  fail "claude/CLAUDE.md does not start by importing ~/.codex/AGENTS.md"
grep -qx '# 開発スタイル' "$repo/codex/AGENTS.md" || fail "codex/AGENTS.md does not hold the shared instructions"
grep -qx '# 開発スタイル' "$repo/claude/CLAUDE.md" && fail "claude/CLAUDE.md repeats the shared instructions"
[[ -x $repo/claude/statusline.sh ]] || fail "claude/statusline.sh is not executable"
grep -qF '"brew:jq"' "$repo/mise/config.toml" || fail "statusline.sh needs jq, which nothing installs"

# Codex rewrites config.toml too (paths, MCP servers): only [desktop] is shared.
live=$home/.codex/config.toml
[[ -f $live && ! -L $live ]] || fail "~/.codex/config.toml is not a regular file"
grep -qx 'followUpQueueMode = "steer"' "$live" 2>/dev/null || fail "~/.codex/config.toml did not get the shared [desktop] keys"
{ grep -qx 'notify = \["codex-notify"\]' "$live" 2>/dev/null &&
  grep -qx '\[mcp_servers.node_repl\]' "$live" 2>/dev/null; } ||
  fail "~/.codex/config.toml lost what Codex wrote there"
grep -qE '^(notify|\[mcp_servers|\[plugins|\[marketplaces)|/Users/' "$repo/codex/config.toml" 2>/dev/null &&
  fail "codex/config.toml holds what Codex writes for itself"
# AGENTS.md is for Codex: no Claude Code tools, no unfilled placeholders.
grep -qE 'AskUserQuestion|\{\{' "$repo/codex/AGENTS.md" 2>/dev/null && fail "codex/AGENTS.md names a Claude Code tool or a placeholder"
# Orca has no settings file to manage, and scripts/bootstrap.sh installs the app:
# as a mise package its tap cask would need Ruby 3 on every new Mac.
grep -qF 'stablyai/orca' "$repo/mise/config.toml" && fail "mise/config.toml declares Orca, which mise cannot read without Ruby 3"

# Ghostty: one theme (a later one silently wins), and every font is installed by a cask.
[[ $(grep -c '^theme = ' "$repo/ghostty/config" 2>/dev/null || true) == 1 ]] ||
  fail "ghostty/config does not set exactly one theme"
while IFS= read -r font; do
  cask=font-$(tr '[:upper:] ' '[:lower:]-' <<<"$font")
  grep -qF "\"brew-cask:$cask\"" "$repo/mise/config.toml" || fail "ghostty font $font has no $cask in mise/config.toml"
done < <(sed -n 's/^font-family = //p' "$repo/ghostty/config" 2>/dev/null)
[[ -n $(sed -n 's/^font-family = //p' "$repo/ghostty/config" 2>/dev/null) ]] || fail "ghostty/config names no font"

# lazygit reads its config from Application Support on macOS (a path with a space).
target="$home/Library/Application Support/lazygit/config.yml"
[[ -L $target && $(cd "$(dirname "$target")" && realpath "$(basename "$target")") == "$repo/lazygit/config.yml" ]] ||
  fail "lazygit's config.yml is not linked to lazygit/config.yml"
# A background fetch would ask Bitwarden to approve the SSH key every minute.
grep -qx '  autoFetch: false' "$repo/lazygit/config.yml" 2>/dev/null ||
  fail "lazygit/config.yml does not turn off git.autoFetch"

# git as it would run in that HOME, with no outside config leaking in.
home_git() {
  env -u GIT_CONFIG_GLOBAL -u XDG_CONFIG_HOME HOME="$home" GIT_CONFIG_NOSYSTEM=1 git "$@"
}
# grep.lineNumber is true in .gitconfig; the local file turns it off.
printf '[user]\n\temail = local@example.com\n[grep]\n\tlineNumber = false\n' >"$home/.gitconfig.local"
# Without --global, as git itself looks it up (--global alone skips includes).
[[ $(home_git -C "$work" config user.email) == local@example.com ]] ||
  fail ".gitconfig does not include ~/.gitconfig.local"
[[ $(home_git -C "$work" config grep.lineNumber) == false ]] ||
  fail "~/.gitconfig.local cannot override a setting in .gitconfig"
# One [include], last, with paths under ~ so the link to this repo is not followed.
[[ $(grep -c '^\[include\]' "$repo/.gitconfig") == 1 && $(grep '^\[' "$repo/.gitconfig" | tail -1) == '[include]' ]] ||
  fail ".gitconfig does not have a single [include] at the end"
grep -qE '^\s*path = [^~]' "$repo/.gitconfig" && fail ".gitconfig includes a path not under ~"
# This repository is public: who I am stays in ~/.gitconfig.local.
grep -q '^\[user\]' "$repo/.gitconfig" && fail ".gitconfig declares [user]"
# The global ignore is git's default ~/.config/git/ignore, so no core.excludesfile.
[[ -z $(home_git -C "$work" config core.excludesfile || true) ]] ||
  fail ".gitconfig sets core.excludesfile instead of using ~/.config/git/ignore"
home_git init -q "$work/ignore-repo"
touch "$work/ignore-repo/.DS_Store"
home_git -C "$work/ignore-repo" check-ignore -q .DS_Store || fail "git does not ignore .DS_Store globally"
# Only files that are junk everywhere are ignored globally; a repository's tmp/ is not.
home_git -C "$work/ignore-repo" check-ignore -q tmp/x && fail "tmp/ is ignored in every repository"

# Settings taken from shibayu36/config-file, as git resolves them.
for pair in \
  pull.rebase=true pull.autoStash=true branch.autoSetupRebase=always \
  rebase.autoSquash=true rebase.autoStash=true \
  merge.conflictStyle=zdiff3 push.default=current \
  diff.colorMoved=default core.quotePath=false \
  color.ui=auto color.diff=auto color.status=auto color.branch=auto; do
  key=${pair%%=*} want=${pair#*=}
  # git config exits 1 for an unset key; that is a failed check, not a crash.
  got=$(home_git -C "$work" config "$key" || true)
  [[ $got == "$want" ]] || fail "git config $key is '$got', want '$want'"
done
[[ -z $(home_git -C "$work" config merge.ff || true) ]] || fail "merge.ff is set; it was left at git's default"
# Only gh answers for github.com: the empty helper drops osxkeychain there.
helpers=$(home_git -C "$work" config --get-all credential.https://github.com.helper || true)
[[ $helpers == $'\n!/opt/homebrew/bin/gh auth git-credential' ]] ||
  fail "github.com HTTPS credentials do not come only from gh: $helpers"
# Elsewhere osxkeychain comes from git's own gitconfig (system config is off here).
others=$(home_git -C "$work" config --get-urlmatch credential.helper https://example.com || true)
[[ -z $others ]] || fail ".gitconfig adds a credential helper for every host: $others"
# column.diff is not a git setting; diff colors belong to [color].
[[ -z $(home_git -C "$work" config column.diff || true) ]] || fail "diff is set under [column] instead of [color]"

# --- ssh --------------------------------------------------------------------

# ~/.ssh/config is not managed here; README.md has it include ssh/config first.
printf 'Include %s\n' "$repo/ssh/config" >"$work/ssh_config"
# Keys come only from the Bitwarden agent: no key files, for any host.
grep -qiE '^[[:space:]]*(IdentityFile|IdentitiesOnly)' "$repo/ssh/config" &&
  fail "ssh/config names key files instead of leaving keys to the agent"
for host in github.com bitbucket.org gitlab.com example.com; do
  resolved=$(ssh -T -F "$work/ssh_config" -G "$host")
  grep -qx 'identityagent .*/\.bitwarden-ssh-agent\.sock' <<<"$resolved" ||
    fail "ssh $host does not use the Bitwarden agent"
  # Reusing one connection means one Bitwarden approval per host, not per git command.
  grep -qx 'controlmaster auto' <<<"$resolved" || fail "ssh $host does not reuse connections"
  grep -qx 'controlpath .*/\.ssh/cm-.*' <<<"$resolved" || fail "ssh $host has no ControlPath under ~/.ssh"
  grep -qx 'serveraliveinterval 10' <<<"$resolved" || fail "ssh $host sends no keepalive every 10s"
  grep -qx 'serveralivecountmax 12' <<<"$resolved" || fail "ssh $host does not give up after 12 missed keepalives"
done

# --- tasks ------------------------------------------------------------------

# This repository's tasks are make's: make is on a new Mac from the start, while just
# (installed for other repositories) only arrives with mise bootstrap.
[[ ! -e $repo/justfile ]] || fail "justfile exists; this repository's tasks belong in the Makefile"
[[ $(sed -n 's/^\([a-z][a-z-]*\):.*/\1/p' "$repo/Makefile" | sort | tr '\n' ' ') == "bootstrap lint plan status sync " ]] ||
  fail "Makefile does not have exactly bootstrap, lint, plan, status and sync"
grep -qx '\.PHONY: bootstrap lint plan status sync' "$repo/Makefile" || fail "Makefile targets are not all .PHONY"
grep -qF '"brew:shellcheck"' "$repo/mise/config.toml" || fail "make lint needs shellcheck, which nothing installs"
# What each target would run, without running it.
dry() { make -s -C "$repo" -n "$1" 2>/dev/null || true; }
[[ $(dry plan) == 'mise bootstrap --dry-run' ]] || fail "make plan does not dry-run mise bootstrap"
[[ $(dry status) == 'mise bootstrap status' ]] || fail "make status does not show mise bootstrap status"
[[ $(dry sync) == $'git pull\nmise bootstrap' ]] || fail "make sync does not pull and then bootstrap"
lint=$(dry lint)
for script in scripts/bootstrap.sh scripts/tests/test-bootstrap.sh claude/statusline.sh; do
  grep -q "^shellcheck .*$script" <<<"$lint" || fail "make lint does not shellcheck $script"
done
grep -q '^gitleaks ' <<<"$lint" || fail "make lint does not look for secrets"

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
