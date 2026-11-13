extends GolfTycoonMod
## Example: Course Clock HUD - a UI script mod.
##
## The whole mod is one registered HUD widget: register_hud_widget hands
## the main scene a factory, the scene calls it while building its HUD and
## adds what comes back. The widget itself (hud_clock.gd) is an ordinary
## Control script - preloaded by relative path, no class_name, exactly
## like the rest of the mod.

const HudClock := preload("hud_clock.gd")


func _mod_load(mod_api: ModAPI) -> void:
	mod_api.register_hud_widget(func() -> Control: return HudClock.new())
