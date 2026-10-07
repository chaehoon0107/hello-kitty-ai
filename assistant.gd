extends CanvasLayer

const Client = preload("res://ai_client.gd")
const Kit = preload("res://ui/kitty_theme.gd")
const Composer = preload("res://ui/composer.gd")
const Chat = preload("res://ui/chat_window.gd")
const Dots = preload("res://ui/loading_dots.gd")
const Icon = preload("res://ui/icon.gd")
var host: Node2D
var client: Node
var composer: PanelContainer
var chat: Window
var summary_panel: PanelContainer
var summary_text: Label
var loading: Control
var notice: Label
var status: Label
var close_button: Button
var dialog: FileDialog
var dialog_for_chat := false
var busy := false
var job_conversation := ""
var summary := ""
var reveal_elapsed := 0.0
var notice_remaining := 0.0
var drop_rect := Rect2()
var last_pointer_down := false
var last_stream := ""
var notice_motion := false
var speech_tail: Control
var options: PanelContainer

func _ready() -> void:
	host = get_parent()
	if OS.get_name() == "Windows":
		OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ProjectSettings.globalize_path("res://start_ai.ps1")]), false)
	get_viewport().gui_embed_subwindows = false
	client = Client.new(); add_child(client)
	composer = Composer.new(); add_child(composer)
	composer.size = Vector2(536, 72)
	composer.hide()
	composer.submitted.connect(func(text, image): _submit(text, image, ""))
	composer.pick_image_requested.connect(func(): _pick_image(false))
	close_button = Kit.button("")
	close_button.custom_minimum_size = Vector2(28,28)
	close_button.add_theme_stylebox_override("normal", Kit.panel(Color.WHITE,14,0))
	close_button.add_theme_stylebox_override("hover", Kit.panel(Kit.PALE,14,0))
	var close_icon := Icon.new(); close_icon.kind = "close"; close_icon.position = Vector2(2,2)
	close_button.add_child(close_icon)
	close_button.pressed.connect(close_popup)
	add_child(close_button); close_button.hide()
	status = Kit.label("", 12, Kit.MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status); status.hide()
	loading = Dots.new(); add_child(loading); loading.hide()
	notice = Kit.label("❗", 36, Kit.BLUE); add_child(notice); notice.hide()
	summary_panel = PanelContainer.new()
	summary_panel.theme = Kit.make_theme()
	summary_panel.add_theme_stylebox_override("panel", Kit.panel(Color.WHITE, 24, 20, true))
	summary_panel.size = Vector2(430, 150)
	add_child(summary_panel); summary_panel.hide()
	speech_tail = preload("res://ui/speech_tail.gd").new()
	add_child(speech_tail); speech_tail.hide()
	var column := VBoxContainer.new(); summary_panel.add_child(column)
	summary_text = Kit.label("", 17)
	summary_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_text.custom_minimum_size = Vector2(360, 44)
	column.add_child(summary_text)
	var actions := HBoxContainer.new(); column.add_child(actions)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(spacer)
	var expand := Kit.button("", false)
	expand.custom_minimum_size = Vector2(36, 36); expand.tooltip_text = "전체 답변과 대화 기록 열기"
	var icon := Icon.new(); icon.kind = "expand"; icon.color = Kit.INK
	expand.add_child(icon); icon.position = Vector2(6,6)
	expand.pressed.connect(open_chat); actions.add_child(expand)
	chat = Chat.new(); add_child(chat); chat.hide()
	chat.visibility_changed.connect(func():
		if not chat.visible: host._restore_overlay.call_deferred())
	chat.question_submitted.connect(_submit)
	chat.select_conversation.connect(_select_conversation)
	chat.pick_image_requested.connect(func(): _pick_image(true))
	dialog = FileDialog.new(); dialog.title = "이미지 첨부"
	dialog.theme = Kit.make_file_dialog_theme()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp;이미지"])
	dialog.size = Vector2i(760, 540)
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: host._restore_overlay.call_deferred())
	dialog.file_selected.connect(func(path):
		if dialog_for_chat: chat.composer.attach_file(path)
		else: composer.attach_file(path))
	get_window().files_dropped.connect(_files_dropped)
	client.health_changed.connect(_health)
	client.job_updated.connect(_job)
	client.history_changed.connect(chat.set_history)
	options = PanelContainer.new()
	options.theme = Kit.make_theme()
	options.add_theme_stylebox_override("panel", Kit.panel(Color.WHITE, 18, 12, true))
	var option_list := VBoxContainer.new()
	options.add_child(option_list)
	var open_button := Kit.button("채팅창 열기", true)
	open_button.pressed.connect(func(): options.hide(); open_chat())
	option_list.add_child(open_button)
	var quit_button := Kit.button("종료")
	quit_button.pressed.connect(host._quit_app)
	option_list.add_child(quit_button)
	add_child(options)
	options.size = Vector2(190, 110)
	options.hide()

func open_options() -> void:
	if options.visible:
		options.hide()
	else:
		close_popup()
		options.show()

func engaged() -> bool:
	return busy or composer.visible or summary_panel.visible or notice.visible or options.visible

func motion() -> String:
	return "Think" if busy else ("Notice" if notice_motion else "Idle")

func open_question() -> void:
	if busy: return
	options.hide()
	summary_panel.hide(); notice.hide()
	composer.clear(); composer.show(); close_button.show(); status.show()
	composer.size = Vector2(536,72)
	await composer.focus_input()
	# Changing NOACTIVATE on Windows can reset native stacking; restore it after focus.
	get_window().always_on_top = false
	get_window().always_on_top = true
	drop_rect = Rect2()

func close_popup() -> void:
	if composer.input.has_focus(): composer.input.release_focus()
	options.hide()
	composer.hide(); summary_panel.hide(); close_button.hide(); status.hide(); notice.hide()
	if not busy: get_window().unfocusable = true

func interactive_rect() -> Rect2:
	var rect := Rect2()
	# Windows clips drawing to the passthrough polygon, including non-clickable UI.
	for control in [composer, summary_panel, close_button, status, loading, notice, speech_tail, options]:
		if control.visible:
			var part: Rect2 = control.get_global_rect()
			rect = part if rect.size == Vector2.ZERO else rect.merge(part)
	if composer.drop_hover and drop_rect.size != Vector2.ZERO: rect = rect.merge(drop_rect)
	return rect

func _process(delta: float) -> void:
	host.pet.walking_enabled = not engaged()
	_anchor(composer)
	_anchor(summary_panel)
	_anchor(options)
	speech_tail.visible = summary_panel.visible
	speech_tail.position = Vector2(clampf(host.pet.position.x-15, summary_panel.position.x+30, summary_panel.position.x+summary_panel.size.x-60),summary_panel.position.y+summary_panel.size.y-1)
	var head: Vector2 = host.pet.position + Vector2(0,-230)
	loading.position = head - Vector2(55,48)
	notice.position = head - Vector2(20,56)
	if composer.visible:
		status.position = composer.position + Vector2(0,-24); status.size.x = composer.size.x
		close_button.position = composer.position + Vector2(composer.size.x-24,-32)
	elif summary_panel.visible:
		close_button.position = summary_panel.position + Vector2(summary_panel.size.x-24,-32)
	if notice_remaining > 0:
		notice_remaining -= delta
		if notice_remaining <= 0:
			notice.hide(); notice_motion = false
			summary_panel.show(); close_button.show()
			reveal_elapsed = 0.0
	if summary_panel.visible:
		reveal_elapsed += delta
		summary_text.visible_characters = int(reveal_elapsed * 32.0)

func _anchor(control: Control) -> void:
	var area: Vector2 = host.get_viewport_rect().size
	var point: Vector2 = host.pet.position + Vector2(-control.size.x/2, -236-control.size.y)
	control.position = Vector2(clampf(point.x,16,area.x-control.size.x-16),clampf(point.y,42,area.y-control.size.y-16))

func _health(data: Dictionary) -> void:
	status.text = str(data.get("message", data.get("error", "키티가 준비하고 있어요")))
	composer.set_busy(busy or not client.healthy)
	chat.set_busy(busy or not client.healthy)
	_native_hover(data)

func _native_hover(data: Dictionary) -> void:
	var pointer_down: bool = data.get("pointer", {}).get("left_down", false)
	if composer.visible and not busy:
		var mouse: Vector2 = host._mouse_local()
		var hit := drop_rect if drop_rect.size != Vector2.ZERO else composer.get_global_rect()
		var native_drag := pointer_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hit.grow(20).has_point(mouse)
		if native_drag and not composer.drop_hover: drop_rect = composer.get_global_rect()
		composer.set_drop_hover(native_drag)
		if not pointer_down: drop_rect = Rect2()
	if chat.visible and not busy:
		var mouse := Vector2(DisplayServer.mouse_get_position() - chat.position)
		chat.composer.set_drop_hover(pointer_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and chat.composer.get_global_rect().has_point(mouse))
	last_pointer_down = pointer_down

func _files_dropped(files: PackedStringArray) -> void:
	if busy or files.is_empty(): return
	if not composer.visible: open_question()
	if not composer.attach_file(files[0]): status.text = "PNG, JPG, WEBP 이미지를 첨부해 주세요"
	drop_rect = Rect2()

func _pick_image(for_chat: bool) -> void:
	if busy: return
	dialog_for_chat = for_chat
	dialog.popup_centered()

func _submit(text: String, image_path: String, conversation_id: String) -> void:
	if busy or not client.healthy: return
	busy = true; last_stream = ""
	composer.set_busy(true); chat.set_busy(true)
	composer.hide(); summary_panel.hide(); status.hide(); close_button.hide(); notice.hide(); loading.show()
	get_window().unfocusable = true
	var result: Dictionary = await client.ask(text, image_path, conversation_id)
	if result.has("error"):
		_error(str(result["error"])); return
	job_conversation = str(result["conversation_id"])
	if chat.visible:
		chat.show_conversation(result["conversation"])
		chat.composer.clear(); chat.show_stream("")
	client.refresh_history()

func _job(data: Dictionary) -> void:
	_native_hover(data)
	if data.has("error") and not data.has("status"):
		_error(str(data["error"])); return
	var state := str(data.get("status", ""))
	var partial := str(data.get("text", ""))
	if chat.visible and chat.current_id == job_conversation and partial != last_stream:
		chat.show_stream(_display_answer(partial)); last_stream = partial
	if state == "done":
		busy = false; loading.hide()
		composer.set_busy(false); chat.set_busy(false)
		summary = str(data.get("summary", "답변을 준비했어요."))
		summary_text.text = summary; summary_text.visible_characters = 0
		notice_remaining = 0.55; notice_motion = true; notice.show()
		if chat.visible and chat.current_id == job_conversation: _select_conversation(job_conversation)
		client.refresh_history()
	elif state in ["error", "cancelled"]:
		_error(str(data.get("error", "질문을 취소했어요")))

func _display_answer(text: String) -> String:
	var start := text.find("답변:")
	return text.substr(start+3).strip_edges() if start >= 0 else text

func _error(message: String) -> void:
	busy = false; loading.hide(); notice.hide(); notice_motion = false
	summary = message; summary_text.text = message; summary_text.visible_characters = -1
	reveal_elapsed = 100; summary_panel.show(); close_button.show()
	composer.set_busy(not client.healthy); chat.set_busy(not client.healthy)
	if chat.visible: chat.show_stream(message)

func open_chat() -> void:
	chat.popup_centered()
	chat.grab_focus()
	client.refresh_history()
	if not job_conversation.is_empty(): await _select_conversation(job_conversation)
	await chat.composer.focus_input()
	RenderingServer.force_draw(false)

func _select_conversation(id: String) -> void:
	var result: Dictionary = await client.get_conversation(id)
	if not result.has("error"):
		chat.show_conversation(result)
		if busy and id == job_conversation: chat.show_stream(_display_answer(last_stream))
