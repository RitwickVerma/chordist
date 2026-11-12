# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
# Chordist: a Plasma widget (applet/) and the local service behind it (chordist/).
# `make` alone prints this help. Targets are documented with a trailing `## text`.

APPLET_ID  := com.ritwick.chordist
PREFIX     ?= $(HOME)/.local
BIN_DIR    := $(PREFIX)/bin
LIB_DIR    := $(PREFIX)/lib/chordist
ICON_BASE  := $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/icons/hicolor
ICON_DIR   := $(ICON_BASE)/512x512/apps
# The chord-box logo that installs before 2.1.0 put here; the icon theme would keep choosing it over the PNG.
OLD_ICON   := $(ICON_BASE)/scalable/apps/chordist.svg
UNIT_DIR   ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/systemd/user
STATE_DIRS := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/chordist $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/chordist
KPT        := kpackagetool6
SYSTEMCTL  ?= systemctl --user
# Where Qt 6 keeps its tools and QML modules differs by distribution (/usr/lib/qt6, /usr/lib64/qt6, a multiarch
# directory): ask Qt's own qtpaths. Override any of the three on the command line, e.g. make QT_BIN=/opt/qt6/bin.
QT_PATHS   ?= $(firstword $(shell command -v qtpaths6 qtpaths-qt6 2>/dev/null))
QT_BIN     ?= $(or $(and $(QT_PATHS),$(shell $(QT_PATHS) --binaries-dir 2>/dev/null)),$(firstword $(wildcard /usr/lib/qt6/bin /usr/lib64/qt6/bin)),/usr/lib/qt6/bin)
QT_QML     ?= $(or $(and $(QT_PATHS),$(shell $(QT_PATHS) --query QT_INSTALL_QML 2>/dev/null)),$(firstword $(wildcard /usr/lib/qt6/qml /usr/lib64/qt6/qml)),/usr/lib/qt6/qml)
VERSION    := $(shell cat VERSION)
QMLLINT    := $(QT_BIN)/qmllint
# Qt 6.8's qmllint (Debian 13, Ubuntu 25.04) does not know this switch and refuses to run with it; ask it first.
QMLLINT_BLOCK_SCOPE = $(shell $(QMLLINT) --help 2>&1 | grep -q -e '--block-scope-var-declaration' && echo '--block-scope-var-declaration disable')
# Extra qmllint switches. Empty: the KDE types resolve wherever Plasma's QML modules are installed (CI installs them
# for the qml job). On a machine without Plasma, `QMLLINT_FLAGS='--import disable --unresolved-type disable
# --missing-property disable --incompatible-type disable --unresolved-alias disable --alias-cycle disable
# --required disable'` stops unresolvable KDE types from counting as warnings.
QMLLINT_FLAGS ?=
QMLTEST    := $(QT_BIN)/qmltestrunner
UV         := uv
QML_FILES  := $(wildcard applet/contents/ui/*.qml applet/contents/ui/config/*.qml applet/contents/config/*.qml)
JS_FILES   := $(wildcard applet/contents/js/*.js)

.DEFAULT_GOAL := help
# install is a sequence (migrate the data, then start the service on it), and a
# MAKEFLAGS=-j in someone's environment must not turn it into a race.
.NOTPARALLEL:
.PHONY: help deps deps-dev install install-service install-applet migrate migrate-panel uninstall doctor status \
        lint lint-reuse lint-python lint-qml lint-shell lint-deadcode \
        test test-python test-js test-qml coverage shots demo chords-db dist pkgbuild aur check-build clean

help: ## Show this help
	@echo "Chordist"
	@echo
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- install ----------------------------------------------------------------
# Installing starts the service (it is yours to run, and safe to restart) but never
# touches plasmashell: that is the one step left to you, and install prints it.
deps: ## What running Chordist needs, and the install line for this distribution
	@tools/deps.sh runtime

deps-dev: ## What the tests and linters need as well, and the install line
	@DEPS_QT_BIN=$(QT_BIN) tools/deps.sh dev

# The widget goes in before the service: it is what a user sees, and what the shell restart below loads.
install: migrate install-applet install-service ## Install the widget and the service into ~/.local
	@echo
	@echo "Installed. Restart the shell to load the new widget:"
	@echo "  systemctl --user restart plasma-plasmashell"
	@echo "  (or, where that unit is not in use: kquitapp6 plasmashell; kstart plasmashell)"
	@if grep -qs 'plugin=com.ritwick.lyricist' $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/plasma-org.kde.plasma.desktop-appletsrc; then \
	    echo; echo "Your panel still has the old widget (com.ritwick.lyricist). Run this instead:"; \
	    echo "  make migrate-panel      # keeps its position and settings"; fi

migrate: ## Move an old "lyricist" install (service, config, charts, caches) to the Chordist names
	PREFIX=$(PREFIX) UNIT_DIR=$(UNIT_DIR) SYSTEMCTL="$(SYSTEMCTL)" KPT=$(KPT) tools/migrate-from-lyricist.sh data

migrate-panel: ## Point the panel at the renamed widget, keeping position and settings (restarts plasmashell)
	KPT=$(KPT) tools/migrate-from-lyricist.sh panel

install-service: ## Install the service, launcher and systemd unit, and (re)start it
	install -d $(LIB_DIR) $(BIN_DIR) $(UNIT_DIR) $(STATE_DIRS)
	rm -rf $(LIB_DIR)/chordist
	cp -r chordist $(LIB_DIR)/chordist
	find $(LIB_DIR) -name __pycache__ -prune -exec rm -rf {} +
	install -m 755 bin/chordistd $(BIN_DIR)/chordistd
	sed -e 's|^ExecStart=.*|ExecStart=$(subst &,\&,$(subst %,%%,$(BIN_DIR)))/chordistd serve|' packaging/chordistd.service > $(UNIT_DIR)/chordistd.service
	chmod 644 $(UNIT_DIR)/chordistd.service
	ln -sf chordistd $(BIN_DIR)/chordist
	install -Dm644 applet/contents/images/guitar.png $(ICON_DIR)/chordist.png
	rm -f $(OLD_ICON)
	@if $(SYSTEMCTL) daemon-reload && $(SYSTEMCTL) enable chordistd.service && $(SYSTEMCTL) restart chordistd.service; then \
	    echo "The service is running."; \
	else \
	    echo; echo "The files are installed, but systemd's user manager did not take the service (no login session here?)."; \
	    echo "In your own session, run:"; \
	    echo "  $(SYSTEMCTL) daemon-reload"; \
	    echo "  $(SYSTEMCTL) enable --now chordistd.service"; \
	fi

install-applet: ## Install or upgrade the Plasma widget
	$(KPT) -t Plasma/Applet -u applet >/dev/null 2>&1 || $(KPT) -t Plasma/Applet -i applet

uninstall: ## Remove the widget, service and unit (your charts and settings stay)
	-$(SYSTEMCTL) disable --now chordistd.service
	-$(KPT) -t Plasma/Applet -r $(APPLET_ID)
	rm -rf $(LIB_DIR) $(BIN_DIR)/chordistd $(BIN_DIR)/chordist $(ICON_DIR)/chordist.png $(OLD_ICON) $(UNIT_DIR)/chordistd.service
	-$(SYSTEMCTL) daemon-reload

doctor: ## Check the running service and its tools
	python3 -m chordist doctor

status: ## Service state and version
	@$(SYSTEMCTL) --no-pager --lines=0 status chordistd.service || true
	@python3 -m chordist health 2>&1 || true

# ---- checks -----------------------------------------------------------------
# `make lint` and `make test` are what CI runs, so a red pipeline reproduces here.
lint: lint-reuse lint-python lint-qml lint-shell lint-deadcode ## Every static check

lint-reuse: ## SPDX headers and licences on every file
	reuse lint

lint-python: ## ruff over the service, tests and tools
	$(UV) run ruff check .

lint-qml: ## qmllint over the widget's QML and JS (warnings are errors)
	$(QMLLINT) -I $(QT_QML) --unqualified disable --compiler disable $(QMLLINT_BLOCK_SCOPE) $(QMLLINT_FLAGS) --max-warnings 0 $(QML_FILES) $(JS_FILES)

lint-shell: ## shellcheck over the launcher and scripts
	shellcheck bin/chordistd tests/qml/run.sh tests/qml/demo.sh tests/qml/components.sh tests/qml/harness/shim.sh tools/migrate-from-lyricist.sh tools/deps.sh ci/*.sh
	shellcheck -s bash -e SC2034,SC2154 packaging/PKGBUILD

lint-deadcode: ## vulture: Python nothing calls
	$(UV) run vulture chordist tools tests/python --min-confidence 60 \
	    --ignore-names 'do_*,log_message,server_version,protocol_version,daemon_threads,allow_reuse_address,xdg,no_network,gitlab,pytestmark,redirect_request'

test: test-python test-js test-qml ## All tests

test-python: ## pytest: parsing, providers, server and its guards
	$(UV) run pytest

coverage: ## Python test coverage, with the lines no test reaches
	$(UV) run pytest --cov=chordist --cov-report=term-missing:skip-covered

test-js: ## node: the widget's pure JS (theory, schedule, tab layout)
	node --test tests/js/*.test.mjs

test-qml: ## qmltestrunner: the song model's logic, and that every component loads on the installed Qt and KDE stack
	QT_QPA_PLATFORM=offscreen $(QMLTEST) -input tests/qml/tst_songmodel.qml
	QMLTEST=$(QMLTEST) tests/qml/components.sh

shots: ## Render the widget headless against a fixture service (build/shots)
	tests/qml/run.sh build/shots

dist: ## Source tarball of the committed tree (dist/chordist-VERSION.tar.gz)
	@mkdir -p dist
	git archive --format=tar.gz --prefix=chordist-$(VERSION)/ -o dist/chordist-$(VERSION).tar.gz HEAD
	@echo dist/chordist-$(VERSION).tar.gz

pkgbuild: dist ## Stage the Arch PKGBUILD and tarball in build/pkg (then: cd build/pkg && makepkg -si)
	@mkdir -p build/pkg
	cp packaging/PKGBUILD packaging/chordist.install build/pkg/
	cp dist/chordist-$(VERSION).tar.gz build/pkg/

aur: dist ## The AUR files (PKGBUILD, chordist.install, .SRCINFO) for that tarball in build/aur (needs makepkg)
	tools/aur-pkgbuild.py --tarball dist/chordist-$(VERSION).tar.gz --out build/aur
	@echo "push them to ssh://aur@aur.archlinux.org/chordist.git (see docs/releasing.md)"

check-build: ## Build the wheel and check the chord database and entry point are in it
	rm -rf dist/*.whl
	$(UV) build --wheel
	python3 tools/check-wheel.py dist/chordist-$(VERSION)-py3-none-any.whl

demo: ## Render the animated demo (docs/images/demo.gif; needs ffmpeg)
	tests/qml/demo.sh docs/images/demo.gif

chords-db: ## Refresh the vendored chords-db fingering data (needs npm)
	tools/update-chords-db.py

clean: ## Remove build output and caches
	rm -rf build .pytest_cache .ruff_cache
	find . -name __pycache__ -prune -exec rm -rf {} +
