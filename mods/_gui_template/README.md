# GUI theme template

The starting point for a GUI theme mod - a mod that re-dresses the whole
game interface (HUD, menus, panels, popups) in one design. This folder is
never loaded (folders beginning with `_` are skipped).

**Faster:** in the game, Mods -> Create New Mod -> tick "GUI theme
starter" writes this same scaffold into your mods library for you.

1. Copy this folder, rename the copy, and set your own `id`, `name` and
   `description` in `mod.json` (the id must never change once players
   have your mod). Swap `icon.png` for your own square picture.
2. Design in `data/gui_theme.json`: colours are named roles (`panel`,
   `button`, `accent`, `text`, `bottom_bar`, ...), metrics set the shapes
   and solidity (`panel_radius`, `border_width`, `panel_opacity`, ...).
   Delete any entry to keep the stock value for it - a three-colour file
   is a complete, valid theme. The starter also carries one `rules`
   entry: a style aimed at a single part of the interface (one screen,
   one control type, or one named control) rather than the whole game.
3. The four bundled designs (`mods/example.gui_glass/`, `.gui_neon`,
   `.gui_parchment`, `.gui_porcelain`) are complete references; the full
   role and metric list is in docs/modding/gui-themes.md.
4. Launch the game, open Mods and tick yours: it loads when you leave
   the screen. With two GUI theme mods on, the lower one in the list wins.
5. Share it: zip the folder so `mod.json` is at the zip root (or run
   `make mod-pack MOD=path/to/folder` from a source checkout).
