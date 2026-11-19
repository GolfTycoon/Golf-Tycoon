extends Node2D
class_name TreeImpactEffect
## Temporary Polygon2D particle burst spawned when a golf ball strikes a tree's
## trunk, canopy foliage, or ground brush. Honors PerformanceSettings quality caps.

const PARTICLE_COUNT: int = 8
const WEB_PARTICLE_COUNT: int = 4
const PARTICLE_LIFETIME: float = 0.75

const WOOD_COLORS: Array = [
	Color(0.55, 0.36, 0.22),
	Color(0.42, 0.26, 0.15),
	Color(0.95, 0.90, 0.75),
]
const LEAF_COLORS_SUMMER: Array = [
	Color(0.28, 0.62, 0.25),
	Color(0.36, 0.72, 0.30),
	Color(0.20, 0.48, 0.20),
]
const LEAF_COLORS_FALL: Array = [
	Color(0.88, 0.45, 0.15),
	Color(0.82, 0.25, 0.16),
	Color(0.92, 0.72, 0.20),
]
const LEAF_COLORS_WINTER: Array = [
	Color(0.88, 0.93, 0.98),
	Color(0.32, 0.46, 0.34),
	Color(0.55, 0.50, 0.44),
]
const BRUSH_COLORS: Array = [
	Color(0.62, 0.56, 0.32),
	Color(0.52, 0.42, 0.58),
	Color(0.45, 0.58, 0.28),
]

var material_type: int = TreeCollisionProfile.MAT_FOLIAGE
var species: String = "oak"
var _particles_finished: int = 0
var _particle_count: int = 0
var _web_mode: bool = false


func _ready() -> void:
	z_index = 200
	_particle_count = PerformanceSettings.particle_count(
		WEB_PARTICLE_COUNT if _web_mode else PARTICLE_COUNT
	)
	if _particle_count <= 0:
		queue_free()
		return
	_spawn_particles()


func _pick_palette() -> Array:
	if material_type == TreeCollisionProfile.MAT_WOOD:
		if species == "cactus":
			return LEAF_COLORS_SUMMER
		return WOOD_COLORS
	if material_type == TreeCollisionProfile.MAT_BRUSH:
		return BRUSH_COLORS
	var season: int = SeasonSystem.Season.SUMMER
	if GameManager:
		season = SeasonSystem.get_season(GameManager.current_day)
	if season == SeasonSystem.Season.FALL and not TreeCollisionProfile.CONIFER_SPECIES.has(species):
		return LEAF_COLORS_FALL
	if season == SeasonSystem.Season.WINTER:
		return LEAF_COLORS_WINTER
	return LEAF_COLORS_SUMMER


func _spawn_particles() -> void:
	var palette := _pick_palette()
	var is_wood := material_type == TreeCollisionProfile.MAT_WOOD

	for i in range(_particle_count):
		var particle := Polygon2D.new()
		particle.color = palette[randi() % palette.size()]
		if is_wood:
			var w := randf_range(1.6, 3.0)
			var h := randf_range(1.0, 2.0)
			particle.polygon = PackedVector2Array([
				Vector2(-w, -h), Vector2(w, -h * 0.6),
				Vector2(w * 0.8, h), Vector2(-w * 0.8, h * 0.7),
			])
		else:
			var s := randf_range(2.0, 3.6)
			particle.polygon = PackedVector2Array([
				Vector2(-s, 0.0), Vector2(0.0, -s * 0.55),
				Vector2(s, 0.0), Vector2(0.0, s * 0.55),
			])
		add_child(particle)

		var angle := randf_range(-PI, 0.0) if is_wood else randf_range(0.0, TAU)
		var speed := randf_range(22.0, 56.0) if is_wood else randf_range(12.0, 32.0)
		var drift := Vector2(cos(angle), sin(angle)) * speed + Vector2(0.0, randf_range(8.0, 22.0))
		var lifetime := randf_range(PARTICLE_LIFETIME * 0.55, PARTICLE_LIFETIME)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", drift, lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(particle, "rotation", randf_range(-3.0, 3.0), lifetime)
		tween.tween_property(particle, "modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN)
		tween.set_parallel(false)
		tween.tween_callback(_on_particle_finished)


func _on_particle_finished() -> void:
	_particles_finished += 1
	if _particles_finished >= _particle_count:
		queue_free()


static func create_at(parent: Node, world_position: Vector2, p_material_type: int,
		p_species: String = "oak") -> TreeImpactEffect:
	if parent == null or not PerformanceSettings.particle_burst_enabled():
		return null
	var effect := TreeImpactEffect.new()
	effect.global_position = world_position
	effect.material_type = p_material_type
	effect.species = p_species
	if OS.get_name() == "Web":
		effect._web_mode = true
	parent.add_child(effect)
	return effect
