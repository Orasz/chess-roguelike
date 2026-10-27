extends GutTest
## The display settings the layouts rely on: portrait 720x1280 scaled with the canvas, expanding on
## taller screens, with sharp pixel art.

func test_the_stretch_expands_on_taller_screens():
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")

func test_the_stretch_scales_the_canvas():
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")

func test_textures_are_filtered_with_the_nearest_neighbour():
	assert_eq(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"), 0)

func test_the_engine_autoload_is_set():
	assert_true(ProjectSettings.has_setting("autoload/ChessEngine"))
