# Example: Hole-in-One Jackpot (a script mod)

The script-mod walkthrough. `mod.json` asks for the `"script"` permission
and names `mod_main.gd` as the entry point; that file extends
`GolfTycoonMod`, gets a `ModAPI` in `_mod_load`, and then:

- connects `EventBus.golfer_finished_hole` to award the bounty with
  `GameManager.modify_money` + `EventBus.log_transaction`,
- registers the `golfer_spawn_rate` hook for the week-long buzz,
- reads its numbers from **config**: defaults declared in `mod.json`,
  overridable in `user://mods/config/example.jackpot.json`
  (e.g. `{"payout": 1000, "announce": false}`),
- stores its record in the save file with `_mod_save` / `_mod_restore`.

Note what it does *not* do: no `class_name`, no edits to game files, no
reaching into another mod. Removing it mid-save simply stops the bounties
- the save keeps an `example.jackpot` slice nobody reads.
