# make is the one task runner a new Mac has (from the Xcode Command Line Tools),
# so this repository keeps its tasks here rather than in a justfile.

.PHONY: bootstrap lint plan skills status sync upgrade

# Install Homebrew, mise and Orca and link mise/ (usage: make bootstrap PROFILE=personal|work|shop)
bootstrap:
	scripts/bootstrap.sh $(PROFILE)

# Show what mise bootstrap would change
plan:
	mise bootstrap --dry-run

# Show the state of every bootstrap part
status:
	mise bootstrap status

install-etc:
	# codex
	sudo mkdir -p /etc/codex
	sudo install -m 644 -o root -g wheel codex/requirements.toml /etc/codex/requirements.toml
	# ClaudeCode
	sudo mkdir -p "/Library/Application Support/ClaudeCode"
	sudo install -m 644 -o root -g admin claude/managed-settings.json "/Library/Application Support/ClaudeCode/managed-settings.json"

# Pull the latest config and apply it
sync: install-etc
	git pull
	mise bootstrap --verbose

# Upgrade the Homebrew packages and mise tools and remove what is no longer needed
upgrade:
	brew update
	brew upgrade
	brew autoremove
	brew cleanup --prune=all
	mise upgrade

# Install the agent skills for Claude Code and Codex
skills:
	scripts/install-skills.sh

# Check the shell scripts and look for secrets in the working tree
lint:
	shellcheck scripts/bootstrap.sh scripts/install-skills.sh scripts/tests/test-bootstrap.sh claude/statusline.sh
	gitleaks dir --no-banner .
