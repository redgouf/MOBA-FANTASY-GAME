class_name FigureView
extends SubViewportContainer
## A small 3D stage inside the UI: its own world with a camera and lights,
## showing one ChampionFigure. The Equipment view uses it live (the figure
## slowly turns left and right); champion select also uses one hidden stage
## to photograph every champion's portrait once.

var viewport: SubViewport
var camera: Camera3D
var figure: ChampionFigure
var sway := true               # turn the figure slowly left and right
var portrait := false          # frame head and shoulders instead of the full body
var facing_deg := -12.0        # portrait: how far the figure turns (+ = looking to the screen's right)

var _pivot: Node3D
var _t := 0.0


static func create(parent: Control, rect: Rect2, p_portrait: bool = false) -> FigureView:
	var v := FigureView.new()
	v.portrait = p_portrait
	v.position = rect.position
	v.size = rect.size
	v.stretch = true
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	v._build(Vector2i(rect.size))
	return v


func _build(px: Vector2i) -> void:
	viewport = SubViewport.new()
	viewport.size = px
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.7, 0.62)
	e.ambient_light_energy = 0.7
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_energy = 1.15
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.45
	rim.light_color = Color(1.0, 0.85, 0.6)
	viewport.add_child(rim)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	camera = Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)


## Shows a champion (replacing the previous figure).
func show_champion(id: String) -> void:
	if figure != null:
		figure.queue_free()
		figure = null
	if id == "":
		return
	figure = ChampionFigure.build(id)
	_pivot.add_child(figure)
	_pivot.rotation = Vector3.ZERO
	_t = 0.0
	_frame()


func _frame() -> void:
	if figure == null:
		return
	var h := figure.height
	var aspect := float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	if portrait:
		# Head and shoulders, from slightly to the side like an OSRS chathead.
		var look := Vector3(0, h * 0.84, 0)
		var dist := h * 0.42 / tan(deg_to_rad(camera.fov * 0.5))
		camera.position = look + Vector3(dist * 0.35, h * 0.04, dist)
		camera.look_at(look)
		_pivot.rotation.y = deg_to_rad(facing_deg)
	else:
		var look := Vector3(0, h * 0.5, 0)
		var fit := maxf(h * 1.12, h * 0.6 / aspect)
		var dist := fit * 0.5 / tan(deg_to_rad(camera.fov * 0.5))
		camera.position = look + Vector3(0, h * 0.08, dist)
		camera.look_at(look)


func _process(delta: float) -> void:
	if figure == null or not sway or portrait:
		return
	_t += delta
	# Slowly turn left and right (about 50 degrees each way, 10 s a sweep).
	_pivot.rotation.y = sin(_t * 0.6) * deg_to_rad(50.0)


## Renders one champion's portrait into a texture (await it). Returns null
## when nothing can be rendered (headless runs).
func snapshot(id: String) -> Texture2D:
	show_champion(id)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex := viewport.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
