# Example: Garden Ornaments (a data mod)

Decorations are the friendliest content to add: the game draws them
procedurally from their `category`, so a brand new decoration needs no art.

- `category` chooses the drawing (`water`, `structures`, `furniture`,
  `sculptures`); `"color"` (a hex string) tints it.
- `aesthetics_value` feeds the course's Aesthetics rating, `theme_bonus`
  names the course themes where the piece counts double - same fields the
  shipped decorations use.
- The `park_bench` entry patches a shipped decoration's price by reusing
  its id, exactly like the buildings example.
