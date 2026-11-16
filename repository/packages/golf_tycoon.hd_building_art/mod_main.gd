extends GolfTycoonMod
## HD Building Art - registers the 24 high-resolution views of every facility.
##
## The pack ships the same manifest format as the game's art: one PNG per
## building, upgrade tier and fifteen-degree view, with the rectangle the
## picture covers in the building node's draw space. Registering those frames
## replaces the shipped smaller sprites for every placed building, ghost and
## catalogue tile. ModAPI decodes each PNG lazily at its draw size, so the
## larger sources cost memory only for views the player actually sees.

const MANIFEST := "art/sprites.json"


func _mod_load(mod_api: ModAPI) -> void:
	var data: Variant = mod_api.read_json(MANIFEST)
	if not (data is Dictionary):
		mod_api.log_error("Could not read %s; keeping the shipped building art." % MANIFEST)
		return
	var buildings: Dictionary = data.get("buildings", {})
	var registered := 0
	for kind in buildings:
		var tiers: Dictionary = buildings[kind].get("tiers", {})
		for tier_key in tiers:
			var facings: Array = tiers[tier_key].get("facings", [])
			for index in range(facings.size()):
				var frame: Dictionary = facings[index]
				var values: Array = frame.get("rect", [])
				if values.size() < 4:
					continue
				var draw_rect := Rect2(values[0], values[1], values[2], values[3])
				if mod_api.register_building_sprite_frame(
						kind, "art/" + str(frame.get("file", "")),
						draw_rect, index, int(tier_key)):
					registered += 1
	mod_api.log_info("HD building art registered %d views." % registered)
