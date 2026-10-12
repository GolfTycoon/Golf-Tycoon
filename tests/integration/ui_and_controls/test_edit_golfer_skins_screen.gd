extends MainSceneTest
## The Edit Golfer Skins studio, opened from the title screen's Golfer Skins
## action, at desktop, tablet and phone window sizes: each arrangement (see
## EditGolferSkinsScreen.layout_mode_for) leaves the painting surface big enough
## to paint on and keeps the studio's controls where a click reaches them, and
## Back returns to the menu. Both sides of the studio are worked: Pixels (a
## colour picker and a brush paint the sprite's own artwork) and Groups (the
## same brush gives pixels to the Re-color Groups).
##
## Where the unit tests check what painting does, this checks that it can be
## done at all: a canvas a few pixels wide, or a Save button pushed off the
## window or hidden under another control, would pass every unit test and still
## be useless. Buttons are hit-tested the way a click would be (see _topmost).

## The sprite is 48x48; a cell this small or smaller is not paintable.
const MIN_CELL := 3.0
## The studio saves into a folder of its own, so the test never touches the
## skins the player has made.
const STUDIO_ROOT := "user://integration_golfer_skins"

var studio: EditGolferSkinsScreen
var title_screen_has_the_action: bool
## The messages the studio's confirmation dialog was asked to show.
var _prompts: PackedStringArray = PackedStringArray()


func before_all() -> void:
	await super()
	var menu_button := _find_button(main.main_menu, "GolferSkinsButton")
	title_screen_has_the_action = menu_button != null
	if menu_button:
		menu_button.pressed.emit()
	await process_frames(6)
	studio = main.get_node_or_null("UI/HUD/EditGolferSkinsScreen")
	if studio:
		# Point the studio at its own folder before anything is saved.
		_remove_tree(STUDIO_ROOT)
		studio.library = GolferSkinLibrary.new(GolferSkinLibrary.BUILT_IN_ROOT, STUDIO_ROOT)
		studio._select_skin(studio.library.get_skin("casual"))
		studio._build()
		await process_frames(2)


func after_all() -> void:
	_remove_tree(STUDIO_ROOT)
	super()


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


func test_the_title_screen_opens_the_skin_studio() -> void:
	assert_true(title_screen_has_the_action, "The title screen has a Golfer Skins action")
	assert_not_null(studio, "which opens the skin studio")


func test_the_desktop_studio_paints_pixels_and_groups() -> void:
	assert_eq(studio._layout_mode, EditGolferSkinsScreen.Layout.WIDE, "1600x1000 uses the wide arrangement")
	await _assert_studio(studio, 1600.0, 1000.0)
	_assert_art_painting(studio, "desktop")
	await _assert_mode_switch(studio)
	_assert_group_painting(studio, "desktop")
	await _assert_group_editing(studio)
	_assert_skin_opening(studio)
	# Opening a skin rebuilds the studio: let the old controls go.
	await process_frames(1)


func test_the_tablet_studio_keeps_its_controls_in_reach() -> void:
	await set_window(Vector2i(1024, 768))
	await process_frames(4)
	assert_eq(studio._layout_mode, EditGolferSkinsScreen.Layout.TABLET, "1024x768 uses the tablet arrangement")
	await _assert_studio(studio, 1024.0, 768.0)
	studio._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	_assert_group_painting(studio, "tablet")


func test_the_phone_studio_is_one_column_that_scrolls_down() -> void:
	await set_window(Vector2i(390, 844))
	await process_frames(4)
	assert_eq(studio._layout_mode, EditGolferSkinsScreen.Layout.PHONE, "390x844 uses the phone arrangement")
	await _assert_studio(studio, 390.0, 844.0)
	assert_eq(_horizontal_overflow(studio), PackedStringArray(), "Nothing in the phone column is wider than the window")
	var scroll := studio.get_node_or_null("Scroll") as ScrollContainer
	assert_true(scroll == null or not scroll.get_h_scroll_bar().visible, "The studio scrolls down, never sideways")
	studio._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	_assert_art_painting(studio, "phone")
	_assert_group_painting(studio, "phone")

	await set_window(Vector2i(844, 390))
	await process_frames(4)
	assert_eq(studio._layout_mode, EditGolferSkinsScreen.Layout.PHONE, "A short window is a phone, whatever its width")
	assert_lte(_canvas_rect(studio).size.x, 844.0, "and the canvas fits it")


func test_save_writes_the_skin_and_back_returns_to_the_menu() -> void:
	await set_window(Vector2i(1600, 1000))
	await process_frames(4)
	var skin: GolferSkin = studio._skin
	studio._on_cell_painted(_free_cell(studio))
	assert_true(studio._dirty, "Painting leaves the skin unsaved")
	var save_button := _find_button(studio, "SaveSkinsButton")
	assert_true(save_button != null and not save_button.disabled, "Save Skins is live with changes to write")
	await click(save_button)
	assert_false(studio._dirty, "Save writes the skin out (status: %s)" % studio._status)
	assert_true(studio.library.has_skin(skin.id), "The studio's skin is in the library")
	assert_true(studio._skin.dir.begins_with(STUDIO_ROOT), "in the player's own folder: %s" % studio._skin.dir)
	assert_true(FileAccess.file_exists(studio._skin.dir.path_join(GolferSkin.MANIFEST_FILE)),
		"as an editable text file")
	# Dress the owner's golfer in it, then put the choice back.
	var worn := GameManager.player_skin_id
	studio._on_wear_pressed()
	assert_eq(GameManager.player_skin_id, skin.id, "Wear This dresses the owner's golfer")
	studio._on_wear_pressed()
	assert_eq(GameManager.player_skin_id, skin.id, "and a second press changes nothing")
	SaveManager.set_user_preference("gameplay", "player_skin", worn)
	GameManager.player_skin_id = worn

	var back := _find_button(studio, "BackButton")
	assert_not_null(back, "The studio has a Back action")
	await click(back)
	await process_frames(4)
	assert_null(main.get_node_or_null("UI/HUD/EditGolferSkinsScreen"), "Back closes the studio")
	assert_true(main.main_menu.visible, "and the title screen is back")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Everything the studio needs at one window size, as the player sees it.
func _assert_studio(screen: EditGolferSkinsScreen, width: float, height: float) -> void:
	assert_true(screen._skin != null, "a skin is open to paint")
	assert_true(screen._canvas != null and screen._canvas.layer != null,
		"the painting surface has a layer on it")
	var rect := _canvas_rect(screen)
	assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "the canvas has room at %dx%d" % [width, height])
	assert_true(screen._canvas.cell_size() >= MIN_CELL,
		"one sprite pixel is %.1f screen pixels across (at least %.0f)" % [
			screen._canvas.cell_size(), MIN_CELL])
	assert_true(rect.position.x >= -0.5 and rect.end.x <= width + 0.5,
		"the canvas is inside the window horizontally")
	assert_true(screen._frame_strip.get_child_count() > 0, "the frame strip is built")
	assert_true(screen._group_rows.get_child_count() == screen._skin.group_count(),
		"every Re-color Group has a row")
	assert_true(screen._palette.get_child_count() == screen._skin.group_count() + 1,
		"the palette offers every group plus None")
	var first_group := screen._group_rows.get_child(0) as Control
	assert_true(first_group != null and first_group.get_global_rect().size.y >= 24.0,
		"a group row is a big enough target")
	assert_true(screen._save_button.get_global_rect().size.x >= 40.0, "Save is a real button")
	assert_true(screen._canvas.active_group > 0, "a group is selected to paint with")

	# The buttons the player cannot do without have to be the control a click
	# lands on - not just to exist and to sit inside the window.
	var tag := "%dx%d" % [int(width), int(height)]
	var save := _find_button(screen, "SaveSkinsButton")
	await _assert_reachable(screen, _find_button(screen, "BackButton"), "Back", tag)
	assert_true(save != null and save.is_visible_in_tree(), "%s: Save Skins is on the screen" % tag)
	await _assert_reachable(screen, _find_button(screen, "PixelsModeButton"), "the Pixels switch", tag)
	await _assert_reachable(screen, _find_button(screen, "GroupsModeButton"), "the Groups switch", tag)
	# The Colour picker and the group buttons live in the other half of the
	# studio: reach for them there, then come back to Pixels. The layout needs a
	# frame to settle after the switch.
	var mode := screen._mode
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	await process_frames(2)
	await _assert_reachable(screen, screen._group_color_button, "the Colour picker", tag)
	await _assert_reachable(screen, _find_button(screen, "NewGroupButton"), "New Group", tag)
	screen._set_mode(mode)
	await process_frames(2)
	# The Sprite Set picker was removed: no picker, no row for it.
	assert_true(screen.find_children("SpritePicker*", "", true, false).is_empty(),
		"%s: there is no Sprite Set picker" % tag)
	var sprite_labels := 0
	for label in screen.find_children("*", "Label", true, false):
		if (label as Label).text.to_lower().contains("sprite set"):
			sprite_labels += 1
	assert_true(sprite_labels == 0, "%s: and no Sprite Set row" % tag)


## Painting through the screen at the size the window gives the canvas.
## The Pixels side: the colour picker and the brush paint the sprite's own
## artwork, and it is the artwork the golfer is drawn with.
func _assert_art_painting(screen: EditGolferSkinsScreen, tag: String) -> void:
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)
	var layer: GolferSkinLayer = screen._canvas.layer
	assert_true(not layer.has_art(), "%s: the sprite starts as the artwork that ships" % tag)
	var drawn := _drawn_cell(screen)
	assert_true(drawn.x >= 0, "%s: the sprite has a pixel to paint" % tag)
	if drawn.x < 0:
		return
	var brush_color := Color8(240, 51, 102)
	screen._on_pixel_color_chosen(brush_color)
	screen._on_cell_painted(drawn)
	assert_true(layer.has_art(), "%s: painting with the brush takes the artwork into the layer" % tag)
	assert_true(layer.art_pixel(drawn.x, drawn.y) == brush_color,
		"%s: the pixel takes the colour the picker shows" % tag)
	assert_true(screen._canvas.image.get_pixel(drawn.x, drawn.y) == brush_color,
		"%s: and the canvas shows it painted" % tag)
	assert_true(layer.get_cell(drawn.x, drawn.y) == GolferSkinLayer.NO_GROUP,
		"%s: a painted pixel is the artwork's own colour, so it leaves its group" % tag)

	# The brush covers a footprint, and erases it again.
	var brush := EditGolferSkinsScreen.BRUSH_SIZES.find(3)
	screen._on_brush_size_selected(brush)
	assert_true(screen._canvas.brush_size == 3, "%s: the brush picker resizes the canvas brush" % tag)
	var spot := _central_cell(screen)
	screen._on_cell_painted(spot)
	var footprint := layer.brush_cells(spot.x, spot.y, 3)
	assert_true(footprint.size() > 1, "%s: a 3-wide brush covers %d pixels" % [tag, footprint.size()])
	var painted := 0
	for covered in footprint:
		if layer.art_pixel(covered.x, covered.y) == brush_color:
			painted += 1
	assert_true(painted == footprint.size(), "%s: every pixel of the footprint is painted" % tag)

	# Alt-click is the eyedropper: it takes the colour already on a pixel.
	screen._on_group_row_pressed(GolferSkinLayer.NO_GROUP)
	screen._on_pixel_color_chosen(Color.WHITE)
	screen._on_cell_picked(spot)
	assert_true(screen._pixel_color == brush_color,
		"%s: alt-click picks the colour already on a pixel up" % tag)

	screen._on_brush_size_selected(EditGolferSkinsScreen.BRUSH_SIZES.find(1))
	screen._on_cell_erased(spot)
	assert_true(layer.art_pixel(spot.x, spot.y).a <= 0.0, "%s: right-click erases the artwork" % tag)
	var still_painted := 0
	for covered in footprint:
		if layer.art_pixel(covered.x, covered.y) == brush_color:
			still_painted += 1
	assert_true(still_painted > 0, "%s: a one-pixel brush leaves the rest of the run alone" % tag)


func _assert_group_painting(screen: EditGolferSkinsScreen, tag: String) -> void:
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	# An earlier check may have left the palette on None: the brush needs a group
	# to give pixels to.
	if screen._canvas.active_group == GolferSkinLayer.NO_GROUP:
		screen._on_group_row_pressed(int(screen._skin.group_list()[0].get("id", 0)))
	var layer: GolferSkinLayer = screen._canvas.layer
	var cell := _free_cell(screen)
	assert_true(cell.x >= 0, "%s: the sprite has a pixel to paint" % tag)
	var group := screen._canvas.active_group
	screen._on_cell_painted(cell)
	assert_true(layer.get_cell(cell.x, cell.y) == group,
		"%s: clicking a pixel gives it to the active group" % tag)
	screen._on_cell_erased(cell)
	assert_true(layer.get_cell(cell.x, cell.y) == GolferSkinLayer.NO_GROUP,
		"%s: right-clicking frees it again" % tag)
	screen._on_cell_painted(cell)
	# The brush gives every pixel it covers to the group, not just the one clicked.
	var brush_cell := _free_cell(screen)
	screen._on_brush_size_selected(EditGolferSkinsScreen.BRUSH_SIZES.find(3))
	screen._on_brush_size_selected(EditGolferSkinsScreen.BRUSH_SIZES.find(3))
	var footprint := layer.brush_cells(brush_cell.x, brush_cell.y, 3)
	screen._on_cell_painted(brush_cell)
	var grouped := 0
	for covered in footprint:
		if layer.get_cell(covered.x, covered.y) == group:
			grouped += 1
	assert_true(grouped == footprint.size(),
		"%s: the brush gives all %d pixels it covers to the group" % [tag, footprint.size()])
	screen._on_brush_size_selected(EditGolferSkinsScreen.BRUSH_SIZES.find(1))
	# One click with the Fill tool takes the whole run of pixels it lands in.
	var filled_from := _cell_of_another_group(screen, group)
	if filled_from.x >= 0:
		var run := screen._canvas.layer.flood_cells(filled_from.x, filled_from.y, screen._canvas.image)
		var before := screen._canvas.layer.count(group)
		screen._on_fill_toggled(true)
		screen._on_cell_painted(filled_from)
		screen._on_fill_toggled(false)
		assert_true(screen._canvas.layer.count(group) == before + run.size(),
			"%s: Fill takes the whole run (%d pixels) in one click" % [tag, run.size()])

	# Re-colouring is checked on a pixel the artwork actually draws - a
	# transparent pixel stays transparent whatever colour its group takes (see
	# GolferSkinLayer.recolor) - and that the active group now owns, whichever
	# skin is open (the Beginner art has groups that own almost no pixels yet).
	var marked := _drawn_cell(screen)
	assert_true(marked.x >= 0, "%s: the sprite has a drawn pixel" % tag)
	screen._on_cell_painted(marked)
	screen._on_group_color_chosen(Color(0.25, 0.75, 0.35))
	var painted := screen._canvas.preview_image.get_pixel(marked.x, marked.y)
	assert_true(painted.g > painted.r and painted.g > painted.b,
		"%s: the re-coloured sprite shows the group's new colour" % tag)


## Pixels mode and Groups mode are two sides of the same studio: the pixel
## controls give way to the group editor, the canvas stays up to show and pick
## the groups, and the switch goes back and forth.
func _assert_mode_switch(screen: EditGolferSkinsScreen) -> void:
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)
	assert_true(screen._pixel_block.visible and not screen._group_block.visible,
		"Pixels mode shows the painting controls and hides the group editor")
	assert_true(screen._recolor_check.visible and screen._pixel_color_button.visible,
		"with the colour picker and the Re-coloured switch on hand")
	assert_true(not screen._fill_check.is_visible_in_tree(),
		"and Fill with the group editor it belongs to")
	assert_true(screen._groups_mode_button != null and not screen._groups_mode_button.button_pressed,
		"and the Pixels switch lit")

	await click(screen._groups_mode_button)
	assert_true(screen._mode == EditGolferSkinsScreen.Mode.GROUPS,
		"clicking the Groups switch changes mode")
	assert_true(screen._group_block.visible and not screen._pixel_block.visible,
		"Groups mode shows the group editor and hides the painting controls")
	assert_true(screen._fill_check.is_visible_in_tree(), "with Fill beside the group it fills with")
	assert_true(not screen._recolor_check.is_visible_in_tree(),
		"the Re-coloured switch stands down with the painting controls")
	assert_true(screen._palette.is_visible_in_tree(),
		"and the group palette is there to choose what the brush gives pixels to")
	assert_true(screen._group_rows.get_child_count() == screen._skin.group_count(),
		"every Re-color Group still has a row")
	assert_true(not screen._canvas.show_recolor,
		"the canvas drops the re-colour wash so the groups are read off the artwork")

	# A click on the sprite in Groups mode picks the group the pixel belongs to,
	# which is how the player reads which group a part of the sprite is.
	var picked := _cell_of_another_group(screen, screen._canvas.active_group)
	if picked.x >= 0:
		var owned_by := screen._skin.layer(screen._current_key()).get_cell(picked.x, picked.y)
		screen._on_cell_picked(picked)
		assert_true(screen._canvas.active_group == owned_by,
			"clicking the sprite selects the group under the pixel")
		assert_true(screen._group_rows.get_child_count() > 0, "and the row list follows the selection")

	await click(screen._pixels_mode_button)
	assert_true(screen._mode == EditGolferSkinsScreen.Mode.PIXELS, "clicking Pixels comes back")
	assert_true(screen._pixel_block.visible and screen._canvas.show_recolor == screen._show_recolor,
		"and the painting surface is back to the artwork the brush edits")


## The Colour button opens a picker (it is a ColorPickerButton, which brings its
## own popup) and the colour is written to the group of the open skin.
func _assert_group_editing(screen: EditGolferSkinsScreen) -> void:
	assert_true(screen._group_color_button is ColorPickerButton,
		"the Colour button is a picker that opens its own popup")
	screen._set_mode(EditGolferSkinsScreen.Mode.GROUPS)
	var group := screen._active_group
	if group == GolferSkinLayer.NO_GROUP:
		for entry in screen._skin.group_list():
			group = int(entry.get("id", 0))
			break
	assert_true(group != GolferSkinLayer.NO_GROUP, "a Re-color Group is selected to edit")
	if group == GolferSkinLayer.NO_GROUP:
		return
	screen._on_group_row_pressed(group)
	# Clicking Colour opens a real picker (the old ColorPicker.popup() call was
	# what broke this), and the colour it hands back reaches the group.
	await click(screen._group_color_button)
	var picker := (screen._group_color_button as ColorPickerButton).get_popup()
	assert_true(picker != null and picker.visible, "clicking Colour opens the colour picker")
	if picker != null:
		picker.hide()
		await process_frames(1)
	var wanted := Color(0.2, 0.6, 0.9)
	screen._on_group_color_chosen(wanted)
	assert_true(screen._skin.group_by_id(group).get("color").is_equal_approx(wanted),
		"picking a colour re-colours the group")
	assert_true(screen._dirty, "and leaves the skin to be saved")
	var swatch := screen._group_color_button as ColorPickerButton
	assert_true(swatch.color.is_equal_approx(wanted), "and the picker shows the group's colour")

	# New group, rename it, then delete it again: the three group actions.
	var before := screen._skin.group_count()
	screen._on_new_group_pressed()
	assert_true(screen._skin.group_count() == before + 1, "New Group adds a Re-color Group")
	var added := screen._skin.group_list()[screen._skin.group_count() - 1]
	var id := int(added.get("id"))
	screen._active_group = id
	screen._on_group_name_submitted("Collars")
	assert_true(str(screen._skin.group_by_id(id).get("name")) == "Collars", "the name field renames it")
	screen._active_group = id
	# Deleting a group asks first (see _confirm): answer the dialog and check it
	# warned about the pixels it would free.
	screen.confirm_callback = func(message: String, _confirm_text: String) -> bool:
		_prompts.append(message)
		return true
	_prompts.clear()
	screen._on_delete_group_pressed()
	screen.confirm_callback = Callable()
	assert_true(_prompts.size() == 1 and _prompts[0].contains("Collars"),
		"Delete asks before freeing a group's pixels (got %s)" % str(_prompts))
	assert_true(screen._skin.group_by_id(id).is_empty(), "and removes it once confirmed")
	screen._set_mode(EditGolferSkinsScreen.Mode.PIXELS)


## Opening the shipped skins and the player's own, as the list does.
func _assert_skin_opening(screen: EditGolferSkinsScreen) -> void:
	var ids := screen.library.skin_ids()
	assert_true(ids.size() >= 2, "the shipped skins are listed: %s" % str(ids))
	for index in screen._skin_list.item_count:
		var listed: String = screen._skin_list.get_item_text(index)
		if listed.begins_with("Beginner"):
			screen._on_skin_selected(index)
			break
	assert_true(screen._skin.id == "beginner",
		"picking another skin opens it (got %s)" % screen._skin.id)
	assert_true(screen._canvas.layer == screen._skin.layer(screen._current_key()),
		"and the canvas paints the new skin's layer")


## A pixel of the sprite that belongs to some group other than this one.
func _cell_of_another_group(screen: EditGolferSkinsScreen, group: int) -> Vector2i:
	for y in 48:
		for x in 48:
			var owned_by := screen._canvas.layer.get_cell(x, y)
			if owned_by != GolferSkinLayer.NO_GROUP and owned_by != group:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A pixel the artwork draws in a colour dark or bright enough to keep a
## shade of it (fully transparent and pitch black pixels are both skipped).
func _drawn_cell(screen: EditGolferSkinsScreen) -> Vector2i:
	var image := screen._canvas.image
	for y in 48:
		for x in 48:
			var color := image.get_pixel(x, y)
			if color.a > 0.2 and maxf(color.r, maxf(color.g, color.b)) > 0.15:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A drawn pixel away from the edges, so a brush centred on it lies inside the
## sprite and its footprint is the whole shape.
func _central_cell(screen: EditGolferSkinsScreen) -> Vector2i:
	var fallback := Vector2i(-1, -1)
	for y in range(12, 36):
		for x in range(12, 36):
			if fallback.x < 0:
				fallback = Vector2i(x, y)
			if screen._canvas.image.get_pixel(x, y).a > 0.2:
				return Vector2i(x, y)
	return fallback


## The first pixel of the sprite that belongs to no group.
func _free_cell(screen: EditGolferSkinsScreen) -> Vector2i:
	for y in 48:
		for x in 48:
			if screen._canvas.layer.get_cell(x, y) == GolferSkinLayer.NO_GROUP:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _canvas_rect(screen: EditGolferSkinsScreen) -> Rect2:
	return screen._canvas.get_global_rect()

## Every control under the screen that reaches past the window's right edge.
func _horizontal_overflow(screen: EditGolferSkinsScreen) -> PackedStringArray:
	var offenders: PackedStringArray = []
	_walk(screen, float(get_window().size.x), offenders)
	return offenders

func _walk(node: Node, limit: float, offenders: PackedStringArray) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		var rect := (node as Control).get_global_rect()
		# Controls inside a scroll container are allowed to be wider than the
		# window as long as the container scrolls (it does not, in the phone
		# arrangement: it is built to fit).
		if rect.end.x > limit + 1.0 and not inside_scroll(node):
			offenders.append("%s %s" % [node.name, rect])
	for child in node.get_children():
		_walk(child, limit, offenders)


## True when a click at the button's centre would land on the button (or one of
## its own children) rather than on something drawn over it. A button below the
## fold of a scrolling column is reachable: the test scrolls to it first, the
## way the player would.
func _assert_reachable(root: Control, button: Button, description: String, tag: String) -> void:
	if button == null:
		fail_test("%s: %s is on the screen" % [tag, description])
		return
	assert_true(button.is_visible_in_tree() and not button.disabled,
		"%s: %s is enabled and shown" % [tag, description])
	await _scroll_into_view(button)
	var rect := button.get_global_rect()
	var centre := rect.position + rect.size * 0.5
	var hit := _topmost(root, centre)
	# _topmost returns "<name>:<class>"; the click reaches the button when the
	# winner is the button itself or a control inside it (a picker draws its own
	# swatch, so the hit may be a child of the button).
	var owner_name := hit.split(":")[0]
	var landed := owner_name == str(button.name)
	if not landed and button.is_ancestor_of(_find_node_named(root, owner_name)):
		landed = true
	assert_true(landed, "%s: a click at %s lands on %s (got %s)" % [
		tag, centre.round(), description, hit])


## Put a control inside the window by scrolling every column above it, then give
## the layout a frame to settle before it is hit-tested.
func _scroll_into_view(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
		parent = parent.get_parent()
	await process_frames(2)


func _find_node_named(root: Node, wanted: String) -> Node:
	for node in root.find_children(wanted, "", true, false):
		return node
	return null


## The topmost Control that would receive a click at this global point, walking
## the tree in reverse draw order (last child on top) and honouring clipping.
func _topmost(root: Control, global_point: Vector2) -> String:
	var clip := root.get_global_rect()
	var children := root.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child := children[i]
		if not (child is Control) or not child.is_visible_in_tree():
			continue
		var control := child as Control
		var rect: Rect2 = control.get_global_rect()
		var allowed := clip.intersection(rect) if control.clip_contents else clip
		if not (allowed.has_point(global_point) and rect.has_point(global_point)):
			continue
		var deeper := _topmost(control, global_point)
		if not deeper.is_empty():
			return deeper
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return "%s:%s" % [control.name, control.get_class()]
	if root.get_global_rect().has_point(global_point) \
			and root.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return "%s:self" % root.name
	return ""


func _find_button(root: Node, button_name: String) -> Button:
	for node in root.find_children(button_name, "", true, false):
		if node is Button:
			return node as Button
	return null
