#!/bin/bash
# Install the agent skills shared by every Mac, for Claude Code and Codex, with the
# skills CLI (https://github.com/vercel-labs/skills).
# Each source is pinned to a commit: to update one, replace its SHA after reading the diff.
# orca-cli is not here: Orca installs and updates it.
# Usage: make skills (or scripts/install-skills.sh)
set -eu

add() {
  local source=$1
  shift
  pnpx skills add "$source" -g -a claude-code codex -y --skill "$@"
}

add mizchi/skills#ab4eb2f7a92a13fb37c225ab427f2f492143ace1 empirical-prompt-tuning
