extends PanelContainer

signal submitted(text: String, image_path: String)
signal geometry_changed
signal pick_image_requested
const Kit = preload("res://ui/kitty_theme.gd")
const Icon = preload("res://ui/icon.gd")

var input: TextEdit
var send_button: Button
var preview_row: HBoxContainer
var preview: TextureRect
var filename: Label
var image_path := ""
var busy := false
var expanded := false
var drop_hover := false
var content: VBoxContainer
var drop_content: VBoxContainer
var style: StyleBoxFlat
var tween: Tween
var target_size := Vector2(536, 72)

func _ready() -> void:
	theme = Kit.make_theme()
	style = Kit.panel(Color.WHITE, 36, 14, true)
	add_theme_stylebox_override("panel", style)
	content = VBoxContainer.new()
	add_child(content)
	preview_row = HBoxContainer.new()
	preview_row.visible = false
	content.add_child(preview_row)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.panel(Kit.PALE, 20, 8))
	preview_row.add_child(card)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(132, 120)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(preview)
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_child(caption)
	caption.add_child(Kit.label("첨부한 이미지", 13, Kit.MUTED))
	filename = Kit.label("", 14)
	filename.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	filename.custom_minimum_size.x = 160
	caption.add_child(filename)
	var remove := Kit.button("제거")
	remove.pressed.connect(clear_attachment)
	caption.add_child(remove)
	var row := HBoxContainer.new()
	content.add_child(row)
	var attach := _icon_button("plus", Kit.MUTED, false)
	attach.tooltip_text = "이미지 첨부 (PNG · JPG · WEBP)"
	attach.pressed.connect(func(): pick_image_requested.emit())
	row.add_child(attach)
	input = TextEdit.new()
	input.name = "QuestionInput"
	input.placeholder_text = "무엇이 궁금하신가요"
	input.custom_minimum_size = Vector2(320, 42)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.scroll_fit_content_height = false
	input.add_theme_font_size_override("font_size", 17)
	input.gui_input.connect(_key_input)
	input.text_changed.connect(_update_send)
	# IME composition changes do not emit text_changed until committed.
	input.lines_edited_from.connect(func(_from, _to): _update_send.call_deferred())
	input.focus_entered.connect(_activate_ime.call_deferred)
	get_window().focus_entered.connect(_activate_ime.call_deferred)
	row.add_child(input)
	send_button = _icon_button("send", Color.WHITE, true)
	send_button.name = "SendQuestion"
	send_button.tooltip_text = "보내기"
	send_button.pressed.connect(_submit)
	row.add_child(send_button)
	drop_content = VBoxContainer.new()
	drop_content.visible = false
	drop_content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(drop_content)
	var icon := Icon.new()
	icon.kind = "image"
	icon.color = Kit.INK
	icon.custom_minimum_size = Vector2(68, 68)
	drop_content.add_child(icon)
	var caption_drop := Kit.label("이미지 첨부하기", 17)
	caption_drop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_content.add_child(caption_drop)
	var hint := Kit.label("PNG · JPG · WEBP", 12, Kit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_content.add_child(hint)
	_update_send()
	resized.connect(func(): geometry_changed.emit())

func _icon_button(kind: String, color: Color, accent: bool) -> Button:
	var button := Kit.button("", accent)
	button.custom_minimum_size = Vector2(44, 44)
	if not accent:
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", Kit.panel(Kit.PALE, 22, 0))
	var icon := Icon.new()
	icon.kind = kind
	icon.color = color
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10; icon.offset_top = 10; icon.offset_right = -10; icon.offset_bottom = -10
	return button

func _key_input(event: InputEvent) -> void:
	# Windows can pair an IME result character with the preceding key-up.
	# TextEdit ignores key-up events, so retain that committed character here.
	if event is InputEventKey and not event.pressed and OS.get_name() == "Windows" and event.unicode >= 0x1100:
		input.insert_text_at_caret(String.chr(event.unicode))
		input.accept_event()
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.shift_pressed:
		input.accept_event()
		_submit()

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_OS_IME_UPDATE and is_node_ready():
		_update_send.call_deferred()

func _submit() -> void:
	if busy: return
	if input.has_ime_text(): input.apply_ime()
	if busy or (input.text.strip_edges().is_empty() and image_path.is_empty()): return
	submitted.emit(input.text.strip_edges(), image_path)

func _update_send() -> void:
	if send_button != null:
		send_button.disabled = busy or (input.text.strip_edges().is_empty() and not input.has_ime_text() and image_path.is_empty())

func focus_input() -> void:
	var window := get_window()
	window.unfocusable = false
	window.grab_focus()
	# The native focusable flag must take effect before TextEdit receives focus.
	await get_tree().process_frame
	if not is_visible_in_tree(): return
	if input.has_focus(): input.release_focus()
	input.grab_focus()
	_activate_ime()

func _activate_ime() -> void:
	var window := get_window()
	if input.has_focus() and is_visible_in_tree() and window.has_focus():
		window.set_ime_active(true)
		window.set_ime_position(Vector2i(input.get_global_position() + input.get_caret_draw_pos()))

func set_busy(value: bool) -> void:
	busy = value
	_update_send()

func attach_file(path: String) -> bool:
	if path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"]: return false
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return false
	image_path = path
	preview.texture = ImageTexture.create_from_image(image)
	filename.text = path.get_file()
	preview_row.show()
	set_drop_hover(false)
	_morph()
	_update_send()
	return true

func clear_attachment() -> void:
	image_path = ""
	preview.texture = null
	preview_row.hide()
	_morph()
	_update_send()

func clear() -> void:
	input.text = ""
	clear_attachment()

func set_drop_hover(value: bool) -> void:
	if drop_hover == value or (busy and value): return
	drop_hover = value
	content.visible = not value
	drop_content.visible = value
	_morph()

func _morph() -> void:
	if expanded:
		style.bg_color = Kit.PALE if drop_hover else Color.WHITE
		custom_minimum_size.y = 220 if drop_hover else (236 if not image_path.is_empty() else 104)
		geometry_changed.emit()
		return
	target_size = Vector2(216, 216) if drop_hover else Vector2(536, 230 if not image_path.is_empty() else 72)
	if tween != null and tween.is_running(): tween.kill()
	style.bg_color = Color("9cdae8") if drop_hover else Color.WHITE
	custom_minimum_size = Vector2.ZERO
	tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "size", target_size, 0.2)
	for key in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		tween.tween_property(style, key, 28 if drop_hover or not image_path.is_empty() else 36, 0.2)
