extends RefCounted
class_name TreeCollisionProfile
## Precomputed 2px-resolution sprite collision mask for one tree variant or
## fallback silhouette. Built lazily once per unique sprite asset and cached
## across all shots so gameplay collision queries run in O(1) array lookups.

const MAT_EMPTY: int = 0
const MAT_FOLIAGE: int = 1
const MAT_WOOD: int = 2
const MAT_BRUSH: int = 3

const DEFAULT_CELL_PX: float = 2.0
const MAX_GRID_DIM: int = 72
const ALPHA_THRESHOLD: float = 0.35

const BRUSH_SPECIES: Dictionary = {
	"heather": true,
	"fescue": true,
	"cattails": true,
}

const SOLID_WOOD_SPECIES: Dictionary = {
	"cactus": true,
	"dead_tree": true,
}

const CONIFER_SPECIES: Dictionary = {
	"pine": true,
	"cypress": true,
}

## Static cache keyed by `"<path>|<species>"` or `"silhouette|<species>|<facing>"`.
static var _cache: Dictionary = {}

var cell_px: float = DEFAULT_CELL_PX
var cols: int = 0
var rows: int = 0
## Bounding box in unvaried (scale_v = 1.0) rendered pixels relative to the
## tree's ground anchor, BEFORE `post_offset` (`art_offset_x` / `art_offset_y`).
## `min_h` can be slightly negative if a mod layout shifts `offset_y` up.
var min_local_x: float = 0.0
var max_local_x: float = 0.0
var min_local_h: float = 0.0
var max_local_h: float = 0.0
var post_offset: Vector2 = Vector2.ZERO

## Bottom-most & top-most opaque height (world-relative with scale_v = 1.0).
var lowest_world_h: float = 0.0
var max_world_h: float = 0.0
var max_abs_dx: float = 0.0
var trunk_center_x: float = 0.0
var crown_center_h: float = 20.0

## Packed cell buffer (rows * cols): row 0 is at `min_local_h`, row `rows - 1`
## is at the crown top.
var cells: PackedByteArray = PackedByteArray()
## Per-row horizontal extents in unvaried local pixels relative to ground X.
var row_min_x: PackedFloat32Array = PackedFloat32Array()
var row_max_x: PackedFloat32Array = PackedFloat32Array()


## Clear the entire profile cache (called when mod tree art is registered/cleared).
static func invalidate_cache() -> void:
	_cache.clear()


## Fetch or build the collision profile for a tree sprite at tile `_pos`.
static func get_profile_for_tile(_grid: TerrainGrid, _pos: Vector2i, species: String,
		facing: int) -> TreeCollisionProfile:
	var day: int = GameManager.current_day if GameManager else 1
	var theme: int = GameManager.current_theme if GameManager else CourseTheme.Type.PARKLAND
	var path := TreeOverlay.sprite_path(species, day, theme, facing)
	var cache_key := "%s|%s" % [path, species] if not path.is_empty() else "silhouette|%s|%d" % [
		species, wrapi(facing, 0, TreeOverlay.FACINGS.size())]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var profile: TreeCollisionProfile = null
	if not path.is_empty():
		var tex := TreeOverlay.texture_at(path)
		if tex != null:
			var img := tex.get_image()
			if img != null:
				if img.is_compressed():
					var decompressed := img.duplicate() as Image
					if decompressed != null and decompressed.decompress() == OK:
						img = decompressed
					else:
						img = null
				if img != null:
					var art_scale_v := TreeOverlay.art_scale(path)
					var src_size := Vector2(img.get_width(), img.get_height())
					var anchor_unit := TreeOverlay.art_anchor_offset(species, path, src_size, 1.0)
					var offset_v := Vector2(TreeOverlay.art_offset_x(path), TreeOverlay.art_offset_y(path))
					profile = _build_from_image(img, species, art_scale_v, anchor_unit, offset_v)

	if profile == null:
		profile = _build_silhouette_profile(species, facing)

	_cache[cache_key] = profile
	return profile


## Build a profile directly from an Image and its TreeOverlay layout transform.
static func _build_from_image(img: Image, species: String, art_scale_v: float,
		anchor_unit: Vector2, offset_v: Vector2) -> TreeCollisionProfile:
	var p := TreeCollisionProfile.new()
	p.post_offset = offset_v

	var img_w := img.get_width()
	var img_h := img.get_height()
	if img_w <= 0 or img_h <= 0:
		return _build_silhouette_profile(species, TreeOverlay.DEFAULT_FACING)

	var rendered_size := Vector2(img_w, img_h) * art_scale_v
	var top_left_unit := -rendered_size * 0.5 - anchor_unit

	# Pass 1: find per-image-row opaque spans & overall rendered bounds.
	var src_row_min := PackedInt32Array()
	var src_row_max := PackedInt32Array()
	var src_row_count := PackedInt32Array()
	src_row_min.resize(img_h)
	src_row_max.resize(img_h)
	src_row_count.resize(img_h)
	src_row_min.fill(img_w)
	src_row_max.fill(-1)
	src_row_count.fill(0)

	var min_lx := INF
	var max_lx := -INF
	var min_lh := INF
	var max_lh := -INF
	var any_opaque := false

	for sy in range(img_h):
		var lh := -(top_left_unit.y + (float(sy) + 0.5) * art_scale_v)
		# Ignore ground-disc art sitting well below the ground anchor.
		if lh + offset_v.y < -4.0:
			continue
		var rmin := img_w
		var rmax := -1
		var rcnt := 0
		for sx in range(img_w):
			if img.get_pixel(sx, sy).a < ALPHA_THRESHOLD:
				continue
			rcnt += 1
			if sx < rmin:
				rmin = sx
			if sx > rmax:
				rmax = sx
		if rcnt == 0:
			continue
		src_row_min[sy] = rmin
		src_row_max[sy] = rmax
		src_row_count[sy] = rcnt
		var row_lx0 := top_left_unit.x + (float(rmin) + 0.5) * art_scale_v
		var row_lx1 := top_left_unit.x + (float(rmax) + 0.5) * art_scale_v
		min_lx = minf(min_lx, row_lx0)
		max_lx = maxf(max_lx, row_lx1)
		min_lh = minf(min_lh, lh)
		max_lh = maxf(max_lh, lh)
		any_opaque = true

	if not any_opaque:
		return _build_silhouette_profile(species, TreeOverlay.DEFAULT_FACING)

	# Estimate trunk center X from the lower third of the visible sprite.
	var lower_h_limit := lerpf(min_lh, max_lh, 0.35)
	var trunk_x_sum := 0.0
	var trunk_x_weight := 0.0
	for sy in range(img_h):
		if src_row_count[sy] == 0:
			continue
		var lh := -(top_left_unit.y + (float(sy) + 0.5) * art_scale_v)
		if lh <= lower_h_limit:
			var span_px := float(src_row_max[sy] - src_row_min[sy] + 1) * art_scale_v
			if span_px <= 22.0 or species in SOLID_WOOD_SPECIES:
				var cx := top_left_unit.x + (float(src_row_min[sy] + src_row_max[sy]) * 0.5 + 0.5) * art_scale_v
				trunk_x_sum += cx * float(src_row_count[sy])
				trunk_x_weight += float(src_row_count[sy])
	p.trunk_center_x = trunk_x_sum / trunk_x_weight if trunk_x_weight > 0.0 else 0.0

	# Estimate height where a dense canopy starts (leaves narrower trunks below as MAT_WOOD).
	# Skip flared root bases near the bottom of broadleaf/palm sprites so roots stay MAT_WOOD.
	var canopy_start_h := INF
	if not BRUSH_SPECIES.has(species) and not SOLID_WOOD_SPECIES.has(species):
		for sy in range(img_h - 1, -1, -1):
			if src_row_count[sy] == 0:
				continue
			var lh := -(top_left_unit.y + (float(sy) + 0.5) * art_scale_v)
			var span_src := src_row_max[sy] - src_row_min[sy] + 1
			var span_px := float(span_src) * art_scale_v
			var fill_ratio := float(src_row_count[sy]) / float(maxi(span_src, 1))
			var above_root_flare := (lh - min_lh) >= 14.0 or span_px >= 26.0
			if above_root_flare and span_px >= 20.0 and fill_ratio >= 0.45:
				canopy_start_h = lh
				break

	# Extend ground anchor down to h=0 (world) for padded trunk roots (e.g. winter sprites).
	var min_lh_with_root := minf(min_lh, -offset_v.y)
	p.min_local_x = min_lx - 1.0
	p.max_local_x = max_lx + 1.0
	p.min_local_h = min_lh_with_root - 1.0
	p.max_local_h = max_lh + 1.0

	var span_w := p.max_local_x - p.min_local_x
	var span_h := p.max_local_h - p.min_local_h
	p.cell_px = maxf(DEFAULT_CELL_PX, maxf(span_w, span_h) / float(MAX_GRID_DIM - 2))
	p.cols = clampi(ceili(span_w / p.cell_px), 1, MAX_GRID_DIM)
	p.rows = clampi(ceili(span_h / p.cell_px), 1, MAX_GRID_DIM)

	p.cells.resize(p.cols * p.rows)
	p.cells.fill(MAT_EMPTY)
	p.row_min_x.resize(p.rows)
	p.row_max_x.resize(p.rows)
	p.row_min_x.fill(INF)
	p.row_max_x.fill(-INF)

	var total_h_span := maxf(max_lh - min_lh, 1.0)
	var is_brush := BRUSH_SPECIES.has(species)
	var is_solid_wood := SOLID_WOOD_SPECIES.has(species)
	var is_conifer := CONIFER_SPECIES.has(species)
	var is_birch := species == "birch"
	var is_leafy_shrub := species == "bush"

	# Pass 2: rasterize opaque pixels into 2px collision cells.
	for sy in range(img_h):
		if src_row_count[sy] == 0:
			continue
		var lh := -(top_left_unit.y + (float(sy) + 0.5) * art_scale_v)
		var row_idx := clampi(floori((lh - p.min_local_h) / p.cell_px), 0, p.rows - 1)
		var span_src := src_row_max[sy] - src_row_min[sy] + 1
		var span_px := float(span_src) * art_scale_v
		var fill_ratio := float(src_row_count[sy]) / float(maxi(span_src, 1))
		var h_ratio := clampf((lh - min_lh) / total_h_span, 0.0, 1.0)

		for sx in range(src_row_min[sy], src_row_max[sy] + 1):
			var col_pixel := img.get_pixel(sx, sy)
			if col_pixel.a < ALPHA_THRESHOLD:
				continue
			var lx := top_left_unit.x + (float(sx) + 0.5) * art_scale_v
			var col_idx := clampi(floori((lx - p.min_local_x) / p.cell_px), 0, p.cols - 1)
			var mat := _classify_pixel(
				col_pixel, species, lx, p.trunk_center_x, lh, canopy_start_h,
				span_px, fill_ratio, h_ratio,
				is_brush, is_solid_wood, is_conifer, is_birch, is_leafy_shrub
			)
			var idx := row_idx * p.cols + col_idx
			if _mat_priority(mat) > _mat_priority(p.cells[idx]):
				p.cells[idx] = mat
			if lx < p.row_min_x[row_idx]:
				p.row_min_x[row_idx] = lx
			if lx > p.row_max_x[row_idx]:
				p.row_max_x[row_idx] = lx

	p._finalize_metrics(min_lh + offset_v.y, max_lh + offset_v.y)
	return p


static func _classify_pixel(c: Color, species: String, lx: float, trunk_cx: float,
		lh: float, canopy_start_h: float, span_px: float, fill_ratio: float, h_ratio: float,
		is_brush: bool, is_solid_wood: bool, is_conifer: bool, is_birch: bool,
		is_leafy_shrub: bool) -> int:
	if is_brush:
		return MAT_BRUSH
	if is_solid_wood:
		return MAT_WOOD
	if is_leafy_shrub:
		return MAT_FOLIAGE

	var dx_trunk := absf(lx - trunk_cx)
	# Clear lower trunk beneath the canopy start (including root flare).
	if lh < canopy_start_h and (span_px <= 16.0 or dx_trunk <= 12.0):
		return MAT_WOOD

	var max_c := maxf(c.r, maxf(c.g, c.b))
	var min_c := minf(c.r, minf(c.g, c.b))
	var sat := (max_c - min_c) / max_c if max_c > 0.001 else 0.0

	# Sparse winter limbs / bare canopy skeleton without green leaves.
	if not is_conifer and species != "palm" and fill_ratio < 0.50 and sat < 0.30 and c.g <= c.r * 1.05:
		return MAT_WOOD

	# Conifers hide their trunk inside the needle skirt.
	if is_conifer and dx_trunk <= 4.0 and h_ratio <= 0.65:
		return MAT_WOOD

	# Birch white bark inside lower foliage.
	if is_birch and dx_trunk <= 5.5 and h_ratio <= 0.65 and sat < 0.22 and c.r > 0.50:
		return MAT_WOOD

	# Exposed brown bark / lower limbs visible inside open canopies or root flares.
	if dx_trunk <= 11.0 and h_ratio <= 0.60 and c.r > c.g * 1.10 \
			and c.g >= c.b * 0.95 and c.r < 0.65:
		return MAT_WOOD

	return MAT_FOLIAGE


## Build a deterministic silhouette collision profile when no PNG sprite exists.
static func _build_silhouette_profile(species: String, facing: int) -> TreeCollisionProfile:
	var p := TreeCollisionProfile.new()
	p.post_offset = Vector2.ZERO
	p.cell_px = DEFAULT_CELL_PX

	var turned := wrapi(facing, 0, TreeOverlay.FACINGS.size())
	var mirror := -1.0 if turned >= 2 else 1.0
	var profile_scale := 0.82 if (turned == 1 or turned == 3) else 1.0
	var tilt := 0.05 if turned == 1 else (-0.05 if turned == 3 else 0.0)

	var shape := str(TreeOverlay.CANOPY_SHAPES.get(species, "broadleaf"))
	var extent_x := 24.0
	var extent_h := 50.0
	match shape:
		"conifer":
			extent_x = 16.0
			extent_h = 48.0
		"mound":
			extent_x = 14.0
			extent_h = 20.0
		"tuft":
			extent_x = 10.0
			extent_h = 18.0
		"reed":
			extent_x = 12.0
			extent_h = 28.0
		"column":
			extent_x = 16.0
			extent_h = 36.0
		"bare":
			extent_x = 16.0
			extent_h = 38.0
		"fan":
			extent_x = 22.0
			extent_h = 48.0

	p.min_local_x = -extent_x
	p.max_local_x = extent_x
	p.min_local_h = 0.0
	p.max_local_h = extent_h
	p.cols = clampi(ceili((p.max_local_x - p.min_local_x) / p.cell_px), 1, MAX_GRID_DIM)
	p.rows = clampi(ceili((p.max_local_h - p.min_local_h) / p.cell_px), 1, MAX_GRID_DIM)
	p.cells.resize(p.cols * p.rows)
	p.cells.fill(MAT_EMPTY)
	p.row_min_x.resize(p.rows)
	p.row_max_x.resize(p.rows)
	p.row_min_x.fill(INF)
	p.row_max_x.fill(-INF)

	var mat_canopy := MAT_BRUSH if BRUSH_SPECIES.has(species) else MAT_FOLIAGE
	for r in range(p.rows):
		var h := p.min_local_h + (float(r) + 0.5) * p.cell_px
		for c_idx in range(p.cols):
			var x := p.min_local_x + (float(c_idx) + 0.5) * p.cell_px
			# Undo tilt/mirror into canonical shape coords to test silhouette.
			var ux := (x + tilt * h) / (mirror * profile_scale)
			var mat := MAT_EMPTY
			match shape:
				"conifer":
					if h <= 12.0 and absf(ux) <= 3.5:
						mat = MAT_WOOD
					elif h >= 10.0 and h <= 46.0:
						for tier in range(3):
							var bottom := 10.0 + float(tier) * 10.0
							var tier_top := bottom + 16.0
							if h >= bottom and h <= tier_top:
								var w := (28.0 - float(tier) * 7.0) * 0.5 * (1.0 - (h - bottom) / 16.0)
								if absf(ux) <= w:
									mat = MAT_WOOD if (absf(ux) <= 2.5 and h <= 28.0) else MAT_FOLIAGE
									break
				"mound":
					var dy := (h - 6.0) / (12.0 * 0.85)
					var dx := ux / 12.0
					if dx * dx + dy * dy <= 1.0:
						mat = mat_canopy
				"tuft":
					if h <= 16.0 and absf(ux) <= 8.0 * (0.4 + 0.6 * h / 16.0):
						mat = MAT_BRUSH
				"reed":
					if h <= 27.0 and absf(ux) <= 9.0:
						mat = MAT_BRUSH
				"column":
					if (h <= 34.0 and absf(ux) <= 4.0) or \
							(h >= 22.0 and h <= 26.0 and ux >= -14.0 and ux <= -4.0) or \
							(h >= 16.0 and h <= 20.0 and ux >= 4.0 and ux <= 14.0):
						mat = MAT_WOOD
				"bare":
					if h <= 26.0 and absf(ux) <= 4.0:
						mat = MAT_WOOD
					elif h >= 18.0 and h <= 34.0:
						var expected := (h - 18.0) / 16.0 * 14.0
						if absf(absf(ux) - expected) <= 2.5:
							mat = MAT_WOOD
				"fan":
					if h <= 34.0 and absf(ux) <= 3.5:
						mat = MAT_WOOD
					elif h >= 22.0 and h <= 46.0:
						var dy_f := (h - 34.0) / 12.0
						var dx_f := ux / 20.0
						if dx_f * dx_f + dy_f * dy_f <= 1.0:
							mat = MAT_FOLIAGE
				_:  # broadleaf
					if h <= 16.0 and absf(ux) <= 4.0:
						mat = MAT_WOOD
					else:
						var main_d := pow(ux / 20.0, 2.0) + pow((h - 24.0) / 17.0, 2.0)
						var left_d := pow((ux + 9.0) / 13.0, 2.0) + pow((h - 18.0) / 11.0, 2.0)
						var right_d := pow((ux - 9.0) / 12.0, 2.0) + pow((h - 19.0) / 10.5, 2.0)
						if main_d <= 1.0 or left_d <= 1.0 or right_d <= 1.0:
							mat = MAT_FOLIAGE
			if mat != MAT_EMPTY:
				p.cells[r * p.cols + c_idx] = mat
				if x < p.row_min_x[r]:
					p.row_min_x[r] = x
				if x > p.row_max_x[r]:
					p.row_max_x[r] = x

	p.trunk_center_x = 0.0
	p._finalize_metrics(0.0, extent_h)
	return p


func _finalize_metrics(lowest_w_h: float, max_w_h: float) -> void:
	# Fill vertical root column down to world ground h=0 if bottom padding lifted roots.
	if lowest_w_h > 0.0 and lowest_w_h <= 14.0:
		var root_h := -post_offset.y
		var r_from := clampi(floori((root_h - min_local_h) / cell_px), 0, rows - 1)
		var r_to := clampi(floori((lowest_w_h - post_offset.y - min_local_h) / cell_px), 0, rows - 1)
		var c_from := clampi(floori((trunk_center_x - 4.0 - min_local_x) / cell_px), 0, cols - 1)
		var c_to := clampi(floori((trunk_center_x + 4.0 - min_local_x) / cell_px), 0, cols - 1)
		for r in range(r_from, r_to + 1):
			for c_idx in range(c_from, c_to + 1):
				var idx := r * cols + c_idx
				if cells[idx] == MAT_EMPTY:
					cells[idx] = MAT_WOOD
			row_min_x[r] = minf(row_min_x[r], trunk_center_x - 4.0)
			row_max_x[r] = maxf(row_max_x[r], trunk_center_x + 4.0)
		lowest_world_h = 0.0
	else:
		lowest_world_h = maxf(lowest_w_h, 0.0)

	max_world_h = maxf(max_w_h, 0.0)
	var max_x := 0.0
	var h_sum := 0.0
	var h_cnt := 0
	for r in range(rows):
		if row_max_x[r] >= row_min_x[r]:
			max_x = maxf(max_x, maxf(absf(row_min_x[r] + post_offset.x), absf(row_max_x[r] + post_offset.x)))
			h_sum += min_local_h + (float(r) + 0.5) * cell_px + post_offset.y
			h_cnt += 1
	max_abs_dx = max_x
	crown_center_h = h_sum / float(h_cnt) if h_cnt > 0 else max_world_h * 0.5


## Sample the tree's horizontal width at world-relative height `h_world` (with `scale_v`).
## Returns half-width in rendered screen pixels (0.0 if height row is empty).
func half_width_at_height(h_world: float, scale_v: float) -> float:
	if rows <= 0:
		return 0.0
	var h_unit := (h_world - post_offset.y) / maxf(scale_v, 0.1)
	if h_unit < min_local_h or h_unit > max_local_h:
		return 0.0
	var r := clampi(floori((h_unit - min_local_h) / cell_px), 0, rows - 1)
	if row_max_x[r] < row_min_x[r]:
		return 0.0
	return (row_max_x[r] - row_min_x[r]) * 0.5 * scale_v


## Sample the ball sphere (radius `ball_r_px` around world-relative `(dx_px, h_world)`)
## against this tree's scaled collision grid.
## Returns highest-priority material hit (`MAT_WOOD > MAT_FOLIAGE > MAT_BRUSH > MAT_EMPTY`).
func sample_ball(dx_px: float, h_world: float, ball_r_px: float, scale_v: float) -> int:
	if cols <= 0 or rows <= 0:
		return MAT_EMPTY
	var inv_s := 1.0 / maxf(scale_v, 0.1)
	var ux := (dx_px - post_offset.x) * inv_s
	var uh := (h_world - post_offset.y) * inv_s
	var ur := ball_r_px * inv_s

	if ux + ur < min_local_x or ux - ur > max_local_x:
		return MAT_EMPTY
	if uh + ur < min_local_h or uh - ur > max_local_h:
		return MAT_EMPTY

	var c0 := clampi(floori((ux - ur - min_local_x) / cell_px), 0, cols - 1)
	var c1 := clampi(floori((ux + ur - min_local_x) / cell_px), 0, cols - 1)
	var r0 := clampi(floori((uh - ur - min_local_h) / cell_px), 0, rows - 1)
	var r1 := clampi(floori((uh + ur - min_local_h) / cell_px), 0, rows - 1)

	var best := MAT_EMPTY
	var ur_sq := ur * ur
	for r in range(r0, r1 + 1):
		var cy := min_local_h + (float(r) + 0.5) * cell_px
		var dy_c := absf(uh - cy) - cell_px * 0.5
		if dy_c > ur:
			continue
		var dy_pos := maxf(dy_c, 0.0)
		var row_off := r * cols
		for c_idx in range(c0, c1 + 1):
			var mat := cells[row_off + c_idx]
			if mat == MAT_EMPTY or _mat_priority(mat) <= _mat_priority(best):
				continue
			var cx := min_local_x + (float(c_idx) + 0.5) * cell_px
			var dx_c := maxf(absf(ux - cx) - cell_px * 0.5, 0.0)
			if dx_c * dx_c + dy_pos * dy_pos <= ur_sq:
				best = mat
				if best == MAT_WOOD:
					return MAT_WOOD
	return best


## Rotation-invariant cylindrical radial collision query at radial distance `r_iso`
## from the trunk center axis and world height `h_world`.
func sample_radial(r_iso: float, h_world: float, ball_r_px: float, scale_v: float) -> int:
	var axis_x := trunk_center_x * scale_v + post_offset.x
	var a := sample_ball(axis_x + r_iso, h_world, ball_r_px, scale_v)
	if a == MAT_WOOD or r_iso <= 0.05:
		return a
	var b := sample_ball(axis_x - r_iso, h_world, ball_r_px, scale_v)
	return a if _mat_priority(a) >= _mat_priority(b) else b


static func _mat_priority(mat: int) -> int:
	match mat:
		MAT_WOOD:
			return 3
		MAT_FOLIAGE:
			return 2
		MAT_BRUSH:
			return 1
		_:
			return 0
