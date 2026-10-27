extends RefCounted
class_name CourseLocationPicture
## CourseLocationPicture - One-of-a-kind pixel-art postcard per course location.
##
## The world map ships 27 locations across 10 course themes, and mods can add
## more, so the location banner cannot ship one bitmap per site. Instead each
## picture is painted here, on a square 32x32 pixel grid, from the location's
## theme plus a deterministic RNG seeded by its id: the theme decides the
## palette and
## the landmarks (mesas and saguaros in the desert, pines and snowcaps in the
## mountains, palms and surf in the tropics), and the id decides where the sun,
## the clouds and every landmark stand. Two locations of the same theme still
## never share a picture, and a location always paints the same one.
##
## Every scene ends on the same golf beat - a fairway ribbon, a putting green
## and a flagstick - so each postcard reads as a golf course at a glance.
##
## Images and textures are cached per location, theme and display scale, the
## same way PixelIcon caches its sprites: the banner rebuilds itself on
## responsive window changes and must not repaint a scene each time.

## Source grid, in pixels. Pictures are square (1:1) and nearest-scaled by
## whole multiples, so every source pixel lands as an even block of screen
## pixels.
const GRID_W := 32
const GRID_H := 32

static var _image_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


# =============================================================================
# PUBLIC API
# =============================================================================

## The baked texture for a location, nearest-scaled to `scale` whole pixels
## per source pixel. Unknown themes fall back to parkland, so mod locations
## with an unrecognised theme still get a picture.
static func texture_for_location(location_id: String, theme: int, scale: int = 2) -> ImageTexture:
	var safe_scale: int = maxi(1, scale)
	var key := "%s|%d|%d" % [location_id, theme, safe_scale]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image := image_for_location(location_id, theme)
	if safe_scale != 1:
		# Duplicate first: resizing would otherwise mutate the cached source.
		image = image.duplicate()
		image.resize(GRID_W * safe_scale, GRID_H * safe_scale, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[key] = texture
	return texture

## The unscaled 32x32 source image for a location.
static func image_for_location(location_id: String, theme: int) -> Image:
	var key := "%s|%d" % [location_id, theme]
	if _image_cache.has(key):
		return _image_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(location_id)
	var image := Image.create_empty(GRID_W, GRID_H, false, Image.FORMAT_RGBA8)
	_paint_scene(image, theme, rng)
	_image_cache[key] = image
	return image

## Drop every cached picture (test helper).
static func clear_cache() -> void:
	_image_cache.clear()
	_texture_cache.clear()

## A stable nonnegative seed for an id string (FNV-1a), so a location paints
## the same picture in every session and two ids get different scenes.
static func _seed_for(location_id: String) -> int:
	var seed_value := 2166136261
	for i in location_id.length():
		seed_value = seed_value ^ location_id.unicode_at(i)
		seed_value = (seed_value * 16777619) & 0x7fffffff
	return seed_value


# =============================================================================
# SCENE COMPOSITION
# =============================================================================

## Paint one location's scene, back layer to front layer.
static func _paint_scene(image: Image, theme: int, rng: RandomNumberGenerator) -> void:
	var palette := _palette_for(theme, rng)
	var ground_row: int = 19
	if theme == CourseTheme.Type.LINKS or theme == CourseTheme.Type.TROPICAL \
			or theme == CourseTheme.Type.RESORT or theme == CourseTheme.Type.MARSHLAND:
		# Coastal sites push the land down so the sea can read behind it.
		ground_row = 21

	# Desert sites always get a hot sun; the other themes occasionally roll a moon.
	var allow_moon: bool = theme != CourseTheme.Type.DESERT
	_paint_sky(image, palette, rng, allow_moon)
	_paint_far_layer(image, theme, palette, rng, ground_row)
	_paint_ground(image, theme, palette, rng, ground_row)
	_paint_midground(image, theme, palette, rng, ground_row)
	_paint_fairway_and_green(image, theme, palette, rng, ground_row)
	_paint_texture(image, theme, palette, rng, ground_row)


# -----------------------------------------------------------------------------
# Sky
# -----------------------------------------------------------------------------

static func _paint_sky(image: Image, palette: Dictionary,
		rng: RandomNumberGenerator, allow_moon: bool) -> void:
	var horizon: int = 17
	for y in horizon:
		var band: Color
		if y < 5:
			band = palette["sky_top"]
		elif y < 10:
			band = palette["sky_mid"]
		else:
			band = palette["sky_low"]
		_fill_rect(image, 0, y, GRID_W, y + 1, band)

	# One celestial body, shifted per location. Desert courses get a higher,
	# hotter sun; a few sites roll a pale moon instead.
	var moon: bool = allow_moon and rng.randf() < 0.12
	var sun_x: int = rng.randi_range(5, GRID_W - 6)
	# Desert skies (where moons never roll) hold their sun high and hot.
	var sun_y: int = 4 if not allow_moon else rng.randi_range(3, 6)
	if moon:
		_fill_disc(image, sun_x, sun_y, 2, palette["moon"])
		_put(image, sun_x + 1, sun_y, palette["sky_mid"])
	else:
		_fill_disc(image, sun_x, sun_y, 2, palette["sun_glow"])
		_fill_disc(image, sun_x, sun_y, 1, palette["sun"])

	# A couple of small pixel clouds, never covering the sun.
	var cloud_count: int = rng.randi_range(1, 3)
	for i in cloud_count:
		var cloud_x: int = rng.randi_range(2, GRID_W - 8)
		var cloud_y: int = rng.randi_range(2, 8)
		if absi(cloud_x - sun_x) < 5 and absi(cloud_y - sun_y) < 4:
			continue
		_paint_cloud(image, cloud_x, cloud_y, rng, palette["cloud"])


static func _paint_cloud(image: Image, x: int, y: int, rng: RandomNumberGenerator, color: Color) -> void:
	var width: int = rng.randi_range(4, 6)
	for i in width:
		_put(image, x + i, y, color)
	_put(image, x + 1, y - 1, color)
	_put(image, x + width - 2, y - 1, color)
	_put(image, x + width, y, color)


# -----------------------------------------------------------------------------
# Far layer: the landmark each theme is recognised by
# -----------------------------------------------------------------------------

static func _paint_far_layer(image: Image, theme: int, palette: Dictionary,
		rng: RandomNumberGenerator, ground_row: int) -> void:
	match theme:
		CourseTheme.Type.MOUNTAIN:
			# Two or three jagged, snow-capped ranges across the horizon.
			var peaks: int = rng.randi_range(2, 3)
			for i in peaks:
				var cx: int = 6 + i * rng.randi_range(11, 14) + rng.randi_range(-2, 2)
				var height: int = rng.randi_range(7, 10)
				_paint_peak(image, clampi(cx, 6, GRID_W - 6), ground_row,
					rng.randi_range(6, 8), height, palette["rock"], palette["snow"], true)
		CourseTheme.Type.DESERT:
			# Flat-topped mesas behind rolling dunes.
			var mesas: int = rng.randi_range(1, 2)
			for i in mesas:
				var mx: int = rng.randi_range(6, GRID_W - 10)
				var mw: int = rng.randi_range(5, 8)
				var top: int = rng.randi_range(9, 12)
				_fill_rect(image, mx, top, mx + mw, ground_row, palette["mesa"])
				_fill_rect(image, mx - 1, top, mx + mw + 1, top + 1, palette["mesa_cap"])
			_paint_ridge(image, ground_row, rng.randf_range(2.0, 3.5), rng.randf() * TAU, palette["dune_far"])
		CourseTheme.Type.CITY:
			_paint_skyline(image, palette, rng, ground_row)
		CourseTheme.Type.LINKS, CourseTheme.Type.TROPICAL, \
				CourseTheme.Type.RESORT, CourseTheme.Type.MARSHLAND:
			_paint_sea(image, theme, palette, rng, ground_row)
		_:
			# Parkland, woodland and heathland wear two rolling ridges.
			_paint_ridge(image, ground_row, rng.randf_range(3.0, 4.5), rng.randf() * TAU, palette["ridge_far"])
			_paint_ridge(image, ground_row, rng.randf_range(2.0, 3.0), rng.randf() * TAU, palette["ridge_near"])


static func _paint_sea(image: Image, theme: int, palette: Dictionary,
		rng: RandomNumberGenerator, ground_row: int) -> void:
	_fill_rect(image, 0, 15, GRID_W, ground_row, palette["water"])
	# A deeper band along the bottom of the sea and white surf dashes on top.
	_fill_rect(image, 0, ground_row - 2, GRID_W, ground_row, palette["water_deep"])
	var waves: int = rng.randi_range(4, 6)
	for i in waves:
		var wx: int = rng.randi_range(1, GRID_W - 4)
		var wy: int = rng.randi_range(16, ground_row - 3)
		_put(image, wx, wy, palette["foam"])
		_put(image, wx + 1, wy, palette["foam"])
		_put(image, wx + 2, wy, palette["foam"])
	# A headland or a volcanic island gives the coast a silhouette.
	if theme == CourseTheme.Type.TROPICAL and rng.randf() < 0.6:
		var ix: int = rng.randi_range(4, GRID_W - 10)
		_paint_peak(image, ix, ground_row, 5, rng.randi_range(5, 7),
			palette["volcano"], palette["lava"], false)
	elif rng.randf() < 0.5:
		_paint_ridge(image, ground_row, rng.randf_range(2.0, 3.0), rng.randf() * TAU, palette["headland"])
	# The beach: a pale strip between the surf and the turf.
	_fill_rect(image, 0, ground_row - 1, GRID_W, ground_row + 1, palette["sand"])


static func _paint_skyline(image: Image, palette: Dictionary, rng: RandomNumberGenerator, ground_row: int) -> void:
	var x := 1
	while x < GRID_W - 2:
		var width: int = rng.randi_range(2, 3)
		var top: int = rng.randi_range(8, 13)
		_fill_rect(image, x, top, x + width, ground_row, palette["building"])
		# Lit windows, one per couple of floors.
		var wy: int = top + 1
		while wy < ground_row - 1:
			var wx: int = x + rng.randi_range(0, width - 1)
			_put(image, wx, wy, palette["window"])
			wy += 2
		# The occasional tower carries an antenna.
		if rng.randf() < 0.25:
			@warning_ignore("integer_division")
			var antenna_x: int = x + width / 2
			_put(image, antenna_x, top - 2, palette["building"])
			_put(image, antenna_x, top - 1, palette["building"])
		x += width + rng.randi_range(1, 2)


# -----------------------------------------------------------------------------
# Ground and midground landmarks
# -----------------------------------------------------------------------------

static func _paint_ground(image: Image, theme: int, palette: Dictionary,
		rng: RandomNumberGenerator, ground_row: int) -> void:
	_fill_rect(image, 0, ground_row, GRID_W, GRID_H, palette["ground"])
	# A darker rough strip along the very bottom grounds the scene.
	_fill_rect(image, 0, GRID_H - 2, GRID_W, GRID_H, palette["rough"])
	match theme:
		CourseTheme.Type.MARSHLAND:
			# Water winds through the wetland on one side, with a mud bank.
			_fill_rect(image, 0, ground_row + 3, rng.randi_range(8, 13), GRID_H - 2, palette["water"])
			_fill_rect(image, 0, ground_row + 2, rng.randi_range(7, 11), ground_row + 4, palette["mud"])
		CourseTheme.Type.RESORT:
			# A turquoise lagoon pocket behind the green.
			var lx: int = rng.randi_range(1, 6)
			_fill_ellipse(image, lx, ground_row + 4, 5, 2, palette["water"])
		CourseTheme.Type.DESERT:
			_paint_ridge(image, GRID_H - 4, rng.randf_range(1.5, 2.5), rng.randf() * TAU, palette["dune_near"])


static func _paint_midground(image: Image, theme: int, palette: Dictionary,
		rng: RandomNumberGenerator, ground_row: int) -> void:
	# Landmarks keep clear of the middle, where the green and flag will sit.
	var spots: Array[int] = _landmark_spots(rng)
	match theme:
		CourseTheme.Type.DESERT:
			for x in spots.slice(0, rng.randi_range(2, spots.size())):
				if rng.randf() < 0.6:
					_paint_cactus(image, x, ground_row + rng.randi_range(3, 6), rng.randi_range(4, 6), palette)
				else:
					_paint_rock(image, x, ground_row + 5, palette["rock"])
		CourseTheme.Type.MOUNTAIN:
			for x in spots.slice(0, rng.randi_range(2, 3)):
				_paint_pine(image, x, ground_row + rng.randi_range(3, 6), rng.randi_range(5, 7), palette)
		CourseTheme.Type.WOODLAND:
			# A dense treeline: pines shoulder to shoulder behind the turf.
			for x in range(2, GRID_W - 2, rng.randi_range(3, 4)):
				_paint_pine(image, x, ground_row + 2, rng.randi_range(4, 6), palette)
		CourseTheme.Type.PARKLAND:
			for x in spots.slice(0, rng.randi_range(2, 3)):
				_paint_deciduous(image, x, ground_row + rng.randi_range(3, 6), rng.randi_range(5, 7), palette)
		CourseTheme.Type.HEATHLAND:
			_paint_heath(image, palette, rng, ground_row)
			for x in spots.slice(0, 2):
				_paint_pine(image, x, ground_row + rng.randi_range(3, 5), rng.randi_range(4, 6), palette)
		CourseTheme.Type.LINKS:
			for x in spots.slice(0, rng.randi_range(3, 4)):
				_paint_fescue(image, x, ground_row + rng.randi_range(4, 7), palette)
		CourseTheme.Type.TROPICAL, CourseTheme.Type.RESORT:
			for x in spots.slice(0, rng.randi_range(2, 3)):
				_paint_palm(image, x, ground_row + rng.randi_range(3, 6), rng.randi_range(6, 8), palette)
		CourseTheme.Type.MARSHLAND:
			for x in spots.slice(0, rng.randi_range(3, 4)):
				_paint_reeds(image, x, ground_row + rng.randi_range(4, 7), palette)
		CourseTheme.Type.CITY:
			# A little clubhouse and park trees among the concrete.
			_paint_clubhouse(image, rng.randi_range(2, 6), ground_row + 4, palette)
			for x in spots.slice(0, 2):
				_paint_deciduous(image, x, ground_row + rng.randi_range(4, 6), 5, palette)


## X positions spread across the flanks, leaving the centre clear for the green.
static func _landmark_spots(rng: RandomNumberGenerator) -> Array[int]:
	var spots: Array[int] = []
	var left: Array[int] = [2, 5, 8, 11]
	var right: Array[int] = [GRID_W - 11, GRID_W - 8, GRID_W - 5, GRID_W - 2]
	_seeded_shuffle(left, rng)
	_seeded_shuffle(right, rng)
	spots.append_array(left.slice(0, 2))
	spots.append_array(right.slice(0, 2))
	return spots


## Fisher-Yates shuffle on the location's seeded RNG, so a postcard's landmark
## placement is deterministic rather than borrowing the global RNG.
static func _seeded_shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = values[i]
		values[i] = values[j]
		values[j] = tmp


# -----------------------------------------------------------------------------
# Fairway, green and flag - the golf beat every scene ends on
# -----------------------------------------------------------------------------

static func _paint_fairway_and_green(image: Image, theme: int, palette: Dictionary,
		rng: RandomNumberGenerator, _ground_row: int) -> void:
	@warning_ignore("integer_division")
	var green_x: int = clampi(GRID_W / 2 + rng.randi_range(-2, 2), 12, GRID_W - 12)
	var green_y: int = GRID_H - 4
	# A broad fairway ribbon sweeping in from one edge.
	var from_left: bool = rng.randf() < 0.5
	var ribbon_x: int = 4 if from_left else GRID_W - 5
	@warning_ignore("integer_division")
	var ribbon_center: int = (ribbon_x + green_x) / 2
	_fill_ellipse(image, ribbon_center, green_y + 1, 11, 4, palette["fairway"])
	# A bunker guards one side of the green on the sandy themes.
	if theme != CourseTheme.Type.TROPICAL:
		var bunker_x: int = green_x + (6 if from_left else -6)
		_fill_ellipse(image, bunker_x, green_y + 1, 3, 1, palette["sand"])
	# Fringe first, then the lighter putting surface.
	_fill_ellipse(image, green_x, green_y, 7, 3, palette["fringe"])
	_fill_ellipse(image, green_x, green_y, 5, 2, palette["green"])
	# The cup and the flagstick.
	_put(image, green_x, green_y, palette["hole"])
	_paint_flag(image, green_x, green_y, palette["pole"], palette["flag"])


static func _paint_texture(image: Image, theme: int, palette: Dictionary,
		rng: RandomNumberGenerator, ground_row: int) -> void:
	# A light deterministic speckle stops the turf and sand reading as flat
	# fills. Dabs stay off the green's centre so the flag stays legible.
	var dabs: int = 26
	for i in dabs:
		var x: int = rng.randi_range(0, GRID_W - 1)
		var y: int = rng.randi_range(ground_row + 1, GRID_H - 1)
		@warning_ignore("integer_division")
		var center_distance: int = absi(x - GRID_W / 2)
		if center_distance <= 9 and y >= GRID_H - 6:
			continue
		if rng.randf() < 0.5:
			_put(image, x, y, palette["texture_dark"])
	# Heather and gorse flecks give heathland its purple-and-gold rough.
	if theme == CourseTheme.Type.HEATHLAND:
		for i in 14:
			var x: int = rng.randi_range(1, GRID_W - 2)
			var y: int = rng.randi_range(ground_row + 2, GRID_H - 2)
			_put(image, x, y, palette["heather"] if rng.randf() < 0.55 else palette["gorse"])


# =============================================================================
# LANDMARK PRIMITIVES
# =============================================================================

static func _paint_peak(image: Image, cx: int, base_y: int, half_w: int,
		height: int, rock: Color, cap: Color, snow: bool) -> void:
	for row in height:
		var y: int = base_y - height + row
		var w: int = int(round(float(half_w) * (float(row) + 1.0) / float(height)))
		_fill_rect(image, cx - w, y, cx + w + 1, y + 1, rock)
		if snow and row < 2:
			_fill_rect(image, cx - w, y, cx + w + 1, y + 1, cap)


## A sine-backed ridge filled down to the ground line.
static func _paint_ridge(image: Image, base_y: int, amp: float, phase: float, color: Color) -> void:
	for x in GRID_W:
		var h: int = int(round(amp * (0.55 + 0.45 * sin(x * 0.22 + phase))))
		_fill_rect(image, x, base_y - h, x + 1, base_y, color)


static func _paint_pine(image: Image, x: int, base_y: int, height: int, palette: Dictionary) -> void:
	_put(image, x, base_y, palette["trunk"])
	_put(image, x, base_y - 1, palette["trunk"])
	for tier in 3:
		@warning_ignore("integer_division")
		var tier_h: int = maxi(2, height / 3)
		var top_y: int = base_y - 2 - tier * tier_h
		var w: int = 2 + tier
		_fill_triangle(image, x, top_y - tier_h, top_y, w, palette["tree_dark"])
	# A lit edge on the right-hand foliage.
	_put(image, x + 1, base_y - 3, palette["tree_light"])


static func _paint_deciduous(image: Image, x: int, base_y: int, height: int, palette: Dictionary) -> void:
	for i in maxi(2, height - 3):
		_put(image, x, base_y - i, palette["trunk"])
	_fill_disc(image, x, base_y - height + 1, 3, palette["tree_dark"])
	_put(image, x - 1, base_y - height, palette["tree_light"])
	_put(image, x, base_y - height - 1, palette["tree_light"])


static func _paint_palm(image: Image, x: int, base_y: int, height: int, palette: Dictionary) -> void:
	for i in height:
		@warning_ignore("integer_division")
		var bend: int = 1 if i > height / 2 else 0
		_put(image, x + bend, base_y - i, palette["trunk"])
	var top_x: int = x + 1
	var top_y: int = base_y - height
	# Five fronds radiating from the crown.
	_fill_rect(image, top_x - 3, top_y, top_x, top_y + 1, palette["tree_light"])
	_fill_rect(image, top_x + 1, top_y, top_x + 4, top_y + 1, palette["tree_light"])
	_put(image, top_x - 3, top_y + 1, palette["tree_dark"])
	_put(image, top_x + 4, top_y + 1, palette["tree_dark"])
	_put(image, top_x, top_y - 1, palette["tree_light"])


static func _paint_cactus(image: Image, x: int, base_y: int, height: int, palette: Dictionary) -> void:
	_fill_rect(image, x, base_y - height, x + 1, base_y, palette["tree_light"])
	# Left arm, then right arm, each a short vertical on a horizontal join.
	_put(image, x - 1, base_y - height + 2, palette["tree_light"])
	_put(image, x - 1, base_y - height + 1, palette["tree_light"])
	_put(image, x + 2, base_y - height + 3, palette["tree_dark"])
	_put(image, x + 2, base_y - height + 2, palette["tree_dark"])


static func _paint_fescue(image: Image, x: int, base_y: int, palette: Dictionary) -> void:
	for dx in 2:
		var h: int = 2 + (x + dx) % 2
		for i in h:
			_put(image, x + dx, base_y - i, palette["tree_light"])


static func _paint_reeds(image: Image, x: int, base_y: int, palette: Dictionary) -> void:
	for dx in 3:
		for i in 3:
			_put(image, x + dx, base_y - i, palette["tree_dark"])
		_put(image, x + dx, base_y - 3, palette["gorse"])


static func _paint_heath(image: Image, palette: Dictionary, rng: RandomNumberGenerator, ground_row: int) -> void:
	for i in 10:
		var x: int = rng.randi_range(1, GRID_W - 2)
		var y: int = rng.randi_range(ground_row + 2, GRID_H - 1)
		_fill_rect(image, x, y, x + 2, y + 1, palette["heather"] if rng.randf() < 0.5 else palette["gorse"])


static func _paint_rock(image: Image, x: int, base_y: int, color: Color) -> void:
	_fill_rect(image, x - 1, base_y - 1, x + 2, base_y + 1, color)
	_put(image, x - 1, base_y - 1, color.lightened(0.15))


static func _paint_clubhouse(image: Image, x: int, base_y: int, palette: Dictionary) -> void:
	_fill_rect(image, x, base_y - 4, x + 7, base_y, palette["building"])
	_fill_triangle(image, x + 3, base_y - 7, base_y - 4, 4, palette["roof"])
	_fill_rect(image, x + 3, base_y - 2, x + 4, base_y, palette["window"])


static func _paint_flag(image: Image, x: int, green_y: int, pole: Color, flag: Color) -> void:
	var pole_top: int = green_y - 6
	for y in range(pole_top, green_y):
		_put(image, x, y, pole)
	# A little triangular pennant pointing away from the nearest edge.
	@warning_ignore("integer_division")
	var direction: int = 1 if x < GRID_W / 2 else -1
	for row in 3:
		var w: int = 3 - row
		for col in w:
			_put(image, x + direction * (col + 1), pole_top + row, flag)


# =============================================================================
# PIXEL PRIMITIVES
# =============================================================================

static func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < GRID_W and y >= 0 and y < GRID_H:
		image.set_pixel(x, y, color)


static func _fill_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(maxi(0, y0), mini(GRID_H, y1)):
		for x in range(maxi(0, x0), mini(GRID_W, x1)):
			image.set_pixel(x, y, color)


static func _fill_disc(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius + radius:
				_put(image, cx + dx, cy + dy, color)


static func _fill_ellipse(image: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	var rx2: float = float(maxi(1, rx * rx))
	var ry2: float = float(maxi(1, ry * ry))
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			if float(dx * dx) / rx2 + float(dy * dy) / ry2 <= 1.0:
				_put(image, cx + dx, cy + dy, color)


static func _fill_triangle(image: Image, cx: int, top_y: int, base_y: int,
		half_w: int, color: Color) -> void:
	var span: int = maxi(1, base_y - top_y)
	for y in range(top_y, base_y):
		var w: int = int(round(float(half_w) * float(y - top_y + 1) / float(span)))
		_fill_rect(image, cx - w, y, cx + w + 1, y + 1, color)


# =============================================================================
# PALETTES
# =============================================================================

## The named colours one scene is painted with. Each theme has its own family;
## a small per-location lightness jitter keeps two sites of one theme from
## matching even before their landmarks are placed.
static func _palette_for(theme: int, rng: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = {}
	match theme:
		CourseTheme.Type.DESERT:
			p = {
				"sky_top": Color("8fc6ec"), "sky_mid": Color("bfe2f4"), "sky_low": Color("e6f4fa"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffd271"), "moon": Color("eef0e6"),
				"cloud": Color("f4fbff"), "mesa": Color("b5794e"), "mesa_cap": Color("c98f5e"),
				"dune_far": Color("d9b079"), "dune_near": Color("c99e63"),
				"ground": Color("e0c084"), "rough": Color("c9a55f"), "fairway": Color("72ad5b"),
				"green": Color("67d16b"), "fringe": Color("4e8f49"), "sand": Color("f0dc9e"),
				"water": Color("4d8cb3"), "water_deep": Color("3a6f92"), "foam": Color("eaf6f8"),
				"tree_dark": Color("3f6a34"), "tree_light": Color("5a8a45"), "trunk": Color("8a6a45"),
				"rock": Color("a6845c"), "ridge_far": Color("d9b079"), "ridge_near": Color("c9a55f"),
				"headland": Color("b5794e"), "volcano": Color("7a5a52"), "lava": Color("ff7a3c"),
				"building": Color("8d7a66"), "window": Color("ffd98a"), "roof": Color("9c5a44"),
				"pole": Color("f4edd9"), "flag": Color("d94f4f"), "hole": Color("20302a"),
				"texture_dark": Color("c4a06a"), "mud": Color("9c7d50"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.MOUNTAIN:
			p = {
				"sky_top": Color("7eb6e2"), "sky_mid": Color("a9d2ec"), "sky_low": Color("d6ebf6"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("8b93a3"), "mesa_cap": Color("aab2bd"),
				"dune_far": Color("7a8a6a"), "dune_near": Color("66755a"),
				"ground": Color("528545"), "rough": Color("3a6333"), "fairway": Color("61b761"),
				"green": Color("5cd16b"), "fringe": Color("3f8f49"), "sand": Color("c7b98e"),
				"water": Color("3880bf"), "water_deep": Color("2c6699"), "foam": Color("eaf6f8"),
				"tree_dark": Color("2d5c2e"), "tree_light": Color("4a8a44"), "trunk": Color("5a4430"),
				"rock": Color("858d98"), "ridge_far": Color("6e8575"), "ridge_near": Color("55705c"),
				"headland": Color("6e7686"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("7d8590"), "window": Color("ffd98a"), "roof": Color("5a4a52"),
				"pole": Color("f4edd9"), "flag": Color("e5c57c"), "hole": Color("1c2e22"),
				"texture_dark": Color("44703a"), "mud": Color("7a6a52"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.CITY:
			p = {
				"sky_top": Color("9dbcd4"), "sky_mid": Color("c2d6e4"), "sky_low": Color("e2edf3"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("54636e"), "mesa_cap": Color("6b7a85"),
				"dune_far": Color("7a8a6a"), "dune_near": Color("66755a"),
				"ground": Color("6b8552"), "rough": Color("4d6539"), "fairway": Color("6bb366"),
				"green": Color("66cc70"), "fringe": Color("4a8f4c"), "sand": Color("d9d2bf"),
				"water": Color("4d7ba0"), "water_deep": Color("3c6280"), "foam": Color("eaf6f8"),
				"tree_dark": Color("355c30"), "tree_light": Color("4f8045"), "trunk": Color("6b4f32"),
				"rock": Color("8a8a86"), "ridge_far": Color("54636e"), "ridge_near": Color("45525c"),
				"headland": Color("54636e"), "volcano": Color("6a5a62"), "lava": Color("ff7a3c"),
				"building": Color("3e4c56"), "window": Color("ffd98a"), "roof": Color("4a3f46"),
				"pole": Color("f4edd9"), "flag": Color("d94f4f"), "hole": Color("1c2e22"),
				"texture_dark": Color("5a7244"), "mud": Color("7a6f5c"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.LINKS:
			p = {
				"sky_top": Color("a7c9dd"), "sky_mid": Color("c9dfe9"), "sky_low": Color("e4f0f3"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("8a8a6a"), "mesa_cap": Color("a5a57e"),
				"dune_far": Color("cbb978"), "dune_near": Color("b7a261"),
				"ground": Color("8c9256"), "rough": Color("6f7340"), "fairway": Color("7aae64"),
				"green": Color("6bc772"), "fringe": Color("4f9452"), "sand": Color("e0d29a"),
				"water": Color("3f6f86"), "water_deep": Color("355c70"), "foam": Color("e8f2f4"),
				"tree_dark": Color("4d6b2a"), "tree_light": Color("8a8a4e"), "trunk": Color("6b5a38"),
				"rock": Color("8c887e"), "ridge_far": Color("b7a261"), "ridge_near": Color("9c8f54"),
				"headland": Color("7a7f56"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("7d7a66"), "window": Color("ffd98a"), "roof": Color("5a4a42"),
				"pole": Color("f4edd9"), "flag": Color("d94f4f"), "hole": Color("20302a"),
				"texture_dark": Color("7a8048"), "mud": Color("8a7d5c"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.TROPICAL:
			p = {
				"sky_top": Color("6fc3ec"), "sky_mid": Color("9fddf4"), "sky_low": Color("d2f2fa"),
				"sun": Color("fff6cc"), "sun_glow": Color("ffd97a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fdff"), "mesa": Color("5a4a55"), "mesa_cap": Color("766069"),
				"dune_far": Color("3f7d56"), "dune_near": Color("336847"),
				"ground": Color("4f9a52"), "rough": Color("35703c"), "fairway": Color("63bd63"),
				"green": Color("5fd071"), "fringe": Color("3f9450"), "sand": Color("efe0b0"),
				"water": Color("2e8fb5"), "water_deep": Color("24708f"), "foam": Color("eafdff"),
				"tree_dark": Color("246b3d"), "tree_light": Color("2e8f4f"), "trunk": Color("8a6a45"),
				"rock": Color("3a3340"), "ridge_far": Color("2f7d4f"), "ridge_near": Color("276b41"),
				"headland": Color("3a5a50"), "volcano": Color("5a4a55"), "lava": Color("ff7a3c"),
				"building": Color("7d6a56"), "window": Color("ffe6a8"), "roof": Color("5a3f38"),
				"pole": Color("f4edd9"), "flag": Color("ff7a3c"), "hole": Color("16281f"),
				"texture_dark": Color("438346"), "mud": Color("7a6a52"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.RESORT:
			p = {
				"sky_top": Color("84cbee"), "sky_mid": Color("b2e0f5"), "sky_low": Color("ddf3fb"),
				"sun": Color("fff6cc"), "sun_glow": Color("ffd97a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fdff"), "mesa": Color("7a9a7a"), "mesa_cap": Color("95b295"),
				"dune_far": Color("6fa577"), "dune_near": Color("5c8f66"),
				"ground": Color("69a85f"), "rough": Color("4d8049"), "fairway": Color("79c069"),
				"green": Color("73d97d"), "fringe": Color("52a058"), "sand": Color("f2e6c8"),
				"water": Color("46b8c8"), "water_deep": Color("2f9db0"), "foam": Color("eafdff"),
				"tree_dark": Color("2e7d43"), "tree_light": Color("3f9e56"), "trunk": Color("8a6a45"),
				"rock": Color("b0a48c"), "ridge_far": Color("6fa577"), "ridge_near": Color("5c8f66"),
				"headland": Color("5c8f80"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("e8e0d0"), "window": Color("8fd4e0"), "roof": Color("d97a5a"),
				"pole": Color("f4edd9"), "flag": Color("e5c57c"), "hole": Color("1c2e22"),
				"texture_dark": Color("5a9050"), "mud": Color("9c8d6a"), "heather": Color("c98ab8"),
				"gorse": Color("e8cf5a"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.HEATHLAND:
			p = {
				"sky_top": Color("a9c2d6"), "sky_mid": Color("cadce8"), "sky_low": Color("e6eff4"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("7d8a5a"), "mesa_cap": Color("96a372"),
				"dune_far": Color("8a9460"), "dune_near": Color("768050"),
				"ground": Color("7c8348"), "rough": Color("5f6638"), "fairway": Color("8aa85c"),
				"green": Color("7fc76a"), "fringe": Color("5e9450"), "sand": Color("c9bd96"),
				"water": Color("4f7f86"), "water_deep": Color("3f666c"), "foam": Color("e8f2f4"),
				"tree_dark": Color("33502e"), "tree_light": Color("5a7540"), "trunk": Color("5a4430"),
				"rock": Color("948e80"), "ridge_far": Color("7d8a5a"), "ridge_near": Color("667048"),
				"headland": Color("66705a"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("7d7266"), "window": Color("ffd98a"), "roof": Color("5a4538"),
				"pole": Color("f4edd9"), "flag": Color("8a6aa8"), "hole": Color("1c2e22"),
				"texture_dark": Color("6a713e"), "mud": Color("8a7d5c"), "heather": Color("9a78b8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.WOODLAND:
			p = {
				"sky_top": Color("93b8d0"), "sky_mid": Color("bcd6e6"), "sky_low": Color("dcecf3"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("4a6b50"), "mesa_cap": Color("628568"),
				"dune_far": Color("3a6340"), "dune_near": Color("2c4f33"),
				"ground": Color("4f7440"), "rough": Color("38552d"), "fairway": Color("6aa85a"),
				"green": Color("66c46e"), "fringe": Color("478a4c"), "sand": Color("c9bd96"),
				"water": Color("3f7a96"), "water_deep": Color("32627a"), "foam": Color("e8f2f4"),
				"tree_dark": Color("213d27"), "tree_light": Color("3f6e3a"), "trunk": Color("4f3a28"),
				"rock": Color("828880"), "ridge_far": Color("3a6340"), "ridge_near": Color("2c4f33"),
				"headland": Color("3a5a48"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("6e6256"), "window": Color("ffd98a"), "roof": Color("45382e"),
				"pole": Color("f4edd9"), "flag": Color("d94f4f"), "hole": Color("18261d"),
				"texture_dark": Color("436436"), "mud": Color("7a6a52"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		CourseTheme.Type.MARSHLAND:
			p = {
				"sky_top": Color("a6c4cf"), "sky_mid": Color("c6dde2"), "sky_low": Color("e2eff0"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("6f7f5a"), "mesa_cap": Color("8a9a72"),
				"dune_far": Color("6f7f4a"), "dune_near": Color("5c6b3e"),
				"ground": Color("67834f"), "rough": Color("4d6338"), "fairway": Color("7aa860"),
				"green": Color("74c978"), "fringe": Color("529454"), "sand": Color("dccfa8"),
				"water": Color("5b8a86"), "water_deep": Color("47756f"), "foam": Color("e8f4f2"),
				"tree_dark": Color("3f5a3a"), "tree_light": Color("5d7a52"), "trunk": Color("5a4632"),
				"rock": Color("8c8678"), "ridge_far": Color("6f7f5a"), "ridge_near": Color("5a6a48"),
				"headland": Color("5a6f60"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("7d7266"), "window": Color("ffd98a"), "roof": Color("50403a"),
				"pole": Color("f4edd9"), "flag": Color("d94f4f"), "hole": Color("1c2a20"),
				"texture_dark": Color("587042"), "mud": Color("8a7a5c"), "heather": Color("9a78b8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
		_:
			# PARKLAND and any unknown theme: lush classic greens.
			p = {
				"sky_top": Color("8fc4e8"), "sky_mid": Color("b7dcf2"), "sky_low": Color("d9eef7"),
				"sun": Color("fff3c4"), "sun_glow": Color("ffe39a"), "moon": Color("eef0e6"),
				"cloud": Color("f6fbff"), "mesa": Color("7a9a6a"), "mesa_cap": Color("95b285"),
				"dune_far": Color("6f9a5e"), "dune_near": Color("5c8a4d"),
				"ground": Color("5f803b"), "rough": Color("4a6935"), "fairway": Color("78ae49"),
				"green": Color("a6d957"), "fringe": Color("477638"), "sand": Color("eddeb0"),
				"water": Color("47877e"), "water_deep": Color("386c65"), "foam": Color("e8f4f2"),
				"tree_dark": Color("2f5e28"), "tree_light": Color("3f7a35"), "trunk": Color("6b4f32"),
				"rock": Color("7a766c"), "ridge_far": Color("6f9a5e"), "ridge_near": Color("5c8a4d"),
				"headland": Color("5c7f56"), "volcano": Color("7a6a72"), "lava": Color("ff7a3c"),
				"building": Color("8a7a66"), "window": Color("ffd98a"), "roof": Color("7a4f38"),
				"pole": Color("f4edd9"), "flag": Color("d94f4f"), "hole": Color("1c2e22"),
				"texture_dark": Color("517032"), "mud": Color("8a7d5c"), "heather": Color("8a6aa8"),
				"gorse": Color("d9b83f"), "snow": Color("f4f8fb"),
			}
	# Gentle per-location jitter on the sky and turf only: landmarks keep their
	# named colours so the theme still reads at a glance.
	p["sky_top"] = _jitter(p["sky_top"], rng, 0.04)
	p["sky_mid"] = _jitter(p["sky_mid"], rng, 0.04)
	p["sky_low"] = _jitter(p["sky_low"], rng, 0.04)
	p["ground"] = _jitter(p["ground"], rng, 0.03)
	p["fairway"] = _jitter(p["fairway"], rng, 0.03)
	return p


## Nudge a colour's lightness by a small deterministic amount, keeping hue.
static func _jitter(color: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var delta: float = rng.randf_range(-amount, amount)
	if delta >= 0.0:
		return color.lightened(delta)
	return color.darkened(-delta)
