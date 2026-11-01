#!/bin/bash
# Install Homebrew and mise, then hand ~/.config/mise to this repository.
# Everything else (packages, dotfiles, macOS defaults) comes from `mise bootstrap`.
# Usage: make bootstrap PROFILE=personal|work (or scripts/bootstrap.sh personal|work)
set -eu

profile=${1:-}
if [ "$profile" != personal ] && [ "$profile" != work ]; then
  echo "usage: make bootstrap PROFILE=personal|work" >&2
  exit 1
fi

repo=$(cd "$(dirname "$0")/.." && pwd -P)
config_dir=$HOME/.config/mise
configs="config.toml config.personal.toml config.work.toml"
# Look where brew lives, not on PATH: right after installing it, it is not on PATH yet.
brew_bin=${HOMEBREW_PREFIX:-/opt/homebrew}/bin/brew

# Leave anything we do not own alone, and stop before installing or linking anything.
if [ -L "$config_dir" ]; then
  echo "refusing to use $config_dir: it is a link to $(readlink "$config_dir"); make it a real directory first" >&2
  exit 1
fi
conflict=0
for f in $configs; do
  target=$config_dir/$f
  if { [ -e "$target" ] || [ -L "$target" ]; } && [ "$(readlink "$target")" != "$repo/mise/$f" ]; then
    echo "refusing to replace $target: it is not a link to $repo/mise/$f; move it away first" >&2
    conflict=1
  fi
done
[ "$conflict" = 0 ] || exit 1

if [ ! -x "$brew_bin" ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi

mkdir -p "$config_dir"
for f in $configs; do
  ln -sfn "$repo/mise/$f" "$config_dir/$f"
done
# Kept across runs: it is this Mac's choice, not the repository's.
if [ ! -e "$config_dir/miserc.local.toml" ]; then
  echo "env = [\"$profile\"]" >"$config_dir/miserc.local.toml"
fi

echo 'Load brew into this shell, then run ~/.local/bin/mise bootstrap:'
echo '  eval "$(/opt/homebrew/bin/brew shellenv)"'
