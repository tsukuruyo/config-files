#!/usr/bin/env bash
# Run bootstrap.sh and mise against a throwaway HOME and check the result.
# Usage: scripts/tests/test-bootstrap.sh
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
# not on PATH, as right after installing it. curl is a stub that only logs, so
# any download attempt shows up in $work/<name>-curl.log.
new_home() {
  local home=$work/$1
  mkdir -p "$home/.local/bin" "$work/$1-bin" "$work/$1-prefix/bin"
  printf '#!/bin/sh\nexit 0\n' >"$work/$1-prefix/bin/brew"
  printf '#!/bin/sh\necho "curl $*" >>"%s"\n' "$work/$1-curl.log" >"$work/$1-bin/curl"
  printf '#!/bin/sh\nexit 0\n' >"$home/.local/bin/mise"
  chmod +x "$work/$1-prefix/bin/brew" "$work/$1-bin/curl" "$home/.local/bin/mise"
  echo "$home"
}

run_bootstrap() {
  local home=$1 name
  name=$(basename "$home")
  shift
  HOME=$home HOMEBREW_PREFIX=$work/$name-prefix PATH=$work/$name-bin:/usr/bin:/bin \
    "$repo/scripts/bootstrap.sh" "$@"
}

# make bootstrap PROFILE=..., as README.md runs it on a new Mac.
run_make_bootstrap() {
  local home=$1 name
  name=$(basename "$home")
  shift
  HOME=$home HOMEBREW_PREFIX=$work/$name-prefix PATH=$work/$name-bin:/usr/bin:/bin \
    make -s -C "$repo" bootstrap "$@"
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
applied=$(HOME=$home MISE_DATA_DIR=$work/data MISE_CACHE_DIR=$work/cache MISE_STATE_DIR=$work/state \
  "$mise_bin" bootstrap --only dotfiles --yes 2>&1) || fail "mise bootstrap --only dotfiles failed: $applied"
for pair in .gitconfig:.gitconfig .config/git/ignore:git/ignore; do
  target=$home/${pair%%:*} source=$repo/${pair#*:}
  [[ -L $target && $(cd "$(dirname "$target")" && realpath "$(basename "$target")") == "$source" ]] ||
    fail "~/${pair%%:*} is not linked to ${pair#*:}"
done

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

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
