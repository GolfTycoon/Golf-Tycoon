# Golfer Skins

> A skin is the set of colours and artwork that dresses a golfer. Skins are plain text files, so you can edit them in the studio or by hand.

**Source:** `scripts/autoload/golfer_skins.gd`, `scripts/systems/golfer_skin.gd`, `scripts/systems/golfer_skin_layer.gd`, `scripts/systems/golfer_skin_library.gd`, `scripts/ui/` (skin studio screens), `tools/generate_golfer_skin_layers.gd`
**Tests:** `tests/unit/test_golfer_skins.gd`, `tests/unit/test_golfer_skin_editor.gd`

---

## Plain English

Every golfer on the course wears a skin. A skin has **groups** (Shirt, Pants, Cap, Hair, Skin and any groups you add) and an **animation sprite** for each direction and frame. Re-colouring a group changes that part of every golfer who wears the skin.

You can change skins in two ways:

- **The Golfer Skins studio** on the title screen. Paint pixels, or re-colour whole groups.
- **By hand.** Skins are text files you can open and edit.

Visiting golfers wear skins too. Each visiting golfer's JSON file names the skin it uses. See [Data Reference](data-reference.md).

## The Studio

- **Edit** switches between the two sides of the studio.
- **Pixels** edits the sprite's artwork with a colour picker and a brush. Right-click erases, and Alt-click picks up a colour.
- **Groups** assigns the pixels under the brush to a group. A click on the sprite selects the group that pixel belongs to. You can rename, re-colour or delete groups, or add your own.
- **Save** copies a built-in skin into your own folder. **Revert** restores the shipped version. **New Skin** starts a skin from scratch. **Duplicate** copies groups and layers together.
- **Wear This** puts a skin on your own golfer. The tiers of visiting golfers that wear it can be chosen too.

## File Format

A skin is a folder with two kinds of file:

| File | Holds |
| --- | --- |
| `skin.txt` | The groups and their colours |
| `layers/<animation>/<direction>/frame_NNN.layer.txt` | The group grid for each sprite frame, plus any painted pixels as hex colours |

Built-in skins live in `data/golfer_skins/`. The shipped ones are `beginner` and `casual`. Skins you save are stored in `user://golfer_skins`, so the shipped files are never changed. **Settings → Data → Delete Custom Skins** removes that whole folder; a golfer wearing one falls back to the shipped skin for its tier. See [Save & Load](save-and-load.md#deleting-player-data).

The sprite PNGs are imported resources. Exported builds may contain only their imported textures rather than the original PNG files, so the runtime discovers animation frames through Godot's resource loader and import remaps.

`tools/generate_golfer_skin_layers.gd` builds the layer files for a skin.

## Related

- [Data Reference](data-reference.md) lists the skin folders and the visitor files that reference them.
- [UI & Controls](ui-and-controls.md) lists where the studio is opened from.
