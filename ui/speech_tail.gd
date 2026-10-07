extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(30, 17)

func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(0,0),Vector2(15,16),Vector2(30,0)]), Color.WHITE)
	draw_polyline(PackedVector2Array([Vector2(0,0),Vector2(15,16),Vector2(30,0)]), Color("e0e5ed"), 1, true)
