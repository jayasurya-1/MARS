extends Node3D
## Main scene root. Assembles everything and runs the title -> tour flow.
##
## Main (Node3D)                       <- this script
## ├─ WorldEnvironment   (environment_controller.gd)
## ├─ Sun                (DirectionalLight3D, cool fill light)
## ├─ SynthAudio         (synth_audio.gd)
## ├─ Player             (player.gd)
## ├─ ChaseCamera        (chase_camera.gd, Camera3D)
## │  └─ Constellation   (appears on milestones)
## ├─ GameController     (game_controller.gd)
## └─ HUD (CanvasLayer)
##    └─ Score, Popup, Center labels
##
## Title screen keys: 1-3 theme, M gentle (reduced-motion) mode, Enter/Space start.

const PlayerScript = preload("res://scripts/player.gd")
const CameraScript = preload("res://scripts/chase_camera.gd")
const ControllerScript = preload("res://scripts/game_controller.gd")
const EnvScript = preload("res://scripts/environment_controller.gd")
const AudioScript = preload("res://scripts/synth_audio.gd")
const ConstellationScript = preload("res://scripts/constellation.gd")

var _touring := false
var _world: EnvironmentController
var _audio: SynthAudio
var _player: Player
var _cam: ChaseCamera
var _controller: GameController
var _score_label: Label
var _popup: Label
var _center: Label
var _popup_tween: Tween
var _reduced := false


func _ready() -> void:
	Engine.time_scale = 1.0

	_world = EnvScript.new() as EnvironmentController
	_world.name = "WorldEnvironment"
	add_child(_world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_color = Color(0.65, 0.75, 1.0)
	sun.light_energy = 0.9
	add_child(sun)

	_audio = AudioScript.new() as SynthAudio
	_audio.name = "SynthAudio"
	add_child(_audio)

	_player = PlayerScript.new() as Player
	_player.name = "Player"
	add_child(_player)
	_world.player = _player

	_cam = CameraScript.new() as ChaseCamera
	_cam.name = "ChaseCamera"
	_cam.target = _player
	add_child(_cam)
	_cam.current = true

	_controller = ControllerScript.new() as GameController
	_controller.name = "GameController"
	add_child(_controller)
	_controller.setup(_player)
	_controller.popup.connect(_show_popup)
	_controller.milestone.connect(_on_milestone)
	_player.collected.connect(_on_collected)

	_build_hud()
	_refresh_title()


func _process(_delta: float) -> void:
	if not _touring:
		if Input.is_action_just_pressed("ui_accept"):
			_touring = true
			_center.text = ""
			_player.active = true
			_controller.running = true
		return
	_score_label.text = "★ %d\n%d m" % [_player.star_count, int(_controller.distance)]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3:
			if not _touring:
				_world.set_theme(event.keycode - KEY_1)
				_refresh_title()
		KEY_M:
			_reduced = not _reduced
			_cam.set_reduced_motion(_reduced)
			if _touring:
				_show_popup("Gentle mode: %s" % ("on" if _reduced else "off"))
			else:
				_refresh_title()


func _on_collected(_count: int, note: int) -> void:
	_audio.play_note(note)
	_cam.shake(0.2)


func _on_milestone(count: int) -> void:
	_audio.play_chime()
	_player.celebrate()
	var c := ConstellationScript.new() as Constellation
	_cam.add_child(c)
	c.position = Vector3(0, 7, -45)
	var shape_name := c.show_shape(count / 10 - 1)
	_show_popup("A new constellation: %s" % shape_name)


func _refresh_title() -> void:
	_center.text = "COSMIC DRIFT\n\nPress Enter / Space to begin the tour\n← → steer  ·  collect glowing lights  ·  fly through rings\n\nTheme (1-3):  %s\nGentle mode (M):  %s" % [
		_world.theme_name(), "on" if _reduced else "off"]


func _show_popup(text: String) -> void:
	_popup.text = text
	_popup.modulate.a = 1.0
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.8).set_delay(1.8)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	_score_label = _make_label(hud, 28, HORIZONTAL_ALIGNMENT_LEFT)
	_score_label.position = Vector2(24, 18)

	_popup = _make_label(hud, 34, HORIZONTAL_ALIGNMENT_CENTER)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.offset_top = 120
	_popup.modulate = Color(0.6, 0.95, 1.0, 0.0)

	_center = _make_label(hud, 38, HORIZONTAL_ALIGNMENT_CENTER)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _make_label(parent: Node, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	parent.add_child(l)
	return l
