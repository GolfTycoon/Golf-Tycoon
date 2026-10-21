# Example: Course Clock HUD (a UI mod)

UI mods add `Control`s to the game's screens through the API instead of
editing scenes:

- `api.register_hud_widget(factory)` is called by the main scene as it
  builds the HUD; the returned Control is added above the course. Give it
  anchors/offsets and a `mouse_filter` that suits it - a read-out like
  this clock ignores the mouse so it can never eat a click.
- The widget stays current by connecting the usual EventBus signals
  (`day_changed`, `season_changed`) and disconnects in `_exit_tree`
  like any well-behaved node. When the mod is switched off the widget
  simply never appears.
- For nodes that belong to the world rather than the HUD, mods listen
  for `EventBus.main_scene_ready` and add children to the main scene -
  the Weather mod's rain (`mods/golf_tycoon.weather/mod_main.gd`) is the
  worked example of that pattern.
