extends Control

@export var kind := "image"
@export var color := Color("233041")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = custom_minimum_size.max(Vector2(24, 24))

func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2.ONE * s * 24) / 2, 0, Vector2.ONE * s)
	match kind:
		"send":
			draw_polyline(PackedVector2Array([Vector2(6, 10), Vector2(12, 4), Vector2(18, 10)]), color, 2.4, true)
			draw_line(Vector2(12, 4), Vector2(12, 20), color, 2.4, true)
		"expand":
			draw_polyline(PackedVector2Array([Vector2(13, 4), Vector2(20, 4), Vector2(20, 11)]), color, 2, true)
			draw_line(Vector2(20, 4), Vector2(11, 13), color, 2, true)
			draw_polyline(PackedVector2Array([Vector2(11, 20), Vector2(4, 20), Vector2(4, 13)]), color, 2, true)
			draw_line(Vector2(4, 20), Vector2(13, 11), color, 2, true)
		"close":
			draw_line(Vector2(6, 6), Vector2(18, 18), color, 2, true)
			draw_line(Vector2(18, 6), Vector2(6, 18), color, 2, true)
		"plus":
			draw_line(Vector2(5, 12), Vector2(19, 12), color, 2, true)
			draw_line(Vector2(12, 5), Vector2(12, 19), color, 2, true)
		"image":
			draw_style_box(_outline(), Rect2(3, 3, 18, 18))
			draw_circle(Vector2(16, 8), 2, color)
			draw_polyline(PackedVector2Array([Vector2(4, 17), Vector2(9, 11), Vector2(14, 16), Vector2(17, 13), Vector2(21, 18)]), color, 1.8, true)
		"bow":
			draw_colored_polygon(PackedVector2Array([Vector2(3, 5), Vector2(12, 9), Vector2(12, 15), Vector2(3, 19)]), color)
			draw_colored_polygon(PackedVector2Array([Vector2(21, 5), Vector2(12, 9), Vector2(12, 15), Vector2(21, 19)]), color)
			draw_circle(Vector2(12, 12), 4, color)

func _outline() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	return box
