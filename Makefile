# Golf Tycoon Makefile
#
# Godot is resolved by scripts/resolve-godot.sh (bundled zip, $GODOT, PATH, or
# download). Override with: make test GODOT=/path/to/godot

GODOT ?= $(shell ./scripts/resolve-godot.sh)

.PHONY: test run editor warnings help repository mod-validate mod-pack

help:
	@echo "Golf Tycoon - Available commands:"
	@echo "  make test     - Run unit tests (extracts Godot and imports on first run)"
	@echo "  make warnings - Fail if any project script carries a GDScript warning"
	@echo "  make run      - Run the game"
	@echo "  make repository        - Validate every mod package, pack repository/zips/ and"
	@echo "                           rewrite repository/official.json (the Official Repository)"
	@echo "  make mod-pack MOD=repository/packages/<folder>      - Pack one mod into a shareable zip"
	@echo "  make mod-validate MOD=repository/packages/<folder>  - Validate one mod (or a mod zip)"
	@echo "  make editor   - Open in Godot editor"
	@echo ""
	@echo "Override Godot path: make test GODOT=/path/to/godot"

test:
	@./test.sh

warnings:
	@./check-warnings.sh

run:
	@if [ -z "$(GODOT)" ]; then \
		echo "Error: Godot not found. Set GODOT variable."; \
		exit 1; \
	fi
	@$(GODOT) --path .

editor:
	@if [ -z "$(GODOT)" ]; then \
		echo "Error: Godot not found. Set GODOT variable."; \
		exit 1; \
	fi
	@$(GODOT) --editor --path .

# The Official Repository: the mods live as folders under
# repository/packages/, and this packs each into repository/zips/<id>.zip
# and rewrites repository/official.json - the feed JSON the game points at
# on the Browse Mods screen. Both generated files are committed, so a mod
# edited without repacking fails the unit tests (see repository/README.md).
repository:
	@if [ -z "$(GODOT)" ]; then echo "Error: Godot not found. Set GODOT variable."; exit 1; fi
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- validate-all
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- pack-repository

mod-pack:
	@if [ -z "$(MOD)" ]; then echo "Usage: make mod-pack MOD=repository/packages/<folder>"; exit 1; fi
	@if [ -z "$(GODOT)" ]; then echo "Error: Godot not found. Set GODOT variable."; exit 1; fi
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- pack "$(MOD)"

mod-validate:
	@if [ -z "$(MOD)" ]; then echo "Usage: make mod-validate MOD=repository/packages/<folder> (or a mod .zip)"; exit 1; fi
	@if [ -z "$(GODOT)" ]; then echo "Error: Godot not found. Set GODOT variable."; exit 1; fi
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- validate "$(MOD)"
