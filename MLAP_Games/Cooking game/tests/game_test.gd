extends Node
## Plays the real game scene through the MarsInput API, the same path the device will use.
## Run: godot --headless --fixed-fps 60 --path . res://tests/game_test.tscn

const TEST_SIZE := Vector2(1280, 720)

var failures := 0
var mars: Node
var main: Node2D


func _ready() -> void:
	mars = MarsInput
	_test_quality_curve()
	_test_right_arm_direction()
	_test_patterns()
	_test_customer_feedback()
	await _test_tracker_scoring()
	await _test_pick_and_drop()
	await _test_stir_flow()
	await _test_tracking_loss()
	await _test_left_arm()
	await _test_timer_end()
	print("FAILED: %d check(s)" % failures if failures > 0 else "ALL TESTS PASSED")
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		failures += 1


func _send(world_point: Vector2, grip: bool) -> void:
	mars.submit_sample(world_point / TEST_SIZE, grip)


## Holds a position for a number of physics ticks, feeding telemetry every tick.
func _hold(world_point: Vector2, grip: bool, ticks: int) -> void:
	for i in ticks:
		_send(world_point, grip)
		await get_tree().physics_frame


func _glide(from: Vector2, to: Vector2, grip: bool, ticks: int) -> void:
	for i in ticks:
		_send(from.lerp(to, float(i + 1) / ticks), grip)
		await get_tree().physics_frame


func _new_game(seconds: float = 600.0) -> void:
	if main != null:
		main.free()
	_send(Vector2(640, 660), false)
	main = load("res://scenes/main.tscn").instantiate()
	main.round_seconds = seconds
	add_child(main)
	await _hold(Vector2(640, 660), false, 3)
	await _hold(Vector2(640, 660), true, 2) # The press starts the game.
	await _hold(Vector2(640, 660), false, 12)


func _carry_to_pot(item: Ingredient) -> void:
	await _glide(Vector2(640, 660), item.global_position, false, 25)
	await _hold(item.global_position, true, 4)
	await _glide(item.global_position, main.pot.global_position, true, 30)
	await _hold(main.pot.global_position, true, 3)
	await _hold(main.pot.global_position, false, 10)
	await _glide(main.pot.global_position, Vector2(640, 660), false, 15)


func _fill_pot() -> void:
	for item: Ingredient in main.ingredients.get_children():
		await _carry_to_pot(item)


## Moves along a circle around the pot, in screen coordinates.
func _stir(radius: float, direction: int, radians: float, grip: bool = true) -> void:
	var centre: Vector2 = main.pot.global_position
	var offset: Vector2 = main.cursor.global_position - centre
	var start := Vector2(offset.x, offset.y / main.pot.tracker.aspect).angle()
	var ticks := int(absf(radians) / 0.03)
	for i in ticks:
		var angle := start + direction * 0.03 * (i + 1)
		_send(centre + Vector2(cos(angle), sin(angle) * main.pot.tracker.aspect) * radius, grip)
		await get_tree().physics_frame


func _grab_spoon() -> void:
	var at: Vector2 = main.pot.to_global(main.pot.tracker.start_point())
	await _glide(main.cursor.global_position, at, false, 20)
	await _hold(at, false, 3)
	await _hold(at, true, 8)


func _test_quality_curve() -> void:
	print("Accuracy curve")
	var tracker := StirTracker.new()
	_check(is_equal_approx(tracker.quality_at(Vector2(125, 0)), 1.0), "on the ideal path scores 100%")
	_check(is_equal_approx(tracker.quality_at(Vector2(125 + 22, 0)), 1.0), "edge of tolerance scores 100%")
	_check(is_equal_approx(tracker.quality_at(Vector2(125 + 51, 0)), 0.5), "halfway to max deviation scores 50%")
	# The path is a 360-point polyline, so inside the circle it can be a hair closer than 51 px.
	_check(absf(tracker.quality_at(Vector2(125 - 51, 0)) - 0.5) < 0.005, "inside and outside deviate equally")
	_check(tracker.quality_at(Vector2(125 + 80, 0)) == 0.0, "max deviation scores 0%")
	tracker.free()


func _test_right_arm_direction() -> void:
	print("Lateral-to-anterior direction, every pattern")
	for id in StirPatterns.Id.values():
		var label := StirPatterns.display_name(id)
		var tracker := StirTracker.new()
		tracker.set_pattern(id)
		tracker.set_training_side(mars.Side.RIGHT)
		var start := tracker.start_point()
		_check(start.x > 0.0, "%s: right arm starts at screen right (lateral)" % label)
		_check(tracker.point_at(0.02).y < start.y, "%s: right arm's first move goes up (anterior)" % label)
		tracker.set_training_side(mars.Side.LEFT)
		start = tracker.start_point()
		_check(start.x < 0.0, "%s: left arm starts at screen left (lateral)" % label)
		_check(tracker.point_at(0.02).y < start.y, "%s: left arm's first move goes up (anterior)" % label)
		tracker.free()


## Follows each pattern's own path, forwards and backwards, through the real scoring code.
func _test_patterns() -> void:
	print("Stir patterns")
	for id in StirPatterns.Id.values():
		var label := StirPatterns.display_name(id)
		var forward := StirTracker.new()
		forward.set_pattern(id)
		forward.set_training_side(mars.Side.RIGHT)
		forward.begin_stroke()
		var steps := 800
		for i in steps * 2 + 1:
			forward.add_sample(forward.point_at(float(i) / steps), 1.0 / 60.0)
		_check(forward.session_accuracy() > 0.99, "%s: following the path scores 100%% (%.1f%%)" % [label, forward.session_accuracy() * 100.0])
		_check(absf(forward.progress - TAU * 2.0) < 0.35, "%s: two laps count as two laps (%.2f of %.2f)" % [label, forward.progress, TAU * 2.0])
		_check(forward.lap_count() >= 1, "%s: laps are counted" % label)

		var backward := StirTracker.new()
		backward.set_pattern(id)
		backward.set_training_side(mars.Side.RIGHT)
		backward.begin_stroke()
		for i in steps + 1:
			backward.add_sample(backward.point_at(1.0 - float(i) / steps), 1.0 / 60.0)
		_check(backward.progress == 0.0, "%s: going the wrong way earns no progress" % label)
		_check(backward.round_stats().wrong_way > 0.9, "%s: and is recorded as wrong way" % label)

		var mirrored := StirTracker.new()
		mirrored.set_pattern(id)
		mirrored.set_training_side(mars.Side.LEFT)
		mirrored.begin_stroke()
		for i in steps + 1:
			mirrored.add_sample(mirrored.point_at(float(i) / steps), 1.0 / 60.0)
		_check(mirrored.session_accuracy() > 0.99 and absf(mirrored.progress - TAU) < 0.35, "%s: the left arm's mirrored path scores 100%%" % label)
		forward.free()
		backward.free()
		mirrored.free()

	# Standing in the middle of a figure eight (where it crosses itself) must not earn laps.
	var eight := StirTracker.new()
	eight.set_pattern(StirPatterns.Id.FIGURE_EIGHT)
	eight.set_training_side(mars.Side.RIGHT)
	eight.begin_stroke()
	for i in 300:
		eight.add_sample(Vector2(sin(i * 0.3) * 10.0, cos(i * 0.3) * 10.0), 1.0 / 60.0)
	var after_first := eight.progress
	for i in 3000:
		eight.add_sample(Vector2(sin(i * 0.3) * 10.0, cos(i * 0.3) * 10.0), 1.0 / 60.0)
	_check(eight.progress <= TAU / StirTracker.CHECKPOINTS * 1.3, "figure eight: wiggling at the crossing is capped near one checkpoint (%.2f rad)" % eight.progress)
	_check(eight.progress - after_first < 0.001 and eight.lap_count() == 0, "figure eight: and wiggling for longer earns nothing more")
	eight.free()

	# Cutting straight across a circle to reach the far side must not count as a lap either.
	var circle := StirTracker.new()
	circle.set_training_side(mars.Side.RIGHT)
	circle.begin_stroke()
	for i in 400:
		var side := 1.0 if (i / 40) % 2 == 0 else -1.0
		circle.add_sample(Vector2(side * (125.0 - 3.0 * (i % 40)), 0.0), 1.0 / 60.0)
	_check(circle.lap_count() == 0, "circle: shuttling across the middle earns no laps")
	circle.free()


func _test_customer_feedback() -> void:
	print("Customer feedback")
	var perfect := {"accuracy": 0.95, "wrong_way": 0.0, "off_path": 0.0, "idle_seconds": 0.0}
	var okay := {"accuracy": 0.7, "wrong_way": 0.0, "off_path": 0.05, "idle_seconds": 0.0}
	var rough := {"accuracy": 0.4, "wrong_way": 0.0, "off_path": 0.2, "idle_seconds": 0.0}
	var backwards := {"accuracy": 0.5, "wrong_way": 0.5, "off_path": 0.0, "idle_seconds": 0.0}
	var straying := {"accuracy": 0.5, "wrong_way": 0.0, "off_path": 0.6, "idle_seconds": 0.0}
	var resting := {"accuracy": 0.9, "wrong_way": 0.0, "off_path": 0.0, "idle_seconds": 5.0}
	_check(CustomerFeedback.stars_for(perfect) == 3, "accurate stirring earns 3 stars")
	_check(CustomerFeedback.stars_for(okay) == 2, "decent stirring earns 2 stars")
	_check(CustomerFeedback.stars_for(rough) == 1, "rough stirring still earns 1 star")
	_check(CustomerFeedback.stars_for({"accuracy": 0.95, "wrong_way": 0.3}) == 2, "lots of backward stirring costs the third star")
	_check(CustomerFeedback.mood_for_stars(3, perfect) == CustomerFeedback.Mood.DELIGHTED, "3 stars delight the customer")
	_check(CustomerFeedback.mood_for_stars(1, rough) == CustomerFeedback.Mood.WORRIED, "1 star worries them")
	_check(CustomerFeedback.mood_for_stars(1, {"accuracy": 0.1}) == CustomerFeedback.Mood.SAD, "a very poor soup saddens them")
	_check("arrows" in CustomerFeedback.tip_for(backwards, StirPatterns.Id.CIRCLE), "backward stirring gets the arrows tip")
	_check("rainbow" in CustomerFeedback.tip_for(straying, StirPatterns.Id.CIRCLE), "straying gets the stay-on-the-line tip")
	_check("moving" in CustomerFeedback.tip_for(resting, StirPatterns.Id.CIRCLE), "resting gets the keep-moving tip")
	_check("corner" in CustomerFeedback.tip_for(okay, StirPatterns.Id.SQUARE), "an ordinary miss gets a tip for that shape")
	_check("Perfect" in CustomerFeedback.tip_for(perfect, StirPatterns.Id.CIRCLE), "a great stir is praised")
	_check(CustomerFeedback.live_mood(0.9, StirTracker.Feedback.GOOD) == CustomerFeedback.Mood.HAPPY, "good stirring looks happy")
	_check(CustomerFeedback.live_mood(0.9, StirTracker.Feedback.WRONG_WAY) == CustomerFeedback.Mood.CONFUSED, "the wrong way looks confused")
	_check(CustomerFeedback.live_mood(0.3, StirTracker.Feedback.GOOD) == CustomerFeedback.Mood.WORRIED, "poor accuracy looks worried")
	_check("figure eight" in CustomerFeedback.order_line(StirPatterns.Id.FIGURE_EIGHT), "the order names the pattern")


## Scoring is checked directly against the tracker with exact sample paths.
func _test_tracker_scoring() -> void:
	print("Stir scoring")
	await get_tree().process_frame
	var run := func(radius_px: float, direction: int, radians: float) -> StirTracker:
		var tracker := StirTracker.new()
		tracker.set_training_side(mars.Side.RIGHT)
		tracker.begin_stroke()
		var ticks := int(radians / 0.04)
		for i in ticks + 1:
			tracker.add_sample(Vector2.from_angle(direction * 0.04 * i) * radius_px, 1.0 / 60.0)
		return tracker

	var perfect: StirTracker = run.call(125.0, -1, TAU)
	_check(perfect.session_accuracy() > 0.999, "perfect lap scores 100%% (%.1f%%)" % (perfect.session_accuracy() * 100.0))
	_check(absf(perfect.progress - TAU) < 0.1, "perfect lap travels one full turn")
	perfect.free()

	var wide: StirTracker = run.call(125.0 + 51.0, -1, TAU)
	_check(absf(wide.session_accuracy() - 0.5) < 0.01, "a consistently wide lap scores 50%% (%.1f%%)" % (wide.session_accuracy() * 100.0))
	wide.free()

	var backward: StirTracker = run.call(125.0, 1, TAU)
	_check(backward.session_accuracy() == 0.0, "stirring backward scores 0%")
	_check(backward.progress == 0.0, "stirring backward earns no lap progress")
	_check(backward.feedback == StirTracker.Feedback.WRONG_WAY, "stirring backward prompts the patient")
	backward.free()

	var tiny: StirTracker = run.call(20.0, -1, TAU * 3.0)
	_check(tiny.progress == 0.0, "tiny circles near the centre earn no laps")
	_check(tiny.session_accuracy() == 0.0, "tiny circles near the centre score 0%")
	tiny.free()

	var still := StirTracker.new()
	still.set_training_side(mars.Side.RIGHT)
	var points := [0.0]
	still.arc_travelled.connect(func(r: float, q: float) -> void: points[0] += r * q)
	for i in 300:
		still.add_sample(Vector2(125, 0), 1.0 / 60.0)
	_check(points[0] == 0.0 and still.session_accuracy() == -1.0, "holding still on the ring earns nothing")
	_check(still.feedback == StirTracker.Feedback.IDLE, "holding still prompts the patient")
	still.free()

	var jitter := StirTracker.new()
	jitter.set_training_side(mars.Side.RIGHT)
	for i in 300:
		jitter.add_sample(Vector2(125, 0) + Vector2(1.2, -1.2) * (1 if i % 2 == 0 else -1), 1.0 / 60.0)
	_check(jitter.session_accuracy() == -1.0, "sensor jitter below min_step is not scored")
	jitter.free()

	# A slow stir with sensor noise: the patient is on the ring, so the score must stay high.
	var noisy := StirTracker.new()
	noisy.set_training_side(mars.Side.RIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 1000:
		var noise := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		noisy.add_sample(Vector2.from_angle(-0.01 * i) * 125.0 + noise, 1.0 / 60.0)
	_check(noisy.session_accuracy() > 0.95, "a slow noisy stir still scores high (%.1f%%)" % (noisy.session_accuracy() * 100.0))
	_check(absf(noisy.progress - 10.0) < 0.5, "noise does not inflate lap progress (%.2f of 10.0 rad)" % noisy.progress)
	noisy.free()

	var jump := StirTracker.new()
	jump.set_training_side(mars.Side.RIGHT)
	jump.add_sample(Vector2(125, 0), 1.0 / 60.0)
	jump.add_sample(Vector2(-125, 0), 1.0 / 60.0)
	_check(jump.progress == 0.0, "a tracking jump earns no progress")
	jump.free()


func _test_pick_and_drop() -> void:
	print("Pick, reach and drop")
	await _new_game()
	var items: Array = main.ingredients.get_children()
	_check(items.size() == 3, "three ingredients are placed")
	var item: Ingredient = items[0]
	var home := item.global_position

	await _glide(Vector2(640, 660), home, false, 25)
	await _hold(home, false, 3)
	_check(item.highlighted, "hovering highlights the ingredient")
	_check(item.state == Ingredient.State.ON_PLATE, "hovering alone does not pick it up")

	await _hold(home, false, 70)
	_check(item.state == Ingredient.State.HELD and main.cursor.held == item, "one-second hover picks it up")

	var away := Vector2(640, 110)
	await _glide(home, away, true, 30)
	await _hold(away, true, 10)
	_check(item.global_position.distance_to(main.cursor.global_position) < 0.01, "it stays snapped to the hand")

	await _hold(away, false, 10)
	_check(main.cursor.held == null, "opening the grip releases it")
	_check(main.score == 0.0, "dropping outside the pot scores nothing")
	await _hold(away, false, 40)
	_check(item.global_position.distance_to(home) < 1.0 and item.state == Ingredient.State.ON_PLATE, "it returns to its plate")

	# One noisy open-grip reading must not drop a carried item.
	await _glide(away, home, false, 30)
	await _hold(home, false, 70)
	await _hold(home, false, 1)
	await _hold(home, false, 4)
	_check(item.state == Ingredient.State.HELD, "hover pickup does not depend on grip glitches")

	var pot_point: Vector2 = main.pot.global_position
	await _glide(home, pot_point, true, 30)
	await _hold(pot_point, true, 3)
	_check(item.target_pot == main.pot, "the pot detects the ingredient over it")
	_check(main.pot.added == 1 and item.state == Ingredient.State.IN_POT, "entering the pot drops it in automatically")
	_check(main.pot.splash.emitting, "the splash plays")
	_check(main.score == 100.0, "the drop adds to the score")
	await _hold(pot_point, true, 4)
	_check(main.cursor.held != item, "an ingredient in the pot can't be taken back out")
	await _hold(pot_point, false, 8)


func _test_stir_flow() -> void:
	print("Stirring flow")
	await _new_game()
	_check(not main.pot.spoon.can_grab(), "the spoon is locked until the pot is full")
	await _fill_pot()
	_check(main.state == main.State.STIRRING, "a full pot starts the stirring phase")
	_check(main.pot.spoon.can_grab(), "the spoon unlocks")
	_check(main.pot.tracker.visible, "the stirring guide appears")
	var score_before: float = main.score

	await _stir(125.0, main.pot.tracker.direction, 2.0, false)
	_check(main.score == score_before, "moving along the ring without the spoon scores nothing")

	await _grab_spoon()
	_check(main.cursor.held == main.pot.spoon, "grip takes the spoon")
	await _stir(125.0, main.pot.tracker.direction, PI)
	_check(main.score > score_before, "the score rises continuously during accurate stirring (+%.0f)" % (main.score - score_before))
	_check(main.pot.tracker.live_accuracy > 0.95, "the live accuracy reads high (%.0f%%)" % (main.pot.tracker.live_accuracy * 100.0))
	await get_tree().process_frame
	_check(main.hud.accuracy_gauge.value > 95.0, "the dial shows it (%.0f)" % main.hud.accuracy_gauge.value)

	# Laps need two turns in all, and half a lap was already done above.
	var soups_before: int = main.soups
	await _stir(125.0, main.pot.tracker.direction, PI * 3.2)
	_check(main.soups == soups_before + 1, "two laps finish the soup")
	_check(main.cursor.held == null, "the spoon is released when the soup is done")
	await _hold(Vector2(640, 660), false, 130)
	_check(main.ratings.size() == 1 and main.ratings[0] == 3, "a perfect stir earns the customer's 3 stars")
	_check(main.customer.mood == CustomerFeedback.Mood.DELIGHTED, "the customer is delighted")
	_check(main.hud.objective_label.text.contains("Delicious"), "and says so")
	await _hold(Vector2(640, 660), false, 150)
	_check(main.state == main.State.COLLECTING, "the next round starts")
	_check(main.pot.tracker.pattern == StirPatterns.SEQUENCE[1], "with the next pattern")
	_check(main.hud.objective_label.text.contains(StirPatterns.display_name(StirPatterns.SEQUENCE[1])), "which the customer orders")
	_check(main.ingredients.get_child_count() == 3 and main.pot.contents.get_child_count() == 0, "with new vegetables and an empty pot")
	_check(main.pot.tracker.lap_count() == 0, "with lap progress reset")


func _test_tracking_loss() -> void:
	print("Tracking loss")
	await _new_game()
	mars.watchdog_ms = 40
	var left_before: float = main.round_timer.time_left
	var deadline := Time.get_ticks_msec() + 120
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not mars.tracking_ok, "silent telemetry trips the watchdog")
	_check(not mars.grip, "the watchdog cancels the grip")
	_check(main.hud.tracking_banner.visible, "the patient sees the warning")
	_check(main.world.process_mode == Node.PROCESS_MODE_DISABLED, "the game is held")
	var frozen: float = main.round_timer.time_left
	for i in 30:
		await get_tree().process_frame
	_check(main.round_timer.time_left == frozen, "the trial clock is stopped (%.2f of %.2f left)" % [frozen, left_before])
	mars.watchdog_ms = 2000
	await _hold(Vector2(640, 660), false, 3)
	_check(mars.tracking_ok and not main.hud.tracking_banner.visible, "telemetry recovery resumes the game")
	_check(main.round_timer.time_left < frozen, "the clock runs again")
	mars.submit_sample(Vector2(NAN, 0.5), true)
	_check(not mars.grip and mars.normalized_position.is_finite(), "a corrupt sample is rejected")


func _test_left_arm() -> void:
	print("Left arm")
	mars.training_side = mars.Side.LEFT
	await _new_game()
	await _fill_pot()
	_check(main.pot.spoon.position.x < 0.0, "the spoon starts on the screen-left (lateral) side")
	await _grab_spoon()
	_check(main.cursor.held == main.pot.spoon, "grip takes the spoon")
	await _stir(125.0, main.pot.tracker.direction, PI * 4.3)
	_check(main.soups == 1, "two laps in the mirrored direction finish the soup")
	_check(main.pot.tracker.session_accuracy() > 0.9, "and score high (%.0f%%)" % (main.pot.tracker.session_accuracy() * 100.0))
	mars.training_side = mars.Side.RIGHT


func _test_timer_end() -> void:
	print("End of trial")
	await _new_game(1.0)
	var item: Ingredient = main.ingredients.get_child(0)
	await _glide(Vector2(640, 660), item.global_position, false, 20)
	await _hold(item.global_position, true, 4)
	# Held in the hand but kept away from the pot: reaching the pot would drop it in and score.
	var held_at: Vector2 = item.global_position
	var ticks := 0
	while main.state != main.State.FINISHED and ticks < 200:
		await _hold(held_at, true, 1)
		ticks += 1
	_check(main.state == main.State.FINISHED, "the timer ends the trial")
	_check(main.score == 0.0, "a vegetable still held at the buzzer doesn't score")
	_check(main.cursor.held == null, "the hand is emptied")
	_check(main.hud.center_panel.visible and main.hud.body_label.text.contains("Money earned: $0"), "results appear with the money earned")
	_check(main.hud.time_label.text == "0:00", "the clock reads 0:00")
	await _hold(Vector2(640, 660), false, 4)
	await _hold(Vector2(640, 660), true, 2)
	_check(main.state == main.State.FINISHED, "an instant press can't skip the results")
	await _hold(Vector2(640, 660), false, 4)
	var unlock: int = Time.get_ticks_msec() + 1050
	while Time.get_ticks_msec() < unlock:
		await _hold(Vector2(640, 660), false, 1)
	await _hold(Vector2(640, 660), true, 2)
	_check(main.state == main.State.COLLECTING and main.score == 0.0, "a later press starts a fresh game")
	_check(main.pot.tracker.session_accuracy() == -1.0, "with the accuracy record cleared")
	main.free()
	main = null
