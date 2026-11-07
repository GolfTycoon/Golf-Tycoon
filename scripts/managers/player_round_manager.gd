extends Node2D
class_name PlayerRoundManager
## Owner rounds run alongside the management simulation as a normal group.
signal session_opened
## Emitted when the player asks to move the ground the owner's own golfer
## works between rounds. main.gd turns it into a click-on-the-course mode.
signal owner_area_move_requested

const PROS = ["Pro Alex", "Pro Morgan", "Pro Riley"]
## The same visiting green used by the on-course golfer cards.
const GOLFER_SKILL_ACCENT := Color("83c9a4")
## A narrower version of the visitor name plate, retaining its height.
const GOLFER_SKILL_BUTTON_SIZE := Vector2(184, 44)
## Marks buttons whose shared visitor-card styling must not be replaced by the
## owner's ordinary pixel controls during the final styling pass.
const GOLFER_SKILL_CARD_META := "golfer_skill_card"
## Toggles to a column on the owner's pages. The pages are horizontal shelves
## with no vertical scroll, so a section that runs longer than this carries on
## in the next column instead of growing past the bottom bar.
const TOGGLES_PER_COLUMN := 4
var player_tab: PlayerTab
## Top-left score card owned by the game HUD (null in isolated tools and tests,
## which fall back to putting the scorecards on the round page).
var scores: RoundScoresPanel = null
var busy := false
var active := false
var player: Golfer
var participants: Array[Golfer] = []
var manager: GolferManager
var camera: IsometricCamera
var hud: Control
var layer: CanvasLayer
var entry: Button = null  # Legacy floating button; replaced by the toolbar's Player tab
var overlay: Control
var content: VBoxContainer
var status: Label
## The shot-type row on the Play Course tab (PlayerTab builds it): one button per
## shot type, replacing the old drop-down selector. Falls back to a row built
## into the floating panel when there is no Player tab (isolated tools, tests).
var shot_bar: ShotTypeBar
var draft: PlayerGolferProfile
var name_edit: LineEdit
## The Edit Player page's Re-color Group section. Its column contains a
## vertical scrollable list of one Visiting-Golfer-styled button per group;
## the column sits directly to the right of the sprite preview and is rebuilt
## when the owner chooses another skin.
var _skin_controls: VBoxContainer = null
var _skin_group_columns: VBoxContainer = null
var _skin_group_scroll: ScrollContainer = null
var _skin_picker: OptionButton = null
var _skin_preview: Golfer = null
var _skin_preview_box: Control = null
var mode_picker: OptionButton
var pro_picker: OptionButton
## Pros added to the next owner round from the Play Course roster.
var _selected_pros: Array[String] = []
var _add_golfer_button: Button = null
var _pro_roster: HBoxContainer = null
var _round_players_row: HBoxContainer = null
var _pro_menu: PopupMenu = null
var _pro_preview_nodes: Dictionary = {}
var _round_player_preview: Golfer = null
var _round_player_preview_box: Control = null
var skill_labels: Array[Label] = []
var points_label: Label
var start_button: Button
var previous_mode: int
var previous_speed: int
var previous_camera: Vector2
var round_kind := 0
var aim_guide: AimGuide
var _was_aiming: bool = false
var _tournament_hud_column: VBoxContainer = null
## The Edit Player page's work-area column: where the owner's own golfer
## works between rounds, and the button that moves it.
var _work_area_label: Label = null
var _work_area_button: Button = null
## True while aiming for the owner's golfer inside a running tournament. The
## TournamentManager owns that round; this flag only tells our _process to skip
## the owner-round bookkeeping (driving the sim, showing round results) and to
## leave the golfer on the course when aiming ends.
var tournament_aim: bool = false

func setup(golfers: GolferManager, view: IsometricCamera, management_hud: Control) -> void:
	manager = golfers
	camera = view
	hud = management_hud
	aim_guide = AimGuide.new()
	add_child(aim_guide)
	layer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	EventBus.game_mode_changed.connect(_on_mode_changed)
	EventBus.load_completed.connect(_on_load_completed)
	EventBus.new_game_started.connect(_on_new_game_started)

func _exit_tree() -> void:
	if EventBus.game_mode_changed.is_connected(_on_mode_changed):
		EventBus.game_mode_changed.disconnect(_on_mode_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_mode_changed(_old: int, mode: int) -> void:
	if busy and mode == GameManager.GameMode.MAIN_MENU:
		leave_round(false)

func _on_new_game_started() -> void:
	_on_load_completed(true)

func _on_load_completed(_success: bool) -> void:
	if busy:
		leave_round(false)
	elif is_instance_valid(player_tab):
		_build_setup()

func _make_panel(full_screen: bool) -> void:
	if is_instance_valid(player_tab):
		# The Play Course tab swaps its setup sections for the aiming HUD.
		content = PlayerTab.add_column(player_tab.clear_aim_page(), 320)
		player_tab.set_playing(true)
		player_tab.select(PlayerTab.PAGE_PLAY)
		return
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP if full_screen else Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var panel := PanelContainer.new()
	overlay.add_child(panel)
	panel.position = Vector2(20, 56) if not full_screen else Vector2(40, 40)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, minf(760, get_viewport_rect().size.y - 100)) if full_screen else Vector2(340, 240)
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

## The skin selector, written into the first column of the shelf, directly under
## the animated golfer wearing it, so what the golfer wears is chosen on the
## golfer itself. It carries no heading of its own: the sprite above it, the
## picker's own entries and its tooltip already say what it chooses. Their
## Re-color Groups are a column of their own further along the shelf (see
## _build_skin_group_controls).
func _build_skin_picker(column: VBoxContainer) -> void:
	_skin_picker = OptionButton.new()
	_skin_picker.name = "GolferSkinPicker"
	_skin_picker.tooltip_text = "Which Golfer Skin your golfer wears. The Edit Golfer Skins screen paints them."
	# No title sits above the picker, so its accessible name is what carries the
	# label: its own text is only the skin it currently shows.
	_skin_picker.accessibility_name = "Golfer skin"
	_skin_picker.custom_minimum_size = Vector2(0, 28)
	_skin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The first column is one sprite wide, and a skin name can be longer than
	# that. Without these the picker widens the column to its longest entry and
	# the golfer beside it stops leading the shelf; trimmed to an ellipsis
	# instead, the menu still lists every name in full.
	_skin_picker.fit_to_longest_item = false
	_skin_picker.clip_text = true
	_skin_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_skin_picker.set_meta("editable_while_playing", true)
	_skin_picker.item_selected.connect(_on_golfer_skin_selected)
	column.add_child(_skin_picker)


## The Re-color Group section: a vertical scrollable column of
## Visiting-Golfer-styled colour buttons for each Re-color Group of the skin
## the owner wears. The column sits directly to the right of the sprite preview
## so the golfer and their palette read as one unit.
func _build_skin_group_controls() -> void:
	_skin_controls = VBoxContainer.new()
	_skin_controls.name = "SkinGroupControls"
	_skin_controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skin_controls.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Wide enough for a Visiting Golfer card plus a little breathing room for the scrollbar.
	_skin_controls.custom_minimum_size.x = VisitorCardButton.BUTTON_SIZE.x + 16
	_skin_controls.add_theme_constant_override("separation", 4)
	var edit_page := player_tab.pages[PlayerTab.PAGE_EDIT]
	# Place immediately to the right of the sprite preview so the palette
	# reads as the golfer's own colours.
	var preview_idx := -1
	if is_instance_valid(_skin_preview_box):
		var preview_col := _skin_preview_box.get_parent()
		if preview_col != null and preview_col.get_parent() == edit_page:
			preview_idx = preview_col.get_index()
	if preview_idx >= 0:
		edit_page.add_child(_skin_controls)
		edit_page.move_child(_skin_controls, preview_idx + 1)
	else:
		edit_page.add_child(_skin_controls)

	var scroll := ScrollContainer.new()
	scroll.name = "SkinGroupScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	_skin_controls.add_child(scroll)
	_skin_group_scroll = scroll

	_skin_group_columns = VBoxContainer.new()
	_skin_group_columns.name = "SkinGroupColumns"
	_skin_group_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_group_columns.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_skin_group_columns.add_theme_constant_override("separation", 4)
	scroll.add_child(_skin_group_columns)
	_refresh_skin_controls()


## The ground the owner's own golfer works between rounds.
##
## The owner is on the course even when they are not playing: they walk the
## ground they were given, pulling weeds and greeting the golfers they meet.
## The button asks main.gd for a click on the course, the same way a staff
## member's designated area is moved.
func _build_work_area_column() -> void:
	_work_area_label = Label.new()
	_work_area_label.name = "OwnerWorkArea"
	_work_area_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_work_area_label)

	_work_area_button = Button.new()
	_work_area_button.name = "MoveWorkArea"
	_work_area_button.text = "Move work area"
	_work_area_button.tooltip_text = "Choose the ground your golfer works when they are not playing."
	_work_area_button.pressed.connect(func(): owner_area_move_requested.emit())
	content.add_child(_work_area_button)

	_refresh_work_area()

## Career Mode export controls on Golfers -> Play Course: save either the open
## course or the owner's golfer for standalone Tournament Mode.
func _build_tournament_play_export_column() -> void:
	_label("Tournament Mode")
	var save_course_btn := _button("Save Course for Tournament", _on_save_course_for_tournament)
	save_course_btn.name = "SaveTournamentCourseButton"
	save_course_btn.tooltip_text = "Export this course so you can select it on the Start Tournament screen from the Main Menu."
	var save_golfer_btn := _button("Save Golfer for Tournament", _on_save_golfer_for_tournament)
	save_golfer_btn.name = "SaveTournamentGolferButton"
	save_golfer_btn.tooltip_text = "Export your golfer's skills, traits and appearance so you can play as them in Tournament Mode."

## Career Mode export control on Golfers -> Edit Player.
func _build_tournament_golfer_export_column() -> void:
	_label("Export this golfer for Main Menu tournaments.")
	var save_golfer_btn := _button("Save Golfer for Tournament", _on_save_golfer_for_tournament)
	save_golfer_btn.name = "SaveEditGolferForTournamentButton"
	save_golfer_btn.tooltip_text = "Export your golfer's skills, traits and appearance for standalone Tournament Mode."

func _on_save_course_for_tournament() -> void:
	var result := TournamentLibrary.save_career_course()
	if bool(result.get("ok", false)):
		EventBus.notify(
			"Saved '%s' (%d holes, Par %d) for Tournament Mode!" % [
				str(result.get("name", "Course")),
				int(result.get("hole_count", 0)),
				int(result.get("par", 0)),
			],
			"success"
		)
	else:
		EventBus.notify(str(result.get("error", "Could not save course for Tournament Mode.")), "warning")

func _on_save_golfer_for_tournament() -> void:
	_persist_player_profile()
	var worn_skin := GolferSkins.player_skin() if GolferSkins != null else null
	var chosen_skin_id := worn_skin.id if worn_skin != null else GameManager.player_skin_id
	var skin_colors := TournamentLibrary.capture_skin_colors(GameManager.player_profile, chosen_skin_id)
	var result := TournamentLibrary.save_career_golfer(GameManager.player_profile, chosen_skin_id, skin_colors)
	if bool(result.get("ok", false)):
		EventBus.notify(
			"Saved golfer '%s' for Tournament Mode!" % str(result.get("name", "Golfer")),
			"success"
		)
	else:
		EventBus.notify(str(result.get("error", "Could not save golfer for Tournament Mode.")), "warning")

## Where the owner's own golfer works, in words the player can read.
func _refresh_work_area() -> void:
	if _work_area_label == null:
		return
	var owner_manager := GameManager.player_golfer_manager
	if owner_manager == null or owner_manager.area_center.x < 0:
		_work_area_label.text = "Your golfer is not on the course yet."
		return
	var center: Vector2i = owner_manager.area_center
	_work_area_label.text = "Working the ground around tile %d, %d — %d tiles wide." \
		% [center.x, center.y, owner_manager.area_radius]

## The player is choosing a new work area (or has finished choosing one).
## The button says which, and the label reads the ground that is set.
func set_owner_area_mode(choosing: bool) -> void:
	if _work_area_button != null:
		if choosing:
			_work_area_button.text = "Pick a tile…"
			_work_area_button.modulate = UIConstants.COLOR_GOLD
		else:
			_work_area_button.text = "Move work area"
			_work_area_button.modulate = Color.WHITE
	_refresh_work_area()


## Fill the picker and rebuild the vertical list for the skin the owner wears.
## Every group gets a Visiting-Golfer-styled colour button; the column scrolls
## vertically when there are more groups than fit the shelf height.
func _refresh_skin_controls() -> void:
	if _skin_picker == null or _skin_controls == null or _skin_group_columns == null:
		return
	var skins := GolferSkins.library.skins()
	_skin_picker.clear()
	for index in skins.size():
		_skin_picker.add_item(skins[index].display_name)
		_skin_picker.set_item_metadata(index, skins[index].id)
	var worn := GolferSkins.player_skin()
	for index in skins.size():
		if worn != null and skins[index].id == worn.id:
			_skin_picker.select(index)
	for child in _skin_group_columns.get_children():
		_skin_group_columns.remove_child(child)
		child.queue_free()
	if worn == null:
		return

	for group in worn.group_list():
		var group_id := int(group.get("id", 0))
		var group_name := str(group.get("name", "Group"))
		var group_color: Color = group.get("color", Color.WHITE)
		var group_column := VBoxContainer.new()
		group_column.name = "SkinGroupColumn%d" % group_id
		group_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		group_column.set_meta("skin_group_column", true)
		_skin_group_columns.add_child(group_column)

		var color_row := HBoxContainer.new()
		color_row.name = "SkinGroupRow%d" % group_id
		color_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		color_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		color_row.add_theme_constant_override("separation", 4)
		group_column.add_child(color_row)

		var name_label := Label.new()
		name_label.name = "SkinGroupName%d" % group_id
		name_label.text = group_name
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Keep for backward-compat tests; the visible name is drawn on the button itself.
		name_label.visible = false
		color_row.add_child(name_label)

		var swatch := ColorPickerButton.new()
		swatch.name = "SkinGroupColor%d" % group_id
		swatch.text = group_name
		swatch.color = group_color
		swatch.edit_alpha = false
		swatch.custom_minimum_size = VisitorCardButton.BUTTON_SIZE
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		swatch.focus_mode = Control.FOCUS_ALL
		swatch.tooltip_text = "The colour %s is drawn in on this skin" % group_name
		swatch.set_meta("editable_while_playing", true)
		swatch.set_meta(GOLFER_SKILL_CARD_META, true)
		# ColorPickerButton hides its native text behind the color preview in some themes;
		# ensure the name is always readable by drawing it explicitly and keeping the native text for accessibility/tests.
		swatch.add_theme_font_override("font", VisitorCardButton.FONT)
		swatch.add_theme_font_size_override("font_size", VisitorCardButton.NAME_FONT_SIZE)
		swatch.add_theme_color_override("font_color", VisitorCardButton.CREAM)
		swatch.add_theme_color_override("font_hover_color", VisitorCardButton.NAME_LIT)
		swatch.add_theme_color_override("font_pressed_color", PixelButtonStyle.INK)
		swatch.add_theme_color_override("font_focus_color", VisitorCardButton.NAME_LIT)
		PixelButtonStyle.paint_card(swatch, group_color, 0, 6, VisitorCardButton.CREAM, VisitorCardButton.NAME_LIT)
		swatch.color_changed.connect(_on_skin_group_color_changed.bind(group_id))
		color_row.add_child(swatch)
		# Overlay label guarantees the group name is visible on top of the ColorPickerButton's swatch
		var name_overlay := Label.new()
		name_overlay.name = "SkinGroupLabel%d" % group_id
		name_overlay.text = group_name
		name_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_overlay.add_theme_font_override("font", VisitorCardButton.FONT)
		name_overlay.add_theme_font_size_override("font_size", VisitorCardButton.NAME_FONT_SIZE)
		name_overlay.add_theme_color_override("font_color", VisitorCardButton.CREAM)
		name_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		swatch.add_child(name_overlay)
	_refresh_skin_preview()


## The first column is a scaled pixel-art golfer rather than a tiny picker icon,
## with the skin they wear picked directly beneath the sprite (see
## _build_skin_picker). Its Control provides the available rectangle; the Node2D
## preview is centered and scaled to use most of that height without cropping
## the sprite. Returns the column so the picker can join it.
func _build_skin_preview(edit_page: HBoxContainer) -> VBoxContainer:
	content = PlayerTab.add_column(edit_page, 116)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skin_preview_box = Control.new()
	_skin_preview_box.name = "SkinPreview"
	_skin_preview_box.custom_minimum_size = Vector2(100, 60)
	_skin_preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skin_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skin_preview_box.clip_contents = true
	content.add_child(_skin_preview_box)

	_skin_preview = Golfer.new()
	_skin_preview.name = "SkinPreviewGolfer"
	_skin_preview.set_physics_process(false)
	_skin_preview_box.add_child(_skin_preview)
	_skin_preview_box.resized.connect(_layout_skin_preview)
	return content


func _refresh_skin_preview() -> void:
	_refresh_round_player_preview()
	if _skin_preview == null or _skin_preview_box == null:
		return
	_skin_preview.player_profile = draft
	if not _skin_preview.use_skin_sprites():
		return
	# The preview is not part of GolferManager's live-golfer list, so refresh it
	# explicitly when the player switches skins or changes one of their colours.
	_skin_preview.refresh_skin_sprites()
	var sprite := _skin_preview.sprite_node()
	if sprite != null and sprite.sprite_frames.has_animation("idle_south"):
		sprite.play("idle_south")
	_layout_skin_preview()


func _layout_skin_preview() -> void:
	if not is_instance_valid(_skin_preview) or not is_instance_valid(_skin_preview_box):
		return
	var available := _skin_preview_box.size - Vector2(12, 12)
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var sprite := _skin_preview.sprite_node()
	var sprite_size := Vector2(48, 48)
	if sprite != null and sprite.sprite_frames != null:
		var animation: StringName = sprite.animation
		if sprite.sprite_frames.has_animation("idle_south"):
			animation = &"idle_south"
		if sprite.sprite_frames.has_animation(animation) and sprite.sprite_frames.get_frame_count(animation) > 0:
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation, 0)
			if texture != null:
				sprite_size = texture.get_size()
	if sprite_size.x <= 0.0 or sprite_size.y <= 0.0:
		return
	var scale_factor := minf(available.x / sprite_size.x, available.y / sprite_size.y)
	_skin_preview.scale = Vector2.ONE * scale_factor
	# Golfer sprites sit eight source pixels above the golfer's origin.
	_skin_preview.position = Vector2(_skin_preview_box.size.x * 0.5,
		_skin_preview_box.size.y * 0.5 + 8.0 * scale_factor)


func _refresh_round_player_preview() -> void:
	if not is_instance_valid(_round_player_preview) or draft == null:
		return
	_round_player_preview.player_profile = draft
	if _round_player_preview.use_skin_sprites():
		_round_player_preview.refresh_skin_sprites()
		var sprite := _round_player_preview.sprite_node()
		if sprite != null and sprite.sprite_frames != null \
				and sprite.sprite_frames.has_animation("idle_south"):
			sprite.play("idle_south")
	else:
		_round_player_preview._update_visual()
	_layout_round_player_preview()


func _layout_round_player_preview() -> void:
	_layout_golfer_portrait(_round_player_preview, _round_player_preview_box)


func _layout_golfer_portrait(golfer: Golfer, box: Control) -> void:
	if not is_instance_valid(golfer) or not is_instance_valid(box):
		return
	var available := box.size - Vector2(6, 6)
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var sprite := golfer.sprite_node()
	var sprite_size := Vector2(48, 48)
	if sprite != null and sprite.sprite_frames != null:
		var animation: StringName = sprite.animation
		if sprite.sprite_frames.has_animation("idle_south"):
			animation = &"idle_south"
		if sprite.sprite_frames.has_animation(animation) and sprite.sprite_frames.get_frame_count(animation) > 0:
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation, 0)
			if texture != null:
				sprite_size = texture.get_size()
	if sprite_size.x <= 0.0 or sprite_size.y <= 0.0:
		return
	var scale_factor := minf(available.x / sprite_size.x, available.y / sprite_size.y)
	golfer.scale = Vector2.ONE * scale_factor
	golfer.position = Vector2(box.size.x * 0.5, box.size.y * 0.5 + 8.0 * scale_factor)


func _create_add_golfer_icon() -> Texture2D:
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var icon_color := Color("f0bf59")
	image.fill_rect(Rect2i(8, 3, 4, 14), icon_color)
	image.fill_rect(Rect2i(3, 8, 14, 4), icon_color)
	return ImageTexture.create_from_image(image)


func _create_add_golfer_button() -> void:
	if not is_instance_valid(_round_players_row) or is_instance_valid(_add_golfer_button):
		return
	_add_golfer_button = Button.new()
	_add_golfer_button.name = "AddGolferButton"
	_add_golfer_button.tooltip_text = "Add a pro golfer to this round (up to three)."
	_add_golfer_button.custom_minimum_size = Vector2(52, 36)
	_add_golfer_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_golfer_button.icon = _create_add_golfer_icon()
	_add_golfer_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_golfer_button.pressed.connect(_open_add_golfer_menu)
	_round_players_row.add_child(_add_golfer_button)
	_pro_menu = PopupMenu.new()
	_pro_menu.id_pressed.connect(_on_add_golfer_selected)
	_add_golfer_button.add_child(_pro_menu)


func _make_pro_portrait(pro_name: String) -> void:
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = 52
	card.add_theme_constant_override("separation", 0)
	var box := Control.new()
	box.name = "ProPreview"
	box.custom_minimum_size = Vector2(52, 66)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	card.add_child(box)
	var preview := Golfer.new()
	preview.name = pro_name.replace(" ", "") + "Preview"
	preview.golfer_tier = GolferTier.Tier.PRO
	preview.golfer_name = pro_name
	preview.defer_skin_setup = true
	preview.set_physics_process(false)
	preview.set_process(false)
	box.add_child(preview)
	preview.input_pickable = false
	if not preview.use_skin_sprites():
		preview._update_visual()
	_pro_preview_nodes[pro_name] = preview
	box.resized.connect(_layout_golfer_portrait.bind(preview, box))
	var remove_row := HBoxContainer.new()
	remove_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var remove := Button.new()
	remove.name = "RemoveProButton"
	remove.text = "×"
	remove.tooltip_text = "Remove %s from this round" % pro_name
	remove.custom_minimum_size = Vector2(24, 20)
	remove.add_theme_font_size_override("font_size", 9)
	remove.pressed.connect(_remove_round_pro.bind(pro_name))
	remove_row.add_child(remove)
	card.add_child(remove_row)
	card.tooltip_text = pro_name
	_pro_roster.add_child(card)


func _open_add_golfer_menu() -> void:
	if not is_instance_valid(_pro_menu) or not is_instance_valid(_add_golfer_button):
		return
	_pro_menu.clear()
	for index in PROS.size():
		if not _selected_pros.has(PROS[index]):
			_pro_menu.add_item(PROS[index], index)
	if _pro_menu.item_count == 0:
		return
	var menu_position := _add_golfer_button.global_position + Vector2(0, _add_golfer_button.size.y)
	_pro_menu.popup(Rect2i(Vector2i(menu_position), Vector2i(maxi(160, int(_add_golfer_button.size.x)), 0)))


func _on_add_golfer_selected(pro_index: int) -> void:
	if pro_index < 0 or pro_index >= PROS.size() or _selected_pros.size() >= 3:
		return
	var pro_name: String = PROS[pro_index]
	if not _selected_pros.has(pro_name):
		_selected_pros.append(pro_name)
	_refresh_pro_roster()


func _remove_round_pro(pro_name: String) -> void:
	_selected_pros.erase(pro_name)
	_refresh_pro_roster()


func _refresh_pro_roster() -> void:
	if not is_instance_valid(_pro_roster):
		return
	for child in _pro_roster.get_children():
		_pro_roster.remove_child(child)
		child.queue_free()
	_pro_preview_nodes.clear()
	for pro_name in _selected_pros:
		_make_pro_portrait(pro_name)
	if _selected_pros.size() >= 3:
		if is_instance_valid(_add_golfer_button):
			_round_players_row.remove_child(_add_golfer_button)
			_add_golfer_button.queue_free()
			_add_golfer_button = null
			_pro_menu = null
	else:
		_create_add_golfer_button()
		if is_instance_valid(_add_golfer_button):
			_add_golfer_button.tooltip_text = "Add a pro golfer to this round (%d of 3 added)." % _selected_pros.size()


## Wear one of the Golfer Skins: it belongs to the player rather than to the
## round, so GolferSkins writes the choice to the user settings at once.
func _on_golfer_skin_selected(index: int) -> void:
	if _skin_picker == null or index < 0 or index >= _skin_picker.item_count:
		return
	var chosen := GolferSkins.library.get_skin(str(_skin_picker.get_item_metadata(index)))
	if chosen == null:
		return
	GolferSkins.set_player_skin(chosen)
	for group in chosen.group_list():
		var key := GolferSkin.profile_key_for_group(str(group.get("name", "")))
		if not key.is_empty():
			var group_color: Color = group.get("color", Color.WHITE)
			draft.appearance[key] = group_color.to_html(false)
	_persist_player_profile()
	GolferSkins.skins_changed.emit()
	_refresh_skin_controls()


## Re-colour one Re-color Group of the skin the owner wears. The skin is the
## player's own from here on (a shipped skin is copied to user://golfer_skins
## first), and the profile's matching appearance key keeps up with it.
func _on_skin_group_color_changed(color: Color, group_id: int) -> void:
	var skin := GolferSkins.player_skin()
	if skin == null:
		return
	if not GolferSkins.library.ensure_editable(skin):
		return
	if not skin.set_group_color(group_id, color):
		return
	GolferSkins.library.save_skin(skin)
	GolferSkins.skins_changed.emit()
	var key := GolferSkin.profile_key_for_group(str(skin.group_by_id(group_id).get("name", "")))
	if not key.is_empty():
		draft.appearance[key] = color.to_html(false)
	_persist_player_profile()
	_refresh_skin_preview()


## With the Save player button removed, player details and fallback appearance
## colours persist as they are edited. During a round GameManager already holds
## the live draft, so keep that object in place for the golfer using it.
func _on_player_name_changed(_value: String) -> void:
	_persist_player_profile()


func _on_profile_color_changed(color: Color, key: String) -> void:
	if draft == null or not draft.appearance.has(key):
		return
	draft.appearance[key] = color.to_html(false)
	_persist_player_profile()


func _persist_player_profile() -> void:
	if draft == null:
		return
	if is_instance_valid(name_edit):
		var edited_name := name_edit.text.strip_edges()
		draft.golfer_name = edited_name if not edited_name.is_empty() else "Course Owner"
	if busy:
		GameManager.player_profile = draft
	else:
		GameManager.player_profile = PlayerGolferProfile.from_data(draft.serialize())
	# The owner's own golfer is on the course: they wear the profile as it
	# is edited.
	var owner_manager := GameManager.player_golfer_manager
	if owner_manager != null:
		owner_manager.refresh_profile()
	_refresh_round_player_preview()


## The PlayerGolferProfile colour keys the Golfer Skin the owner wears does not
## name as a Re-color Group: those are the player's own colours, with no sprite
## to change.
func _standalone_profile_colors() -> Array:
	var worn := GolferSkins.player_skin()
	if worn == null:
		return PlayerGolferProfile.COLORS.duplicate()
	var named := []
	for group in worn.group_list():
		var key := GolferSkin.profile_key_for_group(str(group.get("name", "")))
		if not key.is_empty():
			named.append(key)
	var remaining := []
	for key in PlayerGolferProfile.COLORS:
		if not named.has(key):
			remaining.append(key)
	return remaining


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	if is_instance_valid(player_tab):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	content.add_child(button)
	return button

## Point the shot-type buttons at the owner: the Play Course tab runs the row
## along its top, so a round only has to listen for presses and mirror the
## golfer's shot back onto it. Without the tab (isolated tools and tests) the row
## is built into the panel instead, so shot selection works the same way.
func _build_shot_controls() -> void:
	if is_instance_valid(player_tab):
		shot_bar = player_tab.shot_bar
	else:
		shot_bar = ShotTypeBar.new()
		content.add_child(shot_bar)
	if not shot_bar.shape_selected.is_connected(_on_shot_shape_selected):
		shot_bar.shape_selected.connect(_on_shot_shape_selected)
	shot_bar.select_shape(player.player_shape if is_instance_valid(player) else 0)
	shot_bar.set_ready(false)

func _on_shot_shape_selected(shape: int) -> void:
	if is_instance_valid(player):
		player.player_shape = shape

func attach_player_tab(tab: PlayerTab) -> void:
	player_tab = tab
	open_setup()

## Hand the manager the top-left score card the HUD docked in the corner.
func attach_scores_panel(panel: RoundScoresPanel) -> void:
	scores = panel

func open_setup() -> void:
	if is_instance_valid(player_tab):
		if busy:
			# Mid-round: jump to the Play Course tab showing the aiming HUD.
			player_tab.select(PlayerTab.PAGE_PLAY)
			return
		_build_setup()
		return
	if busy or GameManager.is_paused:
		return
	if GameManager.get_open_hole_count() == 0:
		EventBus.notify("Open at least one complete hole before playing.", "warning")
		return
	if GameManager.tournament_manager and GameManager.tournament_manager.is_tournament_in_progress():
		EventBus.notify("Tournament running - Play It Out on the Tournament shelf first.", "warning")
		return
	busy = true
	previous_mode = GameManager.current_mode
	previous_speed = GameManager.current_speed
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	session_opened.emit()
	_build_setup()

## A Golfer Skill as a selectable name plate in the Visiting Golfers visual
## language: the same pixel font and card frame on a narrower footprint. Off is
## a quiet outlined card; On uses a solid green fill and dark caption so the
## enabled state stands out without a separate checkbox.
func _golfer_skill_button(skill_name: String, is_on: bool) -> Button:
	var button := Button.new()
	button.text = skill_name
	button.toggle_mode = true
	button.button_pressed = is_on
	button.custom_minimum_size = GOLFER_SKILL_BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_description = "%s golfer skill. Toggle on or off." % skill_name
	button.set_meta(GOLFER_SKILL_CARD_META, true)
	button.add_theme_font_override("font", VisitorCardButton.FONT)
	button.add_theme_font_size_override("font_size", VisitorCardButton.NAME_FONT_SIZE)
	PixelButtonStyle.paint_choice(button, GOLFER_SKILL_ACCENT)
	# Strengthen the selected half of the shared choice style: a solid visiting
	# green body makes an enabled skill unmistakable beside the quiet Off cards.
	button.add_theme_stylebox_override("pressed", PixelButtonStyle.card_style(
		GOLFER_SKILL_ACCENT.lightened(0.18), PixelButtonStyle.State.PRESSED,
		GOLFER_SKILL_ACCENT, 0, 0, 0))
	button.add_theme_stylebox_override("hover_pressed", PixelButtonStyle.card_style(
		GOLFER_SKILL_ACCENT.lightened(0.28), PixelButtonStyle.State.HOVER,
		GOLFER_SKILL_ACCENT.lightened(0.12), 0, 0, 0))
	button.add_theme_color_override("font_color", VisitorCardButton.CREAM)
	for state in ["hover", "focus"]:
		button.add_theme_color_override("font_%s_color" % state, VisitorCardButton.NAME_LIT)
	for state in ["pressed", "hover_pressed"]:
		button.add_theme_color_override("font_%s_color" % state, PixelButtonStyle.INK)
	button.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)
	return button


func _style_player_control(control: Control, accent: Color = Color(0.28, 0.78, 0.55)) -> void:
	# Chunky, square-corner pixel UI: dark enamel surfaces, hard outlines and
	# high-contrast mint/gold accents instead of the default rounded widgets.
	control.add_theme_color_override("font_color", Color("f4edcf"))
	control.add_theme_color_override("font_hover_color", Color("ffffff"))
	control.add_theme_color_override("font_pressed_color", Color("14231f"))
	control.add_theme_font_size_override("font_size", 12)
	if control is Button:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("233a35") if state != "pressed" else accent
			box.border_color = accent if state in ["hover", "pressed"] else Color("526b5e")
			box.set_border_width_all(2)
			box.set_corner_radius_all(0)
			box.content_margin_left = 8
			box.content_margin_right = 8
			box.content_margin_top = 5
			box.content_margin_bottom = 5
			control.add_theme_stylebox_override(state, box)

func _build_setup() -> void:
	_selected_pros.clear()
	_add_golfer_button = null
	_pro_roster = null
	_round_players_row = null
	_pro_menu = null
	_pro_preview_nodes.clear()
	_round_player_preview = null
	_round_player_preview_box = null
	draft = PlayerGolferProfile.from_data(GameManager.player_profile.serialize())
	# A rebuilt page means no round is showing: drop whatever scores the last
	# one left on the card.
	if is_instance_valid(scores):
		scores.dismiss()
	var edit_page: HBoxContainer = null
	if is_instance_valid(player_tab):
		player_tab.set_playing(false)
		for index in [PlayerTab.PAGE_EDIT, PlayerTab.PAGE_SKILLS]:
			player_tab.clear_page(index)
		player_tab.clear_aim_page()
		# The management tournament panel survives on the Play Course page.
		player_tab.clear_play_page()
		edit_page = player_tab.pages[PlayerTab.PAGE_EDIT]
		var preview_column := _build_skin_preview(edit_page)
		# The skin the owner wears is chosen under the sprite that wears it, so
		# the golfer leads the shelf with the picker on its feet. It stays
		# editable during a round - dressing the owner is not part of the play
		# loop being protected (see start_round).
		_build_skin_picker(preview_column)
		# Group colours sit directly to the right of the sprite in a vertical
		# scrollable column styled like the Visiting Golfer cards.
		_build_skin_group_controls()
		content = PlayerTab.add_column(edit_page, 200)
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_make_panel(true)

	name_edit = LineEdit.new()
	name_edit.name = "PlayerName"
	name_edit.placeholder_text = "Player name"
	name_edit.accessibility_name = "Player name"
	name_edit.max_length = 32
	name_edit.text = draft.golfer_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_on_player_name_changed)
	content.add_child(name_edit)
	if is_instance_valid(player_tab):
		# The rest of who the golfer is takes the next column. The shelf has no
		# vertical scroll, so a column of this page holds about
		# four controls before it would grow past the bottom bar.
		content = PlayerTab.add_column(edit_page, 200)
		var profession_edit := LineEdit.new()
		profession_edit.name = "PlayerProfession"
		profession_edit.placeholder_text = "Profession"
		profession_edit.tooltip_text = "What your golfer does away from the course"
		profession_edit.text = draft.profession
		profession_edit.text_changed.connect(func(value: String):
			draft.profession = value.left(48)
			_persist_player_profile())
		content.add_child(profession_edit)
		var age_spin := SpinBox.new()
		age_spin.name = "PlayerAge"
		age_spin.prefix = "Age"
		age_spin.tooltip_text = "Your golfer's age, from 18 to 100"
		age_spin.min_value = 18
		age_spin.max_value = 100
		age_spin.value = draft.age
		age_spin.value_changed.connect(func(value: float):
			draft.age = int(value)
			_persist_player_profile())
		content.add_child(age_spin)
		var gender_picker := OptionButton.new()
		gender_picker.name = "PlayerGender"
		gender_picker.tooltip_text = "Your golfer's gender"
		gender_picker.add_item("Male")
		gender_picker.add_item("Female")
		gender_picker.select(draft.gender)
		gender_picker.item_selected.connect(func(value: int):
			draft.gender = value
			_persist_player_profile())
		content.add_child(gender_picker)
		var marital_picker := OptionButton.new()
		marital_picker.name = "PlayerMaritalStatus"
		marital_picker.tooltip_text = "Your golfer's marital status"
		for value in ["Single", "Married", "Divorced", "Widowed"]:
			marital_picker.add_item(value)
		marital_picker.select(draft.marital_status)
		marital_picker.item_selected.connect(func(value: int):
			draft.marital_status = value
			_persist_player_profile())
		content.add_child(marital_picker)
		# The owner's own golfer is on the course: the ground they work when
		# they are not playing gets a column of its own.
		content = PlayerTab.add_column(edit_page, 220)
		_build_work_area_column()
		if not GameManager.is_tournament_mode:
			content = PlayerTab.add_column(edit_page, 210)
			content.add_theme_constant_override("separation", 4)
			_build_tournament_golfer_export_column()
		var traits_column: VBoxContainer = null
		for slot in GolferAttributes.TRAIT_KEYS.size():
			if slot % TOGGLES_PER_COLUMN == 0:
				traits_column = PlayerTab.add_column(edit_page, 210)
				traits_column.add_theme_constant_override("separation", 2)
			var key: String = GolferAttributes.TRAIT_KEYS[slot]
			var trait_toggle := CheckButton.new()
			trait_toggle.text = GolferAttributes.TRAIT_NAMES[key]
			trait_toggle.button_pressed = draft.traits[key]
			trait_toggle.toggled.connect(func(on: bool, trait_key: String = key):
				draft.traits[trait_key] = on
				_persist_player_profile())
			traits_column.add_child(trait_toggle)
	# The player's own colours. The five the Golfer Skins name - Shirt, Pants,
	# Cap, Hair, Skin - are the colours of that skin's Re-color Groups and are
	# edited above (they follow into these fields); what is left here is the
	# appearance the polygon golfer falls back on when a skin has no sprites.
	var standalone := _standalone_profile_colors()
	var color_index := 0
	for key in standalone:
		if is_instance_valid(player_tab) and color_index % 3 == 0:
			content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_EDIT], 260)
		color_index += 1
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := Label.new()
		label.text = key.replace("_", " ").capitalize()
		label.custom_minimum_size.x = 140 if is_instance_valid(player_tab) else 180
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var color := ColorPickerButton.new()
		color.color = Color(draft.appearance[key])
		color.edit_alpha = false
		color.custom_minimum_size = Vector2(100, 28)
		color.color_changed.connect(_on_profile_color_changed.bind(str(key)))
		row.add_child(color)
	if is_instance_valid(player_tab):
		if not GameManager.is_tournament_mode:
			# One round setup: the owner's golfer sits beside a roster of up to
			# three pros, with one start button for either practice or a group.
			content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_PLAY], 220)
			content.add_theme_constant_override("separation", 4)
			mode_picker = OptionButton.new()
			for title in ["Practice round", "Play vs a Pro"]:
				mode_picker.add_item(title)
			mode_picker.hide() # Retained for standalone setup and legacy callers.
			content.add_child(mode_picker)
			pro_picker = OptionButton.new()
			for pro in PROS:
				pro_picker.add_item(pro)
			pro_picker.hide()
			content.add_child(pro_picker)

			var players_row := HBoxContainer.new()
			_round_players_row = players_row
			players_row.add_theme_constant_override("separation", 4)
			players_row.custom_minimum_size.y = 88
			content.add_child(players_row)
			var owner_card := VBoxContainer.new()
			owner_card.add_theme_constant_override("separation", 0)
			players_row.add_child(owner_card)
			_round_player_preview_box = Control.new()
			_round_player_preview_box.name = "RoundPlayerPreview"
			_round_player_preview_box.custom_minimum_size = Vector2(52, 66)
			_round_player_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_round_player_preview_box.clip_contents = true
			owner_card.add_child(_round_player_preview_box)
			_round_player_preview = Golfer.new()
			_round_player_preview.name = "RoundPlayerGolferPreview"
			_round_player_preview.set_physics_process(false)
			_round_player_preview_box.add_child(_round_player_preview)
			_round_player_preview.input_pickable = false
			_round_player_preview_box.resized.connect(_layout_round_player_preview)
			_refresh_round_player_preview()

			_pro_roster = HBoxContainer.new()
			_pro_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_pro_roster.add_theme_constant_override("separation", 4)
			players_row.add_child(_pro_roster)
			_refresh_pro_roster()

			var round_button := _button("Start Round", _start_embedded.bind(0))
			round_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			round_button.set_meta("owner_round_start", true)

			# Export the Career course or golfer for standalone Tournament Mode.
			content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_PLAY], 216)
			content.add_theme_constant_override("separation", 3)
			_build_tournament_play_export_column()
		var skills_page := player_tab.pages[PlayerTab.PAGE_SKILLS]
		# Three untitled visitor-style name plates lead the shelf, ahead of the
		# points-based Golf Skills.
		var golfer_skills_column := PlayerTab.add_column(skills_page, GOLFER_SKILL_BUTTON_SIZE.x)
		golfer_skills_column.add_theme_constant_override("separation", 2)
		for key in GolferAttributes.GOLFER_SKILL_KEYS:
			var skill_name: String = GolferAttributes.GOLFER_SKILL_NAMES[key]
			var skill_toggle := _golfer_skill_button(skill_name, bool(draft.golfer_skills[key]))
			skill_toggle.name = "GolferSkill%s" % key.capitalize()
			skill_toggle.toggled.connect(func(on: bool, skill_key: String = key):
				draft.golfer_skills[skill_key] = on
				_persist_player_profile())
			golfer_skills_column.add_child(skill_toggle)
		content = PlayerTab.add_column(skills_page, 250)
	else:
		_label("Round format")
		mode_picker = OptionButton.new()
		for title in ["Practice round", "Play vs a Pro"]:
			mode_picker.add_item(title)
		content.add_child(mode_picker)
		pro_picker = OptionButton.new()
		for pro in PROS:
			pro_picker.add_item(pro)
		pro_picker.disabled = true
		content.add_child(pro_picker)
		mode_picker.item_selected.connect(func(index: int): pro_picker.disabled = index != 1)
	points_label = _label("")
	_label("Each point adds 10% bonus. Maximum per skill: 990%.")
	skill_labels.clear()
	for i in PlayerGolferProfile.SKILLS.size():
		# Keep the allocation summary with the first two skills, then distribute
		# the remaining skills evenly across the next two shelf columns (2 / 4 / 4).
		if is_instance_valid(player_tab) and (i == 2 or i == 6):
			content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_SKILLS], 290)
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		skill_labels.append(label)
		for change in [-1, 1]:
			var button := Button.new()
			button.text = "+" if change == 1 else "−"
			button.pressed.connect(allocate_skill.bind(i, change))
			row.add_child(button)
	if is_instance_valid(player_tab):
		# Apply one consistent pixel-art visual language to both owner tabs.
		for page_index in [PlayerTab.PAGE_EDIT, PlayerTab.PAGE_SKILLS]:
			for widget in player_tab.pages[page_index].find_children("*", "Control", true, false):
				if not widget.has_meta(GOLFER_SKILL_CARD_META):
					_style_player_control(widget, Color("f0bf59") if page_index == PlayerTab.PAGE_SKILLS else Color("76d6a2"))
				if widget == points_label:
					widget.add_theme_color_override("font_color", Color("f0bf59"))
					widget.add_theme_font_size_override("font_size", 14)
		player_tab.restage_persistent()
		start_button = null
	else:
		start_button = _button("Tee off", start_round)
		_button("Cancel", leave_round)
	_refresh_skills()

func allocate_skill(index: int, change: int) -> bool:
	if draft == null:
		draft = PlayerGolferProfile.from_data(GameManager.player_profile.serialize())
	if not draft.allocate(index, change, true):
		return false
	_save_skills()
	_refresh_skills()
	return true

func _save_skills() -> void:
	if GameManager.player_profile == null:
		GameManager.player_profile = PlayerGolferProfile.new()
	GameManager.player_profile.points = draft.points.duplicate()
	if is_instance_valid(player):
		player.player_profile = GameManager.player_profile
		player.sync_player_profile_skills()
		if player.awaits_player_shot():
			update_aim_guide()
	if GameManager.tournament_manager and GameManager.tournament_manager.has_method("sync_player_skills"):
		GameManager.tournament_manager.sync_player_skills()

func _refresh_skills() -> void:
	points_label.text = "%d of 10 points remaining" % draft.remaining()
	for i in skill_labels.size():
		if i < PlayerGolferProfile.SKILLS.size():
			skill_labels[i].text = "%s: %d%%" % [PlayerGolferProfile.SKILLS[i], draft.points[i] * 10]
	# Unspent points never hold a round up, so the badge on the Player Skills
	# button is what tells the owner points are still waiting to be allocated.
	if is_instance_valid(player_tab):
		player_tab.refresh_skill_badge()

func _start_embedded(kind: int) -> void:
	if busy or GameManager.is_paused:
		EventBus.notify("Finish the current round and unpause before starting.", "info")
		return
	if GameManager.get_open_hole_count() == 0:
		EventBus.notify("Open at least one complete hole before playing.", "warning")
		return
	if GameManager.tournament_manager and GameManager.tournament_manager.is_tournament_in_progress():
		EventBus.notify("Tournament running - Play It Out on the Tournament shelf first.", "warning")
		return
	busy = true
	previous_mode = GameManager.current_mode
	previous_speed = GameManager.current_speed
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	mode_picker.select(clampi(kind, 0, maxi(0, mode_picker.item_count - 1)))
	# Preserve the old Play-vs-Pro entry point for callers outside the new
	# roster UI; the embedded Start Round button uses the selected roster.
	if kind == 1 and _selected_pros.is_empty() and pro_picker.item_count > 0:
		_selected_pros.append(PROS[clampi(pro_picker.selected, 0, PROS.size() - 1)])
	session_opened.emit()
	start_round()

func start_round() -> void:
	if GameManager.get_open_hole_count() == 0:
		return
	draft.golfer_name = name_edit.text.strip_edges()
	if draft.golfer_name.is_empty():
		draft.golfer_name = "Course Owner"
	draft.initialized = true
	GameManager.player_profile = draft
	if is_instance_valid(player_tab):
		if _selected_pros.is_empty() and mode_picker.selected == 1:
			_selected_pros.append(PROS[clampi(pro_picker.selected, 0, PROS.size() - 1)])
		round_kind = 0 if _selected_pros.is_empty() else 1
	else:
		round_kind = mode_picker.selected
		if round_kind == 1 and _selected_pros.is_empty():
			_selected_pros.append(PROS[clampi(pro_picker.selected, 0, PROS.size() - 1)])
	active = true
	if is_instance_valid(player_tab):
		# Lock the Edit Player page while the round runs - except the Golfer
		# Skin controls, which the player is meant to be able to reach during a
		# round (they only ever change how a golfer is drawn).
		for control in player_tab.pages[PlayerTab.PAGE_EDIT].find_children("*", "Control", true, false):
			if control.has_meta("editable_while_playing"):
				continue
			if control is BaseButton:
				control.disabled = true
			elif control is LineEdit:
				control.editable = false

	# Ensure simulation is active so all golfers can play (day always runs)
	if GameManager.current_mode != GameManager.GameMode.SIMULATING:
		GameManager.set_mode(GameManager.GameMode.SIMULATING)
		GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	# Assign a shared group ID so the player and opponents play as a single group
	var group_id: int = manager.next_group_id
	manager.next_group_id += 1

	# The tee of the first open hole: the owner's own golfer walks there from
	# the ground they were working.
	var course_data = GameManager.course_data
	var tee_pos := Vector2i(-1, -1)
	if course_data and not course_data.holes.is_empty():
		var first_open_idx = manager._find_next_open_hole(0, course_data)
		if first_open_idx < course_data.holes.size():
			tee_pos = course_data.holes[first_open_idx].tee_position

	# The owner's own golfer tees off: the same golfer who works the course
	# between rounds plays this round.
	player = _claim_owner(group_id, tee_pos)
	if player == null:
		# No owner golfer on the course (a tool running the game on its own):
		# fall back to a golfer spawned for the round.
		player = _spawn(draft.golfer_name, GolferTier.Tier.CASUAL, group_id)
		player.player_profile = draft
		player.sync_player_profile_skills()
		player.miss_tendency = 0.0
		player.apply_player_appearance(draft)

	if round_kind == 1:
		for pro_name in _selected_pros:
			_spawn(pro_name, GolferTier.Tier.PRO, group_id)

	# Position all participants at the tee of the first open hole
	if tee_pos.x >= 0:
		var tee_screen = GameManager.terrain_grid.grid_to_screen_center(tee_pos) if GameManager.terrain_grid else Vector2.ZERO
		for golfer in participants:
			golfer.ball_position = tee_pos
			golfer.ball_position_precise = Vector2(tee_pos)
			# The owner's own golfer is already walking to the tee from the
			# ground they were working.
			if golfer == player and golfer.current_state == Golfer.State.WALKING:
				continue
			golfer.global_position = tee_screen
		# Follow the owner on their way to the tee.
		if is_instance_valid(player) and is_instance_valid(camera) \
				and player.current_state == Golfer.State.WALKING:
			camera.focus_on(player.global_position)

	# Immediately trigger group update to determine tee honor and advance first shooter
	if is_instance_valid(manager):
		manager._update_golfers(0.0)

	_make_panel(false)
	_label("PLAY THE COURSE · " + ("Practice" if round_kind == 0 else "Vs Pro"))
	status = _label("")
	if is_instance_valid(scores):
		# The score card names every pro in the group, if more than one was added.
		var score_title := "Practice Round" if round_kind == 0 else "Vs Pro · " + ", ".join(PackedStringArray(_selected_pros))
		scores.begin(score_title)
	if is_instance_valid(player_tab):
		status.add_theme_font_size_override("font_size", 12)
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		content = PlayerTab.add_column(player_tab.aim_page)
	_build_shot_controls()
	if is_instance_valid(player_tab):
		_button("End round / Return to management", leave_round)
		content = PlayerTab.add_column(player_tab.aim_page, 420)
	var instructions := _label("Aim with the mouse · Click to shoot\nYellow arc = intended carry · dotted trail = roll until it stops\nGuide assumes a clean strike; wind, lie and slope still apply.\nPutting on the green is automatic.")
	if is_instance_valid(player_tab):
		instructions.add_theme_font_size_override("font_size", 14)
	else:
		_button("End round / Return to management", leave_round)
	_was_aiming = false

func _spawn(golfer_name: String, tier: int, group_id: int) -> Golfer:
	var golfer := manager.spawn_tournament_golfer(tier, group_id)
	golfer.is_owner_round = true
	golfer.golfer_name = golfer_name
	golfer._update_visual()
	participants.append(golfer)
	return golfer

## The owner's own golfer, taken off their work and put on the first tee.
##
## The golfer who works the course between rounds is the golfer who plays the
## round: they join the group, walk to the tee from the ground they were
## working, and when the round is over they walk back to it (see
## PlayerGolferManager).
func _claim_owner(group_id: int, tee: Vector2i = Vector2i(-1, -1)) -> Golfer:
	var owner_manager := GameManager.player_golfer_manager
	if owner_manager == null:
		return null
	var course_owner := owner_manager.claim_for_round(group_id, tee)
	if course_owner == null:
		return null
	course_owner.player_profile = draft
	course_owner.sync_player_profile_skills()
	course_owner.miss_tendency = 0.0
	course_owner.apply_player_appearance(draft)
	course_owner.golfer_name = draft.golfer_name
	participants.append(course_owner)
	return course_owner

## The owner's own golfer goes back to work on the course.
func _release_owner() -> void:
	var owner_manager := GameManager.player_golfer_manager
	if owner_manager == null:
		return
	owner_manager.release_from_round()

# ============================================================================
# TOURNAMENT AIMING
# ============================================================================
## Aim for the owner's golfer inside a running tournament. The TournamentManager
## still owns the round — it spawns the field, scores it and settles the event —
## so this only mirrors what an owner round does for shot input: the aim guide,
## the shape/punch controls, camera focus and click-to-shoot. Putting off the
## player's turn stays automatic (Golfer.awaits_player_shot() is false on green).
func begin_tournament_aim(owner_golfer: Golfer) -> void:
	if not is_instance_valid(owner_golfer) or owner_golfer.player_profile == null:
		return
	player = owner_golfer
	active = true
	busy = true
	tournament_aim = true
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	previous_speed = GameManager.current_speed
	session_opened.emit()
	# The live tournament board is the score display for this round; the owner's
	# round card would only repeat it, so it steps aside.
	if is_instance_valid(scores):
		scores.dismiss()
	_build_tournament_aim_hud()

## Stop aiming for a tournament golfer. Leaves the golfer on the course — the
## TournamentManager clears it — and leaves the scorecard visible in the Play
## Course tab after the shot controls are removed.
func end_tournament_aim() -> void:
	if not tournament_aim:
		return
	tournament_aim = false
	active = false
	busy = false
	_was_aiming = false
	player = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	if is_instance_valid(_tournament_hud_column):
		_tournament_hud_column.queue_free()
		_tournament_hud_column = null
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	content = null

## Tournament shots use the same aiming page as practice and pro rounds: this
## column is the shot controls only. The live leaderboard keeps the scores in the
## HUD's top-left corner (ScoresDock), above the course view.
func _build_tournament_aim_hud() -> void:
	if is_instance_valid(player_tab):
		player_tab.set_playing(true)
		player_tab.select(PlayerTab.PAGE_PLAY)
		_tournament_hud_column = PlayerTab.add_column(player_tab.aim_page, 320)
		_tournament_hud_column.add_theme_constant_override("separation", 1)
		content = _tournament_hud_column
	else:
		# Fallback for isolated use without the game's Player tab.
		_make_panel(false)
		content.add_theme_constant_override("separation", 6)

	status = _label("Your tournament round")
	status.add_theme_font_size_override("font_size", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_build_shot_controls()
	var settle_button := _button("Settle tournament (skip your round)", _on_settle_tournament)
	settle_button.custom_minimum_size.y = 24
	var instructions := _label("Aim + click · Yellow: carry · Dots: roll")
	instructions.add_theme_font_size_override("font_size", 11)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.tooltip_text = "Aim with the mouse · Click to shoot\nYellow arc = intended carry · dotted trail = roll until it stops\nGuide assumes a clean strike; wind, lie and slope still apply.\nPutting on the green is automatic."
	_was_aiming = false

## Skip the rest of the event from the cards as they stand (the Tournament
## shelf's "Play It Out"). Ends aiming first so the HUD is gone before the field
## is settled.
func _on_settle_tournament() -> void:
	if GameManager.tournament_manager:
		end_tournament_aim()
		GameManager.tournament_manager.simulate_remaining_and_complete()

func _process(delta: float) -> void:
	if is_instance_valid(entry):
		entry.visible = not busy and GameManager.current_mode == GameManager.GameMode.SIMULATING
	if not active or GameManager.is_paused or not is_instance_valid(player):
		# Nothing to aim at: grey the shot row out rather than leave a stale
		# selection lit while the round is paused or over.
		if is_instance_valid(shot_bar):
			shot_bar.set_ready(false)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if is_instance_valid(aim_guide):
			aim_guide.clear()
		return

	if not tournament_aim:
		# Owner round: this manager drives the group simulation forward and
		# decides when the round is over. A tournament round is owned by the
		# TournamentManager, which already advances the golfers and settles the
		# event, so here we only supply aiming for the owner.
		if is_instance_valid(manager):
			manager._update_golfers(delta)

		var finished := true
		for golfer in participants:
			if golfer == player and golfer.is_course_owner:
				# The owner's own golfer is not a guest: they stay on the
				# course and go back to work, so their round is over when
				# they have played every hole, not when they leave.
				if not golfer.round_complete:
					finished = false
				continue
			if golfer.current_state != Golfer.State.FINISHED:
				finished = false
				break
		if finished:
			_show_results()
			return

	var is_ready := player.awaits_player_shot() and (not is_instance_valid(player_tab) or player_tab.selected == PlayerTab.PAGE_PLAY)
	var terrain: int = GameManager.terrain_grid.get_tile(Vector2i(player.ball_position_precise.round())) if GameManager.terrain_grid else -1
	if is_instance_valid(shot_bar):
		shot_bar.set_ready(is_ready)
		# Keep the row on the golfer's shot; a lie that no longer allows it
		# falls back to straight here, exactly as the execution guard does.
		shot_bar.select_shape(player.player_shape)
		shot_bar.update_for_lie(terrain)
		player.player_shape = shot_bar.selected_shape()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if is_ready else Input.CURSOR_ARROW)
	update_aim_guide()

	# Track active shooter: the owner first (a tournament pairing has no local
	# participants list), then any owner-round opponent.
	var active_shooter: Golfer = null
	if player.current_state in [Golfer.State.PREPARING_SHOT, Golfer.State.SWINGING, Golfer.State.WATCHING]:
		active_shooter = player
	else:
		for golfer in participants:
			if golfer != player and golfer.current_state in [Golfer.State.PREPARING_SHOT, Golfer.State.SWINGING, Golfer.State.WATCHING]:
				active_shooter = golfer
				break

	# Focus camera on the player's character only when the user needs to aim their shot
	if is_ready and not _was_aiming:
		if is_instance_valid(player) and is_instance_valid(camera):
			camera.focus_on(player.global_position)
	_was_aiming = is_ready

	# Status text
	var hole_num = mini(player.current_hole + 1, GameManager.course_data.holes.size()) if GameManager.course_data else 1
	var action_text = ""
	if is_ready:
		action_text = "Your turn — Aim and click to shoot"
	elif active_shooter == player:
		action_text = "Automatic putting..." if terrain == TerrainTypes.Type.GREEN else "Taking shot..."
	elif active_shooter != null:
		action_text = "%s is shooting..." % active_shooter.golfer_name
	elif player.current_state == Golfer.State.WALKING:
		action_text = "Walking to ball..."
	elif player.current_state == Golfer.State.LEAVING:
		action_text = "Back to the clubhouse..."
	elif player.current_state == Golfer.State.FINISHED:
		action_text = "You've holed out — waiting for the field"
	else:
		action_text = "Waiting for turn..."

	status.text = "%s · Hole %d · Stroke %d\n%s" % [player.golfer_name, hole_num, player.current_strokes + 1, action_text]
	if not tournament_aim:
		_update_live_scores()

## The top-left card carries the running scores: every player's score against par
## and how many holes they have in. Rows refresh in place, so this can run from
## `_process` without rebuilding the card each frame.
func _update_live_scores() -> void:
	if not is_instance_valid(scores):
		return
	var rows: Array = []
	for golfer in participants:
		if not is_instance_valid(golfer):
			continue
		rows.append({
			"name": golfer.golfer_name + (" (you)" if golfer == player else ""),
			"value": _score_text(golfer),
			"color": _score_color(golfer),
		})
	scores.set_scores(rows)

## "-1 · thru 4" once a card is filling up, "-" until the first hole is in.
func _score_text(golfer: Golfer) -> String:
	if golfer.hole_scores.is_empty():
		return "-"
	return "%s · thru %d" % [_format_diff(golfer.total_strokes - golfer.total_par),
		golfer.hole_scores.size()]

func _score_color(golfer: Golfer) -> Color:
	if golfer.hole_scores.is_empty():
		return UIConstants.COLOR_TEXT_DIM
	return UIConstants.get_score_color(golfer.total_strokes - golfer.total_par)

func _format_diff(diff: int) -> String:
	if diff == 0:
		return "E"
	return "%+d" % diff

## Refresh the guide for the mouse position, snapping the intended resting point
## to the nearest tile centre or vertex. Explicit tile-centre overrides are used
## by tests. The guide clears when the owner is not lining up a shot.
## The world point under the player's pointer. `camera` is authoritative so a
## keyboard/controller pointer aims exactly where its reticle is (see
## InputManager.virtual_pointer); the Node2D helper is the fallback.
func _pointer_world_position() -> Vector2:
	if is_instance_valid(camera):
		return camera.get_mouse_world_position()
	return get_global_mouse_position()


func update_aim_guide(target_override: Vector2i = Vector2i(-1, -1)) -> void:
	if not is_instance_valid(aim_guide):
		return
	var grid: TerrainGrid = GameManager.terrain_grid
	if not active or GameManager.is_paused or not is_instance_valid(grid) or not is_instance_valid(player) or not player.awaits_player_shot():
		aim_guide.clear()
		return
	if is_instance_valid(player_tab) and player_tab.selected != PlayerTab.PAGE_PLAY:
		aim_guide.clear()
		return
	var target: Vector2
	var anchor_type := ""
	if target_override == Vector2i(-1, -1):
		var anchor := grid.snap_world_to_tile_anchor(_pointer_world_position())
		if anchor.is_empty():
			aim_guide.clear()
			return
		target = anchor.point
		anchor_type = anchor.anchor_type
	else:
		# Explicit tile overrides are useful to tests and resolve to that tile's
		# centre in the precise shot-aim coordinate system.
		target = Vector2(target_override)
	aim_guide.show_preview(player.preview_shot_to_rest(target, anchor_type))

func _unhandled_input(event: InputEvent) -> void:
	if not active or GameManager.is_paused:
		return
	if is_instance_valid(player_tab) and player_tab.selected != PlayerTab.PAGE_PLAY:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(player) and player.awaits_player_shot() and GameManager.terrain_grid:
			var grid: TerrainGrid = GameManager.terrain_grid
			var anchor := grid.snap_world_to_tile_anchor(_pointer_world_position())
			if not anchor.is_empty() and player.play_shot_to_rest(anchor.point):
				get_viewport().set_input_as_handled()

func _show_results() -> void:
	active = false
	_was_aiming = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	_make_panel(true)
	participants.sort_custom(func(a: Golfer, b: Golfer): return a.total_strokes < b.total_strokes)
	var result := _result_text()
	if is_instance_valid(scores):
		# The final cards belong on the top-left card with the live scores. The
		# round page keeps the way out of the round.
		scores.begin("Round complete", result)
		for golfer in participants:
			scores.add_heading("%s — %d strokes (%s)" % [golfer.golfer_name,
				golfer.total_strokes, _format_diff(golfer.total_strokes - golfer.total_par)])
			for hole in golfer.hole_scores:
				scores.add_line("Hole %d: %d / Par %d" % [hole.hole, hole.strokes, hole.par])
		_label("ROUND COMPLETE")
		_button("Return to management", leave_round)
		return
	_show_results_on_page(result)

## "Winner: Pro Alex" / "Tie: A, B" once a match is over, empty for a solo round.
func _result_text() -> String:
	if round_kind <= 0 or participants.is_empty():
		return ""
	var winners: Array[String] = []
	for golfer in participants:
		if golfer.total_strokes == participants[0].total_strokes:
			winners.append(golfer.golfer_name)
	return ("Tie: " if winners.size() > 1 else "Winner: ") + ", ".join(winners)

## Scorecard fallback for rounds with no top-left card to write to (isolated
## tools and tests): the round page carries the cards as it always did.
func _show_results_on_page(result: String) -> void:
	_label("ROUND COMPLETE")
	if not result.is_empty():
		var result_label := _label(result)
		result_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if is_instance_valid(player_tab):
		_button("Return to management", leave_round)
	for golfer in participants:
		if is_instance_valid(player_tab):
			content = PlayerTab.add_column(player_tab.aim_page, 280)
		var summary := _label("%s — %d strokes (%s)" % [golfer.golfer_name, golfer.total_strokes, _format_diff(golfer.total_strokes - golfer.total_par)])
		summary.autowrap_mode = TextServer.AUTOWRAP_OFF
		var card_lines := ""
		for i in golfer.hole_scores.size():
			if is_instance_valid(player_tab) and i % 4 == 0 and i > 0:
				_label(card_lines.trim_suffix("\n"))
				content = PlayerTab.add_column(player_tab.aim_page, 280)
				var heading := _label(golfer.golfer_name + " · continued")
				heading.autowrap_mode = TextServer.AUTOWRAP_OFF
				card_lines = ""
			var hole: Dictionary = golfer.hole_scores[i]
			card_lines += "Hole %d: %d / Par %d\n" % [hole.hole, hole.strokes, hole.par]
		_label(card_lines.trim_suffix("\n"))
	if not is_instance_valid(player_tab):
		_button("Return to management", leave_round)

func leave_round(_restore_mode: bool = true) -> void:
	var was_tournament_aim := tournament_aim
	var had_round := busy
	if is_instance_valid(scores):
		scores.dismiss()
	active = false
	busy = false
	_was_aiming = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	if not was_tournament_aim:
		# Owner round: the opponents we spawned leave the course. The owner's
		# own golfer does not: they are on the course between rounds as well,
		# and go back to work now the round is over. A tournament golfer
		# belongs to the TournamentManager, which clears it on its own.
		var owner_manager := GameManager.player_golfer_manager
		for golfer in participants:
			if not is_instance_valid(golfer):
				continue
			if owner_manager != null and owner_manager.golfer == golfer:
				_release_owner()
				continue
			manager.remove_golfer(golfer.golfer_id)
	tournament_aim = false
	participants.clear()
	player = null
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	content = null
	if had_round:
		if is_instance_valid(camera):
			camera.focus_on(previous_camera)
		# Day always runs in SIMULATING — keep simulation active after owner round
		if GameManager.current_mode != GameManager.GameMode.SIMULATING:
			GameManager.set_mode(GameManager.GameMode.SIMULATING)
		GameManager.set_speed(previous_speed if GameManager.current_mode == GameManager.GameMode.SIMULATING else GameManager.GameSpeed.NORMAL)

	if is_instance_valid(player_tab):
		_build_setup()
