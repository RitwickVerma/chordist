# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
# Chordist: a Plasma widget (applet/) and the local service behind it (chordist/).
# `make` alone prints this help. Targets are documented with a trailing `## text`.

APPLET_ID  := com.ritwick.chordist
PREFIX     ?= $(HOME)/.local
BIN_DIR    := $(PREFIX)/bin
LIB_DIR    := $(PREFIX)/lib/chordist
ICON_DIR   := $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/icons/hicolor/scalable/apps
UNIT_DIR   ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/systemd/user
STATE_DIRS := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/chordist $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/chordist
KPT        := kpackagetool6
SYSTEMCTL  ?= systemctl --user
QT_BIN     := /usr/lib/qt6/bin
VERSION    := $(shell cat VERSION)
QMLLINT    := $(QT_BIN)/qmllint
QMLTEST    := $(QT_BIN)/qmltestrunner
UV         := uv
QML_FILES  := $(wildcard applet/contents/ui/*.qml applet/contents/ui/config/*.qml applet/contents/config/*.qml)
JS_FILES   := $(wildcard applet/contents/js/*.js)

.DEFAULT_GOAL := help
# install is a sequence (migrate the data, then start the service on it), and a
# MAKEFLAGS=-j in someone's environment must not turn it into a race.
.NOTPARALLEL:
.PHONY: help deps install install-service install-applet migrate migrate-panel uninstall doctor status \
        lint lint-reuse lint-python lint-qml lint-shell lint-deadcode \
        test test-python test-js test-qml coverage shots demo chords-db dist pkgbuild check-build clean

help: ## Show this help
	@echo "Chordist"
	@echo
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- install ----------------------------------------------------------------
# Installing starts the service (it is yours to run, and safe to restart) but never
# touches plasmashell: that is the one step left to you, and install prints it.
deps: ## Check the tools the widget and its checks need
	@missing=0; for tool in python3 $(KPT) uv node shellcheck reuse; do \
	    command -v $$tool >/dev/null || { echo "missing: $$tool"; missing=1; }; done; \
	for tool in $(QMLLINT) $(QMLTEST); do [ -x $$tool ] || { echo "missing: $$tool (qt6-declarative)"; missing=1; }; done; \
	[ $$missing = 0 ] && echo "all present" || { echo "pacman -S --needed python uv nodejs shellcheck reuse qt6-declarative kpackage"; exit 1; }

install: migrate install-service install-applet ## Install the service and the widget into ~/.local
	@echo
	@echo "Installed, and the service is running. Restart the shell to load the new widget:"
	@echo "  systemctl --user restart plasma-plasmashell"
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
	install -m 644 packaging/chordistd.service $(UNIT_DIR)/chordistd.service
	ln -sf chordistd $(BIN_DIR)/chordist
	install -Dm644 packaging/chordist.svg $(ICON_DIR)/chordist.svg
	$(SYSTEMCTL) daemon-reload
	$(SYSTEMCTL) enable chordistd.service
	$(SYSTEMCTL) restart chordistd.service

install-applet: ## Install or upgrade the Plasma widget
	$(KPT) -t Plasma/Applet -u applet >/dev/null 2>&1 || $(KPT) -t Plasma/Applet -i applet

uninstall: ## Remove the widget, service and unit (your charts and settings stay)
	-$(SYSTEMCTL) disable --now chordistd.service
	-$(KPT) -t Plasma/Applet -r $(APPLET_ID)
	rm -rf $(LIB_DIR) $(BIN_DIR)/chordistd $(BIN_DIR)/chordist $(ICON_DIR)/chordist.svg $(UNIT_DIR)/chordistd.service
	-$(SYSTEMCTL) daemon-reload

doctor: ## Check the running service and its tools
	python3 -m chordist doctor

status: ## Service state and version
	@systemctl --user --no-pager --lines=0 status chordistd.service || true
	@python3 -m chordist health 2>&1 || true

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
	shellcheck bin/chordistd tests/qml/run.sh tests/qml/demo.sh tools/migrate-from-lyricist.sh
	shellcheck -s bash -e SC2034,SC2154 packaging/PKGBUILD

lint-deadcode: ## vulture: Python nothing calls
	$(UV) run vulture chordist tools tests/python --min-confidence 60 \
	    --ignore-names 'do_*,log_message,server_version,protocol_version,daemon_threads,allow_reuse_address,xdg,no_network,pytestmark,redirect_request'

test: test-python test-js test-qml ## All tests

test-python: ## pytest: parsing, providers, server and its guards
	$(UV) run pytest

coverage: ## Python test coverage, with the lines no test reaches
	$(UV) run pytest --cov=chordist --cov-report=term-missing:skip-covered

test-js: ## node: the widget's pure JS (theory, schedule, tab layout)
	node --test tests/js

test-qml: ## qmltestrunner: the song model's logic
	QT_QPA_PLATFORM=offscreen $(QMLTEST) -input tests/qml/tst_songmodel.qml

shots: ## Render the widget headless against a fixture service (build/shots)
	tests/qml/run.sh build/shots

dist: ## Source tarball of the committed tree (dist/chordist-VERSION.tar.gz)
	@mkdir -p dist
	git archive --format=tar.gz --prefix=chordist-$(VERSION)/ -o dist/chordist-$(VERSION).tar.gz HEAD
	@echo dist/chordist-$(VERSION).tar.gz

pkgbuild: dist ## Stage the Arch PKGBUILD and tarball in build/pkg (then: cd build/pkg && makepkg -si)
	@mkdir -p build/pkg
	cp packaging/PKGBUILD build/pkg/PKGBUILD
	cp dist/chordist-$(VERSION).tar.gz build/pkg/

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
