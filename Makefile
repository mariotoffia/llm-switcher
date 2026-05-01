# llm-switcher Makefile
#
# Targets:
#   install      - run install.sh (clone/symlink + auto-config)
#   setup        - alias for install (matches CLAUDE.md naming)
#   autoconfig   - re-run install.sh in --autoconfig-only mode
#   test         - run the zsh test suite
#   lint         - syntax-check the plugin, tests, and install.sh
#   clean        - remove temp test artifacts
#   serve-all    - alias for `test`

PLUGIN     := llm-switcher.plugin.zsh
INSTALL_SH := install.sh

.PHONY: setup install autoconfig test lint clean serve-all help

help:
	@printf 'Targets:\n'
	@printf '  install      run install.sh (clone/symlink + auto-config)\n'
	@printf '  setup        alias for install\n'
	@printf '  autoconfig   re-run install.sh in --autoconfig-only mode\n'
	@printf '  test         run the zsh test suite\n'
	@printf '  lint         zsh -n on the plugin and tests; sh -n + shellcheck on install.sh\n'
	@printf '  clean        remove temp test artifacts\n'

install:
	@sh $(INSTALL_SH)

setup: install

autoconfig:
	@sh $(INSTALL_SH) --autoconfig-only

test:
	@zsh tests/run.zsh

lint:
	@zsh -n $(PLUGIN)
	@for f in tests/*.zsh; do zsh -n "$$f"; done
	@sh -n $(INSTALL_SH)
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -s sh $(INSTALL_SH); \
	else \
	  echo "shellcheck not installed; skipped install.sh static analysis"; \
	fi
	@echo "lint OK"

clean:
	@rm -rf /tmp/llm-switcher-test.* /tmp/llm-switcher-install.* 2>/dev/null || true
	@echo "clean OK"

serve-all: test
