extends GutTest
## The project settings the game relies on: portrait 720x1280 scaled with the canvas, expanding on
## taller screens, with sharp pixel art; the engine autoload; the main scene; and one theme for
## every screen.

func test_the_stretch_expands_on_taller_screens():
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")

func test_the_stretch_scales_the_canvas():
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")

func test_textures_are_filtered_with_the_nearest_neighbour():
	assert_eq(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"), 0)

func test_the_engine_autoload_is_set():
	assert_true(ProjectSettings.has_setting("autoload/ChessEngine"))

func test_the_game_starts_at_the_main_scene():
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://main/main.tscn")

func test_every_screen_shares_the_one_theme():
	assert_eq(ProjectSettings.get_setting("gui/theme/custom"), "res://ui/theme.tres")
