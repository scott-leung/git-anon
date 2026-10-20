SCRIPTS := bin/git-anon bin/git-remote-anon install.sh tests/run.sh
BINDIR ?= $(HOME)/.local/bin

.PHONY: test lint install uninstall

test:
	sh tests/run.sh

lint:
	shellcheck $(SCRIPTS)

install:
	BINDIR=$(BINDIR) sh ./install.sh

uninstall:
	BINDIR=$(BINDIR) sh ./install.sh --uninstall
