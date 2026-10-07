extends Window

signal question_submitted(text: String, image_path: String, conversation_id: String)
signal select_conversation(id: String)
signal pick_image_requested
const Kit = preload("res://ui/kitty_theme.gd")
const Composer = preload("res://ui/composer.gd")
const Icon = preload("res://ui/icon.gd")
var composer: PanelContainer
var recent: VBoxContainer
var messages: VBoxContainer
var scroll: ScrollContainer
var heading: Label
var status: Label
var current_id := ""
var streaming: RichTextLabel
var busy := false

func _ready() -> void:
	title = "Kitty AI"
	size = Vector2i(1120, 780)
	min_size = Vector2i(880, 620)
	borderless = false
	transparent = false
	transparent_bg = false
	always_on_top = false
	unfocusable = false
	theme = Kit.make_theme()
	close_requested.connect(hide)
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 244
	sidebar.add_theme_stylebox_override("panel", Kit.panel(Color("f5f7fa"), 0, 20))
	layout.add_child(sidebar)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	sidebar.add_child(side)
	var brand := HBoxContainer.new()
	side.add_child(brand)
	var bow := Icon.new()
	bow.kind = "bow"; bow.color = Kit.BLUE
	bow.custom_minimum_size = Vector2(30, 30)
	brand.add_child(bow)
	brand.add_child(Kit.label("Kitty AI", 24))
	var new_chat := Kit.button("＋  새로운 대화", true)
	new_chat.custom_minimum_size.y = 44
	new_chat.pressed.connect(func():
		current_id = ""
		show_conversation({"title":"새로운 대화", "messages":[]})
		composer.clear()
		composer.focus_input())
	side.add_child(new_chat)
	side.add_child(Kit.label("최근 대화", 13, Kit.MUTED))
	var history_scroll := ScrollContainer.new()
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(history_scroll)
	recent = VBoxContainer.new()
	recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent.add_theme_constant_override("separation", 6)
	history_scroll.add_child(recent)
	status = Kit.label("로컬 · Qwen3.5-2B", 12, Kit.MUTED)
	side.add_child(status)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	layout.add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	margin.add_child(main)
	var header := HBoxContainer.new()
	main.add_child(header)
	heading = Kit.label("새로운 대화", 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(heading)
	header.add_child(Kit.label("Qwen3.5-2B", 12, Kit.MUTED))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	messages = VBoxContainer.new()
	messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages.add_theme_constant_override("separation", 24)
	scroll.add_child(messages)
	composer = Composer.new()
	composer.expanded = true
	composer.custom_minimum_size.y = 104
	main.add_child(composer)
	composer.submitted.connect(func(text, image): question_submitted.emit(text, image, current_id))
	composer.pick_image_requested.connect(func(): pick_image_requested.emit())
	var hint := Kit.label("Enter로 보내기 · Shift + Enter로 줄바꿈", 12, Kit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(hint)
	files_dropped.connect(func(files):
		if not files.is_empty() and not busy: composer.attach_file(files[0]))
	show_conversation({"title":"새로운 대화", "messages":[]})

func set_history(history: Array) -> void:
	for child in recent.get_children():
		recent.remove_child(child); child.queue_free()
	for item in history:
		var button := Kit.button(str(item.get("title", "대화")))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size = Vector2(196, 42)
		button.tooltip_text = button.text
		var id := str(item["id"])
		button.pressed.connect(func(): select_conversation.emit(id))
		recent.add_child(button)

func show_conversation(data: Dictionary) -> void:
	current_id = str(data.get("id", ""))
	heading.text = str(data.get("title", "새로운 대화"))
	streaming = null
	scroll.scroll_vertical = 0
	for child in messages.get_children():
		messages.remove_child(child); child.queue_free()
	var items: Array = data.get("messages", [])
	if items.is_empty():
		var welcome := VBoxContainer.new()
		welcome.add_theme_constant_override("separation", 12)
		welcome.custom_minimum_size.y = 220
		welcome.alignment = BoxContainer.ALIGNMENT_CENTER
		messages.add_child(welcome)
		for text in ["무엇이 궁금하신가요?", "질문하거나 이미지를 첨부해 주세요."]:
			var label := Kit.label(text, 22 if text.begins_with("무엇") else 15, Kit.INK if text.begins_with("무엇") else Kit.MUTED)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			welcome.add_child(label)
	for item in items: _message(str(item.get("role", "assistant")), str(item.get("content", "")), item.get("images", []))
	_scroll_bottom.call_deferred()

func _message(role: String, text: String, images: Array = []) -> RichTextLabel:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages.add_child(row)
	if role == "user":
		var space := Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(space)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Kit.panel(Color("f0f2f6") if role == "user" else Color.WHITE, 20, 16))
	row.add_child(panel)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 10)
	panel.add_child(stack)
	stack.add_child(Kit.label("나" if role == "user" else "키티", 12, Kit.MUTED if role == "user" else Kit.BLUE))
	for attachment in images:
		var image := Image.load_from_file(str(attachment.get("path", "")))
		if image == null: continue
		var texture := TextureRect.new()
		texture.texture = ImageTexture.create_from_image(image)
		texture.custom_minimum_size = Vector2(160, 140)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stack.add_child(texture)
	var rich := RichTextLabel.new()
	rich.fit_content = true
	rich.scroll_active = false
	rich.selection_enabled = true
	rich.bbcode_enabled = true
	rich.text = _format_text(text)
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich.add_theme_font_size_override("normal_font_size", 17)
	stack.add_child(rich)
	return rich

func show_stream(text: String) -> void:
	var bar := scroll.get_v_scroll_bar()
	var at_bottom := bar.value >= bar.max_value - bar.page - 48
	if streaming == null: streaming = _message("assistant", "답변을 생각하고 있어요…")
	streaming.text = _format_text(text if not text.is_empty() else "답변을 생각하고 있어요…")
	if at_bottom: _scroll_bottom.call_deferred()

func _format_text(text: String) -> String:
	# Keep the model's text literal except for simple, readable Markdown emphasis.
	var result := text.replace("[", "\u0001").replace("]", "\u0002")
	var regex := RegEx.new()
	regex.compile("\\*\\*(.+?)\\*\\*")
	result = regex.sub(result, "[b]$1[/b]", true)
	regex.compile("`([^`]+)`")
	result = regex.sub(result, "[color=#208fa9]$1[/color]", true)
	regex.compile("(?m)^#{1,4} (.+)$")
	result = regex.sub(result, "[b]$1[/b]", true)
	return result.replace("\u0001", "[lb]").replace("\u0002", "[rb]")

func set_busy(value: bool) -> void:
	busy = value
	composer.set_busy(value)

func _scroll_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
