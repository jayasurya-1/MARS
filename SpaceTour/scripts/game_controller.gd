class_name GameController
extends Node3D
## Tour director: speed ramp and pooled spawning along the route.
## Collectable segments rotate between light ribbons, ring gates and long melody trails;
## scenery adds drifting rocks, planets, nebulae, auroras, jellyfish and comets.
##
## GameController (Node3D)             <- this script
## ├─ Pool (Node3D) → Asteroid x pool_size, Pickup x pickup_pool_size
## └─ Planet / nebula / Aurora / Jelly nodes (spawned ahead, freed once passed), Comet

signal popup(text: String)
signal milestone(count: int)

const AsteroidScript = preload("res://scripts/asteroid.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const PlanetScript = preload("res://scripts/planet.gd")
const AuroraScript = preload("res://scripts/aurora.gd")
const JellyScript = preload("res://scripts/jelly.gd")
const CometScript = preload("res://scripts/comet.gd")
const PT = preload("res://scripts/path_track.gd")
const Fx = preload("res://scripts/fx.gd")
const NAMES := [
	"Aurelia", "Kepler-9b", "Nyx", "Orion Veil", "Helios",
	"Cygnus Reach", "Lyra Prime", "Vega Minor", "Tau Ceti", "Andromeda Gate",
]

@export var pool_size := 90
@export var pickup_pool_size := 70
@export var spawn_distance := 200.0
@export var despawn_behind := 30.0
@export var speed_gain_per_second := 0.006
@export var max_multiplier := 1.8

var player: Player
var elapsed := 0.0
var distance := 0.0
var running := false

var _free: Array[Asteroid] = []
var _active: Array[Asteroid] = []
var _free_orbs: Array[Pickup] = []
var _active_orbs: Array[Pickup] = []
var _scenery: Array[Node3D] = []
var _next_rock_s := 40.0
var _next_orb_s := 50.0
var _next_planet_s := 150.0
var _next_nebula_s := 60.0
var _next_aurora_s := 120.0
var _next_jelly_s := 90.0
var _comet_timer := 10.0
var _name_i := 0


func setup(p: Player) -> void:
	player = p
	player.collected.connect(_on_collected)
	var holder := Node3D.new()
	holder.name = "Pool"
	add_child(holder)
	for i in pool_size:
		var a := AsteroidScript.new() as Asteroid
		holder.add_child(a)
		_free.append(a)
	for i in pickup_pool_size:
		var o := PickupScript.new() as Pickup
		holder.add_child(o)
		_free_orbs.append(o)
	_name_i = randi() % NAMES.size()


func _process(delta: float) -> void:
	if player == null:
		return
	distance = player.s
	if not running:
		return

	elapsed += delta
	player.speed_multiplier = minf(1.0 + elapsed * speed_gain_per_second, max_multiplier)

	var horizon := player.s + spawn_distance
	while _next_rock_s < horizon:
		_spawn_rocks(_next_rock_s)
		_next_rock_s += randf_range(30.0, 50.0)
	while _next_orb_s < horizon:
		_next_orb_s += _spawn_segment(_next_orb_s) + randf_range(40.0, 70.0)
	while _next_jelly_s < horizon:
		_spawn_jellies(_next_jelly_s)
		_next_jelly_s += randf_range(320.0, 460.0)
	var far := player.s + 380.0
	while _next_planet_s < far:
		_spawn_planet(_next_planet_s)
		_next_planet_s += randf_range(450.0, 700.0)
	while _next_nebula_s < far:
		_spawn_nebula(_next_nebula_s)
		_next_nebula_s += randf_range(320.0, 460.0)
	while _next_aurora_s < far:
		_spawn_aurora(_next_aurora_s)
		_next_aurora_s += randf_range(480.0, 700.0)
	_comet_timer -= delta
	if _comet_timer <= 0.0:
		_spawn_comet()
		_comet_timer = randf_range(50.0, 90.0)

	var ps := player.s
	for i in range(_active.size() - 1, -1, -1):
		var a := _active[i]
		if float(a.get_meta("s")) < ps - despawn_behind:
			a.deactivate()
			_active.remove_at(i)
			_free.append(a)
	for i in range(_active_orbs.size() - 1, -1, -1):
		var o := _active_orbs[i]
		if not o.active or float(o.get_meta("s")) < ps - despawn_behind:
			o.deactivate()
			_active_orbs.remove_at(i)
			_free_orbs.append(o)
	for i in range(_scenery.size() - 1, -1, -1):
		var n := _scenery[i]
		var ns: float = n.get_meta("s")
		if n.has_meta("name") and not n.has_meta("announced") and ns - 130.0 < ps:
			n.set_meta("announced", true)
			popup.emit("Approaching %s" % n.get_meta("name"))
		if ns < ps - 250.0:
			n.queue_free()
			_scenery.remove_at(i)


func _on_collected(count: int, _note: int) -> void:
	if count % 10 == 0:
		popup.emit("Your light grows brighter!  ★ %d" % count)
		milestone.emit(count)
	else:
		popup.emit("★ %d" % count)


# --- collectable segments ---------------------------------------------------

## Picks a segment type; returns its length along the route.
func _spawn_segment(s: float) -> float:
	var r := randf()
	if r < 0.5:
		_spawn_trail(s)
		return 42.0
	if r < 0.78:
		_spawn_rings(s)
		return 110.0
	_spawn_long_trail(s)
	return 64.0


func _take_orb() -> Pickup:
	if _free_orbs.is_empty():
		return null
	return _free_orbs.pop_back()


## Weaving ribbon of 7 lights; the bell notes rise along it.
func _spawn_trail(s: float) -> void:
	var base := randf_range(-3.5, 3.5)
	var phase := randf() * TAU
	var hue := randf()
	for i in 7:
		var o := _take_orb()
		if o == null:
			return
		var x := clampf(base + 3.0 * sin(phase + i * 0.8), -5.5, 5.5)
		var os := s + i * 6.0
		o.note = i
		o.activate(PT.point(os, x, 0.0), Color.from_hsv(fposmod(hue + i * 0.04, 1.0), 0.7, 1.0))
		o.set_meta("s", os)
		_active_orbs.append(o)


## Five big rings to fly through, in a gentle S-curve.
func _spawn_rings(s: float) -> void:
	var base := randf_range(-3.0, 3.0)
	var phase := randf() * TAU
	var hue := randf()
	for i in 5:
		var o := _take_orb()
		if o == null:
			return
		var x := clampf(base + 3.5 * sin(phase + i * 0.9), -5.0, 5.0)
		var os := s + i * 22.0
		o.note = i + 2
		o.activate(PT.point(os, x, 0.0), Color.from_hsv(fposmod(hue + i * 0.06, 1.0), 0.5, 1.0),
				true, PT.frame(os))
		o.set_meta("s", os)
		_active_orbs.append(o)


## A long, smooth serpentine of 16 lights that plays a rising and falling melody.
func _spawn_long_trail(s: float) -> void:
	var phase := randf() * TAU
	var hue := randf()
	for i in 16:
		var o := _take_orb()
		if o == null:
			return
		var x := clampf(3.8 * sin(phase + i * 0.35), -5.2, 5.2)
		var os := s + i * 4.0
		o.note = 6 - absi((i % 12) - 6)
		o.activate(PT.point(os, x, 0.0), Color.from_hsv(fposmod(hue + i * 0.03, 1.0), 0.6, 1.0))
		o.set_meta("s", os)
		_active_orbs.append(o)


# --- scenery ----------------------------------------------------------------

## Harmless drifting rocks around the route (scenery only).
func _spawn_rocks(s: float) -> void:
	for i in randi_range(1, 2):
		if _free.is_empty():
			return
		# Keep the flight lane clear so the collectables are the only things in it.
		var lx := randf_range(14.0, 40.0) * (1.0 if randf() < 0.5 else -1.0)
		var ly := randf_range(-16.0, 16.0)
		var a: Asteroid = _free.pop_back()
		a.activate(PT.point(s + randf_range(-5.0, 5.0), lx, ly), randf_range(0.8, 2.4))
		a.set_meta("s", s)
		_active.append(a)


func _spawn_planet(s: float) -> void:
	var side := 1.0 if randf() < 0.5 else -1.0
	var r := randf_range(14.0, 34.0)
	var p := PlanetScript.new() as Planet
	add_child(p)
	p.setup(r, Color.from_hsv(randf(), 0.55, 0.9), randf() < 0.4)
	p.global_position = PT.point(s, side * (r + randf_range(45.0, 90.0)), randf_range(-35.0, 35.0))
	p.set_meta("s", s)
	p.set_meta("name", NAMES[_name_i % NAMES.size()])
	_name_i += 1
	_scenery.append(p)


func _spawn_nebula(s: float) -> void:
	var side := 1.0 if randf() < 0.5 else -1.0
	var h := Fx.halo(randf_range(120.0, 220.0), Color.from_hsv(randf(), 0.6, 1.0, 0.09))
	add_child(h)
	h.global_position = PT.point(s, side * randf_range(60.0, 160.0), randf_range(-60.0, 60.0))
	h.set_meta("s", s)
	_scenery.append(h)


func _spawn_aurora(s: float) -> void:
	var side := 1.0 if randf() < 0.5 else -1.0
	var a := AuroraScript.new() as Aurora
	add_child(a)
	var hue: float = [0.38, 0.48, 0.78][randi() % 3]
	a.setup(Color.from_hsv(hue, 0.7, 1.0))
	var pos := PT.point(s, side * randf_range(70.0, 120.0), randf_range(20.0, 50.0))
	a.global_position = pos
	a.look_at(PT.point(s, 0.0, 0.0), Vector3.UP)   # curtain faces the route
	a.set_meta("s", s)
	_scenery.append(a)


func _spawn_jellies(s: float) -> void:
	var side := 1.0 if randf() < 0.5 else -1.0
	var hue := randf_range(0.45, 0.95)
	for i in 2:
		var j := JellyScript.new() as Jelly
		add_child(j)
		j.setup(Color.from_hsv(fposmod(hue + i * 0.04, 1.0), 0.45, 1.0), randf_range(1.5, 3.2))
		var js := s + i * randf_range(8.0, 16.0)
		j.global_position = PT.point(js, side * randf_range(20.0, 40.0), randf_range(-12.0, 14.0))
		j.set_meta("s", js)
		_scenery.append(j)


func _spawn_comet() -> void:
	var side := 1.0 if randf() < 0.5 else -1.0
	var s := player.s + 110.0
	var b := PT.frame(s)
	var c := CometScript.new() as Comet
	add_child(c)
	c.global_position = PT.point(s, side * randf_range(35.0, 60.0), randf_range(14.0, 30.0))
	c.velocity = -b.z * 12.0 + b.x * (-side * 9.0) - b.y * 1.5
