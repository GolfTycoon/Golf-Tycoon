# GUI themes: re-dressing the whole interface

A **GUI theme** is a mod that changes how the game's interface *looks* —
the HUD, menus, panels, popups, buttons, fields and scrollbars — without
changing anything the game does. It is the simplest kind of mod there is:
one JSON palette, no code, no permissions. Four bundled examples ship a
complete design each (**Modern Glass**, **Neon Fairway**, **Clubhouse
Parchment**, **Porcelain Fairway**); enable one on the Mods screen, leave
it, and every screen changes at once.

| You want to... | Do this |
| --- | --- |
| Try the bundled designs | Mods screen → tick `Example: … GUI` → Back (it loads on the way out) |
| Make your own in the game | Mods → **Create New Mod** → tick **GUI theme starter** → edit `data/gui_theme.json` → come back in → Back |
| Make your own by hand | Copy `mods/_gui_template/` (or any `example.gui_*` folder) and edit the palette |

## The manifest

A GUI theme is a data-only mod whose `content` holds one key:

```json
{
	"format_version": 1,
	"id": "you.cool_gui",
	"name": "Cool GUI",
	"version": "1.0.0",
	"api_version": 1,
	"author": "You",
	"description": "The whole interface, re-dressed.",
	"types": ["data", "gui", "cosmetic"],
	"content": {
		"gui_theme": "data/gui_theme.json"
	}
}
```

No `entry_point`, no `script` permission — the palette *is* the mod. The
path is relative to the mod folder, as with every content key. A script
mod can also register a theme in code:
`mod_api.register_gui_theme({...})` takes the same dictionary the JSON
file holds.

## The palette file

```json
{
	"name": "Modern Glass",
	"description": "Frosted glass: translucent panes, ice-white text.",
	"font_bold": "fonts/MyDisplay.ttf",
	"colors": {
		"panel": "16222ecc",
		"button": "2b4258b3",
		"accent": "8be9e2",
		"text": "f2f8fc",
		"bottom_bar": "0d1b28"
	},
	"metrics": {
		"panel_radius": 20,
		"panel_opacity": 0.88,
		"shadow_size": 10
	},
	"rules": [
		{ "target": {"screen": "MainMenu", "type": "Button"}, "radius": 22 }
	]
}
```

The file may also wrap the palette — `{ "gui_theme": { … } }` — both are
read. Everything is optional except that the file must parse: **a role
you leave out keeps the stock look**, so a three-line palette that only
moves `accent`, `panel` and `text` already restyles the whole game.
Colours are hex strings with or without the leading `#`, in `rrggbb` or
`rrggbbaa` form (the last pair is transparency — the glass look is just
a translucent `panel`), or an `[r, g, b, a]` array of 0–1 numbers.

A palette has five parts: `colors` (the roles below), `metrics` (shapes
and solidity), `font` / `font_bold` (typefaces), `rules` (styles for one
specific corner of the interface) and the `bottom_bar` colour family
inside `colors`, which dresses the bottom HUD. Broken entries warn in
plain language on the Mods screen and keep the stock value — a theme
with warnings still applies.

### Colour roles

| Role | Where you see it | Stock |
| --- | --- | --- |
| `panel` | Panel, card and dialog fills | dark green `182f29` |
| `inset` | Sunken wells: lists, text fields, grooves | near-black green |
| `deep` | The darkest tone: text on bright accents, deep shadows | `10241f` |
| `button` | Button fill (hover/pressed/disabled derive if unset) | moss green |
| `button_hover` | Button under the pointer | lighter moss |
| `button_pressed` | Button held down | darker moss |
| `button_disabled` | Button that cannot be pressed | faded moss |
| `primary` | The main action on a card (Play, Confirm…) | `365c43` |
| `primary_hover` | That action under the pointer | `476f50` |
| `border` | Hairline borders on panels and buttons | sage |
| `focus` | The keyboard/controller focus ring | warm cream |
| `scrollbar` | Scrollbar grips | grey |
| `scrollbar_hover` | A grip under the pointer | lighter grey |
| `text` | Body text | `f4edd9` |
| `text_dim` | Secondary text, button labels | `b9c7af` |
| `text_muted` | Disabled and quiet text | `7e9184` |
| `accent` | Highlights: card rims, progress fills, links | gold `e5c57c` |
| `accent_text` | Text set on the accent (or a selection) | `10241f` |
| `success` / `warning` / `danger` / `info` | Status colours in lists and labels | green/yellow/red/blue |
| `tooltip` | The tooltip slab (its text auto-picks ink or cream by lightness) | near-black |
| `bottom_bar` | The bottom HUD's turf fan, dark tone | `10241a` |
| `bottom_bar_light` | The fan's alternating mowing tone (derives from `bottom_bar`) | `173423` |
| `bottom_bar_socket` | The dark seat under each dock medallion (also derives) | `0a1811` |

### Metrics

| Metric | What it sets | Range (stock) |
| --- | --- | --- |
| `panel_radius` | Corner radius of panels and cards | 0–32 (16) |
| `button_radius` | Corner radius of buttons | 0–32 (14) |
| `border_width` | Hairline border thickness | 0–4 (1) |
| `font_size` | The interface's base font size | 10–20 (14) |
| `shadow_size` | Panel drop-shadow size | 0–16 (6) |
| `button_opacity` | How solid button backgrounds are (1 = fully painted) | 0–1 (1) |
| `panel_opacity` | How solid panel backgrounds are — the glass lever | 0–1 (1) |

The two opacities are fractions; everything else is whole numbers.
Out-of-range values clamp to the range and say so, never crash.

### Half-specified palettes finish themselves

- Set `button` alone and `button_hover` lifts from it, `button_pressed`
  sinks, `button_disabled` fades toward grey. The same derivation
  completes `primary_hover` from `primary`, `scrollbar_hover` from
  `scrollbar`, and `bottom_bar_light` / `bottom_bar_socket` from
  `bottom_bar` (the light turf lifts ≈×1.42, the sockets sink ≈×0.65).
- An **explicit** value is never derived over: naming `button_hover`
  keeps yours even when `button` also changes.

## Fonts

Two palette entries name typefaces, as paths inside your mod folder (or
a full `res://` / `user://` path):

- `"font"` — the body typeface. It dresses body text and every control
  that inherits the interface font.
- `"font_bold"` — the display typeface for headings and buttons, which
  the game sets in its heavier fonts. Name only this one and body text
  stays stock; name only `font` and display text uses it too.

Ship a `.ttf` or `.otf` in your mod (keep its licence beside it — the
Glass and Parchment examples ship Pixelify Sans weights under the SIL
OFL). A font file that cannot be loaded warns once and the stock
typeface stands in. Script mods may pass a loaded `Font` resource
instead of a path.

## Targeting one part of the interface: rules

Global roles re-dress the whole game at once. A **rule** aims a style at
one screen, one kind of control, or one single named control:

```json
"rules": [
	{ "target": {"screen": "ModsScreen", "type": "Button"},
	  "icon": "icons/bolt.png", "radius": 4 },
	{ "target": {"name": "QuitButton"},
	  "background": "7a1f1f", "text": "ffe9a8" },
	{ "target": {"screen": "HUD", "type": "PixelCircleButton", "name": "MenuBtn"},
	  "glyph": "flag" }
]
```

### The target

Every key you give must match (they AND together); an empty target is
rejected with a warning.

| Key | Matches | Examples |
| --- | --- | --- |
| `screen` | The named node the control lives under — the screen root, or `HUD` | `MainMenu`, `ModsScreen`, `SettingsMenu`, `PauseMenu`, `StartNewGameScreen`, `WorldMapScreen`, `HUD` |
| `type` | The control's engine class or script class | `Button`, `Label`, `PanelContainer`, `CheckBox`, `LineEdit`, `PixelCircleButton` |
| `name` | The control's own node name | `ContinueButton`, `QuitButton`, `MenuBtn` |

Landmark names worth knowing — on the main menu (`MainMenu`):
`ContinueButton`, `TournamentModeButton`, `LoadGameButton`,
`AchievementsButton`, `GolferSkinsButton`, `ModsButton`,
`SettingsButton`, `QuitButton`. In the HUD's bottom dock:
`BuildButton`, `ManageButton`, `GolfersButton` (the section medallions)
and `MenuBtn`, `PauseBtn`, `SpeedBtn`. When in doubt, `screen` + `type`
is the sturdy address: it survives layout changes that move nodes
around.

### The style

| Property | What it does |
| --- | --- |
| `background` | Fill colour. On buttons, hover/pressed/disabled derive from it unless you name them; on medallions it is the face colour; on a `ColorRect`, its colour |
| `background_hover`, `background_pressed`, `background_disabled` | The button states, explicitly |
| `border` | Border colour (gains a 1px border if the box had none) |
| `text` | Text colour, in every state |
| `radius` | Corner radius (0–32) |
| `border_width` | Border thickness (0–4) |
| `shadow_size` | Drop-shadow size (0–16) |
| `font_size` | This target's font size (8–40) |
| `opacity` | Background solidity multiplier (0–1) |
| `font` | A typeface file for this target alone |
| `icon` | An image file (`.png`…) shown as a Button's icon |
| `glyph` | A medallion pictogram for a `PixelCircleButton` |

Anything else in a rule warns as unknown and is ignored; a rule that
ends up styling nothing is skipped with a note.

Medallion glyphs you can name: `menu`, `feed`, `inspect`, `build`,
`manage`, `golfers`, `terrain`, `improvements`, `buildings`,
`elevation`, `holes`, `flag`, `maps`, `club`, `review`, `milestone`,
`world`, `achievement`, `marketing`, `staff`, `edit`, `skills`, `pause`,
`play`, `fast`, `ultra`, `rotate_ccw`, `rotate_cw`, `finance`,
`bulldozer`, `brush_round`, `brush_square`, `minus`, `plus`.

### How rules combine

Rules **merge property by property**. For each property, the most
specific matching rule that sets it wins — specificity is `name` (4) +
`screen` (2) + `type` (1) — and between equals, the rule later in the
list wins. So a broad screen rule and one named-button exception compose
instead of fighting: the exception overrides only what it mentions. A
rule always beats the global palette on its own turf.

## Where the colours land

One design has to dress three 
...[truncated 3075 chars]