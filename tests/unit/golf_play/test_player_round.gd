extends GameTest
## The owner's round (PlayerRoundManager), played with the real golfer and ball
## scenes: practice and group rounds, shots, the round's pages and docks.

var fixture: Node2D
var rounds: PlayerRoundManager
var golfers: GolferManager
var hud: Control
## The window size Screen had before a test pinned the desktop layout to
## measure the owner's pages (see _embedded_toolbar).
var _window_size: Vector2 = Vector2(1600, 1000)

func before_each() -> void:
	super()
	_window_size = Screen.window_size
	GameManager.tournament_manager = null
	GameManager.is_paused = false
	GameManager.player_profile = PlayerGolferProfile.new()
	GameManager.current_course = GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.tee_position = Vector2i(10, 10)
	hole.hole_position = Vector2i(16, 10)
	hole.par = 3
	GameManager.course_data.add_hole(hole)
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	for x in range(40):
		for y in range(40):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.FAIRWAY
	grid._grid[hole.tee_position] = TerrainTypes.Type.TEE_BOX
	grid._grid[hole.hole_position] = TerrainTypes.Type.GREEN
	GameManager.terrain_grid = grid
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	golfers = make_golfer_manager()
	fixture = golfers.get_parent()
	var balls := BallManager.new()
	fixture.add_child(balls)
	balls.set_terrain_grid(grid)
	var camera := IsometricCamera.new()
	fixture.add_child(camera)
	hud = Control.new()
	fixture.add_child(hud)
	rounds = PlayerRoundManager.new()
	fixture.add_child(rounds)
	rounds.setup(golfers, camera, hud)

func after_each() -> void:
	rounds.leave_round()
	golfers.clear_all_golfers()
	await process_frames(1)
	Screen.apply_size(_window_size)
	Screen.set_process(true)
	super()

## A folder of the test's own for the skins a test writes out.
const TEST_SKIN_ROOT := "user://test_player_round_skins"

## Remove a folder under user:// and everything in it.
func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_remove_tree(path.path_join(entry))
		else:
			DirAccess.remove_absolute(path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _start(kind: int) -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds.mode_picker.select(kind)
	rounds.start_round()
	rounds._process(0.0)

## Click a shot-type button the way the mouse does: the toggle flips, then the
## press is delivered.
func _press_shot(bar: ShotTypeBar, shape: int) -> void:
	var button := bar.shot_button(shape)
	button.button_pressed = true
	button.pressed.emit()

## The lie under the owner's ball.
func _set_lie(lie: int) -> void:
	var tile := Vector2i(rounds.player.ball_position_precise.round())
	GameManager.terrain_grid._grid[tile] = lie

func test_setup_cancel_does_not_spend_points() -> void:
	rounds.open_setup()
	assert_false(rounds.start_button.disabled, "Ten unspent points do not hold the tee off")
	rounds.draft.allocate(0, 1)
	rounds.leave_round()
	assert_false(GameManager.player_profile.initialized)
	assert_eq(GameManager.player_profile.remaining(), 10)

func test_practice_waits_for_input_and_restores_visitors() -> void:
	var visitor := golfers.spawn_tournament_golfer(GolferTier.Tier.CASUAL, 99)
	_start(0)
	assert_eq(rounds.shot_bar.shot_count(), 5, "One button per shot type")
	assert_eq(rounds.shot_bar.shot_button(4).text, "Punch")
	_press_shot(rounds.shot_bar, 4)
	assert_eq(rounds.player.player_shape, 4, "Low punch is selected as a shot shape")
	assert_eq(rounds.participants.size(), 1)
	assert_true(rounds.player.awaits_player_shot())
	assert_eq(rounds.player.golfer_name, "Test Owner")
	assert_true(rounds.player._use_sprites, "The owner uses the Casual pixel-art sprite during a round")
	assert_eq(rounds.player.body.color, Color(GameManager.player_profile.appearance.shirt_color))
	assert_eq(visitor.process_mode, Node.PROCESS_MODE_INHERIT, "Visitors are not disabled during round")
	assert_true(rounds.hud.visible, "Management HUD remains visible during play")
	rounds.player._process_preparing_shot(30)
	assert_eq(rounds.player.current_strokes, 0)
	rounds.leave_round()
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING)
	assert_eq(visitor.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(golfers.active_golfers.size(), 1)
	assert_true(GameManager.player_profile.initialized)

func test_pro_selection_and_tie_results() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1)
	rounds.pro_picker.select(2)
	rounds.start_round()
	assert_eq(rounds.participants.size(), 2)
	assert_eq(rounds.participants[1].golfer_name, "Pro Riley")
	assert_eq(rounds.participants[0].group_id, rounds.participants[1].group_id, "Participants share the same group ID")
	assert_true(rounds.hud.visible, "Management HUD is visible")
	rounds.leave_round()
	_start(1)
	assert_eq(rounds.participants.size(), 2)
	assert_eq(rounds.mode_picker.item_count, 2, "Only practice and vs pro formats remain")
	for golfer in rounds.participants:
		golfer.current_strokes = 3
		golfer.ball_position = Vector2i(16, 10)
		golfer.ball_position_precise = Vector2(16, 10)
		golfer.current_state = Golfer.State.IDLE
	rounds._process(0.0)
	assert_false(rounds.active)
	assert_true(rounds.busy)
	for golfer in rounds.participants:
		assert_eq(golfer.hole_scores.size(), 1)
		assert_eq(golfer.total_strokes, 3)
	assert_string_contains(rounds.content.get_child(1).text, "Tie:")
	rounds.leave_round()
	assert_eq(golfers.active_golfers.size(), 0)

func test_no_open_holes_rejected() -> void:
	GameManager.course_data.holes[0].is_open = false
	rounds.open_setup()
	assert_false(rounds.busy)

func test_mode_change_cleans_up_round() -> void:
	_start(0)
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	assert_false(rounds.busy)
	assert_eq(golfers.active_golfers.size(), 0)

func test_real_shot_rejects_double_click_and_round_can_finish() -> void:
	_start(0)
	var player_golfer := rounds.player
	player_golfer.walk_speed = 120
	var resting_target := Vector2(16, 10)
	assert_true(player_golfer.play_shot_to_rest(resting_target))
	assert_false(player_golfer.play_shot_to_rest(resting_target))
	assert_eq(player_golfer.current_strokes, 1)
	# Exercise real swing, ball flight, rollout, walking, putting and pickup.
	Engine.time_scale = 3.0
	for step in 160:
		if not rounds.active:
			break
		if player_golfer.awaits_player_shot():
			player_golfer.play_shot(Vector2i(16, 10))
		await get_tree().create_timer(0.5).timeout
	Engine.time_scale = 1.0
	assert_false(rounds.active, "Real round reaches its results screen")
	assert_eq(player_golfer.hole_scores.size(), 1)

func test_player_round_plays_as_group_with_etiquette() -> void:
	# Start a round vs a pro
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds.mode_picker.select(1)  # Vs Pro
	rounds.pro_picker.select(0)   # Pro Alex
	rounds.start_round()
	rounds._process(0.0)

	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING, "Game mode is SIMULATING")
	assert_true(rounds.hud.visible, "Management HUD is visible")
	assert_eq(rounds.participants.size(), 2)

	var p := rounds.player
	var pro := rounds.participants[1]

	# Both should have the same group_id
	assert_eq(p.group_id, pro.group_id, "Player and Pro share group_id")
	assert_gte(p.group_id, 0, "Group ID is a valid non-negative group ID")

	# Hole 1 tee off order: lowest golfer_id (player spawned first) has honor
	assert_eq(p.current_state, Golfer.State.PREPARING_SHOT, "Player has honor on Hole 1 tee")
	assert_true(p.awaits_player_shot(), "Player awaits input")
	assert_eq(pro.current_state, Golfer.State.IDLE, "Pro waits their turn on the tee")

	# Player takes tee shot
	assert_true(p.play_shot(Vector2i(14, 10)))
	assert_eq(p.current_strokes, 1)

	# While player is swinging/watching/walking, pro is next on tee
	# Advance pro to take tee shot
	p._change_state(Golfer.State.WALKING)
	golfers._update_golfers(0.0)
	assert_eq(pro.current_state, Golfer.State.PREPARING_SHOT, "Pro tees off next in group order")

	rounds.leave_round()

func test_concurrent_visitors_and_player_group() -> void:
	# Spawn a visitor group before player round
	var v1 := golfers.spawn_tournament_golfer(GolferTier.Tier.CASUAL, 10)
	var v2 := golfers.spawn_tournament_golfer(GolferTier.Tier.BEGINNER, 10)
	assert_eq(golfers.active_golfers.size(), 2)

	# Start owner round vs pro
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1)
	rounds.start_round()
	rounds._process(0.0)

	# Both groups should coexist in active_golfers
	assert_eq(golfers.active_golfers.size(), 4, "4 golfers total (2 visitors + 2 player group)")
	assert_eq(v1.process_mode, Node.PROCESS_MODE_INHERIT, "Visitor 1 remains active")
	assert_eq(v2.process_mode, Node.PROCESS_MODE_INHERIT, "Visitor 2 remains active")
	assert_ne(v1.group_id, rounds.player.group_id, "Visitor group ID is different from player group ID")
	assert_eq(v1.group_id, v2.group_id, "Visitors share their own group ID")
	assert_eq(rounds.player.group_id, rounds.participants[1].group_id, "Player and opponent share their own group ID")
	assert_true(rounds.hud.visible, "Management HUD remains visible")
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING, "Simulation mode remains active")

	# Leaving round only removes player group, visitors remain untouched
	rounds.leave_round()
	assert_eq(golfers.active_golfers.size(), 2, "Only visitors remain after owner round ends")
	assert_true(is_instance_valid(v1), "Visitor 1 is still valid")
	assert_true(is_instance_valid(v2), "Visitor 2 is still valid")

func test_name_labels_on_player_group() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds.mode_picker.select(1) # Vs Pro (group size 2)
	rounds.start_round()
	rounds._process(0.0)

	var p := rounds.player
	var pro := rounds.participants[1]
	var label_p := p.get_node_or_null("InfoContainer/NameLabel") as Label
	var label_pro := pro.get_node_or_null("InfoContainer/NameLabel") as Label
	assert_not_null(label_p, "Player has a name label node")
	assert_not_null(label_pro, "Pro has a name label node")

	# Every golfer wears their name above them, and it is always on screen.
	assert_true(label_p.visible, "Player name is visible without hovering")
	assert_true(label_pro.visible, "Pro name is visible without hovering")
	assert_eq(label_p.text, "Test Owner", "Player label shows the owner's name")
	assert_eq(label_pro.text, "Pro Alex", "Opponent label shows their own name")
	assert_ne(label_p.text, label_pro.text, "Golfers in one group are told apart by name")

	# Group, score and hole are gone from above the golfers: the scorecard
	# panels and the click-through popup carry them now.
	assert_null(p.get_node_or_null("InfoContainer/ScoreLabel"), "No score/hole label above the golfer")
	assert_null(p.get_node_or_null("InfoContainer/GroupBadge"), "No group badge above the golfer")
	assert_false(label_p.text.contains("Group"), "Name label carries no group number")
	assert_false(label_p.text.contains("Hole"), "Name label carries no hole number")

	# Hovering swaps in the tier, and leaving restores the plain name.
	p._on_mouse_entered()
	assert_true(label_p.text.ends_with("Test Owner"), "Hovering keeps the name and adds the tier")
	assert_false(label_p.text.contains("Group"), "Hover copy carries no group number")
	p._on_mouse_exited()
	assert_eq(label_p.text, "Test Owner", "Leaving the golfer restores the plain name")

	# It is drawn above the golfer's head, centred on them.
	await process_frames(1)
	var rect := label_p.get_global_rect()
	assert_almost_eq(rect.get_center().x, p.global_position.x, 1.0, "Name label is centred on the golfer")
	assert_lt(rect.get_center().y, p.global_position.y - 20.0, "Name label sits above the golfer")

	# Renaming a golfer after they spawn follows them, and a name too long for
	# the label's box grows it both ways so it stays centred on the golfer.
	p.golfer_name = "Bartholomew Mandeville"
	await process_frames(1)
	assert_eq(label_p.text, "Bartholomew Mandeville", "Renaming the golfer updates their label")
	var long_rect := label_p.get_global_rect()
	assert_gt(long_rect.size.x, 80.0, "A long name widens the label")
	assert_almost_eq(long_rect.get_center().x, p.global_position.x, 1.0, "A long name stays centred on the golfer")

	rounds.leave_round()

func test_aim_guide_shows_intended_arc_and_roll() -> void:
	_start(0)
	var guide: AimGuide = rounds.aim_guide
	assert_not_null(guide, "Starting a round creates the aim guide")
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_false(guide.preview.is_empty(), "Guide follows the owner's aim")
	var preview := guide.preview
	assert_gt(int(preview.carry_yards), 0, "Guide reports the intended carry")
	assert_gt(int(preview.roll_yards), 0, "Guide reports the roll after landing")
	assert_gt(int(preview.get("roll_path", PackedVector2Array()).size()), 1, "Guide traces the roll path")
	assert_eq(preview.anchor_type, "center", "Explicit tile aiming selects the tile centre")
	assert_eq(preview.rest, Vector2(16, 10), "The expected roll ends on the selected anchor")
	var geometry := AimGuide.build_geometry(GameManager.terrain_grid, preview)
	assert_false(geometry.is_empty(), "Guide geometry projects the preview")
	assert_almost_eq(Vector2(geometry.arc[geometry.arc.size() - 1]).distance_to(geometry.carry), 0.0, 0.5,
		"Arc ends on the guide's carry point")
	assert_almost_eq(Vector2(geometry.trajectory[geometry.trajectory.size() - 1]).distance_to(geometry.rest), 0.0,
		0.01, "The combined trajectory reaches its snapped rest point")

	# The guide disappears whenever it is not the owner's shot to hit.
	rounds.player.current_state = Golfer.State.WALKING
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_true(guide.preview.is_empty(), "Guide clears while the owner walks")
	rounds.player.current_state = Golfer.State.PREPARING_SHOT
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_false(guide.preview.is_empty(), "Guide returns with the owner's turn")

	rounds.leave_round()
	assert_true(guide.preview.is_empty(), "Guide clears when the round ends")

func test_aim_guide_reaches_tiles_between_the_clubs_ranges() -> void:
	var saved_wind = GameManager.wind_system
	GameManager.wind_system = null
	_start(0)
	var guide: AimGuide = rounds.aim_guide
	var golfer := rounds.player
	# With a point in every skill the wedge stops at 3.85 tiles while the iron's band
	# only starts at 5, and the iron stops short of the fairway wood's band at 8.
	# The tiles in those gaps used to be "out of range" although a longer club
	# reaches them; the guide now points at exactly the tile under the mouse.
	for target in [Vector2i(14, 12), Vector2i(12, 14), Vector2i(15, 16), Vector2i(16, 15)]:
		var distance := Vector2(golfer.ball_position).distance_to(Vector2(target))
		assert_lt(golfer.player_max_distance(golfer.select_club(distance, TerrainTypes.Type.TEE_BOX)), distance,
			"The club automatic selection proposes for %s cannot reach it" % target)
		rounds.update_aim_guide(target)
		assert_false(guide.preview.is_empty(), "The guide follows the mouse onto %s" % target)
		assert_eq(guide.preview.rest, Vector2(target), "The guide ends on %s" % target)
		assert_false(guide.preview.clamped, "%s is not limited" % target)
		assert_false(guide.preview.range_limited, "%s is not out of range" % target)
		var geometry := AimGuide.build_geometry(GameManager.terrain_grid, guide.preview)
		assert_false(geometry.is_empty(), "Guide geometry exists for %s" % target)
		assert_almost_eq(Vector2(geometry.trajectory[geometry.trajectory.size() - 1]).distance_to(geometry.rest), 0.0,
			0.01, "The drawn line reaches %s" % target)
	# Clicking takes the shot the guide shows.
	rounds.update_aim_guide(Vector2i(14, 12))
	var shown_club: int = guide.preview.club
	assert_true(golfer.play_shot_to_rest(Vector2(14, 12)), "The shot is taken at the highlighted tile")
	assert_eq(golfer._chosen_club, shown_club, "The swing uses the club the guide showed")
	assert_eq(golfer.current_strokes, 1)
	rounds.leave_round()
	GameManager.wind_system = saved_wind

func test_camera_focuses_only_when_aiming_shot() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1) # Vs Pro
	rounds.start_round()

	var p := rounds.player
	var pro := rounds.participants[1]
	var cam := rounds.camera

	# Reset aiming state and set camera target away from player
	rounds._was_aiming = false
	cam._target_position = Vector2(999, 999)

	# When player awaits shot (needs to aim), _process focuses camera on player
	assert_true(p.awaits_player_shot(), "Player needs to aim shot")
	rounds._process(0.0)
	assert_eq(cam._target_position, p.global_position, "Camera moves to focus on player character when aiming")

	# While player continues aiming, camera is not forced every frame
	cam._target_position = Vector2(500, 500) # User panned camera
	rounds._process(0.0)
	assert_eq(cam._target_position, Vector2(500, 500), "Camera allows manual panning while aiming")

	# When player is walking (not aiming), camera does not track player or opponent
	p._change_state(Golfer.State.WALKING)
	rounds._process(0.0)
	assert_eq(cam._target_position, Vector2(500, 500), "Camera does not follow player walking")

	# When opponent is preparing shot, camera does not jump to opponent
	p._change_state(Golfer.State.IDLE)
	pro._change_state(Golfer.State.PREPARING_SHOT)
	rounds._process(0.0)
	assert_eq(cam._target_position, Vector2(500, 500), "Camera does not focus on opponent")

	# When turn returns to player to aim, camera moves to focus on player character
	pro._change_state(Golfer.State.IDLE)
	p._change_state(Golfer.State.PREPARING_SHOT)
	assert_true(p.awaits_player_shot())
	rounds._process(0.0)
	assert_eq(cam._target_position, p.global_position, "Camera focuses on player when turn to aim arrives")

	rounds.leave_round()

func test_embedded_player_navigation_and_setup() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	assert_eq(tab.buttons.size(), 3)
	assert_eq(tab.buttons[PlayerTab.PAGE_PLAY].text, "Play Course")
	assert_eq(tab.buttons[PlayerTab.PAGE_SKILLS].text, "Player Skills")
	assert_false(rounds.busy, "Editing a player does not reserve a round")
	assert_null(rounds.overlay, "Embedded setup creates no floating overlay")
	var edit_page := tab.pages[PlayerTab.PAGE_EDIT]
	assert_eq((edit_page.get_parent() as ScrollContainer).offset_top, PlayerTab.EDIT_PAGE_TOP_GAP,
		"The Edit Player Golfer title has breathing room below it")
	assert_true(edit_page.is_ancestor_of(rounds.name_edit))
	assert_true(edit_page.is_ancestor_of(rounds._skin_picker))
	var preview_column := edit_page.get_child(0) as VBoxContainer
	assert_true(preview_column.is_ancestor_of(rounds._skin_preview_box),
		"The animated golfer preview leads the Edit Player columns")
	assert_eq(rounds._skin_picker.get_parent(), preview_column,
		"The Golfer Skin selector sits in the golfer preview's own column")
	assert_eq(preview_column.get_child(preview_column.get_child_count() - 1), rounds._skin_picker,
		"The selector sits below the sprite it dresses, closing the column")
	assert_eq(rounds._skin_picker.get_index(), rounds._skin_preview_box.get_index() + 1,
		"and directly beneath it")
	assert_false(rounds.name_edit.get_parent() == preview_column,
		"The player name keeps a column of its own")
	for child in preview_column.get_children():
		if child is Label:
			assert_ne((child as Label).text, "Golfer skin",
				"The removed Golfer skin title does not come back above the picker")
	assert_eq(rounds._skin_preview_box.size_flags_vertical, Control.SIZE_EXPAND_FILL,
		"The preview fills the height the selector leaves in its column")
	assert_true(tab.pages[PlayerTab.PAGE_SKILLS].is_ancestor_of(rounds.points_label))
	for label in edit_page.find_children("*", "Label", true, false):
		assert_ne(label.text, "PLAY YOUR COURSE", "The old Edit Player heading is gone")
	for button in edit_page.find_children("*", "Button", true, false):
		assert_ne(button.text, "Save player", "Player edits save without a button")
	var plates := rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false)
	assert_eq(plates.size(), GolferSkins.player_skin().group_count(),
		"One Group Colour plate per Re-color Group, each naming its group")
	for plate in plates:
		assert_ne((plate as SkinGroupColorButton).text, "", "Every plate carries its group's name")
	assert_eq(edit_page.get_child(1), rounds._skin_controls,
		"The Group Colour column stands directly to the right of the sprite")
	assert_true(tab.pages[PlayerTab.PAGE_PLAY].is_ancestor_of(rounds.pro_picker))
	rounds.name_edit.text = "Auto-saved Owner"
	rounds.name_edit.text_changed.emit(rounds.name_edit.text)
	assert_eq(GameManager.player_profile.golfer_name, "Auto-saved Owner",
		"The player name persists immediately without a Save player button")
	var starters := 0
	for child in tab.pages[PlayerTab.PAGE_PLAY].find_children("*", "Button", true, false):
		if child.has_meta("owner_round_start"):
			starters += 1
	assert_eq(starters, 1, "Play Course has one combined Start Round button")
	for index in 3:
		tab.buttons[index].pressed.emit()
		for page in 3:
			assert_eq(tab.pages[page].get_parent().visible, page == index)
		assert_false(tab.aim_scroll.visible, "The aiming view stays hidden outside a round")

func test_identity_colours_use_quiet_cards_and_gender_colours() -> void:
	var toolbar := _embedded_toolbar()
	var page := toolbar.player_tab.pages[PlayerTab.PAGE_EDIT]
	var trait_plate := _find_node(page, "GolferTraitNeat") as Button
	var quiet_texture := (trait_plate.get_theme_stylebox("normal") as StyleBoxTexture).texture
	for node_name in ["PlayerName", "PlayerProfession", "PlayerAgeValue", "PlayerMaritalStatusToggle"]:
		var field := _find_node(page, node_name) as Control
		var state := "pressed" if field is Button else "normal"
		assert_eq((field.get_theme_stylebox(state) as StyleBoxTexture).texture, quiet_texture)
		assert_eq(field.get_theme_color("font_pressed_color" if field is Button else "font_color"), VisitorCardButton.CREAM)
	var gender := _find_node(page, "PlayerGenderToggle") as Button
	var blue := (gender.get_theme_stylebox("pressed") as StyleBoxTexture).texture.get_image().get_pixel(30, 30)
	assert_gt(blue.b, blue.r)
	gender.pressed.emit()
	var pink := (gender.get_theme_stylebox("pressed") as StyleBoxTexture).texture.get_image().get_pixel(30, 30)
	assert_gt(pink.r, pink.b)
	gender.pressed.emit()
	assert_eq((gender.get_theme_stylebox("pressed") as StyleBoxTexture).texture.get_image().get_pixel(30, 30), blue)

func test_owner_actions_share_a_column_to_the_right_of_all_traits() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]
	var actions := _find_node(page, "PlayerActionsColumn") as VBoxContainer
	var move := _find_node(page, "MoveWorkArea") as Button
	var save := _find_node(page, "SaveEditGolferForTournamentButton") as Button
	assert_eq(move.get_parent(), actions)
	assert_eq(save.get_parent(), actions)
	assert_lt(move.global_position.y, save.global_position.y)
	for key in GolferAttributes.TRAIT_KEYS:
		var plate := _find_node(page, "GolferTrait%s" % key.capitalize()) as Button
		assert_gt(actions.global_position.x, plate.get_global_rect().end.x,
			"The shared action column follows every trait column")
	_assert_shelf_fits(page)

func test_skin_work_area_and_export_actions_share_trait_card_style() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]
	var trait_plate := _find_node(page, "GolferTraitNeat") as Button
	var export_button := _find_node(page, "SaveEditGolferForTournamentButton") as Button
	for button in [rounds._skin_picker, rounds._work_area_button, export_button]:
		if not button is OptionButton:
			assert_false(button.toggle_mode, "Actions stay momentary rather than On/Off toggles")
		assert_true(button.has_meta(PlayerRoundManager.VISITOR_CARD_META))
		assert_eq(button.custom_minimum_size.y, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE.y)
		assert_eq(button.get_theme_font("font"), trait_plate.get_theme_font("font"))
		assert_eq(button.get_theme_color("font_color"), trait_plate.get_theme_color("font_color"))
		for state in ["normal", "hover", "pressed", "disabled"]:
			assert_true(button.get_theme_stylebox(state) is StyleBoxTexture)
	assert_true(rounds._skin_picker.has_meta("editable_while_playing"))
	_assert_shelf_fits(page)

func test_identity_column_stacks_name_profession_and_a_row_of_choices() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]
	var column := _find_node(page, "PlayerIdentityColumn") as VBoxContainer
	var profession := _find_node(page, "PlayerProfession") as LineEdit
	var choices := _find_node(page, "PlayerIdentityChoices") as HBoxContainer
	assert_eq(column.get_children(), [rounds.name_edit, profession, choices])
	var age := _find_node(page, "PlayerAge") as HBoxContainer
	var gender := _find_node(page, "PlayerGenderToggle") as Button
	var marital := _find_node(page, "PlayerMaritalStatusToggle") as Button
	assert_eq(choices.get_children(), [age, gender, marital])
	assert_lt(rounds.name_edit.global_position.y, profession.global_position.y)
	assert_lt(profession.global_position.y, choices.global_position.y)
	assert_almost_eq(age.global_position.y, gender.global_position.y, 1.0)
	assert_almost_eq(gender.global_position.y, marital.global_position.y, 1.0)
	assert_lt(age.global_position.x, gender.global_position.x)
	assert_lt(gender.global_position.x, marital.global_position.x)
	assert_almost_eq(rounds.name_edit.size.x, choices.size.x, 1.0)
	assert_almost_eq(profession.size.x, choices.size.x, 1.0)
	_assert_shelf_fits(page)

func test_name_and_profession_share_the_editable_age_card_style() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]
	var age := _find_node(page, "PlayerAgeValue") as LineEdit
	var profession := _find_node(page, "PlayerProfession") as LineEdit
	for field in [rounds.name_edit, profession]:
		assert_true(field.editable)
		assert_eq(field.custom_minimum_size, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE)
		assert_eq(field.get_theme_font("font"), age.get_theme_font("font"))
		assert_eq(field.get_theme_color("font_color"), age.get_theme_color("font_color"))
		assert_true(field.get_theme_stylebox("normal") is StyleBoxTexture)
		assert_eq((field.get_theme_stylebox("normal") as StyleBoxTexture).texture,
			(age.get_theme_stylebox("normal") as StyleBoxTexture).texture)
	profession.text = "Architect"
	profession.text_changed.emit(profession.text)
	assert_eq(GameManager.player_profile.profession, "Architect")
	rounds.name_edit.text = "Green Keeper"
	rounds.name_edit.text_changed.emit(rounds.name_edit.text)
	assert_eq(GameManager.player_profile.golfer_name, "Green Keeper")
	_assert_shelf_fits(page)

func test_age_plate_steps_saves_and_stays_within_limits() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]
	var row := _find_node(page, "PlayerAge") as HBoxContainer
	var decrease := _find_node(row, "PlayerAgeDecrease") as Button
	var increase := _find_node(row, "PlayerAgeIncrease") as Button
	var readout := _find_node(row, "PlayerAgeValue") as LineEdit
	assert_not_null(row, "Age is a plate with separate step buttons, not a SpinBox")
	assert_eq(row.custom_minimum_size, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE)
	for button in [decrease, increase]:
		assert_false(button.toggle_mode)
		assert_eq(button.focus_mode, Control.FOCUS_ALL)
		assert_true(button.get_theme_stylebox("normal") is StyleBoxTexture)
		assert_eq(button.get_theme_font("font"), VisitorCardButton.FONT)
	var initial_age := rounds.draft.age
	increase.pressed.emit()
	assert_eq(rounds.draft.age, initial_age + 1)
	assert_eq(GameManager.player_profile.age, initial_age + 1)
	assert_eq(readout.text, "Age %d" % (initial_age + 1))
	decrease.pressed.emit()
	assert_eq(GameManager.player_profile.age, initial_age)
	for i in 110:
		decrease.pressed.emit()
	assert_eq(rounds.draft.age, 18)
	assert_true(decrease.disabled)
	assert_false(increase.disabled)
	for i in 110:
		increase.pressed.emit()
	assert_eq(rounds.draft.age, 100)
	assert_eq(GameManager.player_profile.age, 100)
	assert_eq(readout.text, "Age 100")
	assert_true(increase.disabled)
	assert_false(decrease.disabled)
	readout.grab_focus()
	assert_eq(readout.text, "100", "Focus exposes the number for typing")
	readout.text = "42"
	readout.text_submitted.emit(readout.text)
	assert_eq(GameManager.player_profile.age, 42)
	assert_eq(readout.text, "Age 42")
	assert_false(increase.disabled)
	for entry in ["150", "12", "invalid", ""]:
		readout.grab_focus()
		readout.text = entry
		readout.release_focus()
		assert_eq(GameManager.player_profile.age, 100 if entry == "150" else 18,
			"Typed ages clamp to limits; invalid or empty input keeps the last age")
	await process_frames(5)
	_assert_shelf_fits(page)

func test_golfer_skills_lead_player_skills_shelf_as_untitled_visitor_cards() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	var skill_page := tab.pages[PlayerTab.PAGE_SKILLS]
	var skill_scroll := skill_page.get_parent() as ScrollContainer
	assert_eq(skill_scroll.offset_top, PlayerTab.SKILLS_PAGE_TOP_GAP,
		"The Player Golfer Skills title has breathing room below it")
	var first_column := skill_page.get_child(0)
	assert_eq(first_column.get_child_count(), 3,
		"The Golfer Skills column contains only its three buttons, with no title")
	var toggle_names: Array[String] = []
	var buttons: Array[Button] = []
	for control in first_column.get_children():
		assert_false(control is Label, "The Golfer Skills title is removed")
		if control is Button:
			buttons.append(control)
			toggle_names.append(control.text)
	assert_eq(toggle_names, ["Length", "Accuracy", "Imagination"],
		"Length, Accuracy and Imagination lead the shelf in that order")
	for button in buttons:
		assert_true(button.toggle_mode, "%s remains an On/Off toggle" % button.text)
		assert_eq(button.custom_minimum_size, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE,
			"%s uses the narrower Golfer Skill card footprint" % button.text)
		assert_lt(button.custom_minimum_size.x, VisitorCardButton.BUTTON_SIZE.x,
			"%s is narrower than a Visiting Golfer card" % button.text)
		assert_eq(button.get_theme_font("font"), VisitorCardButton.FONT,
			"%s uses the Visiting Golfer pixel font" % button.text)
		assert_eq(button.get_theme_color("font_color"), VisitorCardButton.CREAM)
		assert_true(button.get_theme_stylebox("normal") is StyleBoxTexture,
			"The ordinary owner-button styling does not replace the shared card frame")
		assert_true(button.get_theme_stylebox("pressed") is StyleBoxTexture,
			"The selected state uses the shared card frame")
		assert_eq(button.get_theme_color("font_pressed_color"), PixelButtonStyle.INK,
			"The enabled caption contrasts with its solid green fill")
		var off_style := button.get_theme_stylebox("normal") as StyleBoxTexture
		var on_style := button.get_theme_stylebox("pressed") as StyleBoxTexture
		var off_pixel := off_style.texture.get_image().get_pixel(30, 30)
		var on_pixel := on_style.texture.get_image().get_pixel(30, 30)
		assert_gt(on_pixel.get_luminance(), off_pixel.get_luminance() + 0.2,
			"The enabled card is substantially brighter than the Off card")

	buttons[0].button_pressed = true
	buttons[0].toggled.emit(true)
	assert_true(bool(GameManager.player_profile.golfer_skills["length"]),
		"The restyled skill buttons still save their On/Off state")

## The Player Skills navigation button wears the number of points still to spend;
## zero points means no badge.
func test_player_skills_button_badges_unspent_points() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	var button := tab.buttons[PlayerTab.PAGE_SKILLS]
	var badge := tab.skill_badge
	assert_not_null(badge, "The Player Skills button carries a badge")
	assert_eq(badge.get_parent(), button)
	assert_eq(button.text, "Player Skills", "The badge is not part of the button's own label")
	assert_true(badge.visible)
	assert_eq(badge.text, "10", "All ten points are still unspent")

	# It sits in the button's top-right corner, clear of the centered label.
	tab.size = Vector2(720, 160)
	await process_frames(2)
	assert_almost_eq(badge.position.x + badge.size.x, button.size.x - PlayerTab.BADGE_INSET, 1.0,
		"The badge is pinned to the button's right edge")
	assert_almost_eq(badge.position.y, PlayerTab.BADGE_INSET, 1.0, "and to its top edge")
	assert_lte(badge.position.x + badge.size.x, button.size.x, "The badge stays inside the button")
	assert_between(badge.size.x, 14.0, 30.0, "The badge is a small pill, not a second label")
	assert_between(badge.size.y, 12.0, 24.0)

	# Spending keeps it in step, both while points remain and once they are gone.
	assert_true(rounds.allocate_skill(0, 1))
	assert_eq(badge.text, "9")
	for i in range(1, 10):
		rounds.allocate_skill(i, 1)
	assert_false(badge.visible, "A fully allocated golfer wears no badge")
	assert_true(rounds.allocate_skill(0, -1), "A point can be taken back")
	assert_true(badge.visible, "Refunding a point brings the badge back")
	assert_eq(badge.text, "1")

	# A page switch and the toolbar's periodic refresh both re-read the profile.
	tab.set_unused_skill_points(4)
	assert_eq(badge.text, "4")
	tab.select(PlayerTab.PAGE_EDIT)
	assert_eq(badge.text, "1", "Selecting a page refreshes the badge")
	for i in PlayerGolferProfile.SKILLS.size():
		GameManager.player_profile.points[i] = 0
	tab.refresh_skill_badge()
	assert_eq(badge.text, "10", "A refresh reads the profile rather than the last count it was told")

func test_player_skills_use_age_style_stepper_plates() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	assert_eq(rounds.skill_labels.size(), 10)
	assert_false(rounds.points_label.visible, "The shelf has no point-summary text between skill areas")
	var page := tab.pages[PlayerTab.PAGE_SKILLS]
	assert_eq(rounds.skill_labels[0].get_parent().get_parent().get_index(), 1,
		"Golf Skill plates follow the Golfer Skills column without a text column")
	assert_eq(page.get_child_count(), 5)
	for i in 10:
		var row := rounds.skill_labels[i].get_parent()
		assert_eq(row.get_child(0), rounds.skill_decrease_buttons[i])
		assert_eq(row.get_child(2), rounds.skill_increase_buttons[i])
		assert_eq(row.get_parent(), rounds.skill_labels[(i / 3) * 3].get_parent().get_parent())
		assert_true(rounds.skill_decrease_buttons[i].disabled)
		assert_false(rounds.skill_increase_buttons[i].disabled)
	rounds.skill_increase_buttons[0].pressed.emit()
	assert_eq(GameManager.player_profile.points[0], 1)
	assert_eq(rounds.skill_labels[0].text, "Power Hitter: 10%")
	assert_false(rounds.skill_decrease_buttons[0].disabled)
	for i in range(1, 10):
		rounds.skill_increase_buttons[i].pressed.emit()
	assert_true(rounds.skill_increase_buttons[0].disabled)
	rounds.skill_decrease_buttons[0].pressed.emit()
	assert_true(rounds.skill_decrease_buttons[0].disabled)
	assert_false(rounds.skill_increase_buttons[0].disabled)
	assert_eq(GameManager.player_profile.points[0], 0)

func test_embedded_round_uses_aim_page_and_returns_to_setup() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds._start_embedded(1)
	assert_true(rounds.active)
	assert_eq(rounds.participants.size(), 2)
	assert_eq(tab.selected, PlayerTab.PAGE_PLAY)
	assert_true(tab.aim_page.is_ancestor_of(rounds.status))
	assert_true(tab.aim_scroll.visible, "Play Course swaps to the aiming view while playing")
	assert_false(tab.pages[PlayerTab.PAGE_PLAY].visible, "Setup content hides during the round")
	assert_null(rounds.overlay)
	assert_false(rounds.name_edit.editable, "Appearance stays locked during the round")
	rounds.leave_round()
	assert_false(rounds.busy)
	assert_true(rounds.name_edit.editable)
	assert_false(tab.aim_scroll.visible, "Play Course returns to setup after the round")
	assert_true(tab.pages[PlayerTab.PAGE_PLAY].visible)
	var starters := 0
	for child in tab.pages[PlayerTab.PAGE_PLAY].find_children("*", "Button", true, false):
		if child.has_meta("owner_round_start"):
			starters += 1
	assert_eq(starters, 1, "The combined round setup has one Start Round button")

## Unspent skill points are a nudge, not a gate: the round starts, and the play
## page (not Player Skills) is what comes up.
func test_embedded_round_starts_with_unspent_skill_points() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	rounds._start_embedded(0)
	assert_eq(rounds.draft.remaining(), 10, "The ten points are still there to spend later")
	assert_true(rounds.busy, "Practice starts without spending them")
	assert_true(rounds.active)
	assert_eq(tab.selected, PlayerTab.PAGE_PLAY, "The round does not divert to the Player Skills page")
	rounds.leave_round()
	assert_false(rounds.busy)

func test_round_roster_adds_up_to_three_pros_and_starts_one_group() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	assert_true(is_instance_valid(rounds._round_player_preview), "The player's golfer sprite is shown")
	assert_eq(rounds._add_golfer_button.text, "", "The add control is an icon button, not a text button")
	assert_not_null(rounds._add_golfer_button.icon)
	var round_section: VBoxContainer = rounds._round_players_row.get_parent()
	assert_eq(round_section.custom_minimum_size.x, 220.0,
		"The round setup reserves four larger golfer-sprite slots")
	assert_eq(rounds._round_player_preview_box.custom_minimum_size, Vector2(52, 66),
		"The player's golfer sprite has a larger portrait area")
	assert_eq(round_section.find_children("*", "Label", true, false).size(), 0,
		"The setup has no title or visible golfer-name labels")
	assert_eq(rounds._selected_pros.size(), 0, "A new round starts as practice")
	for index in PlayerRoundManager.PROS.size():
		rounds._on_add_golfer_selected(index)
	assert_eq(rounds._selected_pros.size(), 3)
	assert_eq(rounds._pro_roster.get_child_count(), 3, "Each added pro gets a portrait beside the owner")
	for index in PlayerRoundManager.PROS.size():
		var pro_name: String = PlayerRoundManager.PROS[index]
		assert_true(rounds._pro_preview_nodes.has(pro_name))
		assert_true(rounds._pro_preview_nodes[pro_name] is Golfer)
		var remove := rounds._pro_roster.get_child(index).find_child("RemoveProButton", true, false)
		assert_not_null(remove, "Every pro portrait has a remove button")
		assert_false(remove.get_parent().clip_contents,
			"Remove controls sit outside the sprite's clipping rectangle")
	assert_null(rounds._add_golfer_button, "The add icon disappears when the four-person group is full")
	rounds._remove_round_pro(PlayerRoundManager.PROS[2])
	assert_true(is_instance_valid(rounds._add_golfer_button), "Removing a pro restores the add icon")
	rounds._on_add_golfer_selected(2)
	assert_null(rounds._add_golfer_button, "The add icon disappears again at capacity")
	rounds._on_add_golfer_selected(0)
	assert_eq(rounds._selected_pros.size(), 3, "Duplicate pros are ignored")
	rounds._start_embedded(0)
	assert_eq(rounds.participants.size(), 4, "The owner and all three pros play in one group")
	for index in 3:
		assert_eq(rounds.participants[index + 1].golfer_name, PlayerRoundManager.PROS[index])
		assert_eq(rounds.participants[index + 1].group_id, rounds.player.group_id,
			"Every selected pro joins the owner's playing group")
	rounds.leave_round()

## The shot-type buttons are separate buttons running along the top of the Play
## Course page, one per shot type, above the aiming columns — no drop-down.
func test_shot_buttons_run_along_the_top_of_the_play_course_page() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)
	await process_frames(2)

	var bar := tab.shot_bar
	var labels: Array[String] = []
	for shape in bar.shot_count():
		labels.append(bar.shot_button(shape).text)
	assert_eq(labels, ["Straight", "Fade", "Draw", "Backspin", "Punch"],
		"Every shot type gets its own button")
	for shape in bar.shot_count():
		assert_false(bar.shot_button(shape) is OptionButton, "No shot hides behind a menu")
	assert_true(bar.is_ancestor_of(bar.shot_button(0)), "The buttons are the Play Course row")
	assert_lte(bar.get_global_rect().end.y, tab.aim_scroll.get_global_rect().position.y + 1,
		"The shot buttons run above the aiming columns")
	assert_lte(bar.get_combined_minimum_size().y, tab.aim_view.size.y,
		"The row fits inside the Play Course page")

	# The row is live on the owner's turn and lights the shot the golfer will hit.
	assert_true(bar.is_ready_for_shot(), "The row is live while the owner aims")
	assert_true(bar.shot_button(0).button_pressed, "Straight leads by default")
	_press_shot(bar, 2)
	assert_eq(rounds.player.player_shape, 2, "Pressing Draw selects the draw shot")
	assert_true(bar.shot_button(2).button_pressed, "The pressed shot stays lit")
	assert_false(bar.shot_button(0).button_pressed, "Only one shot is lit at a time")
	var fairway_range := rounds.player.player_max_distance(Golfer.Club.IRON)
	_press_shot(bar, 4)
	assert_true(rounds.player.is_player_punch(), "Punch is a normal press on the row")
	assert_almost_eq(rounds.player.player_max_distance(Golfer.Club.IRON), fairway_range * 0.7, 0.001,
		"The lit button is the shot the golfer will hit")
	_assert_shelf_fits(tab.aim_page)

	# Off the tee and fairway the bend shots grey out and an illegal choice falls
	# back to straight, exactly as Golfer.play_shot() does.
	_press_shot(bar, 2)
	assert_eq(rounds.player.player_shape, 2, "Draw is selected from the fairway")
	_set_lie(TerrainTypes.Type.ROUGH)
	rounds._process(0.0)
	assert_true(bar.shot_button(1).disabled, "Fade needs a tee or fairway")
	assert_true(bar.shot_button(2).disabled, "Draw needs a tee or fairway")
	assert_true(bar.shot_button(3).disabled, "Backspin needs a tee or fairway")
	assert_false(bar.shot_button(0).disabled, "Straight works from the rough")
	assert_false(bar.shot_button(4).disabled, "Low punch works from the rough")
	assert_eq(rounds.player.player_shape, 0, "An illegal shape falls back to straight")
	assert_true(bar.shot_button(0).button_pressed, "The row follows the fallback")

	# Waiting for an opponent greys the whole row out instead of hiding it.
	_set_lie(TerrainTypes.Type.FAIRWAY)
	rounds.player._change_state(Golfer.State.WALKING)
	rounds._process(0.0)
	assert_false(bar.is_ready_for_shot(), "The row is dead between shots")
	for shape in bar.shot_count():
		assert_true(bar.shot_button(shape).disabled, "Every shot greys out while waiting")

## Exercise the real toolbar so header, panel margins and scrollbars count
## against the same height budget as the course tiles.
##
## The headless test window is 64x64, which Screen reads as a compact — and so
## touch-sized — layout: a taller bottom bar than the desktop one these pages
## are measured against. The reference window size is pinned for the length of
## the test (and Screen's per-frame polling, which would put the tiny window
## back, paused with it) so the toolbar is the 190px desktop bar main.gd gives
## it. after_each puts both back.
func _embedded_toolbar() -> TerrainToolbar:
	Screen.set_process(false)
	Screen.apply_size(Screen.BASE_SIZE)
	var toolbar := TerrainToolbar.new()
	fixture.add_child(toolbar)
	toolbar.size = Vector2(1000, UIConstants.BOTTOM_BAR_HEIGHT)
	assert_eq(Screen.bottom_bar_height(), float(UIConstants.BOTTOM_BAR_HEIGHT),
		"The pages are measured against the desktop bottom bar")
	var panel := TournamentPanel.new()
	panel.embedded = true
	toolbar.player_tab.add_persistent(panel)
	var tournaments := TournamentManager.new()
	fixture.add_child(tournaments)
	panel.setup(tournaments)
	rounds.attach_player_tab(toolbar.player_tab)
	toolbar.select_tab(TerrainToolbar.Tab.PLAYER)
	return toolbar

func _assert_shelf_fits(shelf: HBoxContainer) -> void:
	var scroll := shelf.get_parent() as ScrollContainer
	assert_lte(scroll.size.y, scroll.get_parent().size.y, "Scroll viewport fits the allocated tab height")
	# The shot-type row rides above the shelf: the two together must fit the page.
	var view := scroll.get_parent() as VBoxContainer
	if view != null:
		assert_lte(view.get_combined_minimum_size().y, view.size.y,
			"The shot buttons and the control columns share the page height")
		for child in view.get_children():
			if child is ShotTypeBar:
				assert_lte(child.get_combined_minimum_size().y, child.size.y, "The shot row keeps its height")
				assert_lte(child.get_combined_minimum_size().x, child.size.x, "The shot row spans the tab")
				assert_lte(child.get_global_rect().end.y, scroll.get_global_rect().position.y + 1,
					"The shot buttons run above the aiming columns")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_false(scroll.get_v_scroll_bar().visible, "No vertical scrolling in the Player tab")
	var available := scroll.size.y
	if scroll.get_h_scroll_bar().visible:
		available -= scroll.get_h_scroll_bar().size.y
	assert_lte(shelf.get_combined_minimum_size().y, available,
		"All content fits above the horizontal scrollbar")
	for control in shelf.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and not control is Popup:
			assert_lte(control.get_global_rect().end.y, scroll.get_global_rect().position.y + available + 1,
				"%s stays inside the shelf" % control.get_class())

## The Group Colour plates stand in a column directly to the right of the sprite
## they dress, ahead of the owner's own details.
func test_the_group_colours_stand_in_a_column_beside_the_sprite() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]
	var preview_column := page.get_child(0) as VBoxContainer
	assert_true(preview_column.is_ancestor_of(rounds._skin_preview_box),
		"The sprite still leads the shelf")
	assert_eq(page.get_child(1), rounds._skin_controls,
		"The Group Colour column comes next, directly right of the sprite")
	assert_gt(rounds._skin_controls.global_position.x,
		preview_column.get_global_rect().end.x - 1.0,
		"It starts at or after the sprite column's right edge")
	assert_eq(rounds._skin_controls.global_position.y,
		preview_column.global_position.y, "and lines up with its top")
	# The plates are one column: same left edge, each below the one before it.
	var plates := rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false)
	assert_eq(plates.size(), GolferSkins.player_skin().group_count(),
		"One plate per Re-color Group of the worn skin")
	assert_gt(plates.size(), 1, "The shipped skins carry more than one group")
	var column := plates[0].get_parent()
	var previous_end := -1.0
	for plate in plates:
		assert_eq(plate.get_parent(), column, "Every plate shares the one column")
		assert_eq(plate.position.x, 0.0, "They line up on the column's left edge")
		assert_gt(plate.position.y, previous_end, "Each plate sits below the one before")
		previous_end = plate.position.y + plate.size.y
	# A long group name is fitted to the plate, never allowed to widen the
	# column past the sprite it stands beside.
	var first := plates[0] as SkinGroupColorButton
	var worn_name := first.text
	first.text = "A Group Name Far Too Long To Fit"
	await process_frames(3)
	assert_eq(first.size, SkinGroupColorButton.BUTTON_SIZE,
		"A long group name does not stretch the plate")
	assert_lte(first.get_combined_minimum_size().x, SkinGroupColorButton.BUTTON_SIZE.x,
		"nor drives its minimum width past the column")
	first.text = worn_name
	# The old arrangement - a tall swatch and a separate name label per group,
	# parked after the traits - is gone.
	assert_eq(rounds._skin_controls.find_children("SkinGroupName*", "Label", true, false).size(),
		0, "The plate carries its own name instead of a separate label")
	assert_eq(rounds._skin_controls.find_children("*", "ColorPickerButton", true, false).size(),
		0, "The tall native colour selectors are replaced by the plates")

## The Group Colour column also fits the portrait tray, the shortest shelf in the
## game: the plates must never force a vertical scrollbar onto the Edit Player
## page there. Screen is pinned for the test and put back by after_each.
func test_the_group_colour_column_fits_the_portrait_tray() -> void:
	Screen.set_process(false)
	Screen.apply_size(Vector2(500, 900))
	assert_true(Screen.uses_portrait_hud(), "The window is a phone portrait")
	var toolbar := TerrainToolbar.new()
	fixture.add_child(toolbar)
	rounds.attach_player_tab(toolbar.player_tab)
	toolbar.select_tab(TerrainToolbar.Tab.EDIT_PLAYER)
	await process_frames(10)
	var page := toolbar.player_tab.pages[PlayerTab.PAGE_EDIT]
	var scroll := page.get_parent() as ScrollContainer
	var bar := scroll.get_h_scroll_bar()
	var available := scroll.size.y - (bar.size.y if bar.visible else 0.0)
	assert_false(scroll.get_v_scroll_bar().visible, "The portrait page never scrolls vertically")
	assert_lte(page.get_combined_minimum_size().y, available,
		"The Group Colour column fits the room the portrait tray leaves")
	assert_lte(rounds._skin_group_columns.get_combined_minimum_size().y, available,
		"The plates themselves fit that room")
	for control in page.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and not control is Popup:
			assert_lte(control.get_global_rect().end.y,
				scroll.get_global_rect().position.y + available + 1,
				"%s stays inside the portrait shelf" % control.get_class())
	# The plates are still one column beside the sprite on a phone.
	assert_eq(page.get_child(1), rounds._skin_controls,
		"The colours still stand directly right of the sprite")
	assert_eq(rounds._skin_group_columns.get_child_count(), 1,
		"The shipped skin's colours stay in a single column")

## A skin with more groups than one column holds carries on in the next column
## to the right, so a custom skin never pushes the page past the bottom bar.
func test_a_skin_with_many_groups_continues_in_the_next_column() -> void:
	# Extra groups are added to the worn skin, so work on a library of the test's
	# own: the shipped skins and the player's own are left alone.
	var previous_library := GolferSkins.library
	var previous_skin_id := GameManager.player_skin_id
	_remove_tree(TEST_SKIN_ROOT)
	GolferSkins.library = GolferSkinLibrary.new(GolferSkinLibrary.BUILT_IN_ROOT, TEST_SKIN_ROOT)
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var worn := GolferSkins.player_skin()
	var original := worn.group_count()
	# Push the worn skin past one column's worth of groups, then rebuild.
	var added: Array[int] = []
	while worn.group_count() < PlayerRoundManager.GROUP_COLORS_PER_COLUMN + 2:
		var id := worn.create_group("Extra")
		assert_gt(id, 0, "The test skin can carry another group")
		added.append(id)
	rounds._refresh_skin_controls()
	await process_frames(5)

	var columns := rounds._skin_group_columns.get_children()
	assert_eq(columns.size(), 2, "The overflow groups open a second column")
	assert_eq(columns[0].get_child_count(), PlayerRoundManager.GROUP_COLORS_PER_COLUMN,
		"The first column holds as many plates as the shelf is tall")
	assert_eq(columns[1].get_child_count(), worn.group_count() - PlayerRoundManager.GROUP_COLORS_PER_COLUMN,
		"and the rest carry on beside it")
	assert_gt(columns[1].global_position.x, columns[0].get_global_rect().end.x - 1.0,
		"The second column stands to the right of the first")
	var plates := rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false)
	assert_eq(plates.size(), worn.group_count(), "Every group still gets exactly one plate")
	# The page still fits the shelf: the overflow went sideways, not downwards.
	_assert_shelf_fits(tab.pages[PlayerTab.PAGE_EDIT])

	for id in added:
		worn.delete_group(id)
	assert_eq(worn.group_count(), original)
	rounds._refresh_skin_controls()
	await process_frames(3)
	assert_eq(rounds._skin_group_columns.get_child_count(), 1,
		"Going back under the limit returns the plates to a single column")

	GameManager.player_skin_id = previous_skin_id
	GolferSkins.set_player_skin(previous_library.player_skin(previous_skin_id))
	GolferSkins.library = previous_library
	_remove_tree(TEST_SKIN_ROOT)

## The Group Colour plates wear the Visiting Golfers' card design: the same
## pixel font, the same shared glass frame, and the sprite-and-caption layout.
func test_the_group_colour_plates_wear_the_visiting_golfer_design() -> void:
	_embedded_toolbar()
	var plates := rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false)
	assert_false(plates.is_empty())
	var visitor := autofree(VisitorCardButton.new()) as VisitorCardButton
	for plate in plates:
		var card := plate as SkinGroupColorButton
		assert_eq(SkinGroupColorButton.FONT, VisitorCardButton.FONT,
			"The plate captions in the visiting golfers' pixel font")
		assert_eq(SkinGroupColorButton.NAME_FONT_SIZE, VisitorCardButton.NAME_FONT_SIZE,
			"at the same caption size")
		assert_eq(SkinGroupColorButton.CREAM, VisitorCardButton.CREAM,
			"The caption wears the same cream")
		# The shared card frame, not the owner's square pixel fields.
		for state in ["normal", "hover", "pressed"]:
			assert_true(card.get_theme_stylebox(state) is StyleBoxTexture,
				"The %s state wears the shared visitor card frame" % state)
		var wash := card.get_theme_stylebox("focus") as StyleBoxFlat
		assert_not_null(wash, "Focus carries the shared warm wash")
		if wash:
			assert_gt(wash.bg_color.a, 0.0, "which is drawn")
			assert_lt(wash.bg_color.a, 0.4, "and stays translucent over the card")
		assert_true(card.has_meta(PlayerRoundManager.VISITOR_CARD_META),
			"and the page's styling pass leaves that frame alone")
		assert_eq(card.get_theme_color("font_color"), Color.TRANSPARENT,
			"The plate paints its own caption rather than the native label")
		assert_eq(card.focus_mode, Control.FOCUS_ALL, "The plate is keyboard reachable")
		assert_eq(card.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND)
		assert_false(card.accessibility_name.is_empty(), "and names itself for screen readers")
	# Same accent as the on-course visiting plates.
	assert_eq(SkinGroupColorButton.ACCENT, Color("83c9a4"))
	assert_eq(SkinGroupColorButton.ACCENT, visitor.accent,
		"The plates share the visiting green")

## Pressing a Group Colour plate opens a real colour picker, and the colour it
## hands back is written to that group of the worn skin.
func test_a_group_colour_plate_opens_a_picker_and_writes_its_group() -> void:
	var previous_library := GolferSkins.library
	var previous_skin_id := GameManager.player_skin_id
	_remove_tree(TEST_SKIN_ROOT)
	GolferSkins.library = GolferSkinLibrary.new(GolferSkinLibrary.BUILT_IN_ROOT, TEST_SKIN_ROOT)
	var toolbar := _embedded_toolbar()
	toolbar.player_tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)

	var worn := GolferSkins.player_skin()
	var group_id := int(worn.group_list()[0].get("id", 0))
	var plate := rounds._skin_controls.find_child("SkinGroupColor%d" % group_id, true, false) as SkinGroupColorButton
	assert_not_null(plate)
	plate.pressed.emit()
	await process_frames(2)
	var popup := plate.get_node_or_null("ColorPopup") as PopupPanel
	assert_not_null(popup, "Pressing the plate builds its picker popup")
	assert_true(popup.visible, "and opens it")
	var picker := plate.get_node_or_null("ColorPopup/ColorPicker") as ColorPicker
	assert_not_null(picker, "The popup carries the engine's own colour picker")
	assert_false(picker.edit_alpha, "A golfer's colours are opaque")

	# Moving the picker writes the group, exactly as the old swatch did.
	picker.color_changed.emit(Color("3070c0"))
	await process_frames(2)
	assert_eq(plate.color, Color("3070c0"), "The plate's swatch follows the pick")
	assert_eq(worn.group_by_id(group_id).get("color"), Color("3070c0"),
		"and the group is re-coloured on the skin")
	popup.hide()
	await process_frames(2)

	GameManager.player_skin_id = previous_skin_id
	GolferSkins.set_player_skin(previous_library.player_skin(previous_skin_id))
	GolferSkins.library = previous_library
	_remove_tree(TEST_SKIN_ROOT)

## The Golfer Skin button belongs to the golfer it dresses: the Edit Player page
## opens on the animated sprite with the picker under its feet, untitled.
func test_the_golfer_preview_leads_with_the_skin_button_beneath_it() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var preview_column := tab.pages[PlayerTab.PAGE_EDIT].get_child(0) as VBoxContainer
	assert_true(preview_column.is_ancestor_of(rounds._skin_preview_box))
	assert_eq(rounds._skin_picker.get_parent(), preview_column,
		"The picker is in the column of the golfer it dresses")
	assert_gt(rounds._skin_picker.get_index(), rounds._skin_preview_box.get_index(),
		"The picker is written below the sprite")
	assert_lte(rounds._skin_preview_box.get_global_rect().end.y,
		rounds._skin_picker.get_global_rect().position.y + 1,
		"and not beside or behind it")
	for child in preview_column.get_children():
		if child is Label:
			assert_ne((child as Label).text, "Golfer skin",
				"No title labels the picker")
	assert_eq(rounds._skin_picker.accessibility_name, "Golfer skin",
		"The picker names itself for screen readers without a visible title")
	# A skin name longer than the narrow column trims instead of widening it.
	var column_width := preview_column.size.x
	rounds._skin_picker.add_item("A Championship Skin With A Name Too Long To Fit")
	rounds._skin_picker.select(rounds._skin_picker.item_count - 1)
	await process_frames(5)
	assert_eq(preview_column.size.x, column_width,
		"A long skin name does not stretch the golfer's column")
	assert_lte(rounds._skin_picker.size.x, preview_column.size.x,
		"The trimmed picker stays inside the column")

## Edit Player keeps its controls without redundant section titles.
func test_edit_player_shelf_has_no_section_titles() -> void:
	var toolbar := _embedded_toolbar()
	var page := toolbar.player_tab.pages[PlayerTab.PAGE_EDIT]
	var removed_titles := ["Player Name", "Golfer Details", "On the course",
		"Tournament Mode", "Golfer Traits", "Golfer Traits (continued)",
		"Golfer colours", "Group colours"]
	for label in page.find_children("*", "Label", true, false):
		assert_false(label.text in removed_titles,
			"Edit Player does not show the section title: %s" % label.text)
	assert_not_null(_find_node(page, "PlayerName"), "The name field remains")
	assert_eq(rounds.name_edit.accessibility_name, "Player name")
	assert_not_null(_find_node(page, "PlayerProfession"), "Golfer details remain")
	assert_not_null(_find_node(page, "MoveWorkArea"), "Work-area controls remain")
	assert_not_null(_find_node(page, "SaveEditGolferForTournamentButton"),
		"Tournament export remains")
	for key in GolferAttributes.TRAIT_KEYS:
		assert_not_null(_find_node(page, "GolferTrait%s" % key.capitalize()),
			"Every trait toggle remains: %s" % key)
	assert_eq(page.find_children("*", "CheckButton", true, false).size(), 0,
		"The traits are name plates, not checkbox rows")
	assert_not_null(_find_node(page, "SkinGroupColumns"), "Group colour controls remain")
	var play_page := toolbar.player_tab.pages[PlayerTab.PAGE_PLAY]
	var play_titles: Array[String] = []
	for label in play_page.find_children("*", "Label", true, false):
		play_titles.append(label.text)
	assert_has(play_titles, "Tournament Mode", "The Play Course heading is unchanged")

## Gender and Marital Status each take one of the Golfer Skills' card plates:
## the caption reads the value the golfer has and a press steps to the next
## value, so neither setting needs a drop-down or a plate per option. The
## Golfer Traits remain one On/Off plate each, with no checkbox rows.
func test_edit_player_identity_and_traits_wear_skill_toggle_plates() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)
	var page := tab.pages[PlayerTab.PAGE_EDIT]

	# One plate each for Gender and Marital Status, plus one per trait.
	var gender := _find_node(page, "PlayerGenderToggle") as Button
	var marital := _find_node(page, "PlayerMaritalStatusToggle") as Button
	assert_not_null(gender, "Gender is one plate")
	assert_not_null(marital, "Marital Status is one plate")
	assert_null(_find_node(page, "PlayerGenderMale"), "No plate per gender")
	assert_null(_find_node(page, "PlayerMaritalStatusSingle"), "No plate per status")
	assert_null(_find_node(page, "PlayerGender"), "The gender drop-down is gone")
	assert_null(_find_node(page, "PlayerMaritalStatus"), "The marital drop-down is gone")
	assert_eq(page.find_children("*", "CheckButton", true, false).size(), 0,
		"The trait checkboxes are gone")

	var traits: Array[Button] = []
	for key in GolferAttributes.TRAIT_KEYS:
		var plate := _find_node(page, "GolferTrait%s" % key.capitalize()) as Button
		assert_not_null(plate, "Trait %s has a plate" % key)
		if plate != null:
			traits.append(plate)
	assert_eq(traits.size(), GolferAttributes.TRAIT_KEYS.size())

	# They wear the Golfer Skills footprint rather than the owner page's own
	# pixel buttons, which the final styling pass would otherwise repaint.
	var all_plates: Array[Button] = [gender, marital]
	all_plates.append_array(traits)
	for plate in all_plates:
		assert_true(plate.toggle_mode, "%s is a card plate" % plate.name)
		if plate in traits:
			assert_eq(plate.custom_minimum_size, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE,
				"Traits keep the Golfer Skills footprint")
		else:
			var widest := 0.0
			for caption in plate.get_meta("cycle_captions"):
				widest = maxf(widest, VisitorCardButton.FONT.get_string_size(
					str(caption), HORIZONTAL_ALIGNMENT_LEFT, -1, VisitorCardButton.NAME_FONT_SIZE).x)
			assert_eq(plate.custom_minimum_size.x, ceilf(widest) + 56.0,
				"Identity choices have Age-like caption padding")
			assert_lt(plate.custom_minimum_size.x, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE.x)
			assert_eq(plate.custom_minimum_size.y, PlayerRoundManager.SHELF_TOGGLE_BUTTON_SIZE.y)
		assert_eq(plate.get_theme_font("font"), VisitorCardButton.FONT,
			"%s uses the Visiting Golfer pixel font" % plate.name)
		assert_true(plate.get_theme_stylebox("normal") is StyleBoxTexture,
			"%s keeps the shared card frame" % plate.name)
		assert_true(plate.has_meta(PlayerRoundManager.VISITOR_CARD_META),
			"%s is exempt from the owner page's button restyling" % plate.name)

	# The Gender plate reads the value the golfer has, stays lit, and steps
	# through the pair each time it is pressed, wrapping back round.
	assert_eq(gender.text, "Male", "The plate reads the golfer's gender")
	assert_true(gender.button_pressed, "A value plate is always lit")
	assert_not_null(gender.button_group, "Its lone group keeps it from switching off")
	assert_false(gender.button_group.allow_unpress)
	gender.pressed.emit()
	assert_eq(gender.text, "Female", "A press steps to the next gender")
	assert_eq(rounds.draft.gender, GolferAttributes.Gender.FEMALE)
	assert_eq(GameManager.player_profile.gender, GolferAttributes.Gender.FEMALE,
		"The gender choice saves at once")
	assert_true(gender.button_pressed, "The plate stays lit after a press")
	gender.pressed.emit()
	assert_eq(gender.text, "Male", "The pair wraps back round")
	assert_eq(GameManager.player_profile.gender, GolferAttributes.Gender.MALE,
		"and saves the wrap the same way")

	# Marital Status is the same one-plate choice over its four values.
	var status_order: Array[String] = []
	for value in GolferAttributes.MARITAL_STATUS_NAMES:
		status_order.append(str(GolferAttributes.MARITAL_STATUS_NAMES[value]))
	assert_eq(marital.text, "Single", "The plate reads the golfer's marital status")
	assert_true(marital.button_pressed, "It is lit like the gender plate")
	for step in status_order.size():
		var expected_name := status_order[(step + 1) % status_order.size()]
		marital.pressed.emit()
		assert_eq(marital.text, expected_name, "A press steps to the next marital status")
		assert_eq(GameManager.player_profile.marital_status,
			GolferAttributes.marital_status_from_name(expected_name),
			"and saves it at once")
		assert_true(marital.button_pressed, "The plate stays lit through the cycle")
	assert_eq(marital.text, "Single", "The four statuses wrap back round")

	# Traits are independent switches: turning one off leaves the rest alone.
	assert_null(traits[0].button_group, "A trait is not part of a single choice")
	assert_eq(traits[0].get_parent().get_child_count(), PlayerRoundManager.TOGGLES_PER_COLUMN,
		"A trait column holds as many plates as the shelf is tall")
	assert_eq(traits[3].get_parent(), traits[4].get_parent(),
		"The last traits continue in the next column")
	assert_ne(traits[0].get_parent(), traits[3].get_parent())
	var neat := traits[GolferAttributes.TRAIT_KEYS.find("neat")]
	neat.button_pressed = true
	neat.toggled.emit(true)
	assert_true(GameManager.player_profile.traits["neat"], "A trait saves when switched On")
	neat.button_pressed = false
	neat.toggled.emit(false)
	assert_false(GameManager.player_profile.traits["neat"], "and when switched Off")
	assert_false(traits[GolferAttributes.TRAIT_KEYS.find("outgoing")].button_pressed,
		"Toggling one trait leaves its neighbours alone")

	# The extra columns still fit the shelf: no vertical scrolling grew.
	await process_frames(3)
	_assert_shelf_fits(page)

## The Edit Player page edits the Golfer Skin the owner wears and the colour of
## each Re-color Group it carries - including while the round is running, since
## it only ever changes how a golfer is drawn.
func test_edit_player_page_changes_the_golfer_skin_and_its_group_colours() -> void:
	# Editing a group colour writes the skin out, so point the library the page
	# reads at a folder of the test's own: the player's skins are left alone.
	var previous_library := GolferSkins.library
	var previous_skin_id := GameManager.player_skin_id
	_remove_tree(TEST_SKIN_ROOT)
	GolferSkins.library = GolferSkinLibrary.new(GolferSkinLibrary.BUILT_IN_ROOT, TEST_SKIN_ROOT)
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	tab.select(PlayerTab.PAGE_EDIT)
	await process_frames(5)

	assert_not_null(rounds._skin_picker, "The Edit Player page picks a Golfer Skin")
	assert_gt(rounds._skin_picker.item_count, 0, "from the skins the game knows")
	assert_not_null(rounds._skin_preview, "and previews the golfer wearing it")
	assert_eq(rounds._skin_preview.skin().id, GolferSkins.player_skin().id)
	assert_true(rounds._skin_preview.sprite_node().is_playing(), "The first-column sprite animates")
	assert_gt(rounds._skin_preview.scale.y, 1.0, "The preview sprite is scaled up to fill the column")

	# Pick a different skin: the owner's golfer is dressed in it at once.
	var swapped := -1
	for index in rounds._skin_picker.item_count:
		if str(rounds._skin_picker.get_item_metadata(index)) != GolferSkins.player_skin().id:
			swapped = index
			break
	if swapped == -1:
		GameManager.player_skin_id = previous_skin_id
		GolferSkins.library = previous_library
		_remove_tree(TEST_SKIN_ROOT)
		pending("only one Golfer Skin on this machine - nothing to switch to")
		return
	var wanted := str(rounds._skin_picker.get_item_metadata(swapped))
	rounds._skin_picker.item_selected.emit(swapped)
	assert_eq(GameManager.player_skin_id, wanted, "the picker sets the skin the owner wears")
	assert_eq(rounds._skin_preview.skin().id, wanted, "the preview follows")

	# One Group Colour plate per Re-color Group of that skin, each writing the skin.
	var swatches := rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false)
	var worn := GolferSkins.player_skin()
	assert_eq(swatches.size(), worn.group_count(),
		"a colour plate per Re-color Group of the chosen skin")
	for group in worn.group_list():
		var id := int(group.get("id", 0))
		var color_plates := rounds._skin_controls.find_children("SkinGroupColor%d" % id, "SkinGroupColorButton", true, false)
		assert_eq(color_plates.size(), 1, "Each group has its own colour plate")
		if color_plates.is_empty():
			continue
		var plate := color_plates[0] as SkinGroupColorButton
		assert_eq(plate.text, str(group.get("name", "")),
			"The plate names the group it colours")
		assert_eq(plate.color, group.get("color", Color.WHITE),
			"and shows that group's colour as its swatch")
		assert_eq(int(plate.get_meta("skin_group_id")), id,
			"The plate writes the group it stands for")
	var group_id := int(worn.group_list()[0].get("id", 0))
	var before := GolferSkins.skins_changed.get_connections().size()
	rounds._on_skin_group_color_changed(Color("00ff00"), group_id)
	assert_eq(worn.group_by_id(group_id).get("color"), Color("00ff00"),
		"the swatch re-colours the group")
	assert_eq(GolferSkins.skins_changed.get_connections().size(), before,
		"and tells the course to redraw the golfers wearing it")
	# The profile keeps up for the groups it names as the skin is re-coloured.
	var key := GolferSkin.profile_key_for_group(str(worn.group_by_id(group_id).get("name", "")))
	if not key.is_empty():
		assert_eq(rounds.draft.appearance.get(key), "00ff00",
			"the profile's own colour for %s follows the skin" % key)
		assert_true(worn.is_user_skin, "the skin became the player's own, so the shipped one is untouched")

	GameManager.player_skin_id = previous_skin_id
	GolferSkins.set_player_skin(previous_library.player_skin(previous_skin_id))
	GolferSkins.library = previous_library
	_remove_tree(TEST_SKIN_ROOT)

## Everything on the Edit Player page is locked during a round except the Golfer
## Skin controls, which the player is meant to reach while playing.
func test_the_round_locks_the_page_but_not_the_skin_controls() -> void:
	_embedded_toolbar()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)
	await process_frames(2)
	assert_true(rounds.active, "the round is running")
	assert_true(rounds.name_edit.editable == false, "the name field is locked while playing")
	assert_false(rounds._skin_picker.disabled, "the Golfer Skin picker stays live")
	for swatch in rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false):
		assert_false((swatch as SkinGroupColorButton).disabled, "and so do the group colours")
	# A plate's picker is part of those skin controls: a round starting while one
	# is open must not disable the picker the player is using.
	var plate := rounds._skin_controls.find_children("SkinGroupColor*", "SkinGroupColorButton", true, false)[0] as SkinGroupColorButton
	plate.pressed.emit()
	await process_frames(2)
	var popup := plate.get_node_or_null("ColorPopup") as PopupPanel
	assert_not_null(popup, "The plate opened its picker")
	if popup != null:
		for control in popup.find_children("*", "BaseButton", true, false):
			assert_false((control as BaseButton).disabled,
				"The picker's own controls stay live during the round")
		popup.hide()
		await process_frames(1)
	rounds.leave_round()

func test_embedded_pages_fit_toolbar_and_overflow_horizontally() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	var expected_toolbar_height := toolbar.size.y
	for width in [1000, 600, 1600]:
		toolbar.size.x = width
		for index in 3:
			tab.select(index)
			await process_frames(5)
			assert_eq(toolbar.size.y, expected_toolbar_height, "Switching pages never grows the bar")
			_assert_shelf_fits(tab.pages[index])
			if index == PlayerTab.PAGE_EDIT:
				assert_gt(rounds._skin_preview_box.size.y, 72.0,
					"The animated preview uses most of the Edit Player page height")
				# The Group Colour plates stack down a column beside the sprite
				# instead of stretching one tall swatch per group.
				var plate_column := rounds._skin_group_columns.get_child(0) as VBoxContainer
				assert_not_null(plate_column)
				assert_gt(plate_column.get_child_count(), 1,
					"The Group Colour plates stack down their column")
				var previous_end := -1.0
				for plate in plate_column.get_children():
					assert_eq(plate.size, SkinGroupColorButton.BUTTON_SIZE,
						"Each Group Colour plate keeps the visitor-card footprint")
					assert_gt(plate.position.y, previous_end,
						"and sits below the plate before it, in one column")
					assert_eq(plate.position.x, 0.0, "The plates share one left edge")
					previous_end = plate.position.y + plate.size.y
				assert_gt(rounds._skin_controls.global_position.x,
					rounds._skin_preview_box.get_global_rect().end.x,
					"The column stands to the right of the sprite, never over it")
			if width == 600:
				var scroll := tab.pages[index].get_parent() as ScrollContainer
				assert_true(scroll.get_h_scroll_bar().visible, "Narrow pages scroll sideways")
				var navigation_x := tab.buttons[0].global_position.x
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_WHEEL_DOWN
				event.pressed = true
				tab._on_scroll_gui_input(event, scroll)
				assert_gt(scroll.scroll_horizontal, 0, "Mouse wheel scrolls horizontally")
				assert_eq(tab.buttons[0].global_position.x, navigation_x,
					"Navigation stays pinned while content scrolls")
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(5)
	assert_eq(toolbar.size.y, expected_toolbar_height)

func test_embedded_tournament_survives_rebuilds_and_fits_all_states() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	var panel: TournamentPanel
	for child in tab.pages[PlayerTab.PAGE_PLAY].get_children():
		if child is TournamentPanel:
			panel = child
	for state in TournamentSystem.TournamentState.values():
		panel._tournament_manager.current_tournament_state = state
		panel._tournament_manager.current_tournament_tier = 0
		panel._tournament_manager.tournament_results = {
			"winner_name": "Tournament Winner", "winning_score": 70, "par": 72}
		panel._refresh_display()
		rounds._build_setup()
		await process_frames(5)
		assert_eq(panel.get_parent(), tab.pages[PlayerTab.PAGE_PLAY])
		_assert_shelf_fits(tab.pages[PlayerTab.PAGE_PLAY])

## The game's top-left score corner, as main.gd builds it: the round card first,
## the tournament board docked under it.
func _scores_dock() -> ScoresDock:
	var dock := ScoresDock.new()
	hud.add_child(dock)
	rounds.attach_scores_panel(dock.round_scores)
	return dock

func test_tournament_board_and_shot_controls_share_the_corner() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	var dock := _scores_dock()
	var leaderboard := TournamentLeaderboard.new()
	dock.attach_leaderboard(leaderboard)
	leaderboard.show_for_tournament("Local Tournament", 12)
	leaderboard.register_golfer(0, "Owner", 0, true)

	var owner_golfer := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 99)
	owner_golfer.player_profile = GameManager.player_profile
	rounds.begin_tournament_aim(owner_golfer)
	await process_frames(5)
	assert_true(rounds.tournament_aim)
	assert_eq(tab.selected, PlayerTab.PAGE_PLAY)
	assert_true(tab.playing)
	assert_true(tab.aim_scroll.visible)
	assert_true(dock.is_ancestor_of(leaderboard), "Tournament scores live in the top-left corner")
	assert_false(tab.aim_page.is_ancestor_of(leaderboard),
		"Tournament scores no longer sit in the Play Course page")
	assert_true(tab.aim_page.is_ancestor_of(rounds.status), "Tournament shot status stays with the controls")
	assert_true(tab.aim_page.is_ancestor_of(rounds._tournament_hud_column))
	_assert_shelf_fits(tab.aim_page)

func test_scores_dock_hugs_the_top_left_corner() -> void:
	var dock := _scores_dock()
	var leaderboard := TournamentLeaderboard.new()
	dock.attach_leaderboard(leaderboard)
	await process_frames(2)
	assert_eq(dock.anchor_left, 0.0)
	assert_eq(dock.anchor_top, 0.0)
	assert_eq(dock.offset_left, float(UIConstants.HUD_COLUMN_MARGIN))
	assert_eq(dock.offset_top, float(UIConstants.HUD_COLUMN_MARGIN))
	assert_true(dock.round_scores.get_parent() == dock, "The round card leads the corner")
	assert_true(leaderboard.get_parent() == dock, "The board docks under it")
	leaderboard.show_for_tournament("Local Tournament", 4)
	await process_frames(2)
	assert_eq(dock.size.x, float(ScoresDock.WIDTH),
		"The corner is wide enough for the board's columns")
	for i in 40:
		leaderboard.register_golfer(i, "Golfer %d" % i, i)
	await process_frames(2)
	assert_eq(leaderboard._scroll.custom_minimum_size.y,
		TournamentLeaderboard.DOCK_BODY_MAX_HEIGHT,
		"A big field is capped so the board cannot run down the screen")
	assert_true(leaderboard._scroll.get_v_scroll_bar().visible, "The rest of the field scrolls")

func test_practice_round_scores_read_out_top_left() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	var dock := _scores_dock()
	var card := dock.round_scores
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(1)
	await process_frames(2)
	assert_true(card.visible, "The round card shows while playing")
	assert_eq(card.title_label.text, "Vs Pro · Pro Alex")
	assert_false(tab.aim_page.is_ancestor_of(card), "The scorecard is out of the Play Course page")
	assert_true(dock.is_ancestor_of(card), "The scorecard sits in the top-left corner")
	var rows := card.score_rows()
	assert_eq(rows.size(), 2, "One row per player in the group")
	assert_eq(rows[0].name, "Test Owner (you)")
	assert_eq(rows[0].value, "-", "No holes in yet")
	# One hole in: the card shows the score against par and the holes completed.
	var owner_golfer: Golfer = rounds.player
	owner_golfer.hole_scores.append({"hole": 1, "strokes": 2, "par": 3})
	owner_golfer.total_strokes = 2
	owner_golfer.total_par = 3
	rounds._process(0.0)
	assert_eq(card.score_rows()[0].value, "-1 · thru 1")
	await process_frames(2)
	assert_true(card._scroll.custom_minimum_size.y < RoundScoresPanel.MAX_BODY_HEIGHT,
		"A short card does not reserve empty space over the course")
	rounds.leave_round()
	await process_frames(2)
	assert_false(card.visible, "Leaving the round drops the card")

func test_round_complete_scores_land_on_the_card() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	var dock := _scores_dock()
	var card := dock.round_scores
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	await process_frames(2)
	for golfer in rounds.participants:
		golfer.hole_scores.clear()
		for hole in 18:
			golfer.hole_scores.append({"hole": hole + 1, "strokes": 4, "par": 4})
		golfer.total_strokes = 72
		golfer.total_par = 72
	rounds._show_results()
	await process_frames(2)
	assert_eq(card.title_label.text, "Round complete")
	var lines: Array[String] = []
	for child in card.body.get_children():
		if child is Label:
			lines.append(child.text)
	assert_true(lines.any(func(line): return line.begins_with("Test Owner — 72 strokes")),
		"The card carries the finished scorecard: " + str(lines))
	assert_true("Hole 18: 4 / Par 4" in lines, "Every hole of the card is on it")
	assert_eq(card._scroll.custom_minimum_size.y, RoundScoresPanel.MAX_BODY_HEIGHT,
		"A long card is capped so it cannot cover the course")
	assert_true(card._scroll.get_v_scroll_bar().visible, "The rest of the card scrolls")
	var return_buttons := 0
	for button in tab.aim_page.find_children("*", "Button", true, false):
		if button.text == "Return to management":
			return_buttons += 1
	assert_eq(return_buttons, 1, "The round page keeps the way out of the round")

func test_embedded_aim_and_full_scorecards_fit_toolbar() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	var expected_toolbar_height := toolbar.size.y
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
	rounds._start_embedded(2)
	rounds._process(0.0)
	await process_frames(5)
	_assert_shelf_fits(tab.aim_page)
	assert_false(tab.pages[PlayerTab.PAGE_PLAY].get_parent().visible,
		"Setup scrollbar is hidden during a round")
	for golfer in rounds.participants:
		golfer.hole_scores.clear()
		for hole in 18:
			golfer.hole_scores.append({"hole": hole + 1, "strokes": 4, "par": 4})
	rounds._show_results()
	await process_frames(5)
	_assert_shelf_fits(tab.aim_page)
	assert_eq(toolbar.size.y, expected_toolbar_height)

func test_save_skills_button_removed_and_skills_save_automatically() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	# Verify that no button with text "Save skills" exists anywhere in the Player Skills page
	var skill_page := tab.pages[PlayerTab.PAGE_SKILLS]
	for button in skill_page.find_children("*", "Button", true, false):
		assert_ne(button.text, "Save skills", "Save skills button must not exist")

	# Verify skills save automatically whenever changed
	assert_eq(GameManager.player_profile.points[0], 0)
	assert_true(rounds.allocate_skill(0, 1), "Allocating a point succeeds")
	assert_eq(GameManager.player_profile.points[0], 1, "Skill automatically saved to player_profile")
	assert_eq(rounds.draft.points[0], 1)

	assert_true(rounds.allocate_skill(0, -1), "Refunding a point succeeds")
	assert_eq(GameManager.player_profile.points[0], 0, "Refund automatically saved to player_profile")

func test_skills_auto_save_and_take_effect_for_next_shot_mid_round() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	# Allocate initial 10 points
	for i in 10:
		rounds.allocate_skill(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)

	assert_true(rounds.active, "Round is active")
	assert_not_null(rounds.player, "Player golfer is spawned")

	# Spent points remain refundable during a round; additions are disabled
	# only because the pool is empty, not because the round is active.
	assert_false(rounds.skill_decrease_buttons[4].disabled)
	assert_true(rounds.skill_increase_buttons[1].disabled)

	# Record the initial driving ability to compare against after allocating points
	var initial_driving_ability := rounds.player.driving_ability()

	# Mid-round: change skills (e.g. shift a point from Accurate Putter to Long Driver)
	# First refund 1 from skill 4 (Accurate Putter)
	rounds.skill_decrease_buttons[4].pressed.emit()
	# Add to skill 1 (Long Driver)
	assert_false(rounds.skill_increase_buttons[1].disabled)
	rounds.skill_increase_buttons[1].pressed.emit()

	# Verify skills auto-saved to GameManager.player_profile
	assert_eq(GameManager.player_profile.points[4], 0, "Accurate Putter points updated in profile")
	assert_eq(GameManager.player_profile.points[1], 2, "Long Driver points updated in profile")

	# Verify abilities are immediately in effect on the golfer for the next shot
	assert_almost_eq(rounds.player.driving_ability(), GameManager.player_profile.driving_ability(), 0.0001,
		"Player driving_ability updated immediately")
	assert_gt(rounds.player.driving_ability(), initial_driving_ability,
		"Driving ability increased after allocating more points to Long Driver")

	# Verify driver distance reflects the new skills immediately
	var new_driver_dist := rounds.player.player_max_distance(Golfer.Club.DRIVER)
	# Power Hitter 1pt (0.1) + Long Driver 2pt (0.2) → factor 0.7 * (1.0 + 0.3)
	assert_almost_eq(new_driver_dist, float(Golfer.CLUB_STATS[Golfer.Club.DRIVER].max_distance) * 0.7 * (1.0 + 0.3), 0.01,
		"Driver distance reflects updated Long Driver skill immediately")

	# Verify aim guide / shot preview reflects the updated skills
	var preview := rounds.player.preview_shot(Vector2i(30, 10))
	assert_false(preview.is_empty(), "Preview shot is available")
	assert_almost_eq(preview.max_range, new_driver_dist, 0.01,
		"Preview shot max range matches updated skill distance")

	# Take shot and verify it succeeds with new skills in effect
	assert_true(rounds.player.play_shot(Vector2i(30, 10)), "Shot executes with new skills in effect")

	rounds.leave_round()

func test_putting_ability_auto_saves_and_takes_effect_for_next_putt() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.allocate_skill(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)

	var initial_putting_ability := rounds.player.putting_ability()

	# Reallocate: shift point from Luck (index 9) to Accurate Putter (index 4)
	assert_true(rounds.allocate_skill(9, -1))
	assert_true(rounds.allocate_skill(4, 1))

	assert_eq(GameManager.player_profile.points[4], 2, "Accurate Putter updated in GameManager.player_profile")
	assert_gt(rounds.player.putting_ability(), initial_putting_ability,
		"Golfer putting_ability immediately reflects new Accurate Putter skill for next putt")

	rounds.leave_round()

func test_skills_change_mid_round_with_tournament_manager_present() -> void:
	var tm := TournamentManager.new()
	fixture.add_child(tm)
	GameManager.tournament_manager = tm

	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.allocate_skill(i, 1)
	rounds.name_edit.text = "Course Golfer"
	rounds._start_embedded(0)
	rounds._process(0.0)

	assert_true(rounds.active, "Course round is active")
	assert_not_null(rounds.player, "Player golfer is present")

	# Change skills while playing the course with TournamentManager active in GameManager
	assert_true(rounds.allocate_skill(0, -1), "Refunding skill mid-round succeeds with TournamentManager present")
	assert_true(rounds.allocate_skill(3, 1), "Allocating skill mid-round succeeds with TournamentManager present")
	assert_eq(GameManager.player_profile.points[0], 0)
	assert_eq(GameManager.player_profile.points[3], 2)
	assert_almost_eq(rounds.player.accuracy_ability(), GameManager.player_profile.accuracy_ability(), 0.0001)

	# Also verify sync_player_skills updates SimulationGolfer if present in field
	var sg := tm._make_player_sim_golfer()
	tm._sim_field = [sg]
	assert_true(rounds.allocate_skill(3, -1))
	assert_true(rounds.allocate_skill(1, 1))
	assert_almost_eq(sg.driving_ability, GameManager.player_profile.driving_ability(), 0.0001,
		"TournamentManager SimulationGolfer abilities update when player skills change")

	rounds.leave_round()

func test_the_round_is_played_with_the_golfer_who_works_the_course() -> void:
	# The owner's own golfer lives on the course between rounds, working a
	# ground of their own. The round is played with that same golfer.
	GameManager.golfer_manager = golfers
	var owner_manager := PlayerGolferManager.new()
	fixture.add_child(owner_manager)
	owner_manager.setup(golfers.golfers_container)
	GameManager.player_golfer_manager = owner_manager
	var course_owner := owner_manager.ensure_golfer()
	assert_true(course_owner.is_on_course_duty(), "Between rounds the owner's golfer works the course")

	_start(0)
	assert_eq(rounds.player, course_owner, "The round is played with the same golfer")
	assert_true(golfers.get_active_golfers().has(course_owner), "They play with the group on the course")
	assert_false(course_owner.is_on_course_duty(), "While they play they are not working")
	assert_eq(rounds.player.golfer_name, "Test Owner")

	rounds.leave_round()
	assert_true(course_owner.is_on_course_duty(), "When the round is over they go back to work")
	assert_false(golfers.get_active_golfers().has(course_owner),
		"They are not one of the guests playing the course")

func test_the_edit_player_page_names_the_ground_they_work() -> void:
	var owner_manager := PlayerGolferManager.new()
	fixture.add_child(owner_manager)
	owner_manager.setup(golfers.golfers_container)
	GameManager.player_golfer_manager = owner_manager
	owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(9, 11))

	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	rounds.open_setup()
	var column := _find_node(tab.pages[PlayerTab.PAGE_EDIT], "OwnerWorkArea")
	assert_not_null(column, "The Edit Player page says where the owner works")
	assert_true(column.text.contains("9"), "The ground the owner works is named: %s" % column.text)
	assert_true(column.text.contains("11"), "The ground the owner works is named: %s" % column.text)

	# The button asks main.gd for a click on the course.
	var moved: Array = []
	rounds.owner_area_move_requested.connect(func(): moved.append(true))
	var button := rounds._work_area_button
	assert_not_null(button, "The page has a button that moves the ground")
	button.pressed.emit()
	assert_eq(moved.size(), 1, "The button asks for the new ground")
	rounds.set_owner_area_mode(true)
	assert_eq(button.text, "Pick a tile…", "While the ground is being chosen the button says so")
	rounds.set_owner_area_mode(false)
	assert_eq(button.text, "Move work area")

## The node named `wanted` under `node`, wherever it sits in the tree.
func _find_node(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_node(child, wanted)
		if found != null:
			return found
	return null

func test_the_owner_walks_to_the_tee_to_start_a_round() -> void:
	# The owner works a ground of their own between rounds. When a round
	# starts they walk from there to the tee - they are not put there.
	GameManager.golfer_manager = golfers
	var owner_manager := PlayerGolferManager.new()
	fixture.add_child(owner_manager)
	owner_manager.setup(golfers.golfers_container)
	GameManager.player_golfer_manager = owner_manager
	var course_owner := owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(25, 25))
	course_owner.global_position = GameManager.terrain_grid.grid_to_screen_center(Vector2i(25, 25))

	_start(0)
	assert_eq(rounds.player, course_owner, "The round is played with the same golfer")
	assert_eq(course_owner.current_state, Golfer.State.WALKING,
		"The owner walks to the tee instead of being put there")
	assert_eq(course_owner.ball_position, Vector2i(10, 10), "Their ball is on the tee")
	assert_almost_eq(
		GameManager.terrain_grid.screen_to_grid_point(course_owner.global_position).distance_to(Vector2(25, 25)),
		0.0, 1.0, "They are still where they were working when the round starts")
	assert_false(owner_manager.duty.running,
		"The work stops while they play, so they do not walk back to it")

func test_the_owner_goes_back_to_work_when_the_round_is_over() -> void:
	GameManager.golfer_manager = golfers
	var owner_manager := PlayerGolferManager.new()
	fixture.add_child(owner_manager)
	owner_manager.setup(golfers.golfers_container)
	GameManager.player_golfer_manager = owner_manager
	var course_owner := owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(25, 25))
	course_owner.global_position = GameManager.terrain_grid.grid_to_screen_center(Vector2i(25, 25))

	_start(0)
	# The round is played from the tee: the owner is there when it ends.
	course_owner.global_position = GameManager.terrain_grid.grid_to_screen_center(Vector2i(10, 10))
	rounds.leave_round()
	assert_eq(owner_manager.duty.commute, OwnerDuty.Commute.HOME,
		"The round ended away from the ground they work, so they walk back to it")
	assert_false(course_owner.is_on_course_duty(), "They are walking home, not working yet")
	# The walk ends on the ground they work, and the work starts again.
	course_owner.global_position = GameManager.terrain_grid.grid_to_screen_center(Vector2i(25, 25))
	course_owner.path.clear()
	course_owner._on_reached_destination()
	owner_manager.duty._process(0.1)
	assert_true(course_owner.is_on_course_duty(), "They are working the course again")
	assert_true(owner_manager.duty.running, "The work is running again")
