extends RefCounted
class_name ModScaffold
## ModScaffold - Writes a new, ready-to-edit mod into the player's library.
##
## The Mods screen's **Create New Mod** button asks for the few things a mod
## cannot be valid without, then scaffolds `user://mods/<id>/`: a `mod.json`
## the loader accepts, a README with the next steps, and - when the box is
## ticked - a starter `mod_main.gd` extending GolfTycoonMod.
##
## Creating is not enabling. The folder is discovered by the rescan that
## follows, arrives switched off like an installed zip, and changes nothing
## until the player ticks it and presses Apply & Reload.
##
## Everything here is static and autoload-free (like ModPackage), so the
## rules can be tested - and reused by tools - without a running game.

const DEFAULT_VERSION: String = "0.1.0"
const SCRIPT_FILE: String = "mod_main.gd"
const GUI_THEME_FILE: String = "data/gui_theme.json"
const README_FILE: String = "README.md"
const ICON_FILE: String = "icon.png"
const DEFAULT_DESCRIPTION: String = "A new Golf Tycoon mod."
## Folder names the mod library keeps for itself. A mod created there would
## either be invisible to discovery (`config`) or break the install shelf
## (`installed`).
const RESERVED_FOLDER_NAMES: Array[String] = ["installed", "config"]

const STARTER_SCRIPT: String = """extends GolfTycoonMod
## {name} - starter entry point.
##
## Created from the Mods screen. This is ordinary GDScript: register hooks,
## providers or HUD widgets through the Mod API, and listen to the game's
## event signals. Two rules keep the mod loadable everywhere:
##
##   * no class_name in mod files (preload() siblings by relative path),
##   * undo in _mod_unload whatever you added outside the Mod API.
##
## The bundled examples each show one kind of mod end to end; see
## docs/modding/mod-api.md for the full surface.


func _mod_load(mod_api: ModAPI) -> void:
	mod_api.log_info("Hello from " + mod_id + " (Mod API " + str(mod_api.api_version()) + ").")


func _mod_unload() -> void:
	# Disconnect signals and free nodes you added to the main scene.
	pass


func _mod_new_game() -> void:
	# A brand new company just started.
	pass


func _mod_save() -> Dictionary:
	# Plain JSON-shaped state to keep in the save file, or {} for none.
	return {}


func _mod_restore(_data: Dictionary) -> void:
	# The dictionary _mod_save returned ({} for older or foreign saves).
	pass
"""


## True when the form asked for a starter script (and so for the "script"
## permission). The dialog defaults to a script, matching mods/_template.
## A GUI theme starter is data-only by design - theming needs no code - so
## it wins over the script tick.
static func has_script(fields: Dictionary) -> bool:
	return bool(fields.get("script", true)) and not has_gui_theme(fields)


## True when the form asked for the GUI theme starter: a mod that
## re-dresses the whole interface from one JSON palette (see
## docs/modding/gui-themes.md). This is how a new GUI theme mod is born.
static func has_gui_theme(fields: Dictionary) -> bool:
	return bool(fields.get("gui_theme", false))


## The id as a safe folder/file token, trimmed. Callers validate it with
## validate() before using it.
static func clean_id(fields: Dictionary) -> String:
	return str(fields.get("id", "")).strip_edges()


## Why this form cannot create a mod yet, as player-readable lines. Empty
## when it can. `taken_ids` is what the library already knows about
## (ModManager.get_installed_mod_ids()).
static func validate(fields: Dictionary, taken_ids: Array = []) -> Array[String]:
	var errors: Array[String] = []
	var mod_id: String = clean_id(fields)
	var display_name: String = str(fields.get("name", "")).strip_edges()
	if mod_id.is_empty():
		errors.append("Give the mod an id, like yourname.my_mod.")
	elif not ModManifest.is_valid_mod_id(mod_id):
		errors.append("That id is not usable: start with a letter and use only lower-case letters, digits, '.', '_' or '-' (for example yourname.my_mod).")
	elif mod_id in RESERVED_FOLDER_NAMES:
		errors.append("'%s' is reserved by the mod library. Pick another id." % mod_id)
	elif taken_ids.has(mod_id):
		errors.append("A mod with the id '%s' is already installed. Pick another id." % mod_id)
	if display_name.is_empty():
		errors.append("Give the mod a name: it is the title players see in this list.")
	elif display_name.length() > 80:
		errors.append("Keep the name to 80 characters or fewer.")
	var version: String = str(fields.get("version", DEFAULT_VERSION)).strip_edges()
	if ModManifest.parse_version(version).is_empty():
		errors.append("The version must look like 0.1.0.")
	if not errors.is_empty():
		return errors
	# The manifest is the contract; build it exactly as it will be written
	# and let its own validation be the last word.
	var manifest := ModManifest.from_dictionary(manifest_for(fields))
	for message in manifest.errors:
		if not message in errors:
			errors.append(message)
	return errors


## The `mod.json` contents as a plain dictionary, in a readable order.
static func manifest_for(fields: Dictionary) -> Dictionary:
	var mod_id: String = clean_id(fields)
	var display_name: String = str(fields.get("name", "")).strip_edges()
	var description: String = str(fields.get("description", "")).strip_edges()
	if description.is_empty():
		description = DEFAULT_DESCRIPTION
	var data: Dictionary = {
		"format_version": ModManifest.FORMAT_VERSION,
		"id": mod_id,
		"name": display_name,
		"version": str(fields.get("version", DEFAULT_VERSION)).strip_edges(),
		"api_version": ModManifest.CURRENT_API_VERSION,
		"author": str(fields.get("author", "")).strip_edges(),
		"description": description,
		"homepage": "",
		"icon": ICON_FILE,
		"types": ["script", "gameplay"] if has_script(fields) \
			else (["data", "gui", "cosmetic"] if has_gui_theme(fields) else ["data"]),
		"dependencies": [],
		"content": {"gui_theme": GUI_THEME_FILE} if has_gui_theme(fields) else {},
		"workshop": {"published_file_id": 0, "tags": []},
	}
	if has_script(fields):
		data["entry_point"] = SCRIPT_FILE
		data["permissions"] = [ModManifest.PERMISSION_SCRIPT]
	return data


## The placeholder icon a new mod is born with: the same muted puzzle piece
## the Mods screen falls back to, so the mod shows a picture of its own
## before the modder has painted one. 64x64, the row size times two.
static func icon_image() -> Image:
	return PixelIcon.image(PixelIcon.Kind.PUZZLE, 64, MenuStyle.ACCENT_UTILITY, true)


## The starter gui_theme.json for a GUI theme scaffold: the stock design
## with a few clearly-marked colours changed, so the mod visibly dresses
## the interface the first time it is enabled and every value it does not
## mention demonstrates the stock fallback it inherits. Edit the colours,
## keep the shape - docs/modding/gui-themes.md lists every role.
static func starter_gui_theme(display_name: String) -> String:
	var heading: String = _one_line(display_name)
	if heading.is_empty():
		heading = "My Interface"
	var spec: Dictionary = {
		"name": heading,
		"description": "A new interface design. Edit the colours in this file, then tick the mod and Apply & Reload.",
		"colors": {
			"accent": "8be9e2",
			"panel": "16222ecc",
			"button": "2b4258b3",
			"text": "f2f8fc",
			"bottom_bar": "0d1b28",
		},
		"metrics": {
			"panel_radius": 18,
			"button_radius": 14,
		},
		# One targeted rule as a worked example: only the Mods screen's
		# buttons round over. Rules can aim at a screen, a control type or
		# one named control - docs/modding/gui-themes.md has the list.
		"rules": [
			{"target": {"screen": "ModsScreen", "type": "Button"}, "radius": 18},
		],
	}
	return JSON.stringify(spec, "\t") + "\n"


## The starter mod_main.gd for a scripted scaffold, or "" for a data mod.
static func starter_script(display_name: String) -> String:
	var heading: String = _one_line(display_name)
	if heading.is_empty():
		heading = "New mod"
	return STARTER_SCRIPT.replace("{name}", heading)


## The folder's README: what this scaffold is, and the shortest path from
## here to a working, shareable mod.
static func readme_text(fields: Dictionary) -> String:
	var mod_id: String = clean_id(fields)
	var display_name: String = _one_line(str(fields.get("name", "")))
	if display_name.is_empty():
		display_name = mod_id
	var lines: Array[String] = []
	lines.append("# " + display_name)
	lines.append("")
	lines.append("Created from the Mods screen's **Create New Mod** button.")
	lines.append("The mod id is `%s`: it names this folder and everything the" % mod_id)
	lines.append("mod adds, and must never change once players have saves.")
	lines.append("")
	lines.append("## Next steps")
	lines.append("")
	lines.append("The `icon.png` at the mod's root is the picture the Mods screen shows")
	lines.append("next to its name - a placeholder until you replace it with your own")
	lines.append("(PNG, JPG, WebP or BMP; a square reads best).")
	lines.append("")
	if has_script(fields):
		lines.append("1. Open `%s` and write the mod." % SCRIPT_FILE)
		lines.append("2. Describe it in `mod.json`; players read that description in the Mods screen.")
		lines.append("3. In the game: Mods -> tick the mod -> Apply & Reload.")
	elif has_gui_theme(fields):
		lines.append("1. Open `%s` and make the design yours: every colour" % GUI_THEME_FILE)
		lines.append("   is a named role (`panel`, `button`, `accent`, `text`, ...),")
		lines.append("   and any role you delete simply keeps the stock look. The")
		lines.append("   starter also carries one `rules` entry - a style aimed at")
		lines.append("   one part of the interface (a screen, a control type, or one")
		lines.append("   named control) instead of the whole game. The full role,")
		lines.append("   metric and rule list is in docs/modding/gui-themes.md in")
		lines.append("   the game repository; the bundled example.gui_* mods are")
		lines.append("   complete designs to borrow from.")
		lines.append("2. Describe it in `mod.json`; players read that description in the Mods screen.")
		lines.append("3. In the game: Mods -> tick the mod -> Apply & Reload. The")
		lines.append("   whole interface - HUD, menus, panels - changes at once.")
		lines.append("   With two GUI theme mods on, the lower one in the list wins.")
	else:
		lines.append("1. Add your JSON files beside this README.")
		lines.append("2. Point the matching key in `mod.json`'s `content` at them.")
		lines.append("   (Start with `content.buildings` or `content.tuning`; the")
		lines.append("   bundled examples show every kind, and this is a data-only")
		lines.append("   mod, so no code runs.)")
		lines.append("3. In the game: Mods -> tick the mod -> Apply & Reload.")
	lines.append("4. Share it: zip this folder so `mod.json` is at the zip root,")
	lines.append("   then install it from Mods -> Install ZIP on another machine.")
	lines.append("")
	lines.append("In the game repository, `docs/modding.md` is the full guide;")
	lines.append("`docs/modding/manifest-and-packaging.md` is the field reference.")
	return "\n".join(lines) + "\n"


## Scaffold `user_root/<id>/`. Result: {ok, mod_id, directory, files, errors}.
## Nothing is written until every rule in validate() passes, and a failure
## while writing removes the folder again rather than leaving it half-made.
static func create(user_root: String, fields: Dictionary, taken_ids: Array = []) -> Dictionary:
	var result: Dictionary = {
		"ok": false, "mod_id": "", "directory": "", "files": [], "errors": [],
	}
	var errors: Array[String] = validate(fields, taken_ids)
	if not errors.is_empty():
		result["errors"] = errors
		return result
	var mod_id: String = clean_id(fields)
	var directory: String = user_root.path_join(mod_id)
	if DirAccess.dir_exists_absolute(directory):
		result["errors"] = ["A folder named '%s' is already in your mods folder. Pick another id." % mod_id]
		return result
	DirAccess.make_dir_recursive_absolute(directory)
	if not DirAccess.dir_exists_absolute(directory):
		result["errors"] = ["Could not create the folder '%s'. Check that the mods folder is writable." % directory]
		return result
	var contents: Dictionary = {
		"mod.json": JSON.stringify(manifest_for(fields), "\t") + "\n",
		README_FILE: readme_text(fields),
	}
	var files: Array[String] = ["mod.json", README_FILE]
	if has_script(fields):
		contents[SCRIPT_FILE] = starter_script(str(fields.get("name", "")))
		files.append(SCRIPT_FILE)
	if has_gui_theme(fields):
		DirAccess.make_dir_recursive_absolute(directory.path_join(GUI_THEME_FILE).get_base_dir())
		contents[GUI_THEME_FILE] = starter_gui_theme(str(fields.get("name", "")))
		files.append(GUI_THEME_FILE)
	for relative in files:
		if not _write_text(directory.path_join(relative), str(contents[relative])):
			ModPackage.remove_directory_recursive(directory)
			result["errors"] = ["Could not write '%s'. Check that the mods folder is writable." % directory.path_join(relative)]
			return result
	# The mod's own picture for the Mods screen, like every other mod's.
	if icon_image().save_png(directory.path_join(ICON_FILE)) != OK:
		ModPackage.remove_directory_recursive(directory)
		result["errors"] = ["Could not write '%s'. Check that the mods folder is writable." % directory.path_join(ICON_FILE)]
		return result
	files.append(ICON_FILE)
	result["ok"] = true
	result["mod_id"] = mod_id
	result["directory"] = directory
	result["files"] = files
	return result


## A form value on one line: names become comment text and headings, so
## stray line breaks must not be able to split either.
static func _one_line(text: String) -> String:
	return text.strip_edges().replace("\n", " ").replace("\r", " ")


static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
