extends GutTest
## The shared encounter base's clock for engine waits. A wait counts foreground time: each frame adds
## its process time, up to Tuning.MAX_WAIT_STEP_S, so the first frame back from the background, whose
## process time covers the whole time away, counts as one short step.


func test_a_frame_adds_its_process_time_to_a_wait():
	assert_almost_eq(Encounter.advance_wait(1.0, 0.016), 1.016, 0.000001)

func test_a_frame_after_the_background_counts_as_one_short_step():
	assert_eq(Tuning.MAX_WAIT_STEP_S, 0.25)
	assert_eq(Encounter.advance_wait(0.0, 30.0), 0.25)
	assert_eq(Encounter.advance_wait(1.0, 30.0), 1.25)

func test_a_frame_of_exactly_one_step_counts_in_full():
	assert_eq(Encounter.advance_wait(0.0, Tuning.MAX_WAIT_STEP_S), Tuning.MAX_WAIT_STEP_S)
