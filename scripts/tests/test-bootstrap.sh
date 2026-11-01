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

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
