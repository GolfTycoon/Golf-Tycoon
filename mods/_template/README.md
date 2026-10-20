# Mod template

The starting point for a new mod. This folder is never loaded (folders
beginning with `_` are skipped) - copy it, rename the copy, and fill it in.

1. Copy `_template/` to a folder named after your mod, here or (better,
   once it works) in your `user://mods/` folder - the Mods screen's
   "Open mods folder" button shows you where that is.
2. Edit `mod.json`: pick a unique reverse-style `id`
   (`yourname.my_mod` - it namespaces everything you add and must never
   change once players have saves), a name, a version, a description.
3. Decide what kind of mod it is (docs/modding.md walks through them):
   data only, scripted gameplay, a feature provider, UI... The bundled
   examples beside this template each do one kind end to end.
4. Launch the game, open **Mods** on the main menu, enable yours, Apply.
5. Share it: zip the folder (the Mods screen installs zips; or run
   `make mod-pack MOD=path/to/folder`), or upload it to the Steam
   Workshop from the same screen in a Steam build.

The full guide is docs/modding.md in the game repository, with the
manifest reference in docs/modding/manifest-and-packaging.md and the
scripting API in docs/modding/mod-api.md.
