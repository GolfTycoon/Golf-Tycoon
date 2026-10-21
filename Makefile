# Golf Tycoon Makefile
#
# Godot is resolved by scripts/resolve-godot.sh (bundled zip, $GODOT, PATH, or
# download). Override with: make test GODOT=/path/to/godot

GODOT ?= $(shell ./scripts/resolve-godot.sh)

.PHONY: test run editor warnings help mods mod-validate mod-pack

help:
	@echo "Golf Tycoon - Available commands:"
	@echo "  make test     - Run unit tests (extracts Godot and imports on first run)"
	@echo "  make warnings - Fail if any project script carries a GDScript warning"
	@echo "  make run      - Run the game"
	@echo "  make mods     - Validate every bundled mod and pack them into dist/mods/"
	@echo "  make mod-pack MOD=mods/<folder>      - Pack one mod folder into a shareable zip"
	@echo "  make mod-validate MOD=mods/<folder>  - Validate one mod (or a mod zip)"
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

# Mods: validate and pack mod folders (see docs/modding.md). The same zips
# install through the in-game Mods screen.
mods:
	@if [ -z "$(GODOT)" ]; then echo "Error: Godot not found. Set GODOT variable."; exit 1; fi
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- validate-all
	@for d in mods/*/; do \
		case "$$d" in mods/_*/) continue ;; esac; \
		$(GODOT) --headless --path . --script tools/mod_tool.gd -- pack "$$d" || exit 1; \
	done

mod-pack:
	@if [ -z "$(MOD)" ]; then echo "Usage: make mod-pack MOD=mods/<folder>"; exit 1; fi
	@if [ -z "$(GODOT)" ]; then echo "Error: Godot not found. Set GODOT variable."; exit 1; fi
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- pack "$(MOD)"

mod-validate:
	@if [ -z "$(MOD)" ]; then echo "Usage: make mod-validate MOD=mods/<folder> (or a mod .zip)"; exit 1; fi
	@if [ -z "$(GODOT)" ]; then echo "Error: Godot not found. Set GODOT variable."; exit 1; fi
	@$(GODOT) --headless --path . --script tools/mod_tool.gd -- validate "$(MOD)"
