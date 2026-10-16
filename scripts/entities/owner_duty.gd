extends Node
class_name OwnerDuty
## OwnerDuty - The owner's own golfer working the course between rounds.
##
## The owner's golfer is not a guest: they live on the course (see
## PlayerGolferManager). When they are not playing they work the ground the
## player gave them - a movable area - doing the two jobs that keep a course
## running:
##
##   Groundskeeper  pull the weeds that sprout on the turf
##   Greeter        chat with the golfers on the course to cheer them up
##
## The machine is the one the hired staff use (see StaffMember): choose a
## task, walk to it, work on it, then look for the next one. The two jobs
## alternate, so the owner keeps the course tidy and keeps the guests
## cheerful in turn.
##
## The duty is a child of the golfer it drives, so it lives and dies with
## them, and the golfer's own state (ON_DUTY) keeps the turn system away
## from them while they work.

## The two jobs the owner's golfer does.
enum Job { GROUNDSKEEPER, GREETER }
## The duty machine's own states.
enum Step { IDLE, WALKING, WORKING }
## Why the owner is walking about rather than working.
enum Commute { NONE, TO_TEE, HOME }

## How close the owner has to be to a weed or a golfer for the work to count.
const SERVICE_RANGE_TILES: float = 2.5
## How close they have to be to their target before the work starts.
const ARRIVE_DISTANCE: float = 8.0
## The cheer the owner gives a golfer - a premium greeter's.
const GREET_EFFECT: float = 0.1
## How long pulling a weed takes, and how long a chat takes.
const WEED_WORK_SECONDS: float = 2.6
const GREET_WORK_SECONDS: float = 2.0
## A walk that takes longer than this has failed - something is in the way -
## and the owner looks for something else to do.
const WALK_TIMEOUT_SECONDS: float = 12.0
## The pause between one job and the next.
const IDLE_PAUSE_MIN: float = 0.4
const IDLE_PAUSE_MAX: float = 1.6
## How fast the owner walks while working. A golfer on the course moves at
## 100; working the ground is a slower, steadier pace.
const WORK_WALK_SPEED: float = 60.0

## The golfer this duty belongs to.
var golfer: Golfer = null
## The ground the owner works: a circle of tiles they do not stray far from.
var area_center: Vector2i = Vector2i(-1, -1)
var area_radius: float = 8.0
## The job the owner looks for work in next.
var job: Job = Job.GROUNDSKEEPER
## Where the duty machine is: idle, walking to a task, or working on it.
var step: Step = Step.IDLE
## Whether the work machine is running. The owner only works between rounds:
## a round takes them to the first tee and the work stops until it is over.
var running: bool = false
## The walk they are on, if any: to the tee to start a round, or back to the
## ground they work when a round is over.
var commute: Commute = Commute.NONE

var _timer: float = 0.0
var _walk_time: float = 0.0
var _target: Vector2 = Vector2.ZERO
var _weed: Vector2i = Vector2i(-1, -1)
var _guest: Golfer = null

## Attach the duty to the golfer it drives.
func setup(course_owner: Golfer) -> void:
	golfer = course_owner

## Start working: the owner walks their area, pulling weeds and greeting
## the golfers they meet, until a round takes them to the first tee.
func begin() -> void:
	running = true
	step = Step.IDLE
	_timer = 0.3
	_weed = Vector2i(-1, -1)
	_guest = null
	var course_owner := golfer
	if course_owner != null and is_instance_valid(course_owner):
		course_owner.activity_text = "Working the course"
		# A walk to the tee that the round ended in the middle of is not
		# resumed: they go back to the ground they work instead.
		if commute == Commute.TO_TEE:
			commute = Commute.NONE
			course_owner.path.clear()
			course_owner.path_index = 0
			course_owner.velocity = Vector2.ZERO
	# The round may have ended away from the ground they work: they walk back
	# to it before they start on the next job.
	if commute == Commute.NONE and _off_their_ground():
		_start_home_walk()

## The round has the owner on the first tee: no duty for now.
func stop() -> void:
	running = false
	commute = Commute.NONE
	step = Step.IDLE
	_weed = Vector2i(-1, -1)
	_guest = null

## Move the ground the owner works. The work in hand is over: it was on the
## old ground.
func set_area(center: Vector2i, radius: float = -1.0) -> void:
	area_center = center
	if radius > 0.0:
		area_radius = radius
	step = Step.IDLE
	_timer = 0.0
	_weed = Vector2i(-1, -1)
	_guest = null

## The round starts: the owner walks to the tee from the ground they were
## working. The work stops until they arrive.
func walk_to_tee(tee: Vector2i) -> bool:
	var grid := GameManager.terrain_grid
	if grid == null or not grid.is_valid_position(tee):
		return false
	running = false
	step = Step.IDLE
	_weed = Vector2i(-1, -1)
	_guest = null
	commute = Commute.TO_TEE
	# The ball is already on the tee; the owner is on their way to it.
	golfer.ball_position = tee
	golfer.ball_position_precise = Vector2(tee)
	golfer.begin_walk_to(grid.grid_to_screen_center(tee), "Walking to the tee")
	return true

## The round is over: the owner walks back to the ground they work.
func begin_home() -> void:
	if _off_their_ground():
		_start_home_walk()
	else:
		begin()

## The walk is over: the owner is where they were going.
func _arrived() -> void:
	var was := commute
	commute = Commute.NONE
	if was == Commute.HOME:
		# Back on the ground they work: the work starts again.
		if golfer != null and is_instance_valid(golfer):
			golfer.begin_course_duty()
		running = true
		step = Step.IDLE
		_timer = 0.3
		if golfer != null and is_instance_valid(golfer):
			golfer.activity_text = "Working the course"

## Is the owner away from the ground they work?
func _off_their_ground() -> bool:
	var grid := GameManager.terrain_grid
	if grid == null or area_center.x < 0:
		return false
	return _grid_point().distance_to(Vector2(area_center)) > area_radius

## Head back to the middle of the ground they work. The walk is the golfer's
## own, so it follows the trails and goes around obstacles.
func _start_home_walk() -> void:
	var grid := GameManager.terrain_grid
	if grid == null or area_center.x < 0:
		return
	commute = Commute.HOME
	golfer.begin_walk_to(grid.grid_to_screen_center(area_center), "Walking back to work")

## The weed the owner is walking to, or (-1, -1) when they are not on one.
func target_weed() -> Vector2i:
	return _weed

## The golfer the owner is walking to, or null when they are not on one.
func target_golfer() -> Golfer:
	return _guest

func _process(delta: float) -> void:
	if golfer == null or not is_instance_valid(golfer):
		return
	if GameManager.is_paused or GameManager.current_speed == GameManager.GameSpeed.PAUSED:
		return
	# A walk to the tee, or back to the ground they work, is the golfer's own
	# (see Golfer.begin_walk_to): wait for them to arrive.
	if commute != Commute.NONE:
		if commute == Commute.TO_TEE:
			golfer.activity_text = "Walking to the tee"
		else:
			golfer.activity_text = "Walking back to work"
		if golfer.current_state == Golfer.State.IDLE:
			_arrived()
		return
	# The work only runs between rounds: a round has the owner on the first
	# tee, not pulling weeds.
	if not running:
		return
	match step:
		Step.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_choose_task()
		Step.WALKING:
			_process_walk(delta)
		Step.WORKING:
			_process_work(delta)

# --- Task selection ---------------------------------------------------------

## Look for work. The jobs alternate, so the owner keeps the course tidy and
## keeps the guests cheerful in turn; when the job they are after has nothing
## to do, they take the other one instead.
func _choose_task() -> void:
	var found := false
	if job == Job.GROUNDSKEEPER:
		found = _seek_weed() or _seek_guest()
	else:
		found = _seek_guest() or _seek_weed()
	if not found:
		_wander()

## The nearest weed inside the owner's area.
func _seek_weed() -> bool:
	var weeds := GameManager.weed_manager
	var grid := GameManager.terrain_grid
	if weeds == null or grid == null:
		return false
	var best := Vector2i(-1, -1)
	var best_distance := INF
	var here := _grid_point()
	for pos in weeds.get_weed_positions():
		if Vector2(pos).distance_to(Vector2(area_center)) > area_radius:
			continue
		var distance := Vector2(pos).distance_to(here)
		if distance < best_distance:
			best_distance = distance
			best = pos
	if best == Vector2i(-1, -1):
		return false
	_weed = best
	_target = grid.grid_to_screen_center(best)
	step = Step.WALKING
	_walk_time = 0.0
	golfer.activity_text = "Pulling weeds"
	return true

## The golfer inside the owner's area who needs cheering up most - the same
## choice a hired greeter makes.
func _seek_guest() -> bool:
	var manager := GameManager.golfer_manager
	var grid := GameManager.terrain_grid
	if manager == null or grid == null:
		return false
	var best: Golfer = null
	var best_attitude := INF
	for guest in manager.get_active_golfers():
		if guest == null or not is_instance_valid(guest) or guest == golfer:
			continue
		if not guest.is_staff_service_available():
			continue
		var guest_grid := grid.screen_to_grid_point(guest.global_position)
		if guest_grid.distance_to(Vector2(area_center)) > area_radius:
			continue
		if guest.attitude < best_attitude:
			best_attitude = guest.attitude
			best = guest
	if best == null:
		return false
	_guest = best
	_target = best.global_position
	step = Step.WALKING
	_walk_time = 0.0
	golfer.activity_text = "Chatting with a golfer"
	return true

## Nothing to do: walk to a random spot inside the area, the way a hired
## employee wanders when their round of work is done.
func _wander() -> void:
	var grid := GameManager.terrain_grid
	if grid == null:
		step = Step.IDLE
		_timer = IDLE_PAUSE_MAX
		return
	var angle := randf() * TAU
	var radius := area_radius * sqrt(randf())
	var point := Vector2(area_center) + Vector2(cos(angle), sin(angle)) * radius
	point.x = clampf(point.x, 0.0, float(grid.grid_width - 1))
	point.y = clampf(point.y, 0.0, float(grid.grid_height - 1))
	_target = grid.grid_point_to_screen(point)
	step = Step.WALKING
	_walk_time = 0.0
	golfer.activity_text = "Walking the course"

# --- The walk ---------------------------------------------------------------

func _process_walk(delta: float) -> void:
	_walk_time += delta
	var to_target := _target - golfer.global_position
	var distance := to_target.length()
	if distance <= ARRIVE_DISTANCE:
		golfer.global_position = _target
		_arrive()
		return
	if _walk_time >= WALK_TIMEOUT_SECONDS:
		# The walk is getting nowhere: something is in the way.
		_abandon()
		return
	var direction := to_target / distance
	var step_length := minf(WORK_WALK_SPEED * delta, distance)
	golfer.velocity = direction * WORK_WALK_SPEED
	var collision := golfer.move_and_collide(direction * step_length)
	if collision != null:
		# Blocked: slide along the obstacle rather than stand still.
		var tangent := collision.get_normal().orthogonal()
		golfer.move_and_collide(tangent * step_length)
	golfer._animate_walking(delta)

## The owner has arrived: the work starts, unless there was nothing to do
## here (a wander point).
func _arrive() -> void:
	golfer.velocity = Vector2.ZERO
	if _weed != Vector2i(-1, -1) or _guest != null:
		step = Step.WORKING
		_timer = WEED_WORK_SECONDS if _weed != Vector2i(-1, -1) else GREET_WORK_SECONDS
		return
	step = Step.IDLE
	_timer = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)

func _process_work(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_finish_work()

## The work is done: the weed is pulled, or the golfer is cheered up.
func _finish_work() -> void:
	if _weed != Vector2i(-1, -1):
		var weeds := GameManager.weed_manager
		if weeds != null:
			weeds.remove_weed(_weed)
		_weed = Vector2i(-1, -1)
	elif _guest != null and is_instance_valid(_guest):
		_greet(_guest)
	_guest = null
	step = Step.IDLE
	_timer = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)
	# The jobs alternate, so the owner keeps the course tidy and keeps the
	# guests cheerful.
	job = Job.GREETER if job == Job.GROUNDSKEEPER else Job.GROUNDSKEEPER
	golfer.activity_text = "Working the course"

## Chat with a golfer. They have to stay close: walking off mid-conversation
## means no cheer, the same rule the hired staff work to.
func _greet(guest: Golfer) -> void:
	var grid := GameManager.terrain_grid
	if grid == null:
		return
	var distance := grid.screen_to_grid_point(guest.global_position).distance_to(_grid_point())
	if distance > SERVICE_RANGE_TILES:
		return
	guest.receive_greeting(GREET_EFFECT)

## The walk failed: drop the task and look for another one.
func _abandon() -> void:
	_weed = Vector2i(-1, -1)
	_guest = null
	step = Step.IDLE
	_timer = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)

## Where the owner stands, in grid space.
func _grid_point() -> Vector2:
	var grid := GameManager.terrain_grid
	if grid == null:
		return Vector2.ZERO
	return grid.screen_to_grid_point(golfer.global_position)
