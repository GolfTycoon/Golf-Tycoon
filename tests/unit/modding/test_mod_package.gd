extends GameTest
## ModPackage: the zips mods travel in - reading a manifest without
## unpacking, packing a folder the way the game reads it back, and refusing
## archives that try to write outside their folder.
## (scripts/modding/mod_package.gd)

const ROOT := "user://ut_mod_package"

const MANIFEST_JSON := """{
	"format_version": 1,
	"id": "tester.zipped",
	"name": "Zipped",
	"version": "2.0.0",
	"api_version": 1,
	"description": "Packed by a test."
}"""


func before_each() -> void:
	super()
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("source/data"))


func after_each() -> void:
	_cleanup()
	super()


func _cleanup() -> void:
	ModPackage.remove_directory_recursive(ROOT)


func _write(relative: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(relative).get_base_dir())
	var file := FileAccess.open(ROOT.path_join(relative), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_source_mod() -> void:
	_write("source/mod.json", MANIFEST_JSON)
	_write("source/data/notes.txt", "hello")
	_write("source/stray.uid", "junk")


func test_a_folder_packs_and_its_manifest_reads_back_out_of_the_zip() -> void:
	_write_source_mod()
	var zip_path := ROOT.path_join("out/tester.zipped.zip")
	var packed := ModPackage.pack_folder(ROOT.path_join("source"), zip_path)
	assert_true(bool(packed.get("ok", false)), "packing succeeds")
	assert_eq(int(packed.get("file_count", 0)), 2, "mod.json + notes; the .uid sidecar stays home")

	var read := ModPackage.read_manifest_from_zip(zip_path)
	assert_true(bool(read.get("ok", false)), "the manifest validates inside the zip")
	var manifest: ModManifest = read["manifest"]
	assert_eq(manifest.id, "tester.zipped")
	assert_eq(str(read.get("root_prefix", "x")), "", "files sit at the zip root")


func test_a_single_wrapper_folder_is_accepted() -> void:
	var packer := ZIPPacker.new()
	var zip_path := ROOT.path_join("wrapped.zip")
	assert_eq(packer.open(zip_path), OK)
	packer.start_file("my_mod/mod.json")
	packer.write_file(MANIFEST_JSON.to_utf8_buffer())
	packer.close_file()
	packer.close()

	var read := ModPackage.read_manifest_from_zip(zip_path)
	assert_true(bool(read.get("ok", false)))
	assert_eq(str(read.get("root_prefix", "")), "my_mod/", "the wrapper is reported, not fatal")

	var installed := ModPackage.install_zip(zip_path, ROOT.path_join("installed"))
	assert_true(bool(installed.get("ok", false)), "and installs unwrapped")
	assert_true(FileAccess.file_exists(ROOT.path_join("installed/tester.zipped/mod.json")),
		"into installed/<mod id>/")


func test_a_zip_mods_icon_is_found_or_flagged_without_installing() -> void:
	var icon := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	icon.fill(Color(0.2, 0.6, 0.4, 1.0))
	var icon_path := ROOT.path_join("icon.png")
	assert_eq(icon.save_png(icon_path), OK)
	var icon_bytes: PackedByteArray = FileAccess.get_file_as_bytes(icon_path)

	# A manifest that declares an icon the zip does not hold.
	var declaring_manifest := """{
	"format_version": 1, "id": "tester.zipped", "name": "Zipped",
	"version": "2.0.0", "api_version": 1, "description": "Packed by a test.",
	"icon": "icon.png"
}"""
	var packer := ZIPPacker.new()
	var bare_zip := ROOT.path_join("no_icon.zip")
	assert_eq(packer.open(bare_zip), OK)
	packer.start_file("mod.json")
	packer.write_file(declaring_manifest.to_utf8_buffer())
	packer.close_file()
	packer.close()
	var bare := ModPackage.read_manifest_from_zip(bare_zip)
	assert_true(bool(bare.get("ok", false)))
	assert_false(bool(bare.get("icon_present", true)),
		"a declared icon that is not in the zip is reported")
	assert_true(ModPackage.read_file_from_zip(bare_zip, "icon.png").is_empty(),
		"and asking for it by hand gives nothing")

	# The same zip with the icon in it, under a wrapper folder.
	packer = ZIPPacker.new()
	var with_zip := ROOT.path_join("with_icon.zip")
	assert_eq(packer.open(with_zip), OK)
	packer.start_file("mod_folder/mod.json")
	packer.write_file(declaring_manifest.to_utf8_buffer())
	packer.close_file()
	packer.start_file("mod_folder/icon.png")
	packer.write_file(icon_bytes)
	packer.close_file()
	packer.close()
	var with_read := ModPackage.read_manifest_from_zip(with_zip)
	assert_true(bool(with_read.get("icon_present", false)),
		"the icon is found through the wrapper folder")
	assert_eq(ModPackage.read_file_from_zip(with_zip, "icon.png"), icon_bytes,
		"and reads back exactly what went in")
	assert_true(ModPackage.read_file_from_zip(with_zip, "nope.png").is_empty(),
		"asking for a file the zip does not hold gives nothing")
	# An unsafe relative path is refused without opening anything.
	assert_true(ModPackage.read_file_from_zip(with_zip, "../icon.png").is_empty())


func test_a_zip_with_no_manifest_is_not_a_mod() -> void:
	var packer := ZIPPacker.new()
	var zip_path := ROOT.path_join("empty.zip")
	assert_eq(packer.open(zip_path), OK)
	packer.start_file("readme.txt")
	packer.write_file("nope".to_utf8_buffer())
	packer.close_file()
	packer.close()
	assert_false(bool(ModPackage.read_manifest_from_zip(zip_path).get("ok", true)))
	assert_false(bool(ModPackage.read_manifest_from_zip(ROOT.path_join("ghost.zip")).get("ok", true)),
		"a missing zip answers the same way")


func test_zip_slip_entries_are_refused() -> void:
	var packer := ZIPPacker.new()
	var zip_path := ROOT.path_join("evil.zip")
	assert_eq(packer.open(zip_path), OK)
	packer.start_file("mod.json")
	packer.write_file(MANIFEST_JSON.to_utf8_buffer())
	packer.close_file()
	packer.start_file("../escaped.txt")
	packer.write_file("owned".to_utf8_buffer())
	packer.close_file()
	packer.close()

	var installed := ModPackage.install_zip(zip_path, ROOT.path_join("installed"))
	assert_false(bool(installed.get("ok", true)), "an escaping entry refuses the whole install")
	assert_false(FileAccess.file_exists(ROOT.path_join("escaped.txt")), "and nothing was written")


func test_reinstalling_replaces_the_previous_copy_wholesale() -> void:
	_write_source_mod()
	var zip_path := ROOT.path_join("mod.zip")
	assert_true(bool(ModPackage.pack_folder(ROOT.path_join("source"), zip_path).get("ok", false)))
	assert_true(bool(ModPackage.install_zip(zip_path, ROOT.path_join("installed")).get("ok", false)))
	_write("installed/tester.zipped/stale.txt", "from an older version")
	assert_true(bool(ModPackage.install_zip(zip_path, ROOT.path_join("installed")).get("ok", false)))
	assert_false(FileAccess.file_exists(ROOT.path_join("installed/tester.zipped/stale.txt")),
		"files deleted between versions do not linger")
