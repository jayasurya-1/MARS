class_name DustPile
extends Node3D
## A pile of dust dropped by the cat and mouse. Sweep the mop over it to clean it.

signal cleaned(p: DustPile)

var mop: MopController
var radius := 0.22
var health := 1.0

var _gone := false
var _clump: Node3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_clump = Node3D.new()
	add_child(_clump)
	for i in 9:
		var m := StandardMaterial3D.new()
		var g := rng.randf_range(0.6, 0.82)
		m.albedo_color = Color(g, g * 0.97, g * 0.92)
		m.roughness = 1.0
		var s := SphereMesh.new()
		var r := rng.randf_range(0.04, 0.09)
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		var a := rng.randf() * TAU
		var d := rng.randf() * radius * 0.8
		mi.position = Vector3(cos(a) * d, r * 0.4, sin(a) * d)
		mi.scale = Vector3(1.2, 0.5, 1.2)
		_clump.add_child(mi)
	# Pop in.
	_clump.scale = Vector3.ONE * 0.1
	create_tween().tween_property(_clump, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if _gone or mop == null:
		return
	var d := mop.head.global_position - global_position
	d.y = 0.0
	if d.length() < radius + 0.25:
		health -= delta * 2.2
		var k := clampf(health, 0.0, 1.0)
		_clump.scale = Vector3.ONE * lerpf(0.25, 1.0, k)
		if health <= 0.0:
			_gone = true
			_poof()
			cleaned.emit(self)


func _poof() -> void:
	_clump.visible = false
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.85, 0.85)
	sm.material = pm
	p.mesh = sm
	p.amount = 18
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -3, 0)
	p.position.y = 0.05
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(queue_free)
