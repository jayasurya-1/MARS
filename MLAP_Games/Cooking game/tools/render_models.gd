extends Node
## Renders Kenney Food Kit models to transparent PNG sprites in assets/props/.
## Needs a real renderer (not --headless):
##   godot --path . res://tools/render_models.tscn

const MODEL_DIR := "res://assets/kenney_food_kit/Models/GLB format/"
const OUT_DIR := "res://assets/props/"
const SIZE := 384
const MODELS := [
	"bowl-soup", "bowl-broth", "cutting-board", "cooking-spoon", "cooking-knife",
	"plate-dinner", "plate-deep", "bottle-oil", "bottle-ketchup", "shaker-salt",
	"shaker-pepper", "pepper-mill", "bag", "pot-stew", "pan-stew", "cabbage", "corn",
	"eggplant", "leek", "radish", "beet", "knife-block", "utensil-spoon", "tomato-slice",
	"cooking-spatula", "cooking-fork", "bowl", "cup-tea",
]
## Yaw and pitch of the camera, giving the same 3/4 view as the kitchen.
const YAW := deg_to_rad(30.0)
const PITCH := deg_to_rad(40.0)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.8, 0.78)
	env.ambient_light_energy = 0.75
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.35
	viewport.add_child(fill)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	camera.current = true

	for model_name: String in MODELS:
		var scene: PackedScene = load(MODEL_DIR + model_name + ".glb")
		if scene == null:
			print("missing: ", model_name)
			continue
		var node: Node3D = scene.instantiate()
		viewport.add_child(node)
		await get_tree().process_frame
		var box := _bounds(node)
		var centre := box.get_center()
		var dir := Vector3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH))
		camera.size = box.size.length() * 1.02
		camera.position = centre + dir * 10.0
		camera.look_at(centre)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.save_png(OUT_DIR + model_name + ".png")
		print("rendered ", model_name)
		node.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
