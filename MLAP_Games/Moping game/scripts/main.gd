extends Node3D
## Builds the kitchen/room, lighting, WorldEnvironment (SSR + glow), floor,
## mop, painter and HUD, and wires them together.

const ROOM := Vector2(7.0, 5.0)     # floor size in metres (X width, Z depth)
const WALL_H := 2.8
const MAX_PILES := 40         # keeps the room playable if dust is left on the floor

const ROOM_NAMES := ["Living room", "Kitchen", "Bedroom"]
const WALL_COLORS := [Color(0.92, 0.88, 0.8), Color(0.97, 0.91, 0.66), Color(0.8, 0.86, 0.93)]

var _painter: FloorPainter
var _mop: MopController
var _hud: Hud
var _cam: Camera3D
var _living: LivingRoom
var _theme_root: Node3D
var _wall_mat: StandardMaterial3D
var _floor_mat: ShaderMaterial
var _events: RoomEvents
var _elapsed := 0.0
var _dust_rate := 1.0          # dust-making speed, set from the HUD slider
var _dust_cleaned := 0
var _piles: Array[DustPile] = []
var _toast := ""
var _toast_until := 0.0
var _rng := RandomNumberGenerator.new()
var _level := 1
var _pair: ChasePair


func _ready() -> void:
	_rng.randomize()
	_painter = FloorPainter.new()
	_painter.floor_size = ROOM
	_painter.analyze_enabled = false       # progress now counts dust piles, not floor coverage
	add_child(_painter)

	_build_environment()
	_build_room()
	_build_floor()
	_build_mop()
	_build_events()
	_spawn_pair()
	_build_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_do_calibrate()
		elif event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			_hud.nudge_dust_rate(0.25)
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_hud.nudge_dust_rate(-0.25)


func _do_calibrate() -> void:
	_mop.calibrate()
	_toast = "Centre set - you're at the middle of the room"
	_toast_until = _elapsed + 2.5


func _process(delta: float) -> void:
	_elapsed += delta        # stops automatically while the tree is paused

	# Hints / status.
	if _elapsed < _toast_until:
		_hud.set_hint(_toast)
	elif not _piles.is_empty():
		_hud.set_hint("Sweep the mop over the dust piles!")
	elif _pair != null:
		_hud.set_hint("The cat is chasing the mouse - they are making a mess!")
	else:
		_hud.set_hint("")
	if _mop.is_device_live():
		_hud.set_device_status("MARS live   ML %+.2f  AP %+.2f" % [_mop.raw_input.x, -_mop.raw_input.y])
	else:
		_hud.set_device_status("No device - mouse control")



func _spawn_pair() -> void:
	if is_instance_valid(_pair):
		_pair.queue_free()
	_pair = ChasePair.new()
	_pair.bounds = ROOM * 0.5 - Vector2(0.4, 0.4)
	_pair.obstacles = _living.obstacles
	_pair.level = _level
	_pair.dust_rate = _dust_rate
	_pair.dropped.connect(_on_dust_dropped)
	_pair.tussle.connect(_on_tussle)
	add_child(_pair)


func _on_tussle(pos: Vector3) -> void:
	_popup(pos + Vector3(0, 0.5, 0), "Crash!", Color(0.85, 0.25, 0.2))


func _on_dust_dropped(pos: Vector3) -> void:
	if _piles.size() >= MAX_PILES:
		return
	var p := DustPile.new()
	p.mop = _mop
	p.position = Vector3(pos.x, 0.0, pos.z)
	p.cleaned.connect(_on_pile_cleaned)
	add_child(p)
	_piles.append(p)


func _on_pile_cleaned(p: DustPile) -> void:
	_piles.erase(p)
	_dust_cleaned += 1
	_hud.set_dust(_dust_cleaned)


func _on_dust_rate_changed(rate: float) -> void:
	_dust_rate = rate
	if is_instance_valid(_pair):
		_pair.dust_rate = rate


## Floating feedback text.
func _popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.outline_modulate = Color.WHITE
	l.position = pos + Vector3(0, 0.4, 0)
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.9, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.65, 0.95)
	sky_mat.sky_horizon_color = Color(0.85, 0.9, 0.95)
	sky_mat.ground_horizon_color = Color(0.85, 0.82, 0.75)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.89, 0.93)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	# Screen Space Reflections (Forward+ only): the wet floor mirrors lights/walls.
	env.ssr_enabled = true
	env.ssr_max_steps = 128
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	# Subtle bloom for a clean, modern look.
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.ssao_enabled = true
	env.ssao_intensity = 1.5

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Fixed camera.
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 3.5, 5.3)
	_cam.fov = 60
	add_child(_cam)
	_cam.look_at(Vector3(0, 0.2, -0.3), Vector3.UP)


func _build_room() -> void:
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = WALL_COLORS[0]
	_wall_mat.roughness = 0.85

	# Thick walls (inner faces stay at +-ROOM/2), a floor slab and a base plate:
	# the room reads like a cutaway model standing on a table.
	var t := 0.3
	var hx := ROOM.x * 0.5
	var hz := ROOM.y * 0.5
	_box(Vector3(ROOM.x + 2.0 * t, WALL_H, t), Vector3(0, WALL_H * 0.5, -hz - t * 0.5), _wall_mat)
	_box(Vector3(t, WALL_H, ROOM.y), Vector3(-hx - t * 0.5, WALL_H * 0.5, 0), _wall_mat)
	_box(Vector3(t, WALL_H, ROOM.y), Vector3(hx + t * 0.5, WALL_H * 0.5, 0), _wall_mat)
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.93, 0.93, 0.92)
	slab_mat.roughness = 0.8
	_box(Vector3(ROOM.x + 2.0 * t, 0.3, ROOM.y + t + 0.2), Vector3(0, -0.153, (0.2 - t) * 0.5), slab_mat)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.78, 0.81, 0.86)
	base_mat.roughness = 0.9
	_box(Vector3(ROOM.x + 3.0, 0.2, ROOM.y + 3.0), Vector3(0, -0.4, 0), base_mat)

	# Furniture, windows, curtains and pictures live under one node so a room can be swapped.
	_theme_root = Node3D.new()
	add_child(_theme_root)
	_apply_room(0)

	# Ceiling light (no visible panel: the room is open on top).
	var omni := OmniLight3D.new()
	omni.position = Vector3(0, WALL_H - 0.3, 0)
	omni.omni_range = 9.0
	omni.light_energy = 2.0
	omni.shadow_enabled = true
	add_child(omni)

	var spot := SpotLight3D.new()
	spot.position = Vector3(1.9, 1.9, -ROOM.y * 0.5 + 0.3)
	spot.spot_range = 9.0
	spot.spot_angle = 50.0
	spot.light_energy = 5.0
	spot.light_color = Color(1.0, 0.92, 0.78)
	spot.shadow_enabled = true
	add_child(spot)
	spot.look_at(Vector3(0.6, 0.0, 0.8))


## Builds the room for level index `idx` (living room, kitchen, bedroom).
func _apply_room(idx: int) -> void:
	for c in _theme_root.get_children():
		c.queue_free()
	_wall_mat.albedo_color = WALL_COLORS[idx]
	match idx:
		1: _living = KitchenRoom.new()
		2: _living = BedroomRoom.new()
		_: _living = LivingRoom.new()
	_living.room = ROOM
	_theme_root.add_child(_living)
	_build_wall_art(_art_items(idx))


## [position, yaw (deg), picture size, style] per room.
func _art_items(idx: int) -> Array:
	var hx := ROOM.x * 0.5
	var hz := ROOM.y * 0.5
	match idx:
		1:
			return [
				[Vector3(hx, 1.7, 1.7), -90.0, Vector2(0.8, 0.6), 3],
				[Vector3(-hx, 1.65, -1.6), 90.0, Vector2(0.6, 0.8), 1],
				[Vector3(-hx, 1.6, 1.9), 90.0, Vector2(0.7, 0.55), 0],
				[Vector3(0.2, 1.6, -hz), 0.0, Vector2(0.55, 0.55), 5],
			]
		2:
			return [
				[Vector3(-1.0, 1.7, -hz), 0.0, Vector2(1.0, 0.7), 3],
				[Vector3(hx, 1.65, 1.5), -90.0, Vector2(0.8, 0.6), 0],
				[Vector3(-hx, 1.7, -1.2), 90.0, Vector2(0.6, 0.8), 4],
				[Vector3(hx, 1.7, -2.2), -90.0, Vector2(0.45, 0.45), 2],
			]
		_:
			return [
				[Vector3(-1.6, 1.65, -hz), 0.0, Vector2(1.1, 0.75), 0],
				[Vector3(0.1, 1.6, -hz), 0.0, Vector2(0.6, 0.85), 1],
				[Vector3(-hx, 1.6, -0.6), 90.0, Vector2(1.0, 0.72), 2],
				[Vector3(-hx, 1.55, 1.6), 90.0, Vector2(0.75, 0.75), 3],
				[Vector3(hx, 1.7, -1.7), -90.0, Vector2(0.7, 0.95), 4],
				[Vector3(-hx, 1.6, -1.9), 90.0, Vector2(0.55, 0.7), 5],
			]


func _apply_floor_theme(idx: int) -> void:
	if _floor_mat == null:
		return
	match idx:
		1:    # kitchen: ceramic tiles
			_floor_mat.set_shader_parameter("floor_style", 1)
			_floor_mat.set_shader_parameter("dirty_roughness", 0.6)
		2:    # bedroom: pale oak
			_floor_mat.set_shader_parameter("floor_style", 0)
			_floor_mat.set_shader_parameter("wood_light", Color(0.86, 0.73, 0.55))
			_floor_mat.set_shader_parameter("wood_dark", Color(0.68, 0.52, 0.36))
			_floor_mat.set_shader_parameter("dirty_roughness", 0.72)
		_:    # living room: warm hardwood
			_floor_mat.set_shader_parameter("floor_style", 0)
			_floor_mat.set_shader_parameter("wood_light", Color(0.74, 0.52, 0.30))
			_floor_mat.set_shader_parameter("wood_dark", Color(0.50, 0.31, 0.15))
			_floor_mat.set_shader_parameter("dirty_roughness", 0.72)


func _build_wall_art(items: Array) -> void:
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.25, 0.15, 0.08)
	frame_mat.roughness = 0.5
	for i in items.size():
		var it: Array = items[i]
		var size: Vector2 = it[2]
		var root := Node3D.new()
		root.position = it[0]
		root.rotation_degrees.y = it[1]
		_theme_root.add_child(root)
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(size.x + 0.1, size.y + 0.1, 0.05)
		frame.mesh = fb
		frame.material_override = frame_mat
		frame.position.z = 0.025
		root.add_child(frame)
		var pic := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = size
		pic.mesh = q
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = WallArt.make(int(it[3]), 1000 + i * 17)
		pm.roughness = 0.7
		pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.material_override = pm
		pic.position.z = 0.054
		root.add_child(pic)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# ---------------------------------------------------------------- floor
func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = ROOM     # UV (0..1) spans the whole room => maps 1:1 to the mask

	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	noise_tex.width = 512
	noise_tex.height = 512

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/floor.gdshader")
	mat.set_shader_parameter("clean_mask", _painter.mask_texture())
	mat.set_shader_parameter("grime_noise", noise_tex)
	var fine := FastNoiseLite.new()
	fine.frequency = 0.09
	var fine_tex := NoiseTexture2D.new()
	fine_tex.noise = fine
	fine_tex.seamless = true
	fine_tex.width = 512
	fine_tex.height = 512
	mat.set_shader_parameter("grime_fine", fine_tex)
	mat.set_shader_parameter("floor_size_m", ROOM)
	_floor_mat = mat
	_apply_floor_theme(0)

	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	floor_mi.mesh = plane
	floor_mi.material_override = mat
	add_child(floor_mi)


# ---------------------------------------------------------------- mop / HUD
func _build_mop() -> void:
	_mop = MopController.new()
	_mop.room_half_extents = ROOM * 0.5 - Vector2(0.2, 0.2)
	_mop.head_bounds = ROOM * 0.5 - Vector2(0.08, 0.08)
	_mop.obstacles = _living.obstacles
	_painter.obstacles = _living.obstacles
	add_child(_mop)
	_painter.track(_mop.mop_area)
	_mop.calibrated.connect(func(_o: Vector2): _painter.reset_stroke())


func _build_events() -> void:
	_events = RoomEvents.new()
	_events.room = ROOM
	_events.painter = _painter
	_events.mop = _mop
	_events.obstacles = _living.obstacles
	add_child(_events)
	_events.announce.connect(func(t: String):
		_toast = t
		_toast_until = _elapsed + 4.5)
	_events.points.connect(_on_event_points)


func _on_event_points(_amount: int, pos: Vector3) -> void:
	_popup(pos + Vector3(0, 0.3, 0), "Nice!", Color(0.9, 0.55, 0.1))


func _build_hud() -> void:
	_hud = Hud.new()
	add_child(_hud)
	_hud.recalibrate_requested.connect(_do_calibrate)
	_hud.auto_range_toggled.connect(func(on: bool): _mop.auto_scale_range = on)
	_hud.pause_toggled.connect(func(p: bool): get_tree().paused = p)
	_hud.set_dust(0)
	_hud.dust_rate_changed.connect(_on_dust_rate_changed)
