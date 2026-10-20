# Example: Golden Hour Parkland (a theme mod)

A theme mod patches one of the shipped course themes by its save name
(`parkland`, `desert`, ...):

- `colors` repaints the terrain palette - the colour keys are the ones
  CourseTheme.get_terrain_colors returns (`grass`, `fairway_light`,
  `bunker`, ...), as hex strings.
- `modifiers` patches the theme's gameplay numbers
  (`green_fee_baseline`, `maintenance_cost_multiplier`,
  `wind_base_strength`, ...).
- `name` / `description` restyle what the new-game screens call it. The
  save name (`parkland`) never changes, so saves stay valid with the mod
  on or off - the course just changes clothes.

Fully new themes would need new theme ids, which the game allocates
itself (they are written into saves); restyling the ten shipped ones is
the supported, always-safe version of the same idea.
