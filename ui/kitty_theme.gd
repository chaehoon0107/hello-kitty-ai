extends RefCounted

const INK := Color("233041")
const MUTED := Color("8491a3")
const BLUE := Color("49bad2")
const PALE := Color("e8f6fa")
const BORDER := Color("e0e5ed")
const FONT = preload("res://assets/fonts/Griun_Yeeun-Rg.ttf")

static func panel(color := Color.WHITE, radius := 22, padding := 16, shadow := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(padding)
	box.border_color = BORDER
	box.set_border_width_all(1)
	if shadow:
		box.shadow_color = Color(0.10, 0.18, 0.29, 0.12)
		box.shadow_size = 14
		box.shadow_offset = Vector2(0, 5)
	return box

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_stylebox("normal", "Button", panel(Color.WHITE, 12, 10))
	theme.set_stylebox("hover", "Button", panel(PALE, 12, 10))
	theme.set_stylebox("pressed", "Button", panel(Color("d4edf5"), 12, 10))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("normal", "TextEdit", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "TextEdit", StyleBoxEmpty.new())
	theme.set_color("font_color", "TextEdit", INK)
	theme.set_color("font_placeholder_color", "TextEdit", MUTED)
	theme.set_color("caret_color", "TextEdit", BLUE)
	theme.set_color("selection_color", "TextEdit", Color("c5eaf4"))
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 12)
	return theme

static func label(text: String, font_size := 16, color := INK) -> Label:
	var result := Label.new()
	result.add_theme_font_override("font", FONT)
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

static func make_file_dialog_theme() -> Theme:
	var theme := make_theme()
	for type in ["AcceptDialog", "FileDialog", "Window", "PopupPanel", "PopupMenu"]:
		theme.set_stylebox("panel", type, panel(Color("f5f7fb"), 12, 16))
	for type in ["Tree", "ItemList", "LineEdit"]:
		theme.set_stylebox("panel" if type != "LineEdit" else "normal", type, panel(Color.WHITE, 8, 8))
		theme.set_stylebox("focus", type, panel(PALE, 8, 8))
		for key in ["font_color", "font_selected_color", "font_hovered_color"]:
			theme.set_color(key, type, INK)
		theme.set_color("font_uneditable_color", type, MUTED)
	for key in ["selected", "selected_focus", "hovered", "hovered_dimmed"]:
		theme.set_stylebox(key, "Tree", panel(Color("c5eaf4"), 6, 4))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_stylebox("hover", "PopupMenu", panel(PALE, 6, 6))
	theme.set_color("font_disabled_color", "Button", Color("68788a"))
	theme.set_stylebox("disabled", "Button", panel(Color("e5e9ef"), 12, 10))
	return theme

static func button(text: String, accent := false) -> Button:
	var result := Button.new()
	result.theme = make_theme()
	result.text = text
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.focus_mode = Control.FOCUS_NONE
	if accent:
		result.add_theme_stylebox_override("normal", panel(BLUE, 24, 10))
		result.add_theme_stylebox_override("hover", panel(Color("32a9c2"), 24, 10))
		result.add_theme_stylebox_override("pressed", panel(Color("208fa9"), 24, 10))
		result.add_theme_stylebox_override("disabled", panel(Color("cfdae1"), 24, 10))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			result.add_theme_color_override(state, Color.WHITE)
	return result
