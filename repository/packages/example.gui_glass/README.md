# Example: Modern Glass GUI (a GUI theme mod)

The whole game in frosted glass - and not one line of code. A GUI theme
mod is a single JSON palette:

- `mod.json` declares one content key, `"gui_theme": "data/gui_theme.json"`.
  That is the entire mechanism: no `entry_point`, no `script` permission.
- `data/gui_theme.json` names colours by **role** (`panel`, `button`,
  `accent`, `text`, ...) plus a few metrics (corner radii, border width,
  shadow size). When the mod is enabled and the game reloads, the main
  scene builds its Theme from the palette, re-maps the code-built HUD and
  panel styles onto the same roles, and repaints the menu cards - so the
  HUD, menus, panels, popups, fields, menus and scrollbars all change at
  once.
- Roles a file leaves out keep the stock look. This example sets almost
  every role; a smaller file that only sets `accent`, `panel` and `text`
  is just as valid and restyles everything in those three moves.
- The glass itself is two metrics: `panel_opacity` 0.88 and
  `button_opacity` 0.82 wear the palette's colours at that solidity
  instead of fully painted. Headings set in the chunkier Pixelify Sans
  ExtraBold, shipped in `fonts/` (SIL OFL, licence beside it) and named
  by the palette's `font_bold`. Even the bottom bar's turf fan follows,
  through the `bottom_bar` colours.

With two GUI theme mods enabled, the one lower in the Mods list wins -
the same rule as every provider. Switch this one off (or move it above
another GUI theme) and leave the screen to go back.

**Make your own:** copy this folder (or use Mods -> Create New Mod and
tick "GUI theme starter"), change the hex colours, and reload. The full
role and metric reference, the derivation rules for half-specified
palettes and the coverage notes live in docs/modding/gui-themes.md.
