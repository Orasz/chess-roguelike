extends GutTest
## How the phone shell fits a window: pillarbox above 0.75, and the safe area in viewport units.

func test_wide_windows_are_pillarboxed():
	assert_eq(ScreenFit.aspect_for(Vector2i(1260, 2800)), Window.CONTENT_SCALE_ASPECT_EXPAND)
	assert_eq(ScreenFit.aspect_for(Vector2i(1080, 1440)), Window.CONTENT_SCALE_ASPECT_EXPAND, "exactly 0.75")
	assert_eq(ScreenFit.aspect_for(Vector2i(1840, 2208)), Window.CONTENT_SCALE_ASPECT_KEEP, "unfolded foldable")
	assert_eq(ScreenFit.aspect_for(Vector2i(2560, 1600)), Window.CONTENT_SCALE_ASPECT_KEEP, "landscape tablet")

func test_a_window_without_height_does_not_divide_by_zero():
	assert_eq(ScreenFit.aspect_for(Vector2i(100, 0)), Window.CONTENT_SCALE_ASPECT_KEEP)

func test_safe_margins_in_viewport_units():
	var m := ScreenFit.safe_margins(Rect2i(0, 121, 1260, 2623), Vector2i(1260, 2800), Vector2(720, 1600))
	assert_almost_eq(m.top, 69.14, 0.01)
	assert_almost_eq(m.bottom, 32.0, 0.01)
	assert_eq([m.left, m.right], [0.0, 0.0])
	var tablet := ScreenFit.safe_margins(Rect2i(0, 0, 2560, 1600), Vector2i(2560, 1600), Vector2(720, 1280))
	assert_eq([tablet.left, tablet.top, tablet.right, tablet.bottom], [0.0, 0.0, 0.0, 0.0], "pillarbox bars are outside the content")

func test_a_cutout_inside_the_content_of_a_pillarboxed_window_counts():
	# 2560x1600 window, 720x1280 viewport: scale 1.25, content 900 px wide, starting at x = 830.
	var m := ScreenFit.safe_margins(Rect2i(0, 50, 2560, 1500), Vector2i(2560, 1600), Vector2(720, 1280))
	assert_almost_eq(m.top, 40.0, 0.01)
	assert_almost_eq(m.bottom, 40.0, 0.01)
	var side := ScreenFit.safe_margins(Rect2i(900, 0, 1700, 1600), Vector2i(2560, 1600), Vector2(720, 1280))
	assert_almost_eq(side.left, 56.0, 0.01, "70 px into the content, over a scale of 1.25")
	assert_eq(side.right, 0.0)

func test_current_margins_are_zero_on_a_desktop_or_headless_run():
	var m := ScreenFit.current_margins(get_viewport())
	for side in ["left", "top", "right", "bottom"]:
		assert_gte(m[side], 0.0, side)
	# The display of a desktop or a headless run is never inside the window, so there is no inset.
	assert_eq([m.left, m.top, m.right, m.bottom], [0.0, 0.0, 0.0, 0.0])

func test_android_keeps_content_out_of_the_gesture_zone_when_the_display_reports_no_inset():
	var m := ScreenFit.current_margins(get_viewport(), "Android")
	assert_eq(m.bottom, float(Tuning.ANDROID_MIN_BOTTOM_MARGIN))
	assert_eq([m.left, m.top, m.right], [0.0, 0.0, 0.0], "only the bottom is raised")

func test_android_keeps_a_bigger_inset_than_the_least():
	var m := ScreenFit.with_platform_minimum({"left": 0.0, "top": 69.0, "right": 0.0, "bottom": 80.0}, "Android")
	assert_eq(m.bottom, 80.0)
	assert_eq(m.top, 69.0)
	var small := ScreenFit.with_platform_minimum({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 32.0}, "Android")
	assert_eq(small.bottom, float(Tuning.ANDROID_MIN_BOTTOM_MARGIN), "a smaller inset is raised to the least")

func test_other_platforms_keep_the_zero_bottom_margin():
	for platform in ["macOS", "Windows", "Linux", "iOS", "Web"]:
		var m := ScreenFit.current_margins(get_viewport(), platform)
		assert_eq(m.bottom, 0.0, platform)

func test_a_safe_margin_container_adds_the_inset_to_its_own_margins():
	var box := SafeMarginContainer.new()
	box.add_theme_constant_override("margin_top", 24)
	box.add_theme_constant_override("margin_left", 16)
	add_child_autofree(box)
	assert_eq(box.get_theme_constant("margin_top"), 24, "no inset here")
	box.apply_margins({"left": 0.0, "top": 69.14, "right": 0.0, "bottom": 32.0})
	assert_eq(box.get_theme_constant("margin_top"), 24 + 70, "rounded up")
	assert_eq(box.get_theme_constant("margin_bottom"), 32)
	assert_eq(box.get_theme_constant("margin_left"), 16)
	box.apply_margins({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	assert_eq(box.get_theme_constant("margin_top"), 24, "the base comes back, it does not accumulate")

func test_a_safe_margin_container_on_android_adds_the_least_bottom_margin():
	var box := SafeMarginContainer.new()
	box.add_theme_constant_override("margin_bottom", 16)
	box.platform = "Android"
	add_child_autofree(box)
	assert_eq(box.get_theme_constant("margin_bottom"), 16 + Tuning.ANDROID_MIN_BOTTOM_MARGIN)
