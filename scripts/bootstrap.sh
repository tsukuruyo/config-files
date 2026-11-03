#!/bin/bash
# Install Homebrew, mise and (on the dev Macs) Orca, then hand ~/.config/mise to this repository.
# Everything else (packages, dotfiles, macOS defaults) comes from `mise bootstrap`.
# Usage: make bootstrap PROFILE=personal|work|shop (or scripts/bootstrap.sh personal|work|shop)
set -eu

# Each Mac's mise envs, in the order they layer on config.toml. The personal and work
# Macs are dev Macs: they add config.dev.toml under their own file. The shop Mac does not.
profile=${1:-}
case $profile in
  personal | work) envs="\"dev\", \"$profile\"" dev=1 ;;
  shop) envs="\"shop\"" dev=0 ;;
  *)
    echo "usage: make bootstrap PROFILE=personal|work|shop" >&2
    exit 1
    ;;
esac

repo=$(cd "$(dirname "$0")/.." && pwd -P)
config_dir=$HOME/.config/mise
configs="config.toml config.dev.toml config.personal.toml config.work.toml config.shop.toml"
# Look where brew lives, not on PATH: right after installing it, it is not on PATH yet.
brew_bin=${HOMEBREW_PREFIX:-/opt/homebrew}/bin/brew
appdir=${BOOTSTRAP_APPDIR:-/Applications}

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

# Orca's cask lives in stablyai's own tap. mise can read a tap cask only with
# Ruby 3, which a new Mac lacks, so brew (which bundles its Ruby) installs it.
# An Orca installed by hand is left alone: it updates itself. The shop Mac does not get it.
if [ "$dev" = 1 ] && [ ! -d "$appdir/Orca.app" ]; then
  "$brew_bin" install --cask stablyai/orca/orca
fi

mkdir -p "$config_dir"
for f in $configs; do
  ln -sfn "$repo/mise/$f" "$config_dir/$f"
done
# Kept across runs: it is this Mac's choice, not the repository's.
if [ ! -e "$config_dir/miserc.local.toml" ]; then
  echo "env = [$envs]" >"$config_dir/miserc.local.toml"
fi

echo 'Load brew into this shell, then run ~/.local/bin/mise bootstrap:'
# shellcheck disable=SC2016 # printed for the user to run, not expanded here
echo '  eval "$(/opt/homebrew/bin/brew shellenv)"'
