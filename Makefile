# make is the one task runner a new Mac has (from the Xcode Command Line Tools);
# everything after this comes from `mise bootstrap`.

.PHONY: bootstrap

# Usage: make bootstrap PROFILE=personal|work
bootstrap:
	scripts/bootstrap.sh $(PROFILE)
