# The CLI and the menu bar app look for mbrightd next to their own executable,
# then in ../Helpers, before falling back to PATH.
CLIENTS := mbright mbright-menubar

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
# regenerable, so they belong in the cache. Bare `swift build` does not go
# through make and still uses ./.build.
BUILD_DIR := $(XDG_CACHE_HOME)/mbright/build

# The install is an app bundle so Spotlight, Raycast and the Dock can launch
# the menu bar app. It is a plain directory with an Info.plist, no Xcode
# involved. All three binaries live inside it; the CLI is reached through a
# symlink in BINDIR, and the sibling-daemon lookup resolves symlinks. The
# daemon goes in Contents/Helpers, not Contents/MacOS: anything running from
# MacOS counts to LaunchServices as an instance of the app, so a daemon
# running there while the app is not (started by the CLI, say) would be
# what a launch activates instead of the menu bar app.
APP         := $(HOME)/Applications/mbright.app
APP_BIN     := $(APP)/Contents/MacOS
APP_HELPERS := $(APP)/Contents/Helpers

# An explicit PREFIX wins. Otherwise fall back to XDG_BIN_HOME, which is already
# a bin directory rather than a prefix. No XDG spec defines it, but setups that
# put ~/.local/bin on PATH commonly export it.
ifneq ($(origin PREFIX),undefined)
  BINDIR := $(PREFIX)/bin
else ifneq ($(XDG_BIN_HOME),)
  BINDIR := $(XDG_BIN_HOME)
else
  BINDIR := $(HOME)/.local/bin
endif
BINDIR := $(call tilde,$(BINDIR))

# Written by mbrightd from the config's login key; launchd reads only this path.
LAUNCH_AGENT_LABEL := com.axklim.mbright
BUNDLE_ID          := com.axklim.mbright
LAUNCH_AGENT       := $(HOME)/Library/LaunchAgents/$(LAUNCH_AGENT_LABEL).plist

# The pre-config-file label. mbrightd never writes this one; uninstall only
# ever removes it, as a courtesy for upgrades from that version.
LEGACY_LAUNCH_AGENT_LABEL := com.axklim.mbright.menubar
LEGACY_LAUNCH_AGENT       := $(HOME)/Library/LaunchAgents/$(LEGACY_LAUNCH_AGENT_LABEL).plist

SWIFT_FLAGS := --scratch-path "$(BUILD_DIR)"
TEST_ARGS   := $(if $(FILTER),--filter $(FILTER),)

.DEFAULT_GOAL := help
.PHONY: help build build-release run test clean install uninstall

help: ## Show this help
	@printf 'Targets:\n'
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'
	@printf '\nVariables:\n'
	@printf '  %-16s %s\n' 'FILTER' 'run only matching tests (make test FILTER=Percent)'
	@printf '  %-16s %s\n' 'PREFIX' 'CLI symlink prefix; overrides XDG_BIN_HOME'
	@printf '  %-16s %s\n' '' 'symlink goes to $(BINDIR)/mbright'
	@printf '  %-16s %s\n' '' 'app bundle goes to $(APP)'
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

# Stops the menu bar app and the daemon. The daemon never exits unasked, so
# without this a rebuilt or reinstalled app would talk to a daemon still
# serving the previous build. The app goes first: it would otherwise restart
# the daemon we are about to stop. `daemon stop` through the CLI in $(1) is
# the graceful route and stops whoever owns the socket; the pkill after it is
# scoped to the daemon in $(2), so it clears a wedged daemon of that build
# without touching a scratch one under another XDG_RUNTIME_DIR.
define stop
pkill -x mbright-menubar 2>/dev/null || true; \
"$(1)/mbright" daemon stop >/dev/null 2>&1 || true; \
pkill -f "^$(2)/mbrightd" 2>/dev/null || true; \
n=0; while pgrep -x mbright-menubar >/dev/null 2>&1 \
    || pgrep -f "^$(2)/mbrightd" >/dev/null 2>&1; do \
  [ $$n -ge 50 ] && break; sleep 0.1; n=$$((n + 1)); \
done
endef

# Foreground, Ctrl-C or Quit to stop. The app starts mbrightd itself, and the
# debug directory holds all three binaries, so it spawns the debug daemon as
# a sibling rather than the installed one. Whatever was running is stopped
# first, and the debug daemon is stopped again afterwards so nothing from
# this build outlives the test; relaunch the installed app from Spotlight.
# The trap keeps the shell alive through Ctrl-C long enough to do that.
run: build ## Stop anything running, run the menu bar app, stop its daemon on exit
	@$(call stop,$(BUILD_DIR)/debug,$(BUILD_DIR)/debug)
	@trap ':' INT; "$(BUILD_DIR)/debug/mbright-menubar"; \
	  "$(BUILD_DIR)/debug/mbright" daemon stop >/dev/null 2>&1 || true

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

# The bundle is ad-hoc signed, so every build is a new binary to TCC and a
# stale Accessibility grant would show as allowed while the hotkey tap is
# refused. Dropping it makes the app ask again on launch.
#
# `config update` brings a config file from an older version into this
# one's shape: set keys stay, new keys get their defaults, unknown keys go.
# It needs a daemon, so the installed CLI starts the installed one, which
# the app then finds running. A failure here is reported, not fatal.
install: build-release ## Build, stop anything running, install the app bundle, update the config, launch it
	@$(call stop,$(BUILD_DIR)/release,$(APP_HELPERS))
	@mkdir -p "$(APP_BIN)" "$(APP_HELPERS)" "$(BINDIR)"
	@for b in $(CLIENTS); do \
	  install -m 0755 "$(BUILD_DIR)/release/$$b" "$(APP_BIN)/$$b" || exit 1; \
	done
	@install -m 0755 "$(BUILD_DIR)/release/mbrightd" "$(APP_HELPERS)/mbrightd"
	@sed "s/@VERSION@/$$("$(BUILD_DIR)/release/mbright" --version)/g" \
	  scripts/Info.plist.in > "$(APP)/Contents/Info.plist"
	@ln -sfn "$(APP_BIN)/mbright" "$(BINDIR)/mbright"
	@tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1 || true
	@echo "installed $(APP)"
	@echo "installed $(BINDIR)/mbright -> $(APP_BIN)/mbright"
	@"$(APP_BIN)/mbright" config update --daemon-autostart \
	  || echo "warning: could not update the config file; run 'mbright config update' by hand"
	@open -a "$(APP)"

# Only a symlink that points into the bundle is ours to remove. The
# LaunchAgent is unloaded best-effort: mbrightd never bootstraps it, so it is
# only loaded if this login started mbright.
uninstall: ## Stop anything running, remove the app bundle, CLI symlink and LaunchAgent
	@$(call stop,$(APP_BIN),$(APP_HELPERS))
	@launchctl bootout "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)" >/dev/null 2>&1 || true
	@if [ -e "$(LAUNCH_AGENT)" ]; then \
	  rm -f "$(LAUNCH_AGENT)" && echo "removed $(LAUNCH_AGENT)"; \
	fi
	@launchctl bootout "gui/$$(id -u)/$(LEGACY_LAUNCH_AGENT_LABEL)" >/dev/null 2>&1 || true
	@if [ -e "$(LEGACY_LAUNCH_AGENT)" ]; then \
	  rm -f "$(LEGACY_LAUNCH_AGENT)" && echo "removed $(LEGACY_LAUNCH_AGENT)"; \
	fi
	@if [ "$$(readlink "$(BINDIR)/mbright")" = "$(APP_BIN)/mbright" ]; then \
	  rm -f "$(BINDIR)/mbright" && echo "removed $(BINDIR)/mbright"; \
	fi
	@if [ -d "$(APP)" ]; then \
	  rm -r "$(APP)" && echo "removed $(APP)"; \
	else \
	  echo "not installed: $(APP)"; \
	fi
