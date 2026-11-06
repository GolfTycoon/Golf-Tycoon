# Example: Harbour Dusk & Starfield (a background mod)

A menu-background mod adds pictures and overlays to **Settings → Display →
Background**. Everything here is data: `mod.json` declares two catalogue files
and nothing else, so no script runs and the mod needs no permissions.

## What ships in the box

| Entry | Kind | What it is |
| --- | --- | --- |
| `harbour_dusk` | backdrop | The clubhouse after sundown, warm harbour lights. Tagged for Fall and for resort/tropical courses. |
| `moonlit_frost` | backdrop | A blue winter night over the snow. Tagged for Winter and mountain/woodland courses. |
| `starfield` | overlay | A scatter of stars (`sparkle`), with its own Density choice. Tagged for Winter. |
| `club_crest` | overlay | A gold `grid` lattice at any angle - the same painter the shipped Clubhouse Lattice uses, restyled. |
| `green_keeper_bands` | overlay | Wide mowing `stripes`, tagged for parkland and links courses. |

## The two files

`data/backdrops.json` and `data/overlays.json`, declared in `mod.json` as:

```json
"content": {
	"menu_backdrops": "data/backdrops.json",
	"menu_overlays":  "data/overlays.json"
}
```

Both use a wrapper key (`backdrops` / `overlays`) around `{id: entry}`.

### A backdrop entry

| Field | Meaning |
| --- | --- |
| `name`, `description` | What the picker and its tooltip say. |
| `image` | The picture, **relative to the JSON file's own folder** (or a full `res://` / `user://` path). PNG, JPG, WEBP and BMP all decode. 1280×720 or wider is the size the menus are designed for; any shape is cover-cropped, never stretched. |
| `tint` | Optional hex colour multiplied over the picture - restyle a shipped image without repainting it. `ffffff` leaves it alone. |
| `tint` | A colour multiplied over the picture; `ffffff` leaves it alone |
| `seasons`, `themes` | What **Auto** looks at. As soon as a picture is tagged for the season or the course theme being played, Auto prefers it. Leave both empty to stay out of Auto's way. |

### An overlay entry

| Field | Meaning |
| --- | --- |
| `pattern` | One of `none`, `wash`, `vignette`, `glow`, `split`, `stripes`, `grid`, `scanlines`, `dots`, `sparkle` (see `MenuBackdropOverlay`). |
| `color`, `strength` | The ink and its opacity. |
| `scale` | The pattern's feature size in logical pixels - band width, grid spacing, dot pitch. |
| `setting_ids` | The extra choices the overlay offers, each declared in the file's `settings` block. |
| `seasons`, `themes` | Same Auto rule as a backdrop. |

### Patching instead of adding

Naming an id that already exists - `clubhouse`, `winter`, `fairway_stripes` -
patches that entry rather than adding a new one. This mod could have repainted
the shipped clubhouse with a warm tint instead of shipping its own file. New ids
are namespaced to the mod automatically (`example.backgrounds:harbour_dusk`),
so two mods can never collide by accident.

## Try it

1. The Mods screen lists this mod as **off** (only the three official mods load
   by default). Tick it and press **Apply & Reload**.
2. Open **Settings → Display → Background**. Both new pictures and all three
   overlays are in the lists, marked with this mod's id.
3. Leave both on **Auto** and visit the title screen in Winter, or open a resort
   course: Auto picks the new pictures by itself, because of the tags.

See `docs/modding/manifest-and-packaging.md` for the field reference.
