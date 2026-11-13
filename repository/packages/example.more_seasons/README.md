# Example: Extra Seasonal Events (an add-on mod)

A mod *for* another mod - the shape of most real mod ecosystems:

- `dependencies` declares the Seasons mod, at least version 1.0.0. It is
  a **hard** dependency, so enabling this mod loads Seasons first even if
  the player left it off the list, and if Seasons is ever missing this
  mod is reported (with the reason) in the Mods screen instead of loading.
- New events join the same `seasonal_events` registry the Seasons mod
  fills - the calendar is a shared shelf, in load order.
- The first entry patches the Seasons mod's own Spring Opening Week by
  its full namespaced id (`golf_tycoon.seasons:spring_open`), replacing
  it wholesale. That is the sanctioned way to retune another mod's
  content: namespaced ids, load order decides.
