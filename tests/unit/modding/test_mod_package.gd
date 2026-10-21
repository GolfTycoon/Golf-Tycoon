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
