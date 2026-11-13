# Example: Clubhouse Parchment GUI (a GUI theme mod)

The members' ledger look: paper, ink and brass. This example exists to
prove the format handles a **light design on a dark game** - `text`,
`text_dim` and `text_muted` go dark while `panel` and `button` go cream,
and every role that assumed a dark surround (tooltip, focus, scrollbars,
status colours) is restated in sepia-friendly values with it. One JSON
palette, no code, the same `"gui_theme"` content key as the other GUI
examples.

Parchment also ships a **typeface**: `fonts/PixelifySans-Bold.ttf`
(the game's own display font, SIL OFL - see the licence beside it) is
named by the palette's `font` entry, so every line of body text is set
in bold, like entries stamped into the ledger. Any .ttf or .otf in your
mod folder works the same way.

Note the tooltip stays a dark slab (`2e2114f2`): the game picks a legible
tooltip text colour from the tooltip's own lightness, so a parchment
interface can keep dark tooltips - or set a cream one and get ink text.
See docs/modding/gui-themes.md for the full role list.
