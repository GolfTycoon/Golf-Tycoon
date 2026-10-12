class_name Heightmap
extends RefCounted
## Heightmap - Course-wide R8 grayscale texture encoding sub-tile elevation
##
## Resolution: 512x512 (4 pixels per tile on a 128x128 grid)
## Value encoding: 0 = lowest (level 0), 128 = flat ground (BASE_ELEVATION = 5),
## 255 = highest (level 10). Updated on elevation/tile changes, not every frame.
##
## A full rebuild touches every pixel of the texture, so it is kept off the
## critical path twice over: request_rebuild() defers the work to the next
## flush_dirty() (one rebuild however many times a frame asks for one — a new
## course refreshes its overlays after every generation pass), and the pixel
## passes run over the image's bytes with the position-only noise worked out
## once, rather than through a Color per pixel. The bytes produced are exactly
## the ones the per-pixel get_pixel()/set_pixel() passes produced.

const PIXELS_PER_TILE: int = 4
const SEA_LEVEL: int = 128  # Grayscale value for BASE_ELEVATION (flat ground)
const ELEVATION_SCALE: float = 25.6  # Grayscale units per integer elevation level

# 5-tap separable Gaussian kernel (sigma ~1.0, pre-normalized)
const BLUR_KERNEL: Array[float] = [0.06136, 0.24477, 0.38774, 0.24477, 0.06136]
const BLUR_RADIUS: int = 2

# Per-terrain noise amplitude in elevation units (not grayscale)
const NOISE_AMPLITUDES: Dictionary = {
	TerrainTypes.Type.EMPTY: 0.08,
	TerrainTypes.Type.GRASS: 0.15,
	TerrainTypes.Type.FAIRWAY: 0.12,
	TerrainTypes.Type.ROUGH: 0.16,
	TerrainTypes.Type.HEAVY_ROUGH: 0.18,
	TerrainTypes.Type.GREEN: 0.04,
	TerrainTypes.Type.TEE_BOX: 0.02,
	TerrainTypes.Type.BUNKER: 0.06,
	TerrainTypes.Type.WATER: 0.0,
	TerrainTypes.Type.OUT_OF_BOUNDS: 0.10,
	TerrainTypes.Type.TREES: 0.14,
	TerrainTypes.Type.OAK: 0.14,
	TerrainTypes.Type.PINE: 0.14,
	TerrainTypes.Type.MAPLE: 0.14,
	TerrainTypes.Type.BIRCH: 0.14,
	TerrainTypes.Type.PALM: 0.14,
	TerrainTypes.Type.CACTUS: 0.14,
	TerrainTypes.Type.DEAD_TREE: 0.14,
	TerrainTypes.Type.SHRUB: 0.14,
	TerrainTypes.Type.FESCUE: 0.14,
	TerrainTypes.Type.CATTAILS: 0.14,
	TerrainTypes.Type.HEATHER: 0.14,
	TerrainTypes.Type.FLOWER_BED: 0.10,
	TerrainTypes.Type.ROCKS: 0.12,
	TerrainTypes.Type.SMALL_BOULDERS: 0.12,
	TerrainTypes.Type.LARGE_BOULDERS: 0.12,
	TerrainTypes.Type.FIRM_FAIRWAY: 0.12,
	TerrainTypes.Type.POT_BUNKER: 0.04,
	TerrainTypes.Type.STREAM: 0.0,
	TerrainTypes.Type.DEEP_ROUGH: 0.18,
	TerrainTypes.Type.WASTE_BUNKER: 0.1,
	TerrainTypes.Type.BRUSH: 0.16,
}

## What Image.get_pixel(...).r * 255.0 reads for each stored byte, and the byte
## Image.set_pixel() stores for each gray value. Taken from the engine itself
## (see _ensure_conversion_tables) so the byte passes match it exactly.
static var _gray_of_byte: PackedFloat64Array = PackedFloat64Array()
static var _byte_of_gray: PackedByteArray = PackedByteArray()
## The position-only noise of the last texture size (and seed) worked out, so a
## new heightmap of the same course size starts from it instead of re-sampling.
static var _variation_cache_key: Vector2i = Vector2i(-1, -1)
static var _variation_cache: PackedFloat64Array = PackedFloat64Array()
static var _terrain_noise_cache_key: Vector3i = Vector3i(-1, -1, -1)
static var _terrain_noise_cache: PackedFloat64Array = PackedFloat64Array()

var _image: Image
var _texture: ImageTexture
var _grid_width: int
var _grid_height: int
var _tex_width: int
var _tex_height: int
var _terrain_grid: TerrainGrid = null  # Source of vertex heights + terrain types
var _noise_detail: FastNoiseLite  # Small-scale texture (freq 0.15)
var _noise_broad: FastNoiseLite   # Broad rolling hills (freq 0.03)
var _noise_seed: int
var _dirty_tiles: Dictionary = {}  # Vector2i -> true, tiles needing blur + upload
var _rebuild_pending: bool = false
## The image's pixels, one gray byte each (FORMAT_R8), pushed to the image and
## texture whenever they change.
var _pixels: PackedByteArray
## Per pixel: ElevationProfiles.variation() of its sub-tile, and the blend of
## the two noise layers. Both depend on the position alone.
var _variation: PackedFloat64Array = PackedFloat64Array()
var _terrain_noise: PackedFloat64Array = PackedFloat64Array()

func _init(grid_width: int = 128, grid_height: int = 128, noise_seed: int = 0) -> void:
	_grid_width = grid_width
	_grid_height = grid_height
	_noise_seed = noise_seed if noise_seed != 0 else randi()

	# Detail noise: small-scale terrain texture
	_noise_detail = FastNoiseLite.new()
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_detail.seed = _noise_seed
	_noise_detail.frequency = 0.15
	_noise_detail.fractal_octaves = 2
	_noise_detail.fractal_lacunarity = 2.0
	_noise_detail.fractal_gain = 0.5

	# Broad noise: rolling hills spanning 5-10 tiles
	_noise_broad = FastNoiseLite.new()
	_noise_broad.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_broad.seed = _noise_seed + 1000  # Different seed for independent pattern
	_noise_broad.frequency = 0.03
	_noise_broad.fractal_octaves = 2
	_noise_broad.fractal_lacunarity = 2.0
	_noise_broad.fractal_gain = 0.5

	_tex_width = grid_width * PIXELS_PER_TILE   # 512
	_tex_height = grid_height * PIXELS_PER_TILE  # 512
	_image = Image.create(_tex_width, _tex_height, false, Image.FORMAT_R8)
	_image.fill(Color(float(SEA_LEVEL) / 255.0, 0, 0))  # R8: uses red channel only
	_pixels = _image.get_data()
	_texture = ImageTexture.create_from_image(_image)
	_ensure_conversion_tables()

## Point the heightmap at the grid whose vertices supply the base surface.
func initialize(terrain_grid: TerrainGrid) -> void:
	_terrain_grid = terrain_grid

func get_texture() -> ImageTexture:
	return _texture

func get_noise_seed() -> int:
	return _noise_seed

## Convert an integer elevation level (MIN_ELEVATION..MAX_ELEVATION) to a
## grayscale byte (0..255), with BASE_ELEVATION landing on SEA_LEVEL.
static func elevation_to_grayscale(elevation: int) -> int:
	return clampi(SEA_LEVEL + roundi((elevation - TerrainGrid.BASE_ELEVATION) * ELEVATION_SCALE), 0, 255)

## Convert grayscale byte back to an elevation level
static func grayscale_to_elevation(gray: int) -> float:
	return TerrainGrid.BASE_ELEVATION + (float(gray) - SEA_LEVEL) / ELEVATION_SCALE

## The gray byte stored at pixel (x, y).
func get_gray(x: int, y: int) -> int:
	return _pixels[y * _tex_width + x]

func refresh_tile(pos: Vector2i) -> void:
	if _terrain_grid and _terrain_grid.is_valid_position(pos):
		_dirty_tiles[pos] = true

func refresh_tiles(tiles: Array) -> void:
	for tile in tiles:
		if tile is Vector2i:
			refresh_tile(tile)

## True while a full rebuild waits for the next flush_dirty().
func is_rebuild_pending() -> bool:
	return _rebuild_pending

func flush_dirty() -> void:
	if _rebuild_pending:
		rebuild_from_grids(_terrain_grid)
		return
	if _dirty_tiles.is_empty():
		return
	var tiles: Array = _dirty_tiles.keys()
	_dirty_tiles.clear()
	for tile_pos in tiles:
		_write_tile(tile_pos)
	for tile_pos in tiles:
		_blur_region(tile_pos)
	_upload()

## Rebuild the whole texture at the next flush_dirty(). Asking again before
## then costs nothing, so a run of terrain passes rebuilds once at the end.
func request_rebuild(terrain_grid: TerrainGrid) -> void:
	_terrain_grid = terrain_grid
	_dirty_tiles.clear()
	_rebuild_pending = true

## Bulk rebuild, at once — call after loading a save or generating terrain
## (or request_rebuild() to wait for the next flush).
func rebuild_from_grids(terrain_grid: TerrainGrid) -> void:
	_terrain_grid = terrain_grid
	_dirty_tiles.clear()
	_rebuild_pending = false
	for y in _grid_height:
		for x in _grid_width:
			_write_tile(Vector2i(x, y))

	_blur_full()
	_upload()

func _upload() -> void:
	_image.set_data(_tex_width, _tex_height, false, Image.FORMAT_R8, _pixels)
	_texture.update(_image)

func _write_tile(pos: Vector2i) -> void:
	if _terrain_grid == null or not _terrain_grid.is_valid_position(pos):
		return
	_ensure_position_noise()
	var terrain_type: int = _terrain_grid.get_tile(pos)
	var profile: Array = ElevationProfiles.get_profile(terrain_type)
	var amplitude: float = NOISE_AMPLITUDES.get(terrain_type, 0.04)
	var corners: Vector4 = _terrain_grid.get_tile_corner_heights(pos)
	var px: int = pos.x * PIXELS_PER_TILE
	var py: int = pos.y * PIXELS_PER_TILE

	for ly in PIXELS_PER_TILE:
		var y: int = py + ly
		if y < 0 or y >= _tex_height:
			continue
		var fy: float = (float(ly) + 0.5) / float(PIXELS_PER_TILE)
		var left: float = lerpf(corners.x, corners.z, fy)
		var right: float = lerpf(corners.y, corners.w, fy)
		var profile_row: Array = profile[ly]
		for lx in PIXELS_PER_TILE:
			var x: int = px + lx
			if x < 0 or x >= _tex_width:
				continue
			var index: int = y * _tex_width + x
			var fx: float = (float(lx) + 0.5) / float(PIXELS_PER_TILE)
			# Vertex heights are absolute levels: measure them from BASE_ELEVATION
			# so flat ground lands on SEA_LEVEL gray.
			var base_gray: int = roundi((lerpf(left, right, fx) - TerrainGrid.BASE_ELEVATION) * ELEVATION_SCALE)
			# The varied profile (ElevationProfiles.get_varied_profile).
			var offset_gray: int = roundi((profile_row[lx] + _variation[index]) * ELEVATION_SCALE)
			# Dual-frequency noise, scaled by the terrain type's amplitude.
			var noise_offset: int = 0
			if amplitude > 0.0:
				noise_offset = roundi(_terrain_noise[index] * amplitude * ELEVATION_SCALE)
			_pixels[index] = _byte_of_gray[clampi(SEA_LEVEL + base_gray + offset_gray + noise_offset, 0, 255)]

## Separable Gaussian blur over the entire heightmap image
func _blur_full() -> void:
	var w: int = _tex_width
	var h: int = _tex_height
	var k0: float = BLUR_KERNEL[0]
	var k1: float = BLUR_KERNEL[1]
	var k2: float = BLUR_KERNEL[2]
	var k3: float = BLUR_KERNEL[3]
	var k4: float = BLUR_KERNEL[4]

	# Horizontal pass: pixels -> temp. `row` holds the pixel row as gray values
	# with the edge pixel repeated twice either side (the clamp of the taps).
	var temp: PackedFloat32Array = PackedFloat32Array()
	temp.resize(w * h)
	var row: PackedFloat64Array = PackedFloat64Array()
	row.resize(w + 2 * BLUR_RADIUS)
	for y in h:
		var start: int = y * w
		for x in w:
			row[x + BLUR_RADIUS] = _gray_of_byte[_pixels[start + x]]
		row[0] = row[BLUR_RADIUS]
		row[1] = row[BLUR_RADIUS]
		row[w + BLUR_RADIUS] = row[w + BLUR_RADIUS - 1]
		row[w + BLUR_RADIUS + 1] = row[w + BLUR_RADIUS - 1]
		for x in w:
			temp[start + x] = row[x] * k0 + row[x + 1] * k1 + row[x + 2] * k2 \
					+ row[x + 3] * k3 + row[x + 4] * k4

	# Vertical pass: temp -> pixels
	for y in h:
		var up2: int = clampi(y - 2, 0, h - 1) * w
		var up1: int = clampi(y - 1, 0, h - 1) * w
		var mid: int = y * w
		var down1: int = clampi(y + 1, 0, h - 1) * w
		var down2: int = clampi(y + 2, 0, h - 1) * w
		for x in w:
			var total: float = temp[up2 + x] * k0 + temp[up1 + x] * k1 + temp[mid + x] * k2 \
					+ temp[down1 + x] * k3 + temp[down2 + x] * k4
			_pixels[mid + x] = _byte_of_gray[clampi(roundi(total), 0, 255)]

## Blur a small region around a single tile (tile pixels + 2px border)
func _blur_region(tile_pos: Vector2i) -> void:
	var w: int = _tex_width
	var h: int = _tex_height
	var px: int = tile_pos.x * PIXELS_PER_TILE
	var py: int = tile_pos.y * PIXELS_PER_TILE

	# Region to write back (tile + blur radius border)
	var x0: int = maxi(px - BLUR_RADIUS, 0)
	var y0: int = maxi(py - BLUR_RADIUS, 0)
	var x1: int = mini(px + PIXELS_PER_TILE + BLUR_RADIUS, w)
	var y1: int = mini(py + PIXELS_PER_TILE + BLUR_RADIUS, h)
	var rw: int = x1 - x0
	var rh: int = y1 - y0
	if rw <= 0 or rh <= 0:
		return

	# Horizontal pass into temp array
	var temp: PackedFloat32Array = PackedFloat32Array()
	temp.resize(rw * rh)

	for ry in rh:
		var row_start: int = (y0 + ry) * w
		for rx in rw:
			var gx: int = x0 + rx
			var total: float = 0.0
			for k in BLUR_KERNEL.size():
				var sx: int = clampi(gx + k - BLUR_RADIUS, 0, w - 1)
				total += _gray_of_byte[_pixels[row_start + sx]] * BLUR_KERNEL[k]
			temp[ry * rw + rx] = total

	# Vertical pass from temp, write to image
	for ry in rh:
		var gy: int = y0 + ry
		for rx in rw:
			var gx: int = x0 + rx
			var total: float = 0.0
			for k in BLUR_KERNEL.size():
				var sy: int = clampi(gy + k - BLUR_RADIUS, 0, h - 1)
				# Use temp if within our region, otherwise read from image
				var ty: int = sy - y0
				if ty >= 0 and ty < rh:
					total += temp[ty * rw + rx] * BLUR_KERNEL[k]
				else:
					total += _gray_of_byte[_pixels[sy * w + gx]] * BLUR_KERNEL[k]
			_pixels[gy * w + gx] = _byte_of_gray[clampi(roundi(total), 0, 255)]

## Work out (or reuse) the per-pixel noise that depends on position alone.
func _ensure_position_noise() -> void:
	if _variation.size() != _tex_width * _tex_height:
		_variation = _position_variation(_grid_width, _grid_height)
	if _terrain_noise.size() != _tex_width * _tex_height:
		_terrain_noise = _blended_noise()

## ElevationProfiles.variation() for every pixel of a grid this size.
static func _position_variation(grid_width: int, grid_height: int) -> PackedFloat64Array:
	var key := Vector2i(grid_width, grid_height)
	if _variation_cache_key == key:
		return _variation_cache
	var tex_width: int = grid_width * PIXELS_PER_TILE
	var values := PackedFloat64Array()
	values.resize(tex_width * grid_height * PIXELS_PER_TILE)
	for ty in grid_height:
		for tx in grid_width:
			var tile := Vector2i(tx, ty)
			for ly in PIXELS_PER_TILE:
				var start: int = (ty * PIXELS_PER_TILE + ly) * tex_width + tx * PIXELS_PER_TILE
				for lx in PIXELS_PER_TILE:
					values[start + lx] = ElevationProfiles.variation(tile, lx, ly)
	_variation_cache_key = key
	_variation_cache = values
	return values

## The two noise layers blended for every pixel: broad hills 60%, detail 40%.
func _blended_noise() -> PackedFloat64Array:
	var key := Vector3i(_noise_seed, _tex_width, _tex_height)
	if _terrain_noise_cache_key == key:
		return _terrain_noise_cache
	var values := PackedFloat64Array()
	values.resize(_tex_width * _tex_height)
	for y in _tex_height:
		for x in _tex_width:
			var detail: float = _noise_detail.get_noise_2d(float(x), float(y))  # [-1, 1]
			var broad: float = _noise_broad.get_noise_2d(float(x), float(y))    # [-1, 1]
			values[y * _tex_width + x] = broad * 0.6 + detail * 0.4
	_terrain_noise_cache_key = key
	_terrain_noise_cache = values
	return values

## Read the engine's own byte <-> gray conversions for an R8 image once.
static func _ensure_conversion_tables() -> void:
	if _byte_of_gray.size() == 256:
		return
	var written := Image.create(256, 1, false, Image.FORMAT_R8)
	for gray in 256:
		written.set_pixel(gray, 0, Color(float(gray) / 255.0, 0, 0))
	var bytes := PackedByteArray()
	bytes.resize(256)
	for value in 256:
		bytes[value] = value
	var read := Image.create_from_data(256, 1, false, Image.FORMAT_R8, bytes)
	var grays := PackedFloat64Array()
	grays.resize(256)
	for value in 256:
		grays[value] = read.get_pixel(value, 0).r * 255.0
	_gray_of_byte = grays
	_byte_of_gray = written.get_data()
