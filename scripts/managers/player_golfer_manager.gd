extends Node
class_name PlayerGolferManager
## PlayerGolferManager - The owner's own golfer, and the ground they work.
##
## The owner's golfer is not a guest: they are on the course from the start
## and stay there. Between rounds they work the course - walking a movable
## area, pulling the weeds a groundskeeper would pull and chatting with the
## golfers a greeter would cheer up (see OwnerDuty).
##
## When the owner starts a round the same golfer tees off, and when the round
## is over they go back to work. The manager owns that golfer: it creates
## them, keeps them dressed in the owner's profile, moves them on and off the
## course for a round, and holds the ground they work so that it can be
## saved with the course.

const GOLFER_SCENE := preload("res://scenes/entities/golfer.tscn")
## The ground the owner works, in tiles around its centre.
const AREA_RADIUS: float = 8.0
## The owner's golfer keeps this id. Negative, so it never clashes with the
## guests the GolferManager numbers from zero.
const OWNER_GOLFER_ID: int = -1

## The owner's golfer.
var golfer: Golfer = null
## Their duty: the work they do between rounds.
var duty: OwnerDuty = null
## The ground the owner works, and how wide it is.
var area_center: Vector2i = Vector2i(-1, -1)
var area_radius: float = AREA_RADIUS
## Where the golfer is parented - the Golfers container of the course.
var container: Node2D = null

## The ground the owner works moved.
signal area_changed(center: Vector2i)

func _ready() -> void:
	# A Golfer Skin the player paints in the studio dresses the owner too.
	GolferSkins.skins_changed.connect(_on_skins_changed)

func _exit_tree() -> void:
	if GolferSkins.skins_changed.is_connected(_on_skins_changed):
		GolferSkins.skins_changed.disconnect(_on_skins_changed)

## Seat the manager: the owner's golfer lives in `golfers_container`.
func setup(golfers_container: Node2D) -> void:
	container = golfers_container

## The owner's golfer, created the first time it is asked for. They wear the
## owner's profile: their name, their colours and the skills they allocated.
func ensure_golfer() -> Golfer:
	if golfer != null and is_instance_valid(golfer):
		refresh_profile()
		_push_area()
		return golfer
	if container == null:
		return null
	var node := GOLFER_SCENE.instantiate() as Golfer
	node.name = "OwnerGolfer"
	node.golfer_id = OWNER_GOLFER_ID
	# They are the owner of the course, not a guest on it: they never leave,
	# and their round ends when they have played every hole.
	node.is_course_owner = true
	container.add_child(node)
	golfer = node
	duty = OwnerDuty.new()
	duty.name = "OwnerDuty"
	golfer.add_child(duty)
	duty.setup(golfer)
	refresh_profile()
	if area_center.x < 0:
		area_center = _default_area_center()
	_push_area()
	_place_at_area()
	golfer.begin_course_duty()
	# They start work straight away: the ground they were given is where
	# they are standing.
	if duty != null:
		duty.begin()
	return golfer

## Hand the ground the owner works to their duty.
func _push_area() -> void:
	if duty != null and is_instance_valid(duty):
		duty.set_area(area_center, area_radius)

## Dress the owner's golfer in the owner's profile: their name, their
## colours and the skills they allocated.
func refresh_profile() -> void:
	if golfer == null or not is_instance_valid(golfer):
		return
	var profile := GameManager.player_profile
	if profile == null:
		return
	golfer.player_profile = profile
	golfer.golfer_name = profile.golfer_name
	golfer.miss_tendency = 0.0
	golfer.sync_player_profile_skills()
	golfer.apply_player_appearance(profile)

## The owner's golfer tees off: the same golfer who works the course plays
## the round, and the course plays on with them in it. They walk to the tee
## from the ground they were working.
func claim_for_round(group_id: int, tee: Vector2i = Vector2i(-1, -1)) -> Golfer:
	var course_owner := ensure_golfer()
	if course_owner == null:
		return null
	course_owner.is_owner_round = true
	course_owner.group_id = group_id
	_clear_round(course_owner)
	var manager := GameManager.golfer_manager
	if manager != null:
		manager.join_course(course_owner, group_id)
	if duty != null:
		duty.stop()
	course_owner.end_course_duty()
	# The walk to the tee: the round waits for them to arrive, because the
	# turn system only ever plays an IDLE golfer.
	if duty != null and tee.x >= 0:
		duty.walk_to_tee(tee)
	return course_owner

## The round is over: the owner goes back to work on the course.
func release_from_round() -> void:
	if golfer == null or not is_instance_valid(golfer):
		return
	var manager := GameManager.golfer_manager
	if manager != null:
		manager.take_off_course(golfer)
	golfer.is_owner_round = false
	golfer.group_id = -1
	_clear_round(golfer)
	golfer.begin_course_duty()
	if duty != null:
		duty.begin()

## The owner has played every hole of their round. They are not a guest: they
## do not leave the course, they go back to work on it.
func owner_finished_round() -> void:
	if golfer == null or not is_instance_valid(golfer):
		return
	var manager := GameManager.golfer_manager
	if manager != null:
		manager.take_off_course(golfer)
	golfer.is_owner_round = false
	golfer.group_id = -1
	golfer.begin_course_duty()
	if duty != null:
		duty.begin_home()

## Clear the last round off the owner's golfer: the scorecard belongs to the
## round that is over, not to the one that is starting.
func _clear_round(course_owner: Golfer) -> void:
	course_owner.hole_scores.clear()
	course_owner.total_strokes = 0
	course_owner.total_par = 0
	course_owner.current_strokes = 0
	course_owner.previous_hole_strokes = 0
	course_owner.current_hole = 0
	course_owner.paid_round_fee = 0
	course_owner.amenities_used = 0
	course_owner.staff_help_cooldown = 0.0
	course_owner.has_cart = false
	course_owner.walk_speed = 100.0
	course_owner.round_complete = false

## Move the ground the owner works.
func set_area_center(center: Vector2i) -> bool:
	var grid := GameManager.terrain_grid
	if grid == null or not grid.is_valid_position(center):
		return false
	area_center = center
	_push_area()
	# If the ground they were working is not the ground they work now, they
	# head for the new ground rather than trudging across the course.
	if golfer != null and is_instance_valid(golfer):
		var here := grid.screen_to_grid_point(golfer.global_position)
		if here.distance_to(Vector2(area_center)) > area_radius:
			_place_at_area()
	area_changed.emit(area_center)
	return true

## Where the owner works when the player has not chosen: the middle of the
## course, or the clubhouse when the course has one.
func _default_area_center() -> Vector2i:
	var course := GameManager.current_course
	if course != null and course.holes.size() > 0:
		var sum := Vector2.ZERO
		for hole in course.holes:
			sum += Vector2(hole.tee_position)
		return Vector2i((sum / float(course.holes.size())).round())
	var layer = GameManager.entity_layer
	if layer != null and layer.has_method("get_all_buildings"):
		for building in layer.get_all_buildings():
			if building.building_type == "clubhouse":
				return building.grid_position
	var grid := GameManager.terrain_grid
	if grid != null:
		# The area is a whole tile; truncate any fractional grid centre.
		@warning_ignore_start("integer_division")
		return Vector2i(grid.grid_width / 2, grid.grid_height / 2)
		@warning_ignore_restore("integer_division")
	return Vector2i(64, 64)

## Put the owner's golfer on the ground they work.
func _place_at_area() -> void:
	var grid := GameManager.terrain_grid
	if grid == null or golfer == null or not is_instance_valid(golfer):
		return
	golfer.global_position = grid.grid_to_screen_center(area_center)

## A new course: the owner is on it from the start, working the middle of it
## until the player moves their area somewhere else.
func on_course_ready() -> void:
	var grid := GameManager.terrain_grid
	if grid != null and area_center.x >= 0 and not grid.is_valid_position(area_center):
		area_center = Vector2i(-1, -1)
	if area_center.x < 0:
		area_center = _default_area_center()
	ensure_golfer()
	_push_area()
	_place_at_area()

## A new course starts with the ground unchosen: the owner works the middle
## of it until the player moves their area somewhere else.
func reset_area() -> void:
	area_center = Vector2i(-1, -1)

## The player painted a skin: the owner wears it like everyone else.
func _on_skins_changed() -> void:
	if golfer != null and is_instance_valid(golfer):
		golfer.refresh_skin_sprites()

## The ground the owner works, for the save file.
func serialize() -> Dictionary:
	return {
		"area_center": {"x": area_center.x, "y": area_center.y},
		"area_radius": area_radius,
	}

## Restore the ground the owner works.
func deserialize(data: Dictionary) -> void:
	area_radius = maxf(1.0, float(data.get("area_radius", AREA_RADIUS)))
	var center_data = data.get("area_center", {})
	var center := Vector2i(-1, -1)
	if center_data is Dictionary and center_data.has("x"):
		center = Vector2i(int(center_data.x), int(center_data.y))
	elif center_data is Vector2i:
		center = center_data
	area_center = center
	_push_area()
	area_changed.emit(area_center)
