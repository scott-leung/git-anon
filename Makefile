SCRIPTS := bin/git-anon bin/git-remote-anon install.sh tests/run.sh
BINDIR ?= $(HOME)/.local/bin

.PHONY: test lint check-version install uninstall

test:
	sh tests/run.sh

lint:
	shellcheck $(SCRIPTS)

# VERSION in bin/git-anon must equal package.json (and TAG, if given: make check-version TAG=v1.2.3)
check-version:
	@v=$$(sed -n 's/^VERSION=//p' bin/git-anon); \
	p=$$(sed -n 's/^  "version": "\(.*\)",$$/\1/p' package.json); \
	[ "$$v" = "$$p" ] || { echo "bin/git-anon VERSION=$$v != package.json $$p"; exit 1; }; \
	[ -z "$(TAG)" ] || [ "v$$v" = "$(TAG)" ] || { echo "VERSION=$$v != tag $(TAG)"; exit 1; }; \
	echo "version $$v ok"

install:
	BINDIR=$(BINDIR) sh ./install.sh

uninstall:
	BINDIR=$(BINDIR) sh ./install.sh --uninstall
