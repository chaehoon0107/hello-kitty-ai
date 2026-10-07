extends Control

var time := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(110, 38)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if is_visible_in_tree():
		time += delta
		queue_redraw()

func _draw() -> void:
	for i in 4:
		var wave := pow(maxf(0, sin(time * 4.5 - i * 0.7)), 3)
		var center := Vector2(size.x / 2 - 36 + i * 24, size.y / 2 - wave * 3)
		draw_set_transform(center, 0, Vector2(1 + wave * 0.35, 1 - wave * 0.10))
		draw_circle(Vector2.ZERO, 5.2 + wave * 1.5, Color("4fc6d8").lerp(Color("9eedf2"), wave))
