# Example: Neon Fairway GUI (a GUI theme mod)

The clubhouse after dark, in neon. Same mechanism as every GUI theme
mod - one `"gui_theme"` content key and one JSON palette, no code - but
the design leans on the **metrics** as much as the colours: small 6px
corner radii and a 2px border turn the game's soft glass pills into
sharp neon signage, while `focus` in electric yellow keeps keyboard and
controller navigation unmissable.

This example also shows **rules** - styles aimed at one part of the
interface instead of the whole game. Its one rule gives every button on
the Mods screen a bolt icon (a plain PNG in `icons/`, loaded like any
other mod art) plus a tighter radius and heavier border. And the bottom
bar gets its own say through the `bottom_bar` turf colours.

Compare this file with `example.gui_glass`: identical shape, opposite
character. That is the point of the format - see
docs/modding/gui-themes.md for every role, metric and rule you can set.
