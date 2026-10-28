extends PixelCircleButton
class_name InspectButton
## The round Inspect toggle pinned to a Build tab's bottom-right corner.
##
## Inspection reads the tiles the Build shelves lay out — terrain, improvements
## and buildings — so the toggle belongs on the Build tabs themselves, beside
## what it inspects, instead of occupying a utility circle in the bottom-left
## dock. Every Build tab (Terrain, Improvements, Buildings, Elevation) pins one
## of these to its bottom-right corner, clear of the Bulldozer and brush dock
## that own the bottom-left. The four copies share one mode through
## TerrainToolbar.set_inspect_active, the same way the pinned Bulldozer buttons
## share bulldozer mode. The medallion lights its ring while inspecting; Esc or
## right-click leaves the mode.

## Fixed diameter: a comfortable click target inside the 190px bottom bar, and
## already large enough to clear the 44px touch minimum without a separate
## touch resize.
const BUTTON_DIAMETER := 46.0
## Distance kept from the page's bottom-right corner.
const CORNER_MARGIN := 10.0
## The single sentence every copy carries, as both its hover tooltip and its
## assistive description.
const INSPECT_TOOLTIP := "Inspect terrain, improvements and buildings. Esc or right-click to exit."

func _init() -> void:
	diameter = BUTTON_DIAMETER
	glyph = "inspect"
	accent = TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.BUILD]
	toggle_mode = true
	accessibility_name = "Inspect"
	accessibility_description = INSPECT_TOOLTIP
	tooltip_text = INSPECT_TOOLTIP
	focus_mode = Control.FOCUS_ALL
