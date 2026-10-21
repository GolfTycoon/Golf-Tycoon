extends PanelContainer
## The Course Clock widget: the in-game date and season, top-centre of the
## HUD. It ignores the mouse entirely (it is a read-out, not a control),
## and refreshes off the same signals the core HUD does.

var _label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	position = Vector2(-110, 8)
	custom_minimum_size = Vector2(220, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.08, 0.72)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.93, 0.96, 0.90))
	add_child(_label)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.season_changed.connect(_on_season_changed)
	_refresh()


func _exit_tree() -> void:
	if EventBus.day_changed.is_connected(_on_day_changed):
		EventBus.day_changed.disconnect(_on_day_changed)
	if EventBus.season_changed.is_connected(_on_season_changed):
		EventBus.season_changed.disconnect(_on_season_changed)


func _on_day_changed(_new_day: int) -> void:
	_refresh()


func _on_season_changed(_old_season: int, _new_season: int) -> void:
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var text: String = GameManager.get_date_string()
	if GameManager.is_feature_enabled("seasons"):
		var season: int = SeasonSystem.get_season(GameManager.current_day)
		text += "  ·  " + SeasonSystem.get_season_name(season)
	_label.text = text
