class_name GameManager
extends Node2D
## Spawns items, tracks score / mistakes / time, detects level completion.
##
## Keys:  D = toggle hold-still (dwell) selection   R = restart   Esc = quit

signal score_changed(score: int)
signal level_completed(stats: Dictionary)

@export var items_per_category := 3
@export var points_per_item := 10
@export var assist_hint := true      ## pulse the correct bin while an item is carried
@export var dwell_enabled := true    ## hold the pointer still to "click"
@export var dwell_time := 1.8

@onready var bins_root: Node2D = $Bins
@onready var items_root: Node2D = $Items
@onready var pool: ItemPool = $Pool
@onready var hud: GameHud = $HUD
@onready var cursor: RobotCursor = $CursorLayer/Cursor
@onready var mascot: Mascot = $Mascot
@onready var shelf: StickerShelf = $Shelf

var score := 0
var sorted_count := 0
var total_items := 0
var mistakes := 0
var _won := false
var _started_ms := -1
var _zones: Array[DropZone] = []
var _sfx: Sfx

const PATTERNS := ["grid", "wave", "zigzag", "stagger", "arch"]
const HUES := [0.65, 0.58, 0.76, 0.5, 0.86]
var _pattern := "grid"

const PRAISE := ["Great job!", "Well done!", "Perfect!", "Nice one!", "Excellent!", "Lovely!"]


func _ready() -> void:
	InteractableItem.held = null
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN  # we draw our own large cursor
	_sfx = Sfx.new()
	add_child(_sfx)

	for n in get_tree().get_nodes_in_group("drop_zones"):
		_zones.append(n as DropZone)
	# every new game: random categories, background colour and tray pattern
	var picks := Catalog.pick(_zones.size())
	for i in _zones.size():
		_zones[i].configure(picks[i]["id"], picks[i]["name"], picks[i]["color"])
	$Background.hue = HUES.pick_random()
	_pattern = PATTERNS.pick_random()
	for z in _zones:
		z.filled.connect(func(_z: DropZone) -> void: _sfx.play("full"))
	_spawn_items()

	cursor.dwell_enabled = dwell_enabled
	cursor.dwell_time = dwell_time
	cursor.dwell_check = _dwell_ok
	cursor.dwell_triggered.connect(_on_dwell)
	hud.set_progress(score, 0, total_items)
	hud.say("Click an item to pick it up", Color.WHITE, 4.0)
	mascot.greet()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _spawn_items() -> void:
	var per_cat := items_per_category
	var specs: Array = []
	for z in _zones:
		z.set_capacity(per_cat)
		for v in per_cat:
			specs.append([z, v])
	specs.shuffle()
	total_items = specs.size()

	var rect := pool.get_pool_rect()
	for i in total_items:
		var zone: DropZone = specs[i][0]
		var variant: int = specs[i][1]
		var base := _layout(i, total_items, rect)
		base += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))

		var item := InteractableItem.new()
		item.category_id = zone.category_id
		item.accent = zone.accent
		item.tint = Color.from_hsv(fposmod(zone.accent.h + 0.045 * (variant - 1), 1.0),
			clampf(zone.accent.s, 0.3, 0.55), 0.85)
		item.picked_up.connect(_on_picked)
		item.released.connect(_on_released)
		item.sorted.connect(_on_sorted)
		item.rejected.connect(_on_rejected)
		items_root.add_child(item)
		item.global_position = base
		item.home_position = base
		item.pop_in(i * 0.06)


## Two rows; the game's pattern bends or shifts them so each game looks different.
func _layout(i: int, n: int, rect: Rect2) -> Vector2:
	var cols := ceili(n / 2.0)
	var c := i % cols
	var r := floori(float(i) / cols)
	var cw := rect.size.x / cols
	var rh := rect.size.y / 2.0
	var x := rect.position.x + cw * (c + 0.5)
	var y := rect.position.y + rh * (r + 0.5)
	match _pattern:
		"wave":
			y += sin(c * 0.9 + r * PI) * 40.0
		"zigzag":
			y += 35.0 if (c + r) % 2 == 0 else -35.0
		"stagger":
			x += cw * 0.2 if r == 0 else -cw * 0.2
		"arch":
			var m := (cols - 1) * 0.5
			var u := (c - m) / maxf(m, 0.5)
			y += (u * u - 0.5) * 80.0
	return Vector2(x, y)


func _zone_for(category: String) -> DropZone:
	for z in _zones:
		if z.category_id == category:
			return z
	return null


# --- item signals -----------------------------------------------------------

func _on_picked(item: InteractableItem) -> void:
	if _started_ms < 0:
		_started_ms = Time.get_ticks_msec()
	var zone := _zone_for(item.category_id)
	if assist_hint and zone:
		zone.set_hint(true)
	hud.say("Take it to: %s" % zone.display_name, zone.accent, 6.0)
	_sfx.play("pick")
	mascot.on_pick()


func _on_released(_item: InteractableItem) -> void:
	for z in _zones:
		z.set_hint(false)


func _on_sorted(_item: InteractableItem, _zone: DropZone) -> void:
	sorted_count += 1
	score += points_per_item
	score_changed.emit(score)
	hud.set_progress(score, sorted_count, total_items)
	_sfx.play_note(sorted_count - 1)
	mascot.on_sorted()
	if sorted_count >= total_items:
		_win()
	elif sorted_count == total_items / 2:
		hud.say("Halfway there!", Color(0.92, 0.8, 0.55))
	else:
		hud.say(PRAISE[randi() % PRAISE.size()], Color(0.62, 0.82, 0.7))


func _on_rejected(item: InteractableItem, zone: DropZone) -> void:
	mistakes += 1  # tracked for the therapist, never subtracted from the score
	_sfx.play("oops")
	mascot.on_rejected()
	var right := _zone_for(item.category_id)
	if zone != null:
		hud.say("Almost! Try the %s bin" % right.display_name, right.accent)
	else:
		hud.say("Move it over a bin, then click", Color.WHITE)


# --- completion -------------------------------------------------------------

func _win() -> void:
	_won = true
	await get_tree().create_timer(0.9).timeout
	Fx.confetti(self, 1920.0)
	_sfx.play("win")
	shelf.add_sticker()
	mascot.celebrate()
	var seconds := 0.0
	if _started_ms >= 0:
		seconds = (Time.get_ticks_msec() - _started_ms) / 1000.0
	hud.say("All sorted!", Color(0.92, 0.8, 0.55), 3.0)
	level_completed.emit({"score": score, "seconds": seconds, "retries": mistakes, "items": total_items})
	await get_tree().create_timer(3.5).timeout
	restart()


func restart() -> void:
	get_tree().reload_current_scene()


# --- dwell (hold-still) selection -------------------------------------------

func _dwell_ok(p: Vector2) -> bool:
	if _won:
		return false
	var h := InteractableItem.held
	if is_instance_valid(h):
		return h.find_target_zone() != null
	for n in items_root.get_children():
		var item := n as InteractableItem
		if item and item.is_selectable_at(p):
			return true
	return false


func _on_dwell(p: Vector2) -> void:
	if _won:
		return
	# Synthesize a left click so items handle dwell exactly like a real click.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	ev.global_position = p
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_D:
				dwell_enabled = not dwell_enabled
				cursor.dwell_enabled = dwell_enabled
				hud.say("Hold-still select: %s" % ("ON" if dwell_enabled else "OFF"))
			KEY_R:
				restart()
			KEY_ESCAPE:
				get_tree().quit()
