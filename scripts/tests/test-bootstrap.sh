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
for f in config.toml config.dev.toml config.personal.toml config.work.toml config.shop.toml; do
  link=$home/.config/mise/$f
  [[ -L $link && $(readlink "$link") == "$repo/mise/$f" ]] || fail "~/.config/mise/$f is not linked to mise/$f"
done
# The dev Macs layer config.dev.toml under their own file.
[[ $(cat "$home/.config/mise/miserc.local.toml" 2>/dev/null) == 'env = ["dev", "personal"]' ]] ||
  fail "miserc.local.toml does not select dev and personal"
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

# The shop Mac gets the shared layer and its own, without the dev layer or Orca.
home=$(new_home shop)
run_bootstrap "$home" shop >/dev/null || fail "bootstrap.sh shop exited with $?"
[[ $(cat "$home/.config/mise/miserc.local.toml" 2>/dev/null) == 'env = ["shop"]' ]] ||
  fail "miserc.local.toml does not select shop only"
grep -q 'orca' "$work/shop-brew.log" 2>/dev/null && fail "bootstrap.sh installed Orca on the shop Mac"

mkdir -p "$home/.config/mise"
echo 'env = ["kept"]' >"$home/.config/mise/miserc.local.toml"
run_bootstrap "$home" work >/dev/null || fail "second bootstrap.sh run exited with $?"
[[ $(cat "$home/.config/mise/miserc.local.toml") == 'env = ["kept"]' ]] ||
  fail "bootstrap.sh overwrote an existing miserc.local.toml"

home=$(new_home make)
run_make_bootstrap "$home" PROFILE=work >/dev/null 2>&1 || fail "make bootstrap PROFILE=work failed"
[[ $(cat "$home/.config/mise/miserc.local.toml" 2>/dev/null) == 'env = ["dev", "work"]' ]] ||
  fail "make bootstrap PROFILE=work does not select dev and work"

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
# Each Mac's envs, as bootstrap.sh writes them: every file layers on config.toml in this order,
# and nothing else is read. The shop Mac never sees config.dev.toml.
for envs in dev,personal dev,work shop; do
  loaded=$(HOME=$home MISE_DATA_DIR=$work/data MISE_CACHE_DIR=$work/cache MISE_STATE_DIR=$work/state \
    MISE_ENV=$envs "$mise_bin" config ls 2>&1) || fail "MISE_ENV=$envs mise config ls failed: $loaded"
  files=$(sed -n 's|^[^ ]*/\(config[.a-z]*\.toml\) .*|\1|p' <<<"$loaded" | tr '\n' ' ')
  want="config.toml "
  for env in ${envs//,/ }; do want+="config.$env.toml "; done
  [[ $files == "$want" ]] || fail "MISE_ENV=$envs loads '$files', want '$want'"
done
# Apps for every Mac, the shop one included: the shell, git, the terminal and a few apps.
declared() { grep -qE "^\"$2\" = \"latest\"" "$repo/mise/$1" 2>/dev/null; }
for pkg in brew:{fzf,gh,git,git-delta,mas,pam-reattach,ripgrep,sheldon,starship} \
  brew-cask:{bitwarden,ghostty,google-chrome,google-japanese-ime,keka,raycast,zoom,font-udev-gothic-nf}; do
  declared config.toml "$pkg" || fail "mise/config.toml does not declare $pkg"
done
# The dev tools, for the personal and work Macs only.
for pkg in brew:{ghq,git-filter-repo,git-lfs,gitleaks,jq,just,lazygit,shellcheck,sops} \
  brew-cask:{claude,chatgpt,arc,visual-studio-code,orbstack} \
  brew-cask:{notion,linear,pearcleaner,sequel-ace} \
  brew-cask:{tailscale-app,ngrok,libreoffice,google-gemini} \
  mas:{497799835,937984704,1452453066,1532419400,457622435,1342896380}; do
  declared config.dev.toml "$pkg" || fail "mise/config.dev.toml does not declare $pkg"
  declared config.toml "$pkg" && fail "$pkg is declared for the shop Mac too"
done
# Languages are dev tools too: config.toml installs none on the shop Mac.
grep -q '^\[tools\]' "$repo/mise/config.toml" && fail "mise/config.toml installs languages on every Mac"
for tool in node python ruby pnpm; do
  grep -q "^$tool = " "$repo/mise/config.dev.toml" || fail "mise/config.dev.toml does not install $tool"
done
# The shop Mac adds LINE, as the personal one does: the two envs never load together.
declared config.shop.toml mas:539883307 || fail "mise/config.shop.toml does not declare LINE"
# Dotfiles for the dev tools go with them; the shell, git and the terminal are for every Mac.
for key in .claude/ .codex/ Code/User/ .npmrc .yarnrc.yml pnpm/config.yaml lazygit/config.yml; do
  grep -F -- "$key" "$repo/mise/config.toml" | grep -q '^"~' && fail "mise/config.toml links $key on the shop Mac too"
  grep -F -- "$key" "$repo/mise/config.dev.toml" | grep -q '^"~' || fail "mise/config.dev.toml does not link $key"
done
for key in .gitconfig git/ignore .zshrc sheldon/plugins.toml starship.toml ghostty/config .vimrc; do
  grep -F -- "$key" "$repo/mise/config.toml" | grep -q '^"~' || fail "mise/config.toml does not link $key for every Mac"
done
# Sequel Ace comes from its cask, not also from the App Store.
grep -qF '"mas:1518036000"' "$repo"/mise/config*.toml && fail "Sequel Ace is declared from the App Store as well as its cask"
for pkg in brew-cask:{obsidian,lm-studio,comfy,unity-hub,godot,epic-games,adobe-creative-cloud,google-drive,jetbrains-toolbox} \
  mas:{975937182,539883307,905953485,904280696,585829637,1278508951,310633997,1380563956}; do
  declared config.personal.toml "$pkg" || fail "mise/config.personal.toml does not declare $pkg"
done
for pkg in brew:{git,git-delta,ripgrep,pam-reattach}; do
  declared config.toml "$pkg" || fail "mise/config.toml does not declare $pkg"
done
# The Canon Utilities here are the inkjet scanner tools, not the camera's EOS Utility.
grep -qF '"brew-cask:canon-eos-utility"' "$repo"/mise/config*.toml && fail "mise declares Canon's camera utility"
# .NET is a language runtime, so it is a mise tool, on the personal Mac only.
grep -q '^dotnet = ' "$repo/mise/config.personal.toml" || fail "mise/config.personal.toml does not install .NET"
grep -q '^dotnet' "$repo/mise/config.toml" && fail "mise/config.toml installs .NET on every Mac"
grep -qF '"brew:dotnet' "$repo"/mise/config*.toml && fail "mise declares .NET as a Homebrew package"
grep -qF '"brew-cask:dotnet' "$repo"/mise/config*.toml && fail "mise declares .NET as a cask"
grep -qF '"brew-cask:ngrok"' "$repo/mise/config.personal.toml" && fail "ngrok is declared for the personal Mac only"
for pkg in brew-cask:{slack,microsoft-teams}; do
  declared config.work.toml "$pkg" || fail "mise/config.work.toml does not declare $pkg"
done
for cask in google-drive jetbrains-toolbox; do
  grep -qF "\"brew-cask:$cask\"" "$repo/mise/config.toml" && fail "$cask is declared for every Mac"
done
grep -q 'TODO' "$repo/mise/config.personal.toml" && fail "mise/config.personal.toml still has a TODO"
# Every App Store id says which app it is.
grep -E '^"mas:' "$repo"/mise/config*.toml | grep -v '" # ' && fail "an App Store id has no app name"
# The dotfile merges need a recent mise; an older one must stop instead of linking settings.json.
min=$(sed -n 's/^min_version = "\(.*\)"$/\1/p' "$repo/mise/config.toml")
have=$("$mise_bin" --version 2>/dev/null | awk '{print $1}')
[[ -n $min ]] || fail "mise/config.toml sets no min_version"
[[ -z $min || $(printf '%s\n%s\n' "$min" "$have" | sort -V | head -1) == "$min" ]] ||
  fail "min_version $min is newer than the mise under test ($have)"

# macOS settings, read from the file rather than applied: defaults write to the real
# user's preferences whatever HOME is.
cfg() {
  MISE_DATA_DIR=$work/data MISE_CACHE_DIR=$work/cache MISE_STATE_DIR=$work/state \
    "$mise_bin" config get -f "$repo/mise/config.toml" "$1" 2>/dev/null || true
}
for pair in \
  bootstrap.macos.defaults.NSGlobalDomain.KeyRepeat=2 \
  bootstrap.macos.defaults.NSGlobalDomain.InitialKeyRepeat=15 \
  bootstrap.macos.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled=false \
  bootstrap.macos.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled=false \
  bootstrap.macos.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled=false \
  'bootstrap.macos.defaults."com.apple.AppleMultitouchTrackpad".Clicking=true' \
  'bootstrap.macos.defaults."com.apple.driver.AppleBluetoothMultitouch.trackpad".Clicking=true' \
  'bootstrap.macos.defaults."com.apple.dock".autohide=true' \
  'bootstrap.macos.defaults."com.apple.finder".AppleShowAllFiles=true' \
  'bootstrap.macos.defaults."com.apple.finder".FXPreferredViewStyle=Nlsv'; do
  key=${pair%=*} want=${pair##*=}
  got=$(cfg "$key")
  [[ $got == "$want" || $got == "\"$want\"" ]] || fail "mise/config.toml $key is '$got', want '$want'"
done
# Left at macOS's defaults on purpose: period substitution, spelling correction, fn keys,
# natural scrolling, swipe navigation, screenshots and the Ctrl+Space input source shortcut.
[[ $(cfg bootstrap.macos.defaults.NSGlobalDomain | grep -c ' = ' || true) == 6 ]] ||
  fail "NSGlobalDomain sets keys other than the six chosen"
[[ -z $(cfg 'bootstrap.macos.defaults."com.apple.screencapture"') ]] || fail "screenshot settings were not chosen"
# Printed as a table, a float keeps its .0: macOS checks the type, and a single value would print 3.
macos=$(cfg bootstrap.macos)
grep -qx '"com.apple.trackpad.scaling" = 3.0' <<<"$macos" || fail "trackpad scaling is not the float 3.0"
# macOS stores the key repeat rates as floats, and turns even `defaults write -int` into one.
# [bootstrap.macos.keyboard] writes integers, so it saw them differ and rewrote them every run.
for rate in 'KeyRepeat = 2.0' 'InitialKeyRepeat = 15.0'; do
  grep -qx "$rate" <<<"$macos" || fail "key repeat is not the float in '$rate'"
done
grep -q 'key_repeat' <<<"$macos" && fail "key repeat is set in [bootstrap.macos.keyboard], whose integers macOS stores as floats"
# Writing accessibility settings needs Full Disk Access, and without it mise bootstrap
# stops there; README.md has them set by hand, as shibayu36/config-file does.
grep -q 'universalaccess' <<<"$macos" && fail "mise/config.toml sets accessibility settings, which need Full Disk Access"
# Tap to click for the login window too lives in the current host's NSGlobalDomain.
entries=$(sed -n '/^\[\[defaults_entries\]\]/,$p' <<<"$macos")
{ grep -q 'com.apple.mouse.tapBehavior' <<<"$entries" && grep -q 'host = "current"' <<<"$entries"; } ||
  fail "tap to click is not set for the current host"
grep -q 'symbolichotkeys' <<<"$entries" && fail "keyboard shortcuts were not chosen"

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
  .claude/keybindings.json:claude/keybindings.json \
  .npmrc:.npmrc .yarnrc.yml:.yarnrc.yml Library/Preferences/pnpm/config.yaml:pnpm/config.yaml \
  .codex/AGENTS.md:codex/AGENTS.md .codex/keybindings.json:codex/keybindings.json; do
  target=$home/${pair%%:*} source=$repo/${pair#*:}
  [[ -L $target && $(cd "$(dirname "$target")" && realpath "$(basename "$target")") == "$source" ]] ||
    fail "~/${pair%%:*} is not linked to ${pair#*:}"
done

# npm, yarn and pnpm wait as long as mise's minimum_release_age before using a new release,
# each in its own unit: npm in days, yarn as a duration, pnpm in minutes. pnpm 11+ reads only
# auth and registry settings from .npmrc, so its own config.yaml carries the age.
days=$(sed -n 's/^minimum_release_age = "\([0-9]*\)d"$/\1/p' "$repo/mise/config.toml")
[[ -n $days ]] || fail "mise/config.toml has no minimum_release_age in days"
grep -qx "min-release-age=$days" "$repo/.npmrc" 2>/dev/null || fail ".npmrc does not wait $days days"
grep -qx "npmMinimalAgeGate: \"${days}d\"" "$repo/.yarnrc.yml" 2>/dev/null || fail ".yarnrc.yml does not wait $days days"
grep -qx "minimumReleaseAge: $((days * 24 * 60))" "$repo/pnpm/config.yaml" 2>/dev/null || fail "pnpm/config.yaml does not wait $days days"
grep -qE 'min-release-age` は ?pnpm ?が読む' "$repo/README.md" && fail "README.md says pnpm reads .npmrc's release age"

# .zshrc is shared by every Mac.
zsh -n "$repo/.zshrc" 2>/dev/null || fail ".zshrc has a zsh syntax error"
grep -qE '/Users/|nyagasuki|\.zshrc_project|stree' "$repo/.zshrc" &&
  fail ".zshrc still holds something specific to one Mac"
for sdk in google-cloud-sdk lmstudio unity/env DOTNET_CLI_TELEMETRY_OPTOUT; do
  grep -qF "$sdk" "$repo/.zshrc" || fail ".zshrc lost the $sdk setting shared by every Mac"
done
# The visual-studio-code cask puts code in Homebrew's bin, so the app bundle is not on PATH.
grep -qF 'Visual Studio Code.app' "$repo/.zshrc" && fail ".zshrc adds VS Code's app bundle to PATH"
# Tools installed by hand on some Macs only take effect where their directory exists:
# a DOTNET_ROOT pointing at nothing misleads a .NET installed elsewhere.
# mise sets DOTNET_ROOT for the .NET it installs, and would adopt one already in the environment.
grep -v '^[[:space:]]*#' "$repo/.zshrc" | grep -qF 'DOTNET_ROOT' && fail ".zshrc sets DOTNET_ROOT, which mise manages"
grep -qF 'if [[ -d "${HOME}/.lmstudio/bin" ]]; then' "$repo/.zshrc" ||
  fail ".zshrc adds LM Studio's bin to PATH without checking it exists"
grep -qx 'export HOMEBREW_NO_INSTALL_UPGRADE=1' "$repo/.zshrc" ||
  fail ".zshrc lets brew install upgrade what is already installed"
# Settings for one Mac go in ~/.zshrc.local, sourced last so they can override the shared ones.
[[ $(grep -v '^[[:space:]]*#' "$repo/.zshrc" | grep -v '^[[:space:]]*$' | tail -3 | head -1) == *'.zshrc.local'* ]] ||
  fail ".zshrc does not source ~/.zshrc.local at the end"

# A Mac without some tool must still start a shell cleanly.
# A sourced file is checked with -f on the line before, or inline as `[[ -f f ]] && . f`.
unguarded=$(awk '
  /^[[:space:]]*(\.|source) / {
    file = $2
    if (index(prev, "-f") == 0 || index(prev, file) == 0) print NR ": " $0
  }
  { prev = $0 }' "$repo/.zshrc")
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
python3 -I - "$repo/claude/settings.json" <<'PY' || fail "claude/settings.json breaks a rule for what is shared"
import json, sys
s = json.load(open(sys.argv[1]))
# Rules approved on the spot (allow) and hooks installed by Orca stay in that Mac's file.
assert "allow" not in s["permissions"], "allow is per Mac"
# Pushing waits for a yes each time rather than being impossible: Anthropic's own
# example puts git push under ask.
assert "Bash(git push *)" in s["permissions"].get("ask", []), "git push does not ask first"
assert not any("git push" in r for r in s["permissions"]["deny"]), "git push is denied outright"
# ask replaces each Mac's list wholesale on merge, so every rule the user asks on lives here.
for rule in ["Bash(brew install *)", "Bash(gh pr create *)", "Bash(git rebase *)", "Bash(git reset *)",
             "Bash(rm *)", "Bash(ssh *)", "Read(~/.claude/**)"]:
    assert rule in s["permissions"]["ask"], f"{rule} does not ask first"
deny = s["permissions"]["deny"]
# Bash rules match each subcommand on its own and redirects go to file rules, so a rule
# with a pipe or starting with > never matches; argument patterns are easy to sidestep.
assert not [r for r in deny if "|" in r or r.startswith("Bash(>")], "a deny rule can never match"
assert not [r for r in deny if r.startswith("Bash(curl -")], "a curl argument rule stands in for the sandbox"
assert not any("git reset" in r for r in deny), "git reset is denied rather than asked"
# A single leading / is relative to the settings file (~/.claude here); // is the real root.
import re
assert not [r for r in deny + s["permissions"]["ask"] if re.match(r"(Read|Edit)\(/[^/]", r)], "a path rule meant to be absolute starts with one /"
assert "Edit(//etc/**)" in deny, "/etc is not protected from edits"
# Bypass mode is disabled, so skipping its warning means nothing.
assert "skipDangerousModePermissionPrompt" not in s, "skipDangerousModePermissionPrompt is set"
assert s["permissions"].get("disableBypassPermissionsMode") == "disable"
assert s["enabledPlugins"].get("ui-ux-pro-max@ui-ux-pro-max-skill") is False, "ui-ux-pro-max is not recorded as off"
assert "ui-ux-pro-max-skill" in s["extraKnownMarketplaces"], "ui-ux-pro-max's marketplace is missing"
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
grep -qx '# 全般' "$repo/codex/AGENTS.md" || fail "codex/AGENTS.md does not hold the shared instructions"
grep -qx '# 全般' "$repo/claude/CLAUDE.md" && fail "claude/CLAUDE.md repeats the shared instructions"
# Both tools load the two files together: Anthropic keeps them under 200 lines, and
# both vendors say capitalised emphasis makes newer models over-apply a rule.
(($(cat "$repo/codex/AGENTS.md" "$repo/claude/CLAUDE.md" | wc -l) < 200)) || fail "the global instructions are 200 lines or more"
grep -qE '\b(IMPORTANT|MUST|ALWAYS|NEVER|YOU MUST)\b' "$repo/codex/AGENTS.md" "$repo/claude/CLAUDE.md" &&
  fail "the global instructions use capitalised emphasis"
# Global rules come first in the prompt, so they say that the repository's rules and chat win.
grep -qE 'リポジトリの.*(AGENTS|CLAUDE).*優先' "$repo/codex/AGENTS.md" || fail "codex/AGENTS.md does not yield to repository rules"
# The rules sources rank highest: verify before saying done, and never game the tests.
grep -q '実行したコマンドと結果' "$repo/codex/AGENTS.md" || fail "codex/AGENTS.md does not ask for evidence of verification"
grep -q 'アサーションを弱め' "$repo/codex/AGENTS.md" || fail "codex/AGENTS.md does not forbid weakening tests"
# The note for people reading claude/CLAUDE.md is an HTML comment, which Claude Code strips.
grep -q '^共通の指示は' "$repo/claude/CLAUDE.md" && fail "claude/CLAUDE.md loads its maintainer note as an instruction"
[[ -x $repo/claude/statusline.sh ]] || fail "claude/statusline.sh is not executable"
grep -qF '"brew:jq"' "$repo/mise/config.dev.toml" || fail "statusline.sh needs jq, which nothing installs"

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
# lazygit shows diffs through delta too, without delta's own pager.
grep -qx '    - command: delta --paging=never' "$repo/lazygit/config.yml" 2>/dev/null ||
  fail "lazygit/config.yml does not render diffs with delta"

# VS Code keeps its settings in Application Support, and Settings Sync is off.
for f in settings.json keybindings.json; do
  target="$home/Library/Application Support/Code/User/$f"
  [[ -L $target && $(cd "$(dirname "$target")" && realpath "$(basename "$target")") == "$repo/vscode/$f" ]] ||
    fail "VS Code's $f is not linked to vscode/$f"
done
# These casks clone all of google/fonts (several GB), and mise bootstrap stalls on them.
for cask in font-biz-udgothic font-google-sans-code; do
  grep -qF "\"brew-cask:$cask\"" "$repo"/mise/config*.toml && fail "mise declares $cask, which clones all of google/fonts"
done
# Like Ghostty's, the editor font comes from a cask.
vscode_font=$(sed -n "s/.*\"editor.fontFamily\": \"'\([^']*\)'.*/\1/p" "$repo/vscode/settings.json")
[[ -n $vscode_font ]] || fail "vscode/settings.json names no editor font"
grep -qF "\"brew-cask:font-$(tr '[:upper:] ' '[:lower:]-' <<<"$vscode_font")\"" "$repo/mise/config.toml" ||
  fail "VS Code font $vscode_font has no cask in mise/config.toml"

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
# Diffs, logs and git add -p go through delta.
[[ $(home_git -C "$work" config core.pager || true) == delta ]] || fail "git does not page through delta"
[[ $(home_git -C "$work" config interactive.diffFilter || true) == 'delta --color-only' ]] ||
  fail "git add -p does not show delta's diff"
[[ $(home_git -C "$work" config delta.navigate || true) == true ]] || fail "delta cannot jump between files with n/N"
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
[[ $(sed -n 's/^\([a-z][a-z-]*\):.*/\1/p' "$repo/Makefile" | sort | tr '\n' ' ') == "bootstrap lint plan skills status sync " ]] ||
  fail "Makefile does not have exactly bootstrap, lint, plan, skills, status and sync"
grep -qx '\.PHONY: bootstrap lint plan skills status sync' "$repo/Makefile" || fail "Makefile targets are not all .PHONY"
grep -qF '"brew:shellcheck"' "$repo/mise/config.dev.toml" || fail "make lint needs shellcheck, which nothing installs"
# What each target would run, without running it.
dry() { make -s -C "$repo" -n "$1" 2>/dev/null || true; }
[[ $(dry plan) == 'mise bootstrap --dry-run' ]] || fail "make plan does not dry-run mise bootstrap"
[[ $(dry status) == 'mise bootstrap status' ]] || fail "make status does not show mise bootstrap status"
[[ $(dry sync) == $'git pull\nmise bootstrap' ]] || fail "make sync does not pull and then bootstrap"
[[ $(dry skills) == scripts/install-skills.sh ]] || fail "make skills does not run scripts/install-skills.sh"
lint=$(dry lint)
for script in scripts/bootstrap.sh scripts/install-skills.sh scripts/tests/test-bootstrap.sh claude/statusline.sh; do
  grep -q "^shellcheck .*$script" <<<"$lint" || fail "make lint does not shellcheck $script"
done
grep -q '^gitleaks ' <<<"$lint" || fail "make lint does not look for secrets"

# --- skills -----------------------------------------------------------------

# install-skills.sh runs the skills CLI through pnpx; a stub logs what it was asked.
mkdir -p "$work/skills-bin"
printf '#!/bin/sh\necho "$*" >>"%s"\n' "$work/pnpx.log" >"$work/skills-bin/pnpx"
chmod +x "$work/skills-bin/pnpx"
{ [[ -x $repo/scripts/install-skills.sh ]] && PATH="$work/skills-bin:$PATH" "$repo/scripts/install-skills.sh" >/dev/null 2>&1; } ||
  fail "scripts/install-skills.sh did not run"
calls=$(cat "$work/pnpx.log" 2>/dev/null || true)
grep -qE -- "--skill( [a-z-]+)* empirical-prompt-tuning( |$)" <<<"$calls" ||
  fail "install-skills.sh does not install empirical-prompt-tuning"
# Orca installs and updates its own skill.
grep -q orca-cli <<<"$calls" && fail "install-skills.sh installs orca-cli, which Orca manages"
# A skill turned off in claude/settings.json is not worth installing on every Mac.
while IFS= read -r off; do
  [[ -z $off ]] && continue
  grep -qE -- "--skill( [a-z-]+)* $off( |$)" <<<"$calls" && fail "install-skills.sh installs $off, which claude/settings.json turns off"
done < <(jq -r '.skillOverrides // {} | to_entries[] | select(.value == "off") | .key' "$repo/claude/settings.json")
for skill in grill-me find-skills stop-slop; do
  grep -qE -- "--skill( [a-z-]+)* $skill( |$)" <<<"$calls" && fail "install-skills.sh still installs $skill"
done
# Global, for both agents, without prompts, and every source pinned to a commit.
while IFS= read -r call; do
  [[ -z $call ]] && continue
  [[ $call =~ ^skills\ add\ [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9a-f]{40}\ -g\ -a\ claude-code\ codex\ -y\ --skill\  ]] ||
    fail "install-skills.sh call is not pinned, global and for both agents: $call"
done <<<"$calls"
[[ -n $calls ]] || fail "install-skills.sh called nothing"

# --- repository rules --------------------------------------------------------

# The global instructions leave the documentation language to each repository.
grep -q '^## 言語' "$repo/AGENTS.md" || fail "AGENTS.md does not say which language this repository writes in"
# The global instructions now defer to each repository, so make is no exception to them.
grep -q '例外' "$repo/AGENTS.md" && fail "AGENTS.md still calls the Makefile an exception to the global instructions"
# A comment above a group of packages describes every line under it.
sed -n '/^# These run a .pkg installer/,/^$/p' "$repo/mise/config.toml" | grep -q libreoffice &&
  fail "libreoffice sits under the .pkg installer comment"

# GitHub renders text between two ~ as strikethrough, so a path under ~ is a code span.
bare_tilde=$(python3 -I - "$repo/README.md" "$repo/AGENTS.md" <<'PY2'
import re, sys
for path in sys.argv[1:]:
    fence = False
    for n, line in enumerate(open(path), 1):
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if not fence and "~" in re.sub(r"`[^`]*`", "", line):
            print(f"{path.rsplit('/', 1)[-1]}:{n}")
PY2
)
[[ -z $bare_tilde ]] || fail "a ~ outside a code span can turn into strikethrough: $bare_tilde"

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
