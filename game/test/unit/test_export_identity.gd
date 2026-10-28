extends GutTest
## The identity the game exports under: two Android presets (the developer APK and the Play bundle),
## their ids, version and permissions, and the launcher icons they point at.

const PRESETS_PATH := "res://export_presets.cfg"
const DEV := "preset.0"
const PLAY := "preset.1"
const PLAY_ID := "io.github.orasz.chessroguelike"
const STORE_ICON := "../store/graphics/icon_512.png"

## The options the identity depends on, with their exact value, per preset. Godot ignores a misspelt
## option without a word and falls back to its default, so a typo here would silently change the
## app: the key being absent is what fails. The list is open on purpose: the editor writes every
## option of a preset when it saves `export_presets.cfg`, and those extra keys are fine.
const REQUIRED_DEV := {
	"package/unique_name": "io.github.orasz.chessroguelike.dev",
	"package/name": "Chess Roguelike Dev",
	"gradle_build/use_gradle_build": false,
	"architectures/arm64-v8a": true,
	"launcher_icons/main_192x192": "res://assets/icon/launcher_192.png",
	"launcher_icons/adaptive_foreground_432x432": "res://assets/icon/adaptive_fg_432.png",
	"launcher_icons/adaptive_background_432x432": "res://assets/icon/adaptive_bg_432.png",
	"launcher_icons/adaptive_monochrome_432x432": "res://assets/icon/adaptive_mono_432.png",
}
const REQUIRED_PLAY := {
	"package/unique_name": PLAY_ID,
	"package/name": "Chess Roguelike",
	"version/code": 1,
	"version/name": "0.1.0",
	"gradle_build/use_gradle_build": true,
	"gradle_build/export_format": 1,
	"gradle_build/min_sdk": "24",
	"gradle_build/target_sdk": "36",
	"gradle_build/compress_native_libraries": false,
	"architectures/arm64-v8a": true,
	"architectures/armeabi-v7a": false,
	"architectures/x86": false,
	"architectures/x86_64": false,
	"user_data_backup/allow": false,
	"launcher_icons/main_192x192": "res://assets/icon/launcher_192.png",
	"launcher_icons/adaptive_foreground_432x432": "res://assets/icon/adaptive_fg_432.png",
	"launcher_icons/adaptive_background_432x432": "res://assets/icon/adaptive_bg_432.png",
	"launcher_icons/adaptive_monochrome_432x432": "res://assets/icon/adaptive_mono_432.png",
}

## The launcher icons, with the least size each Android generation needs.
const ICON_SIZES := {
	"launcher_icons/main_192x192": Vector2i(192, 192),
	"launcher_icons/adaptive_foreground_432x432": Vector2i(432, 432),
	"launcher_icons/adaptive_background_432x432": Vector2i(432, 432),
	"launcher_icons/adaptive_monochrome_432x432": Vector2i(432, 432),
}

var _presets := ConfigFile.new()


func before_each() -> void:
	assert_eq(_presets.load(PRESETS_PATH), OK, "export_presets.cfg loads")


## Reads a PNG as it is on disk. A `res://` path would work too, but Godot warns that it would not on
## export, and GUT counts the warning as an error.
func _load_png(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _option(preset: String, key: String) -> Variant:
	return _presets.get_value(preset + ".options", key, null)


func test_the_developer_preset_exports_a_debug_apk_under_its_own_id() -> void:
	assert_eq(_presets.get_value(DEV, "name"), "Android Dev")
	assert_eq(_option(DEV, "package/unique_name"), PLAY_ID + ".dev")
	assert_eq(_option(DEV, "package/name"), "Chess Roguelike Dev")
	assert_eq(_presets.get_value(DEV, "export_path"), "../build/chess-roguelike-dev.apk")


func test_the_developer_id_differs_from_the_play_id() -> void:
	assert_ne(_option(DEV, "package/unique_name"), _option(PLAY, "package/unique_name"))


func test_the_retired_slice_id_is_gone() -> void:
	for preset: String in [DEV, PLAY]:
		assert_ne(_option(preset, "package/unique_name"), "io.github.chessroguelike.slice")


func test_the_play_preset_has_the_play_identity() -> void:
	assert_eq(_presets.get_value(PLAY, "name"), "Android Play")
	assert_eq(_option(PLAY, "package/unique_name"), PLAY_ID)
	assert_eq(_option(PLAY, "package/name"), "Chess Roguelike")
	assert_eq(_presets.get_value(PLAY, "export_path"), "../build/chess-roguelike-0.1.0-1.aab")


func test_the_play_preset_builds_a_bundle_for_the_play_targets() -> void:
	assert_eq(_option(PLAY, "gradle_build/use_gradle_build"), true)
	assert_eq(_option(PLAY, "gradle_build/export_format"), 1, "1 is the Android App Bundle")
	assert_eq(_option(PLAY, "gradle_build/min_sdk"), "24")
	assert_eq(_option(PLAY, "gradle_build/target_sdk"), "36")
	assert_eq(_option(PLAY, "gradle_build/compress_native_libraries"), false, "the 16 KB alignment needs stored libraries")


func test_the_play_preset_starts_at_version_code_1_and_name_0_1_0() -> void:
	assert_eq(_option(PLAY, "version/code"), 1)
	assert_eq(_option(PLAY, "version/name"), "0.1.0")


func test_the_play_version_name_is_the_project_version() -> void:
	assert_eq(_option(PLAY, "version/name"), ProjectSettings.get_setting("application/config/version"))


func test_the_play_preset_ships_arm64_only() -> void:
	assert_eq(_option(PLAY, "architectures/arm64-v8a"), true)
	for abi in ["armeabi-v7a", "x86", "x86_64"]:
		assert_eq(_option(PLAY, "architectures/" + abi), false, abi)


func test_the_play_preset_declares_no_permission() -> void:
	for key in _presets.get_section_keys(PLAY + ".options"):
		if key.begins_with("permissions/"):
			assert_false(_presets.get_value(PLAY + ".options", key), key)


func test_the_save_is_kept_out_of_the_cloud_backup() -> void:
	# allowBackup="false" stops Google's cloud backup; it does not stop Android's device-to-device transfer,
	# and PRIVACY.md says so.
	assert_eq(_option(PLAY, "user_data_backup/allow"), false, "PRIVACY.md says the save is not part of the cloud backup")


func test_both_presets_keep_the_same_filters() -> void:
	for preset: String in [DEV, PLAY]:
		assert_eq(_presets.get_value(preset, "include_filter"), "*.json, legal/*", preset)
		assert_eq(_presets.get_value(preset, "exclude_filter"), "test/*, addons/gut/*, tools/*, spike/*, .gutconfig.json", preset)


func test_every_option_the_identity_depends_on_is_present_with_its_value() -> void:
	for preset: String in [DEV, PLAY]:
		var required: Dictionary = REQUIRED_DEV if preset == DEV else REQUIRED_PLAY
		var section := preset + ".options"
		for key: String in required:
			assert_true(_presets.has_section_key(section, key), "%s lacks '%s' (misspelt?)" % [preset, key])
			assert_eq(_presets.get_value(section, key, null), required[key], "%s: %s" % [preset, key])


func test_every_launcher_icon_exists_at_its_minimum_size() -> void:
	for preset: String in [DEV, PLAY]:
		for key: String in ICON_SIZES:
			var path: String = _option(preset, key)
			assert_not_null(path, "%s sets %s" % [preset, key])
			assert_true(path.begins_with("res://assets/icon/"), path)
			var image := _load_png(path)
			assert_not_null(image, "%s loads" % path)
			if image != null:
				var least: Vector2i = ICON_SIZES[key]
				assert_gte(image.get_width(), least.x, path)
				assert_gte(image.get_height(), least.y, path)


## Android 13+ tints this layer with the wallpaper's colour: it reads only its alpha, and the launcher's
## mask hides whatever lies outside the 264 px safe circle.
func test_the_monochrome_icon_is_a_white_silhouette_inside_the_safe_circle() -> void:
	var image := _load_png("res://assets/icon/adaptive_mono_432.png")
	assert_not_null(image, "it loads")
	if image == null:
		return
	var opaque := 0
	var centre := Vector2(image.get_size()) / 2.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			opaque += 1
			assert_eq(pixel, Color.WHITE, "(%d, %d) is opaque white" % [x, y])
			assert_lte(centre.distance_to(Vector2(x + 0.5, y + 0.5)), 132.0, "(%d, %d) is inside the safe circle" % [x, y])
	assert_gt(opaque, 0, "the knight is there")


func test_the_project_icon_is_set_and_exists() -> void:
	var path: String = ProjectSettings.get_setting("application/config/icon")
	assert_eq(path, "res://assets/icon/icon.png")
	assert_not_null(_load_png(path))


func test_the_store_icon_is_512_square_with_alpha_and_under_1024_kb() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(STORE_ICON).simplify_path()
	var image := _load_png(path)
	assert_not_null(image, "%s loads" % path)
	if image == null:
		return
	assert_eq(image.get_size(), Vector2i(512, 512))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8, "32-bit with alpha")
	assert_lte(FileAccess.get_file_as_bytes(path).size(), 1024 * 1024)
