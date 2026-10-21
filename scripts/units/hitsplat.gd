class_name Hitsplat
extends Label3D
## Floating damage number, a nod to OSRS hitsplats (blue for zero, red for damage).


static func spawn(parent: Node, at: Vector3, amount: float, color: Color) -> void:
	var splat := Hitsplat.new()
	splat.text = str(int(round(amount)))
	splat.modulate = color
	splat.outline_modulate = Color(0, 0, 0, 0.9)
	splat.outline_size = 10
	splat.font_size = 44
	splat.pixel_size = 0.01
	splat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	splat.no_depth_test = true
	parent.add_child(splat)
	splat.global_position = at
	var tween := splat.create_tween()
	tween.set_parallel(true)
	tween.tween_property(splat, "global_position", at + Vector3.UP * 1.2, 0.8)
	tween.tween_property(splat, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(splat.queue_free)
