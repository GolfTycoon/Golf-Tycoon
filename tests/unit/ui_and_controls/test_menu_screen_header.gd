extends GameTest
## Fullscreen headers keep only the title across all responsive layouts.

var _back_pressed := false

func test_shared_header_keeps_title_back_and_trailing_control() -> void:
	for mode in [MenuScreenKit.LayoutMode.DESKTOP, MenuScreenKit.LayoutMode.TABLET_LANDSCAPE,
			MenuScreenKit.LayoutMode.TABLET_PORTRAIT, MenuScreenKit.LayoutMode.PHONE_LANDSCAPE,
			MenuScreenKit.LayoutMode.PHONE_PORTRAIT]:
		_back_pressed = false
		var trailing := Button.new()
		trailing.text = "Action"
		var header := autofree(MenuScreenKit.make_screen_header(mode, "Screen title",
			func(): _back_pressed = true, trailing, PixelIcon.Kind.GEAR)) as HBoxContainer
		add_child(header)
		var title_block := header.get_node("TitleBlock") as VBoxContainer
		assert_eq(title_block.get_child_count(), 1, "the title block contains no extra text")
		var title := title_block.get_node("Title") as Label
		assert_eq(title.text, "Screen title")
		assert_eq(title.get_theme_color("font_color"), MenuScreenKit.COLOR_TEXT_BRIGHT)
		assert_eq(title.get_theme_color("font_outline_color"), PixelButtonStyle.INK)
		assert_eq(title.get_theme_constant("outline_size"), 3,
			"the title remains legible over bright or busy backgrounds")
		assert_gt(title.get_theme_color("font_shadow_color").a, 0.0)
		assert_eq(title.get_theme_constant("shadow_offset_y"), 2)
		assert_true(title.clip_text)
		assert_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
		var icon := header.get_node("ScreenIcon") as TextureRect
		assert_eq(icon.texture, PixelIcon.texture(PixelIcon.Kind.GEAR,
			int(MenuScreenKit._header_metrics(mode)["mark"]), MenuScreenKit.COLOR_GOLD))
		assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_eq(header.get_node("Trailing"), trailing)
		(header.get_node("BackButton") as Button).pressed.emit()
		assert_true(_back_pressed, "the back action still works")
