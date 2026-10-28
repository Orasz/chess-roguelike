extends GutTest
## The identity the game exports under: two Android presets (the developer APK and the Play bundle),
## their ids, version and permissions, and the launcher icons they point at.

const PRESETS_PATH := "res://export_presets.cfg"
const DEV := "preset.0"
const PLAY := "preset.1"
const PLAY_ID := "io.github.orasz.chessroguelike"
const STORE_ICON := "../store/graphics/icon_512.png"

## Every option key the presets may carry, written from the EditorExportPlatformAndroid class reference
## (Godot 4.7). Godot ignores a misspelt key without a word, so a typo would silently fall back to the
## default: the test rejects any key outside this list. `permissions/*` keys are checked by prefix.
const KNOWN_KEYS: Array[String] = [
	"architectures/arm64-v8a", "architectures/armeabi-v7a", "architectures/x86", "architectures/x86_64",
	"command_line/extra_args", "custom_template/debug", "custom_template/release",
	"gesture/swipe_to_dismiss",
	"gradle_build/android_source_template", "gradle_build/compress_native_libraries",
	"gradle_build/custom_theme_attributes", "gradle_build/export_format",
	"gradle_build/gradle_build_directory", "gradle_build/min_sdk", "gradle_build/minification",
	"gradle_build/target_sdk", "gradle_build/use_gradle_build",
	"graphics/opengl_debug",
	"keystore/debug", "keystore/debug_password", "keystore/debug_user",
	"keystore/release", "keystore/release_password", "keystore/release_user",
	"launcher_icons/adaptive_background_432x432", "launcher_icons/adaptive_foreground_432x432",
	"launcher_icons/adaptive_monochrome_432x432", "launcher_icons/main_192x192",
	"package/app_category", "package/exclude_from_recents", "package/name",
	"package/retain_data_on_uninstall", "package/show_as_launcher_app", "package/show_in_android_tv",
	"package/show_in_app_library", "package/signed", "package/unique_name",
	"user_data_backup/allow", "version/code", "version/name",
]

## The launcher icons, with the least size each Android generation needs.
const ICON_SIZES := {
	"launcher_icons/main_192x192": Vector2i(192, 192),
	"launcher_icons/adaptive_foreground_432x432": Vector2i(432, 432),
	"launcher_icons/adaptive_background_432x432": Vector2i(432, 432),
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


func test_user_data_never_leaves_the_phone_through_the_backup() -> void:
	assert_eq(_option(PLAY, "user_data_backup/allow"), false, "PRIVACY.md says the save never leaves the phone")


func test_both_presets_keep_the_same_filters() -> void:
	for preset: String in [DEV, PLAY]:
		assert_eq(_presets.get_value(preset, "include_filter"), "*.json, legal/*", preset)
		assert_eq(_presets.get_value(preset, "exclude_filter"), "test/*, addons/gut/*, tools/*, spike/*, .gutconfig.json", preset)


func test_every_option_key_is_a_real_godot_key() -> void:
	for preset: String in [DEV, PLAY]:
		for key in _presets.get_section_keys(preset + ".options"):
			var known: bool = KNOWN_KEYS.has(key) or key.begins_with("permissions/")
			assert_true(known, "%s: '%s' is not an option of Godot's Android exporter" % [preset, key])


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
