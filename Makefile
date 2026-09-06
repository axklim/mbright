# The CLI and the menu bar app look for mbrightd next to their own executable
# before falling back to PATH, so all three must be installed side by side.
# Formula/mbright.rb does the same thing for the Homebrew path.
BINARIES := mbright mbrightd mbright-menubar

# XDG Base Directory Specification v0.8.
#
# Two spec rules that `?=` does not cover: an *empty* value means the default
# just as an unset one does, and a non-absolute path must be ignored rather
# than used. A leading ~/ is expanded first, because zsh does not do it for
# `make XDG_CACHE_HOME=~/...`. XDG_RUNTIME_DIR has no default by design.
tilde = $(patsubst ~/%,$(HOME)/%,$(1))
xdg   = $(or $(filter /%,$(call tilde,$(1))),$(2))

XDG_CONFIG_HOME := $(call xdg,$(XDG_CONFIG_HOME),$(HOME)/.config)
XDG_DATA_HOME   := $(call xdg,$(XDG_DATA_HOME),$(HOME)/.local/share)
XDG_STATE_HOME  := $(call xdg,$(XDG_STATE_HOME),$(HOME)/.local/state)
XDG_CACHE_HOME  := $(call xdg,$(XDG_CACHE_HOME),$(HOME)/.cache)
XDG_RUNTIME_DIR := $(call xdg,$(XDG_RUNTIME_DIR),)

# Of the five, only XDG_CACHE_HOME is read by a target: build products are
# regenerable, so they belong in the cache. Bare `swift build` and the Homebrew
# formula do not go through make and still use ./.build.
BUILD_DIR := $(XDG_CACHE_HOME)/mbright/build

# An explicit PREFIX wins. Otherwise fall back to XDG_BIN_HOME, which is already
# a bin directory rather than a prefix. No XDG spec defines it, but setups that
# put ~/.local/bin on PATH commonly export it.
ifneq ($(origin PREFIX),undefined)
  BINDIR := $(PREFIX)/bin
else ifneq ($(XDG_BIN_HOME),)
  BINDIR := $(XDG_BIN_HOME)
else
  BINDIR := /usr/local/bin
endif
BINDIR := $(call tilde,$(BINDIR))

SWIFT_FLAGS := --scratch-path "$(BUILD_DIR)"
TEST_ARGS   := $(if $(FILTER),--filter $(FILTER),)

.DEFAULT_GOAL := help
.PHONY: help build build-release test clean install uninstall

help: ## Show this help
	@printf 'Targets:\n'
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'
	@printf '\nVariables:\n'
	@printf '  %-16s %s\n' 'FILTER' 'run only matching tests (make test FILTER=Percent)'
	@printf '  %-16s %s\n' 'PREFIX' 'install prefix; overrides XDG_BIN_HOME'
	@printf '  %-16s %s\n' '' 'binaries go to $(BINDIR)'
	@printf '\nXDG base directories (resolved):\n'
	@printf '  %-16s %s\n' 'XDG_CONFIG_HOME' '$(XDG_CONFIG_HOME)'
	@printf '  %-16s %s\n' 'XDG_DATA_HOME'   '$(XDG_DATA_HOME)'
	@printf '  %-16s %s\n' 'XDG_STATE_HOME'  '$(XDG_STATE_HOME)'
	@printf '  %-16s %s\n' 'XDG_CACHE_HOME'  '$(XDG_CACHE_HOME)   <- build products'
	@printf '  %-16s %s\n' 'XDG_RUNTIME_DIR' '$(if $(XDG_RUNTIME_DIR),$(XDG_RUNTIME_DIR),(unset; no default))'

build: ## Debug build
	swift build $(SWIFT_FLAGS)

build-release: ## Optimized build of all three binaries
	swift build -c release $(SWIFT_FLAGS)

test: ## Run the test suite
	./scripts/test.sh $(SWIFT_FLAGS) $(TEST_ARGS)

# SwiftPM deletes what SwiftPM created, so no recursive delete of a computed
# path lives here. The second invocation clears ./.build, which a bare
# `swift build` outside make may have left behind. Both are no-ops if the
# directory is already gone. Fetched dependencies survive, so the next build
# does not re-download them.
clean: ## Remove build products (fetched dependencies are kept)
	swift package clean $(SWIFT_FLAGS)
	swift package clean

install: build-release ## Build, then install all three into PREFIX/bin
	@mkdir -p "$(BINDIR)" 2>/dev/null || true
	@if [ ! -w "$(BINDIR)" ]; then \
	  echo "make: $(BINDIR) is not writable." >&2; \
	  echo "      Re-run with sudo, or install elsewhere: make install PREFIX=\$$HOME/.local" >&2; \
	  exit 1; \
	fi
	@for b in $(BINARIES); do \
	  install -m 0755 "$(BUILD_DIR)/release/$$b" "$(BINDIR)/$$b" || exit 1; \
	  echo "installed $(BINDIR)/$$b"; \
	done

uninstall: ## Remove all three binaries from PREFIX/bin
	@for b in $(BINARIES); do \
	  if [ ! -e "$(BINDIR)/$$b" ]; then \
	    echo "not installed: $(BINDIR)/$$b"; \
	  elif [ ! -w "$(BINDIR)" ]; then \
	    echo "make: $(BINDIR) is not writable, re-run with sudo." >&2; \
	    exit 1; \
	  else \
	    rm -f "$(BINDIR)/$$b"; \
	    echo "removed $(BINDIR)/$$b"; \
	  fi; \
	done
