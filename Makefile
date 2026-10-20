# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
# Chordist: a Plasma widget (applet/) and the local service behind it (lyricist/).
# `make` alone prints this help. Targets are documented with a trailing `## text`.

APPLET_ID  := com.ritwick.lyricist
PREFIX     ?= $(HOME)/.local
BIN_DIR    := $(PREFIX)/bin
LIB_DIR    := $(PREFIX)/lib/lyricist
UNIT_DIR   ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/systemd/user
STATE_DIRS := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/lyricist $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/lyricist
KPT        := kpackagetool6
SYSTEMCTL  ?= systemctl --user
QT_BIN     := /usr/lib/qt6/bin
QMLLINT    := $(QT_BIN)/qmllint
QMLTEST    := $(QT_BIN)/qmltestrunner
UV         := uv
QML_FILES  := $(wildcard applet/contents/ui/*.qml applet/contents/ui/config/*.qml applet/contents/config/*.qml)
JS_FILES   := $(wildcard applet/contents/js/*.js)

.DEFAULT_GOAL := help
.PHONY: help deps install install-service install-applet uninstall doctor status \
        lint lint-reuse lint-python lint-qml lint-shell lint-deadcode \
        test test-python test-js test-qml shots chords-db clean

help: ## Show this help
	@echo "Chordist"
	@echo
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- install ----------------------------------------------------------------
# Nothing here restarts anything: the service and the shell are yours to restart,
# and install prints the two commands.
deps: ## Check the tools the widget and its checks need
	@missing=0; for tool in python3 $(KPT) uv node shellcheck reuse; do \
	    command -v $$tool >/dev/null || { echo "missing: $$tool"; missing=1; }; done; \
	for tool in $(QMLLINT) $(QMLTEST); do [ -x $$tool ] || { echo "missing: $$tool (qt6-declarative)"; missing=1; }; done; \
	[ $$missing = 0 ] && echo "all present" || { echo "pacman -S --needed python uv nodejs shellcheck reuse qt6-declarative kpackage"; exit 1; }

install: install-service install-applet ## Install the service and the widget into ~/.local
	@echo
	@echo "Installed. To start using this version:"
	@echo "  systemctl --user restart lyricistd"
	@echo "  systemctl --user restart plasma-plasmashell   # reloads the widget"

install-service: ## Install the service, launcher and systemd unit
	install -d $(LIB_DIR) $(BIN_DIR) $(UNIT_DIR) $(STATE_DIRS)
	rm -rf $(LIB_DIR)/lyricist
	cp -r lyricist $(LIB_DIR)/lyricist
	find $(LIB_DIR) -name __pycache__ -prune -exec rm -rf {} +
	install -m 755 bin/lyricistd $(BIN_DIR)/lyricistd
	install -m 644 packaging/lyricistd.service $(UNIT_DIR)/lyricistd.service
	$(SYSTEMCTL) daemon-reload
	$(SYSTEMCTL) enable lyricistd.service

install-applet: ## Install or upgrade the Plasma widget
	$(KPT) -t Plasma/Applet -u applet 2>/dev/null || $(KPT) -t Plasma/Applet -i applet

uninstall: ## Remove the widget, service and unit (your charts and settings stay)
	-$(SYSTEMCTL) disable --now lyricistd.service
	-$(KPT) -t Plasma/Applet -r $(APPLET_ID)
	rm -rf $(LIB_DIR) $(BIN_DIR)/lyricistd $(UNIT_DIR)/lyricistd.service
	-$(SYSTEMCTL) daemon-reload

doctor: ## Check the running service and its tools
	python3 -m lyricist doctor

status: ## Service state and version
	@systemctl --user --no-pager --lines=0 status lyricistd.service || true
	@python3 -m lyricist health 2>&1 || true

# ---- checks -----------------------------------------------------------------
# `make lint` and `make test` are what CI runs, so a red pipeline reproduces here.
lint: lint-reuse lint-python lint-qml lint-shell lint-deadcode ## Every static check

lint-reuse: ## SPDX headers and licences on every file
	reuse lint

lint-python: ## ruff over the service, tests and tools
	$(UV) run ruff check .

lint-qml: ## qmllint over the widget's QML and JS (warnings are errors)
	$(QMLLINT) -I /usr/lib/qt6/qml --unqualified disable --compiler disable --block-scope-var-declaration disable --max-warnings 0 $(QML_FILES) $(JS_FILES)

lint-shell: ## shellcheck over the launcher and scripts
	shellcheck bin/lyricistd tests/qml/run.sh

lint-deadcode: ## vulture: Python nothing calls
	$(UV) run vulture lyricist tools tests/python --min-confidence 60 \
	    --ignore-names 'do_*,log_message,server_version,protocol_version,daemon_threads,allow_reuse_address,xdg,no_network'

test: test-python test-js test-qml ## All tests

test-python: ## pytest: parsing, providers, server and its guards
	$(UV) run pytest

test-js: ## node: the widget's pure JS (theory, schedule, tab layout)
	node --test tests/js

test-qml: ## qmltestrunner: the song model's logic
	QT_QPA_PLATFORM=offscreen $(QMLTEST) -input tests/qml/tst_songmodel.qml

shots: ## Render the widget headless against a fixture service (build/shots)
	tests/qml/run.sh build/shots

chords-db: ## Refresh the vendored chords-db fingering data (needs npm)
	tools/update-chords-db.py

clean: ## Remove build output and caches
	rm -rf build .pytest_cache .ruff_cache
	find . -name __pycache__ -prune -exec rm -rf {} +
