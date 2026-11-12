extends Node
## Autoload "MarsInput": the only place in the game that knows where input comes from.
##
## Everything else reads `normalized_position`, `grip` and `tracking_ok`. To drive the game
## from the device, call submit_sample() once per telemetry packet. The first call switches
## off the mouse simulation for the rest of the run.

signal tracking_changed(ok: bool)

enum Source { SIMULATION, DEVICE }
enum Side { RIGHT, LEFT }

## Matches the two-second telemetry timeout in MARS-HOMER's core/robot.gd.
@export var watchdog_ms := 2000

var source := Source.SIMULATION
## The arm being trained. Sets which way "lateral to anterior" runs on screen.
var training_side := Side.RIGHT
## (0,0) is the top-left of the patient's assessed range, (1,1) the bottom-right.
var normalized_position := Vector2(0.5, 0.5)
var grip := false
var tracking_ok := true

var _last_sample_ms := 0


func _ready() -> void:
	# Must keep running while the game is held, or tracking could never recover.
	process_mode = Node.PROCESS_MODE_ALWAYS


## position: 0..1 on both axes. grip_down: true while the handle button is held.
## The MARS button is active-low, so pass `packet.button == 0`.
func submit_sample(position: Vector2, grip_down: bool) -> void:
	if not position.is_finite():
		return
	source = Source.DEVICE
	_last_sample_ms = Time.get_ticks_msec()
	normalized_position = position.clamp(Vector2.ZERO, Vector2.ONE)
	grip = grip_down
	_set_tracking(true)


func _process(_delta: float) -> void:
	if source == Source.SIMULATION:
		_poll_simulation()
	elif Time.get_ticks_msec() - _last_sample_ms > watchdog_ms:
		# A stale press must not stay active, so the grip is cancelled with the link.
		grip = false
		_set_tracking(false)


## Mouse stands in for the arm. Left button or Space stands in for the grip.
func _poll_simulation() -> void:
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	normalized_position = (viewport.get_mouse_position() / size).clamp(Vector2.ZERO, Vector2.ONE)
	grip = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)


func _set_tracking(ok: bool) -> void:
	if ok != tracking_ok:
		tracking_ok = ok
		tracking_changed.emit(ok)
