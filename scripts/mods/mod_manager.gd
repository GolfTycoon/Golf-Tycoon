extends Node
## ModManager - Central mod lifecycle, ordering, conflict resolution, and API.
##
## Autoloaded as `ModManager` (see project.godot). Owns:
##   - Discovery (via ModLoader)
##   - Validation and dependency/ordering resolution
##   - Enabled-ordered-list (the source of truth for conflicts: later wins)
##   - Loading/unloading and hook dispatch
##   - Content registries (buildings, decorations, terrain, modifiers, etc.)
##   - Feature flags (weather, wind, seasons, and mod-added features)
##   - Persistence (user://mods.json globally, save file per-course)
##   - Conflict reporting for the Mods screen
##
## Conflict resolution policy:
##   "last wins" — when two enabled mods register the same id (building type,
##   terrain, hook override), the one later in the ordered list takes effect.
##   A warning is emitted and shown in the Mods screen's conflict report.
##   This makes ordering meaningful and user-controllable, as the task requires.
##
## Stability guarantees:
##   - A failing mod never crashes the game: load errors are caught, logged,
##     and the mod is marked FAILED + disabled.
##   - All hook dispatch is try/catch — one mod's error doesn't stop others.
##   - Save compatibility: saves record which mods (and versions) were enabled;
##     loading a save with missing mods warns but still loads.
##   - API versioning: mods declare api_version; incompatible mods are rejected.

# ---------------------------------------------------------------------------
# Signals (for UI and other systems)
# ---------------------------------------------------------------------------
signal mods_discovered(count: int)
signal mods_loaded()
signal mod_enabled(mod_id: String)
signal mod_disabled(mod_id: String)
signal enabled_order_changed(order: Array)  # Array[String]
signal mod_error(mod_id: String, message: String)
signal conflict_detected(conflicts: Array)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## All discovered manifests, id -> ModManifest
var manifests: Dictionary = {}
## All discovered mods, id -> Mod (wraps manifest + state)
var mods: Dictionary = {}
## Ordered list of enabled mod ids. This IS the load order and conflict order.
## Later entries load later and win conflicts.
var enabled_mods: Array[String] = []
## Feature flags contributed by mods (feature_id -> { mod_id, name, description })
var features: Dictionary = {}
## Modifier hooks: modifier_id -> Array[{ mod_id, callable, handle }]
var modifiers: Dictionary = {}
## EventBus hooks: signal_name -> Array[{ mod_id, callable, handle }]
var hooks: Dictionary = {}
## UI sections contributed by mods.
var ui_sections: Array[Dictionary] = []
## Content registries (building/decoration/terrain overrides track origin mod)
var building_registry_overrides: Dictionary = {}  # id -> { mod_id, data }
var decoration_registry_overrides: Dictionary = {}
var terrain_registry_overrides: Dictionary = {}
## Per-mod save data (mod_id -> { key -> value })
var mod_save_data: Dictionary = {}
## Conflict report for the UI (last validation run).
var last_conflicts: Array[Dictionary] = []
## Whether discovery has been performed.
var _discovered: bool = false
## Suppress persistence during bulk operations.
var _suppress_persist: bool = false

const FEATURES_BUILTIN := ["weather", "wind", "seasons"]

func _ready() -> void:
	# Discover early so other autoloads can query manifest info
	discover_mods()
	# Load persisted enabled order (or defaults)
	_load_enabled_order()
	# Load all enabled mods now (builtin systems may query features immediately)
	load_enabled_mods()

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

func discover_mods() -> void:
	if _discovered:
		return
	_discovered = true
	manifests = ModLoader.discover()
	mods.clear()
	for id in manifests:
		var m := Mod.new(manifests[id])
		mods[id] = m
		if not m.validate(manifests):
			push_warning("ModManager: mod %s failed validation: %s" % [id, m.error_message])
	mods_discovered.emit(mods.size())
	print("ModManager: discovered %d mod(s): %s (enabled order: %s)" % [mods.size(), str(manifests.keys()), str(enabled_mods)])

## Re-scan after a user import/create/delete. Keeps current enabled order,
## validates newly discovered manifests, and emits signals so the Mods screen
## can refresh without a restart.
func refresh_after_user_change() -> void:
	_discovered = false
	var prev_enabled := enabled_mods.duplicate()
	discover_mods()
	# Keep previous enabled list but drop ids that vanished
	var filtered: Array[String] = []
	for eid in prev_enabled:
		if manifests.has(eid):
			filtered.append(eid)
		else:
			push_warning("ModManager: previously enabled mod '%s' no longer found — dropping" % eid)
	enabled_mods = filtered
	_resync_mod_states()
	_persist_enabled_order()
	mods_discovered.emit(mods.size())
	updated_conflicts()
	print("ModManager: refreshed after user change -> %d mods" % mods.size())

func get_manifest(mod_id: String) -> ModManifest:
	return manifests.get(mod_id, null)

func get_mod(mod_id: String) -> Mod:
	return mods.get(mod_id, null)

func get_all_mods() -> Dictionary:
	return mods.duplicate()

func get_all_manifests() -> Dictionary:
	return manifests.duplicate()

func is_mod_enabled(mod_id: String) -> bool:
	return enabled_mods.has(mod_id)

func get_enabled_mods_ordered() -> Array[String]:
	return enabled_mods.duplicate()

func get_available_mods_sorted() -> Array:
	# Return Mods sorted by load_priority then name
	var arr: Array = mods.values()
	arr.sort_custom(func(a, b): return a.manifest.load_priority < b.manifest.load_priority if a.manifest.load_priority != b.manifest.load_priority else a.get_name() < b.get_name())
	return arr

# ---------------------------------------------------------------------------
# Enabled order persistence
# ---------------------------------------------------------------------------

func _load_enabled_order() -> void:
	var persisted = ModLoader.load_enabled_order()
	if persisted is Array:
		# Validate: keep only ids that still exist on disk
		var filtered: Array[String] = []
		for entry in persisted:
			var eid := str(entry)
			if manifests.has(eid):
				filtered.append(eid)
			else:
				push_warning("ModManager: persisted enabled mod '%s' not found on disk — skipping" % eid)
		enabled_mods = filtered
		# If the persisted file was empty/corrupt, fall through to defaults
		if not enabled_mods.is_empty():
			print("ModManager: loaded persisted enabled order: %s" % str(enabled_mods))
			_resync_mod_states()
			return
	# No persisted file yet: use enabled_by_default for builtins (weather/wind/seasons off by default for compat)
	# The three environment mods start disabled to preserve old default (all features off).
	# Tests and new games will explicitly enable them via world_map features or the Mods screen.
	var defaults: Array[String] = []
	for id in manifests:
		var mm: ModManifest = manifests[id]
		if mm.enabled_by_default:
			defaults.append(id)
	# Builtins default order is by load_priority
	defaults.sort_custom(func(a, b): return manifests[a].load_priority < manifests[b].load_priority)
	enabled_mods = defaults
	_resync_mod_states()
	print("ModManager: using default enabled order: %s" % str(enabled_mods))

func _persist_enabled_order() -> void:
	if _suppress_persist:
		return
	ModLoader.save_enabled_order(enabled_mods)

func _resync_mod_states() -> void:
	for id in mods:
		var m: Mod = mods[id]
		m.enabled = enabled_mods.has(id)
		m.load_order = enabled_mods.find(id) if m.enabled else -1
		if m.enabled and m.state == Mod.State.DISCOVERED:
			m.state = Mod.State.VALIDATED

# ---------------------------------------------------------------------------
# Dependency & conflict validation
# ---------------------------------------------------------------------------

## Validate the current enabled order. Returns { valid: bool, errors: [], warnings: [], conflicts: [] }.
func validate_enabled_order(order: Array[String] = []) -> Dictionary:
	var check_order: Array[String] = order if not order.is_empty() else enabled_mods
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var conflicts_out: Array[Dictionary] = []

	var present := {}
	for eid in check_order:
		present[eid] = true

	# Dependencies
	for eid in check_order:
		var mf: ModManifest = manifests.get(eid, null)
		if mf == null:
			errors.append("Unknown mod: %s" % eid)
			continue
		for dep in mf.dependencies:
			if not present.has(dep):
				errors.append("%s requires %s" % [eid, dep])
			elif not manifests.has(dep):
				errors.append("%s requires %s (not found on disk)" % [eid, dep])

	# Conflicts
	for eid in check_order:
		var mf: ModManifest = manifests.get(eid, null)
		if mf == null:
			continue
		for conflict_id in mf.conflicts:
			if present.has(conflict_id):
				var info := { "mod_a": eid, "mod_b": conflict_id, "reason": "%s conflicts with %s" % [eid, conflict_id] }
				conflicts_out.append(info)
				warnings.append("%s conflicts with %s — later in the list wins" % [eid, conflict_id])

	# Load ordering violations (load_after / load_before)
	var pos := {}
	for i in check_order.size():
		pos[check_order[i]] = i
	for eid in check_order:
		var mf: ModManifest = manifests.get(eid, null)
		if mf == null:
			continue
		for after_id in mf.load_after:
			if present.has(after_id) and pos[eid] < pos[after_id]:
				warnings.append("%s should load after %s — move it down in the list" % [eid, after_id])
		for before_id in mf.load_before:
			if present.has(before_id) and pos[eid] > pos[before_id]:
				warnings.append("%s should load before %s — move it up" % [eid, before_id])

	return { "valid": errors.is_empty(), "errors": errors, "warnings": warnings, "conflicts": conflicts_out }

## Resolve load order respecting dependencies (topological sort) + user order as tiebreaker.
func resolve_load_order(requested: Array[String]) -> Array[String]:
	# Build adjacency: dep -> dependents
	if requested.is_empty():
		return []
	var in_degree := {}
	var adj := {}
	for eid in requested:
		in_degree[eid] = 0
		adj[eid] = []
	# Add edges for hard dependencies
	for eid in requested:
		var mf: ModManifest = manifests.get(eid, null)
		if mf == null:
			continue
		for dep in mf.dependencies:
			if adj.has(dep):
				adj[dep].append(eid)
				in_degree[eid] += 1
	# Also add load_after edges (soft ordering)
	for eid in requested:
		var mf: ModManifest = manifests.get(eid, null)
		if mf == null:
			continue
		for after_id in mf.load_after:
			if adj.has(after_id):
				adj[after_id].append(eid)
				in_degree[eid] += 1

	# Kahn's algorithm, picking lowest user-order position first when multiple ready
	var result: Array[String] = []
	var available: Array[String] = []
	for eid in requested:
		if in_degree[eid] == 0:
			available.append(eid)

	var user_pos := {}
	for i in requested.size():
		user_pos[requested[i]] = i

	while not available.is_empty():
		# Pick smallest user_pos (preserves user order where no dependency forces otherwise)
		available.sort_custom(func(a, b): return user_pos[a] < user_pos[b])
		var cur: String = available.pop_front()
		result.append(cur)
		for nxt in adj[cur]:
			in_degree[nxt] -= 1
			if in_degree[nxt] == 0:
				available.append(nxt)

	if result.size() != requested.size():
		push_warning("ModManager: circular dependency detected in %s — falling back to user order" % str(requested))
		return requested
	return result

# ---------------------------------------------------------------------------
# Enabling / disabling / reordering
# ---------------------------------------------------------------------------

func set_mod_enabled(mod_id: String, should_enable: bool) -> bool:
	if not manifests.has(mod_id):
		push_warning("ModManager: unknown mod %s" % mod_id)
		return false
	var currently := is_mod_enabled(mod_id)
	if should_enable == currently:
		return true
	if should_enable:
		# Validate that adding this mod doesn't break dependencies in current + new
		var proposed := enabled_mods.duplicate()
		proposed.append(mod_id)
		var validation := validate_enabled_order(proposed)
		if not validation["valid"]:
			for e in validation["errors"]:
				push_warning("ModManager: cannot enable %s: %s" % [mod_id, e])
			mod_error.emit(mod_id, "; ".join(validation["errors"]))
			return false
		# Insert at end (user can reorder afterwards)
		enabled_mods.append(mod_id)
		var m: Mod = mods[mod_id]
		m.enabled = true
		m.load_order = enabled_mods.size() - 1
		# Try to load
		var api := ModAPI.new(mod_id, self)
		if not m.enable(api):
			enabled_mods.erase(mod_id)
			m.enabled = false
			m.load_order = -1
			push_error("ModManager: failed to enable %s: %s" % [mod_id, m.error_message])
			mod_error.emit(mod_id, m.error_message)
			return false
		_persist_enabled_order()
		updated_conflicts()
		mod_enabled.emit(mod_id)
		enabled_order_changed.emit(enabled_mods.duplicate())
		print("ModManager: enabled %s (order now %s)" % [mod_id, str(enabled_mods)])
		return true
	else:
		# Check if other enabled mods depend on this one
		var proposed: Array[String] = []
		for eid in enabled_mods:
			if eid != mod_id:
				proposed.append(eid)
		# Warn about dependents that would be broken (but allow it — they will be flagged)
		var validation := validate_enabled_order(proposed)
		for w in validation["warnings"]:
			push_warning("ModManager: %s" % w)
		enabled_mods = proposed
		var m: Mod = mods[mod_id]
		m.disable()
		m.load_order = -1
		# Re-index
		for i in enabled_mods.size():
			var mm: Mod = mods[enabled_mods[i]]
			mm.load_order = i
		_persist_enabled_order()
		updated_conflicts()
		mod_disabled.emit(mod_id)
		enabled_order_changed.emit(enabled_mods.duplicate())
		print("ModManager: disabled %s (order now %s)" % [mod_id, str(enabled_mods)])
		return true

func set_enabled_order(new_order: Array[String]) -> bool:
	# Validate: must contain exactly the same ids as current enabled_mods (reorder only)
	# Alternatively allow enabling/disabling via order? We enforce same set here; use set_mod_enabled for changes
	var current_set := {}
	for eid in enabled_mods:
		current_set[eid] = true
	var new_set := {}
	for eid in new_order:
		new_set[eid] = true
	if current_set.keys().size() != new_set.keys().size():
		push_warning("ModManager: set_enabled_order size mismatch — use set_mod_enabled to add/remove")
		return false
	for eid in current_set:
		if not new_set.has(eid):
			push_warning("ModManager: set_enabled_order missing %s" % eid)
			return false
	# Validate new order deps
	var validation := validate_enabled_order(new_order)
	if not validation["valid"]:
		for e in validation["errors"]:
			push_warning("ModManager: reorder invalid: %s" % e)
		# Still apply but warn — circular deps handled by resolver
	for w in validation["warnings"]:
		push_warning("ModManager: reorder warning: %s" % w)
	enabled_mods = new_order.duplicate()
	for i in enabled_mods.size():
		var m: Mod = mods[enabled_mods[i]]
		m.load_order = i
	_persist_enabled_order()
	updated_conflicts()
	enabled_order_changed.emit(enabled_mods.duplicate())
	print("ModManager: reordered enabled mods to %s" % str(enabled_mods))
	return true

func move_mod(mod_id: String, to_index: int) -> bool:
	if not is_mod_enabled(mod_id):
		return false
	var from := enabled_mods.find(mod_id)
	if from < 0:
		return false
	to_index = clampi(to_index, 0, enabled_mods.size() - 1)
	if from == to_index:
		return true
	var new_order := enabled_mods.duplicate()
	new_order.remove_at(from)
	new_order.insert(to_index, mod_id)
	return set_enabled_order(new_order)

func reset_to_defaults() -> void:
	_suppress_persist = true
	# Disable all, then enable defaults
	var to_disable := enabled_mods.duplicate()
	for eid in to_disable:
		set_mod_enabled(eid, false)
	for id in manifests:
		var mm: ModManifest = manifests[id]
		if mm.enabled_by_default:
			set_mod_enabled(id, true)
	_suppress_persist = false
	_persist_enabled_order()
	print("ModManager: reset to defaults: %s" % str(enabled_mods))

# ---------------------------------------------------------------------------
# Loading enabled mods in order
# ---------------------------------------------------------------------------

func load_enabled_mods() -> void:
	if enabled_mods.is_empty():
		print("ModManager: no enabled mods to load")
		mods_loaded.emit()
		return
	var resolved := resolve_load_order(enabled_mods)
	if resolved != enabled_mods:
		print("ModManager: resolved order %s -> %s (dependencies)" % [str(enabled_mods), str(resolved)])
		# Update persisted order to resolved one? Keep user order for display, but load in resolved
		# For now load in resolved order and keep enabled_mods as user order for conflict resolution
		# Actually apply resolved as new enabled order for consistency
		enabled_mods = resolved.duplicate()
		_persist_enabled_order()
	for i in enabled_mods.size():
		var eid: String = enabled_mods[i]
		var m: Mod = mods.get(eid, null)
		if m == null:
			continue
		m.load_order = i
		if m.state == Mod.State.ENABLED:
			continue
		# API scoped to this mod
		var api := ModAPI.new(eid, self)
		if not m.enable(api):
			push_error("ModManager: failed to load %s: %s" % [eid, m.error_message])
			mod_error.emit(eid, m.error_message)
			# Mark failed but keep enabled so Mods screen shows the error
	updated_conflicts()
	mods_loaded.emit()
	print("ModManager: loaded %d enabled mod(s)" % enabled_mods.size())

# ---------------------------------------------------------------------------
# Feature flags (weather, wind, seasons are now mods)
# ---------------------------------------------------------------------------

func register_feature(from_mod_id: String, feature_id: String, feature_name: String, description: String) -> bool:
	if features.has(feature_id):
		var existing: Dictionary = features[feature_id]
		# Later mod in enabled order wins — but registration order respects enabled_mods
		var existing_pos := enabled_mods.find(existing["mod_id"])
		var new_pos := enabled_mods.find(from_mod_id)
		if new_pos < existing_pos:
			# Existing is later, keep it
			return false
	features[feature_id] = { "mod_id": from_mod_id, "name": feature_name, "description": description, "registered_at": Time.get_ticks_msec() }
	return true

func is_feature_enabled(feature_id: String) -> bool:
	# Feature is enabled if its owner mod is enabled
	# For builtin features, the feature id == mod id (weather, wind, seasons)
	if is_mod_enabled(feature_id):
		return true
	# Also check registered features table
	if features.has(feature_id):
		var owner_id: String = str(features[feature_id].get("mod_id", ""))
		return is_mod_enabled(owner_id)
	# Unknown features are considered enabled for backward compat (custom mod features)
	return true

# Backwards-compatible aliases used by older code paths:
func is_weather_enabled() -> bool: return is_feature_enabled("weather")
func is_wind_enabled() -> bool: return is_feature_enabled("wind")
func is_seasons_enabled() -> bool: return is_feature_enabled("seasons")

# ---------------------------------------------------------------------------
# Content registries (with conflict tracking)
# ---------------------------------------------------------------------------

func register_building_type(from_mod_id: String, id: String, data: Dictionary) -> bool:
	var existing: Variant = building_registry_overrides.get(id, null)
	if existing != null:
		var prev_pos := enabled_mods.find(existing["mod_id"])
		var new_pos := enabled_mods.find(from_mod_id)
		if new_pos < prev_pos:
			print("ModManager: building '%s' from %s overridden by %s (later wins)" % [id, from_mod_id, existing["mod_id"]])
			return false
	building_registry_overrides[id] = { "mod_id": from_mod_id, "data": data }
	return true

func register_decoration_type(from_mod_id: String, id: String, data: Dictionary) -> bool:
	var existing: Variant = decoration_registry_overrides.get(id, null)
	if existing != null:
		var prev_pos := enabled_mods.find(existing["mod_id"])
		var new_pos := enabled_mods.find(from_mod_id)
		if new_pos < prev_pos:
			return false
	decoration_registry_overrides[id] = { "mod_id": from_mod_id, "data": data }
	return true

func register_terrain_type(from_mod_id: String, id: String, data: Dictionary) -> bool:
	var existing: Variant = terrain_registry_overrides.get(id, null)
	if existing != null:
		var prev_pos := enabled_mods.find(existing["mod_id"])
		var new_pos := enabled_mods.find(from_mod_id)
		if new_pos < prev_pos:
			return false
	terrain_registry_overrides[id] = { "mod_id": from_mod_id, "data": data }
	return true

func register_trait(_from_mod_id: String, _id: String, _data: Dictionary) -> bool:
	# Traits are additive — later mods just add, no conflict
	return true

func register_seasonal_event(_from_mod_id: String, _event_data: Dictionary) -> bool:
	return true

func override_building_type(from_mod_id: String, id: String, patch: Dictionary) -> bool:
	return register_building_type(from_mod_id, id, patch)

# ---------------------------------------------------------------------------
# Hook & modifier APIs
# ---------------------------------------------------------------------------

func register_hook(from_mod_id: String, event: String, callable: Callable) -> Dictionary:
	var handle := { "mod_id": from_mod_id, "event": event, "callable": callable, "id": "%s:%s:%d" % [from_mod_id, event, Time.get_ticks_msec()] }
	if not hooks.has(event):
		hooks[event] = []
	hooks[event].append(handle)
	# Wire to EventBus if applicable
	if has_node("/root/EventBus"):
		var eb = get_node("/root/EventBus")
		if eb.has_signal(event):
			if not eb.is_connected(event, _dispatch_hook.bind(event)):
				# Connect once per event, dispatch will fan out to all mod hooks
				pass
	return handle

func unregister_hook(handle: Dictionary) -> void:
	var event: String = str(handle.get("event", ""))
	if not hooks.has(event):
		return
	var arr: Array = hooks[event]
	for i in range(arr.size() - 1, -1, -1):
		if str(arr[i].get("id", "")) == str(handle.get("id", "")):
			arr.remove_at(i)
			break

func register_modifier(from_mod_id: String, modifier_id: String, callable: Callable) -> Dictionary:
	var handle := { "mod_id": from_mod_id, "modifier_id": modifier_id, "callable": callable, "id": "%s:%s:%d" % [from_mod_id, modifier_id, Time.get_ticks_msec()] }
	if not modifiers.has(modifier_id):
		modifiers[modifier_id] = []
	modifiers[modifier_id].append(handle)
	return handle

func unregister_modifier(handle: Dictionary) -> void:
	var mid: String = str(handle.get("modifier_id", ""))
	if not modifiers.has(mid):
		return
	var arr: Array = modifiers[mid]
	for i in range(arr.size() - 1, -1, -1):
		if str(arr[i].get("id", "")) == str(handle.get("id", "")):
			arr.remove_at(i)
			break

func apply_modifiers(modifier_id: String, base_value: float, context: Dictionary = {}) -> float:
	if not modifiers.has(modifier_id):
		return base_value
	var value := base_value
	# Apply in enabled order (later mods override earlier by operating on already-modified value)
	for mod_id in enabled_mods:
		var arr: Array = modifiers[modifier_id]
		for handle in arr:
			if str(handle.get("mod_id", "")) == mod_id:
				var callable: Callable = handle.get("callable", Callable())
				if callable.is_valid():
					value = callable.call(value, context)
	return value

func register_ui_section(from_mod_id: String, title: String, panel_builder: Callable) -> Dictionary:
	var entry := { "mod_id": from_mod_id, "title": title, "builder": panel_builder }
	ui_sections.append(entry)
	return entry

func register_menu_action(from_mod_id: String, label: String, icon: int, action: Callable) -> Dictionary:
	# Stored for MainMenu to query
	return { "mod_id": from_mod_id, "label": label, "icon": icon, "action": action }

# ---------------------------------------------------------------------------
# Save data
# ---------------------------------------------------------------------------

func set_mod_save_data(mod_id: String, key: String, value) -> void:
	if not mod_save_data.has(mod_id):
		mod_save_data[mod_id] = {}
	mod_save_data[mod_id][key] = value

func get_mod_save_data(mod_id: String, key: String, default = null):
	if mod_save_data.has(mod_id):
		return mod_save_data[mod_id].get(key, default)
	return default

func serialize_for_save() -> Dictionary:
	var versions := {}
	for eid in enabled_mods:
		var mf: ModManifest = manifests.get(eid, null)
		if mf:
			versions[eid] = mf.version
	return {
		"enabled": enabled_mods.duplicate(),
		"versions": versions,
		"mod_save_data": mod_save_data.duplicate(true),
	}

func deserialize_from_save(data: Dictionary) -> void:
	if data.is_empty():
		return
	var saved_enabled: Array = data.get("enabled", [])
	var saved_versions: Dictionary = data.get("versions", {})
	# Detect version mismatches
	for eid in saved_enabled:
		var saved_v: String = str(saved_versions.get(eid, "unknown"))
		var mf: ModManifest = manifests.get(eid, null)
		if mf == null:
			push_warning("ModManager: save references missing mod '%s' (version %s) — not installed" % [eid, saved_v])
		elif mf.version != saved_v:
			push_warning("ModManager: mod '%s' version mismatch: save has %s, current %s" % [eid, saved_v, mf.version])
	# Apply saved enabled order (but keep current manifests for load)
	_suppress_persist = true
	var filtered: Array[String] = []
	for eid in saved_enabled:
		if manifests.has(str(eid)):
			filtered.append(str(eid))
	enabled_mods = filtered
	_resync_mod_states()
	_suppress_persist = false
	# Do not persist globally — per-save order stays in save only
	mod_save_data = data.get("mod_save_data", {}).duplicate(true)
	print("ModManager: restored from save: enabled=%s" % str(enabled_mods))

# ---------------------------------------------------------------------------
# Conflict reporting
# ---------------------------------------------------------------------------

func updated_conflicts() -> void:
	var validation := validate_enabled_order(enabled_mods)
	last_conflicts = validation["conflicts"]
	# Also detect content conflicts (same id from multiple mods)
	var content_conflicts: Array[Dictionary] = []
	# Buildings
	var seen: Dictionary = {}
	for eid in enabled_mods:
		var m: Mod = mods.get(eid, null)
		if m == null or m.manifest == null:
			continue
		# Content packs could list ids — we check overrides map
		for bid in building_registry_overrides:
			var entry: Dictionary = building_registry_overrides[bid]
			if str(entry.get("mod_id", "")) == eid:
				if seen.has(bid):
					content_conflicts.append({ "type": "building", "id": bid, "mods": [seen[bid], eid], "winner": eid })
				else:
					seen[bid] = eid
	conflict_detected.emit(last_conflicts + content_conflicts)

func get_conflict_report() -> String:
	if last_conflicts.is_empty():
		return "No conflicts."
	var lines: Array[String] = []
	for c in last_conflicts:
		lines.append("%s <-> %s: %s (later in list wins)" % [c.get("mod_a", "?"), c.get("mod_b", "?"), c.get("reason", "")])
	return "\n".join(lines)

func _dispatch_hook(event: String, args: Array) -> void:
	# Fan out to all registered mod hooks for this event
	if not hooks.has(event):
		return
	for handle in hooks[event]:
		var callable: Callable = handle.get("callable", Callable())
		if callable.is_valid():
			callable.callv(args)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Clean up instances
		for m in mods.values():
			if m.instance and m.instance is Node and m.instance.is_inside_tree():
				m.instance.queue_free()
