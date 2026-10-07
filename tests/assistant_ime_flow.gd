extends Node

func run(host: Node) -> void:
	var assistant = host.assistant
	var limit := Time.get_ticks_msec() + 120000
	while not assistant.client.healthy and Time.get_ticks_msec() < limit:
		await get_tree().process_frame
	assert(assistant.client.healthy)
	await assistant.open_question()
	assistant.composer.input.text = "검증: "
	assistant.composer.input.set_caret_column(4)
	for character in "안녕하세요":
		var event := InputEventKey.new()
		event.keycode = KEY_UNKNOWN
		event.unicode = character.unicode_at(0)
		event.pressed = false
		host.get_window().push_input(event)
	await get_tree().process_frame
	assert(assistant.composer.input.text == "검증: 안녕하세요", "GUI must retain committed Hangul key-up characters")
	assistant.composer.send_button.pressed.emit()
	for i in 30: await get_tree().process_frame
	assert(assistant.busy and assistant.loading.visible)
	assert(assistant.interactive_rect().encloses(assistant.loading.get_global_rect()))
	RenderingServer.force_draw(false)
	host.get_viewport().get_texture().get_image().save_png("res://previews/ime_sending.png")
	limit = Time.get_ticks_msec() + 120000
	while assistant.busy and Time.get_ticks_msec() < limit:
		await get_tree().process_frame
	assert(not assistant.busy and not assistant.job_conversation.is_empty())
	var conversation: Dictionary = await assistant.client.get_conversation(assistant.job_conversation)
	assert(conversation.get("messages",[]).size() >= 2)
	assert(conversation.messages[-1].role == "assistant")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.double_click = true
	click.pressed = true
	click.position = host.pet.position + Vector2(0,-100)
	host.get_window().push_input(click)
	await get_tree().process_frame
	assert(assistant.options.visible, "Double-click must open options")
	assistant.options.get_child(0).get_child(0).pressed.emit()
	for i in 120: await get_tree().process_frame
	assert(assistant.chat.visible and assistant.chat.current_id == assistant.job_conversation)
	RenderingServer.force_draw(false)
	assistant.chat.get_texture().get_image().save_png("res://previews/ime_chat_result.png")
	var report := {"gui_korean_commit_pass":true,"send_and_real_answer_pass":true,
		"automatic_loader_region_pass":true,"double_click_menu_pass":true,"open_chat_pass":true,
		"conversation_id":assistant.job_conversation}
	var file := FileAccess.open("res://previews/ime_flow_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ASSISTANT_IME_FLOW_PASS ",JSON.stringify(report))
