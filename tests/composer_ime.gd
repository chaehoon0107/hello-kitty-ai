extends SceneTree

func _compose_hangul(character: String) -> void:
	# Exercise TextEdit's native IME buffer through Unicode composition.
	var start := InputEventKey.new()
	start.keycode = KEY_KP_ADD
	start.alt_pressed = true
	start.pressed = true
	root.push_input(start)
	for digit in "%X" % character.unicode_at(0):
		var event := InputEventKey.new()
		event.keycode = digit.unicode_at(0)
		event.alt_pressed = true
		event.pressed = true
		root.push_input(event)

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	var composer := preload("res://ui/composer.gd").new()
	root.add_child(composer)
	composer.size = Vector2(536,72)
	await composer.focus_input()
	var sent: Array = []
	composer.submitted.connect(func(text, _path): sent.append(text))
	# Reproduce Windows result WM_CHAR being paired with a key-up instead of key-down.
	for character in "안녕하세요":
		var event := InputEventKey.new()
		event.keycode = KEY_UNKNOWN
		event.unicode = character.unicode_at(0)
		event.pressed = false
		composer._key_input(event)
	assert(composer.input.text == "안녕하세요", "Every committed Korean syllable must remain")
	var english_release := InputEventKey.new()
	english_release.keycode = KEY_A
	english_release.unicode = 97
	composer._key_input(english_release)
	assert(composer.input.text == "안녕하세요", "Regular key releases must not repeat text")
	composer._submit()
	assert(sent == ["안녕하세요"], "Send must preserve the complete question")
	composer.input.text = ""
	composer._update_send()
	assert(composer.send_button.disabled)
	_compose_hangul("안")
	assert(composer.input.has_ime_text(), "Native Hangul composition must be active")
	composer.notification(MainLoop.NOTIFICATION_OS_IME_UPDATE)
	await process_frame
	await process_frame
	assert(not composer.send_button.disabled, "Uncommitted Hangul must enable Send")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter)
	assert(sent == ["안녕하세요", "안"], "One Enter must commit and send Hangul")
	composer.input.text = ""
	_compose_hangul("요")
	composer.send_button.pressed.emit()
	assert(sent[-1] == "요", "Send button must commit the last syllable")
	var dialog_theme := preload("res://ui/kitty_theme.gd").make_file_dialog_theme()
	assert(dialog_theme.get_stylebox("panel", "Tree").bg_color == Color.WHITE)
	assert(dialog_theme.get_color("font_color", "Tree") == Color("233041"))
	print("COMPOSER_IME_REGRESSION_PASS")
	quit()
