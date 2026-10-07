extends Node2D

const PetBody = preload("res://pet_body.gd")
const PET_TEXTURE_SIZE := Vector2i(240, 256)
const PET_HEIGHT := 196.0
const FOOT_MARGIN := 28.0
const EDGE_MARGIN := 98.0
const GAIT_REFERENCE_SPEED := 29.9

@export var display_blender_tpose := false

var pet: CharacterBody2D
var pet_viewport: SubViewport
var visual: Sprite2D
var model_pivot: Node3D
var animation_player: AnimationPlayer
var floor_body: StaticBody2D
var wall_left: StaticBody2D
var wall_right: StaticBody2D
var work_area := Rect2i()
var dragging := false
var grab_offset := Vector2.ZERO
var throw_velocity := Vector2.ZERO
var last_mouse := Vector2.ZERO
var geometry_timer := 0.0
var current_animation := ""
var verify_mode := false
var last_input_rect := Rect2()
var was_dragging := false
var preview_mode := false
var skeleton: Skeleton3D
var unshaded_mesh_count := 0
var hidden_plane: StaticBody3D
var assistant: CanvasLayer
var runtime_status_timer := 0.0

func _ready() -> void:
	verify_mode = "--verify" in OS.get_cmdline_user_args()
	preview_mode = "--preview-walk" in OS.get_cmdline_user_args()
	get_window().transparent = true
	get_window().transparent_bg = true
	get_window().borderless = true
	get_window().always_on_top = true
	get_window().unfocusable = true
	get_window().unresizable = true
	Engine.max_fps = 60
	_create_physics()
	_create_model()
	_update_screen(true)
	pet.position = Vector2(work_area.size.x * 0.5, work_area.size.y - 1.0)
	pet.reset_physics_interpolation()
	if not verify_mode and not preview_mode and "--preview-model" not in OS.get_cmdline_user_args():
		assistant = preload("res://assistant.gd").new()
		add_child(assistant)
	if "--assistant-ui-test" in OS.get_cmdline_user_args():
		pet.held = true
		_assistant_preview.call_deferred()
	if "--assistant-flow-test" in OS.get_cmdline_user_args():
		_assistant_flow_test.call_deferred()
	if "--assistant-ime-test" in OS.get_cmdline_user_args():
		_assistant_ime_test.call_deferred()
	if "--ui-test" in OS.get_cmdline_user_args():
		pet.held = true
		_ui_snapshot.call_deferred()
	_update_mouse_region()
	_restore_overlay.call_deferred()
	if verify_mode:
		_verify.call_deferred()
	if preview_mode:
		pet.held = true
		_render_walk_preview.call_deferred()
	if "--preview-model" in OS.get_cmdline_user_args():
		pet.held = true
		_render_original_preview.call_deferred()

func _restore_overlay() -> void:
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.show()
	window.position = work_area.position
	# A screen-wide borderless window is auto-maximized by Windows. Keep the
	# transparent overlay windowed so native IME and additional windows stay usable.
	window.size = Vector2i(work_area.size.x - 1, work_area.size.y)
	window.always_on_top = false
	window.always_on_top = true
	last_input_rect = Rect2()
	_update_mouse_region()
	await get_tree().process_frame
	RenderingServer.force_draw(false)

func _create_physics() -> void:
	pet = PetBody.new()
	pet.name = "PetPhysics"
	pet.floor_snap_length = 6.0
	pet.floor_constant_speed = true
	pet.floor_stop_on_slope = true
	pet.safe_margin = 0.08
	add_child(pet)
	var collision := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 48.0
	capsule.height = PET_HEIGHT
	collision.shape = capsule
	collision.position = Vector2(0, -PET_HEIGHT / 2.0)
	pet.add_child(collision)
	floor_body = StaticBody2D.new()
	floor_body.name = "InvisibleTaskbarPlane2D"
	add_child(floor_body)
	var ground_collision := CollisionShape2D.new()
	var plane_shape := WorldBoundaryShape2D.new()
	plane_shape.normal = Vector2.UP
	ground_collision.shape = plane_shape
	floor_body.add_child(ground_collision)
	wall_left = _make_wall("LeftBoundary")
	wall_right = _make_wall("RightBoundary")

func _make_wall(wall_name: String) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	add_child(wall)
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	wall.add_child(collision)
	return wall

func _set_wall(wall: StaticBody2D, center: Vector2, dimensions: Vector2) -> void:
	wall.position = center
	var collision := wall.get_child(0) as CollisionShape2D
	(collision.shape as RectangleShape2D).size = dimensions

func _create_model() -> void:
	if display_blender_tpose:
		_create_tpose_sprite()
		return
	pet_viewport = SubViewport.new()
	pet_viewport.name = "Pet3DViewport"
	pet_viewport.size = PET_TEXTURE_SIZE
	pet_viewport.transparent_bg = true
	pet_viewport.own_world_3d = true
	pet_viewport.msaa_3d = Viewport.MSAA_4X
	pet_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pet_viewport)
	model_pivot = Node3D.new()
	model_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	pet_viewport.add_child(model_pivot)
	hidden_plane = preload("res://hidden_taskbar_plane.tscn").instantiate() as StaticBody3D
	pet_viewport.add_child(hidden_plane)
	var scene: PackedScene = load("res://assets/pet_blender_rigged.glb")
	var model := scene.instantiate() as Node3D
	model.position.y = 0.48901367
	model_pivot.add_child(model)
	_apply_unshaded_materials(model)
	skeleton = _find_skeleton(model)
	animation_player = _find_animation_player(model)
	assert(skeleton != null and animation_player != null, "Walking pet requires its rig and animations")
	if animation_player != null:
		for animation_name in animation_player.get_animation_list():
			animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
		_play_animation("Idle")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.28
	camera.position = Vector3(0, 0.5, 3)
	pet_viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.5, 0))
	visual = Sprite2D.new()
	visual.name = "PetVisual"
	visual.texture = pet_viewport.get_texture()
	visual.position = Vector2(0, -PET_TEXTURE_SIZE.y / 2.0 + FOOT_MARGIN)
	pet.add_child(visual)

func _apply_unshaded_materials(node: Node) -> void:
	if node is MeshInstance3D:
		unshaded_mesh_count += 1
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var original := instance.get_active_material(surface) as BaseMaterial3D
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			if original != null:
				material.albedo_texture = original.albedo_texture
				material.albedo_color = original.albedo_color
			instance.set_surface_override_material(surface, material)
	for child in node.get_children():
		_apply_unshaded_materials(child)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _create_tpose_sprite() -> void:
	var texture: Texture2D = load("res://assets/pet_tpose.png")
	assert(texture != null, "Blender T-pose render is missing")
	visual = Sprite2D.new()
	visual.name = "BlenderTposeVisual"
	visual.texture = texture
	var render_scale := PET_HEIGHT / texture.get_height()
	visual.scale = Vector2.ONE * render_scale
	visual.position = Vector2(0, -PET_HEIGHT / 2.0)
	pet.add_child(visual)
	current_animation = "Tpose"

func _save_visual_preview(path: String) -> void:
	if pet_viewport != null:
		pet_viewport.get_texture().get_image().save_png(path)
	else:
		visual.texture.get_image().save_png(path)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null

func _play_animation(requested: String) -> void:
	if requested == current_animation:
		return
	for animation_name in animation_player.get_animation_list():
		if animation_name == requested or animation_name.ends_with("/" + requested):
			animation_player.play(animation_name, 0.12)
			current_animation = requested
			return
	push_error("Missing animation: " + requested)

func _update_screen(force: bool = false) -> void:
	var screen := DisplayServer.get_primary_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	if not force and area == work_area:
		return
	work_area = area
	DisplayServer.window_set_position(area.position)
	DisplayServer.window_set_size(Vector2i(area.size.x - 1, area.size.y))
	var width := float(area.size.x)
	var height := float(area.size.y)
	# A single infinite collision plane has no joints or edges under the feet.
	floor_body.position = Vector2(0, height)
	_set_wall(wall_left, Vector2(-40, height / 2.0), Vector2(80, height + 600))
	_set_wall(wall_right, Vector2(width + 40, height / 2.0), Vector2(80, height + 600))
	if not force:
		pet.position = _clamp_pet(pet.position)
		pet.reset_physics_interpolation()

func _mouse_local() -> Vector2:
	return Vector2(DisplayServer.mouse_get_position() - work_area.position)

func _clamp_pet(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, EDGE_MARGIN, work_area.size.x - EDGE_MARGIN), clampf(point.y, PET_HEIGHT + 6, work_area.size.y - 0.5))

func _unhandled_input(event: InputEvent) -> void:
	if verify_mode:
		return
	if event is InputEventMouseMotion and dragging:
		_move_drag(event.position, 1.0 / Engine.physics_ticks_per_second)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if assistant != null and _pet_input_rect().has_point(event.position):
			assistant.open_question()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse: Vector2 = event.position
			if _pet_input_rect().has_point(mouse):
				if event.double_click and assistant != null:
					if dragging: _release_drag()
					assistant.open_options()
					get_viewport().set_input_as_handled()
					return
				_begin_drag(mouse)
		elif dragging:
			_move_drag(event.position, 1.0 / Engine.physics_ticks_per_second)
			_release_drag()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if assistant != null and assistant.engaged(): assistant.close_popup()
		else: _quit_app()

func _quit_app() -> void:
	if assistant != null:
		await assistant.client.request_json("/shutdown", HTTPClient.METHOD_POST)
	get_tree().quit()

func _begin_drag(mouse: Vector2) -> void:
	dragging = true
	pet.held = true
	pet.grounded = false
	pet.velocity = Vector2.ZERO
	pet.reset_physics_interpolation()
	grab_offset = pet.position - mouse
	last_mouse = mouse
	throw_velocity = Vector2.ZERO
	_update_mouse_region()
	print("PET_DRAG_BEGIN ", pet.position)

func _move_drag(mouse: Vector2, delta: float) -> void:
	var previous := pet.position
	pet.position = _clamp_pet(mouse + grab_offset)
	pet.reset_physics_interpolation()
	var velocity := (pet.position - previous) / maxf(delta, 0.001)
	throw_velocity = throw_velocity.lerp(velocity, 0.5)
	last_mouse = mouse

func _release_drag() -> void:
	dragging = false
	pet.held = false
	pet.grounded = false
	pet.velocity = throw_velocity.limit_length(1400.0)
	_update_mouse_region()
	print("PET_DRAG_RELEASE position=", pet.position, " velocity=", pet.velocity)

func _physics_process(delta: float) -> void:
	geometry_timer += delta
	if geometry_timer >= 1.0:
		geometry_timer = 0.0
		_update_screen()
	if dragging and not verify_mode:
		_move_drag(_mouse_local(), delta)
	if pet.position.x < EDGE_MARGIN:
		pet.direction = 1.0
	elif pet.position.x > work_area.size.x - EDGE_MARGIN:
		pet.direction = -1.0
	_update_mouse_region()

func _process(delta: float) -> void:
	runtime_status_timer += delta
	if runtime_status_timer >= 1.0:
		runtime_status_timer = 0.0
		if FileAccess.file_exists("res://.godot/restore_pet.request"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.godot/restore_pet.request"))
			_restore_overlay()
		var status_file := FileAccess.open("res://.godot/pet_runtime.json", FileAccess.WRITE)
		if status_file:
			status_file.store_string(JSON.stringify({"pet_position":str(pet.position),"pet_velocity":str(pet.velocity),"grounded":pet.grounded,"window_visible":get_window().visible,"window_mode":get_window().mode,"window_position":str(get_window().position),"window_size":str(get_window().size),"viewport_rect":str(get_viewport_rect()),"work_area":str(work_area),"visual_visible":visual.is_visible_in_tree(),"always_on_top":get_window().always_on_top,"animation":current_animation,"canvas_transform":str(get_viewport().get_canvas_transform())}))
	if animation_player == null or preview_mode:
		return
	var walking: bool = pet.grounded and not dragging and absf(pet.velocity.x) > 5.0
	var interacting: bool = assistant != null and assistant.engaged()
	if interacting: walking = false
	_play_animation(assistant.motion() if interacting else ("Walk" if walking else "Idle"))
	if walking:
		animation_player.speed_scale = clampf(absf(pet.velocity.x) / GAIT_REFERENCE_SPEED, 0.45, 1.4)
	else:
		animation_player.speed_scale = 1.0
	var target_yaw: float = pet.direction * deg_to_rad(55.0) if not dragging and not interacting else 0.0
	model_pivot.rotation.y = lerp_angle(model_pivot.rotation.y, target_yaw, 1.0 - exp(-delta * 8.0))

func _pet_input_rect() -> Rect2:
	return Rect2(pet.position + Vector2(-110, -220), Vector2(220, 223))

func _update_mouse_region() -> void:
	if "--ui-test" in OS.get_cmdline_user_args():
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return
	if dragging:
		if was_dragging:
			return
		# Keep capture while the pointer moves outside the pet during a drag.
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		was_dragging = true
		return
	var rect := _pet_input_rect()
	if assistant != null:
		var ui_rect: Rect2 = assistant.interactive_rect()
		if ui_rect.size != Vector2.ZERO: rect = rect.merge(ui_rect)
	if rect == last_input_rect and not was_dragging:
		return
	last_input_rect = rect
	was_dragging = false
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.end, rect.position + Vector2(0, rect.size.y)
	]))

func _ui_snapshot() -> void:
	for i in 120:
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	print("UI_GEOMETRY root=", get_viewport_rect(), " window=", get_window().size, " sprite=", visual.global_position)
	get_viewport().get_texture().get_image().save_png("res://previews/ui_root.png")
	_save_visual_preview("res://previews/ui_model.png")

func _assistant_preview() -> void:
	for i in 45: await get_tree().process_frame
	assistant.client.set_process(false)
	assistant.composer.set_busy(false)
	assistant.open_question()
	for i in 30: await get_tree().process_frame
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png("res://previews/ai_composer.png")
	assistant.composer.set_busy(false)
	assistant.composer.set_drop_hover(true)
	for i in 30: await get_tree().process_frame
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png("res://previews/ai_drop.png")
	assistant.composer.set_drop_hover(false)
	assistant.composer.attach_file(ProjectSettings.globalize_path("res://previews/vision_test.png"))
	for i in 30: await get_tree().process_frame
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png("res://previews/ai_attachment.png")
	assistant.composer.hide(); assistant.status.hide(); assistant.close_button.hide()
	assistant.busy = true; assistant.loading.show()
	for i in 45: await get_tree().process_frame
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png("res://previews/ai_thinking.png")
	assistant.busy = false; assistant.loading.hide()
	assistant.summary_text.text = "답변은 머리 위에서 간단히 확인하고, 펼치기를 누르면 대화를 이어갈 수 있어요."
	assistant.summary_panel.show(); assistant.reveal_elapsed = 100; assistant.close_button.show()
	for i in 30: await get_tree().process_frame
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png("res://previews/ai_summary.png")
	await assistant.open_chat()
	var history: Array = await assistant.client.refresh_history()
	for item in history:
		if str(item.get("title", "")).begins_with("검증: 이미지"):
			await assistant._select_conversation(str(item["id"]))
			break
	for i in 45: await get_tree().process_frame
	RenderingServer.force_draw(false)
	assistant.chat.get_texture().get_image().save_png("res://previews/ai_chat.png")
	print("CHAT_LAYOUT scroll=", assistant.chat.scroll.scroll_vertical, " maximum=", assistant.chat.scroll.get_v_scroll_bar().max_value, " page=", assistant.chat.scroll.get_v_scroll_bar().page, " messages=", assistant.chat.messages.size)
	for row in assistant.chat.messages.get_children():
		print("CHAT_ROW ", row.position, " ", row.size)
	assistant.chat.hide()
	assistant.open_options()
	for i in 10: await get_tree().process_frame
	assert(assistant.options.visible)
	get_viewport().get_texture().get_image().save_png("res://previews/ai_options.png")
	assistant.dialog.popup_centered()
	for i in 10: await get_tree().process_frame
	assert(assistant.dialog.current_dir == OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP))
	assistant.dialog.get_texture().get_image().save_png("res://previews/ai_file_dialog.png")
	assistant.dialog.hide()
	print("ASSISTANT_UI_PREVIEW_OK")
	get_tree().quit()

func _assistant_flow_test() -> void:
	var report: Dictionary = {}
	for i in 60: await get_tree().process_frame
	var ready_limit := Time.get_ticks_msec() + 120000
	while not assistant.client.healthy and Time.get_ticks_msec() < ready_limit:
		await get_tree().process_frame
	assert(assistant.client.healthy, "Real local AI must be ready")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = pet.position + Vector2(0,-100)
	Input.parse_input_event(right_click)
	for i in 90: await get_tree().process_frame
	report["right_click_input_pass"] = assistant.composer.visible and not get_window().unfocusable
	report["front_and_pause_pass"] = absf(model_pivot.rotation.y) < 0.05 and absf(pet.velocity.x) < 0.1
	report["custom_font_pass"] = assistant.composer.theme.default_font.resource_path.ends_with("Griun_Yeeun-Rg.ttf")
	assert(report["right_click_input_pass"] and report["front_and_pause_pass"])
	assistant.composer.attach_file(ProjectSettings.globalize_path("res://previews/vision_test.png"))
	assistant.composer.input.text = "검증: 이미지의 색과 도형을 한 문장으로 알려줘."
	assistant.composer.send_button.pressed.emit()
	for i in 30: await get_tree().process_frame
	report["thinking_and_loader_pass"] = assistant.busy and assistant.loading.visible and current_animation == "Think"
	var timeout := Time.get_ticks_msec() + 180000
	while assistant.busy and Time.get_ticks_msec() < timeout: await get_tree().process_frame
	assert(not assistant.busy, "Real model request must finish")
	for i in 90: await get_tree().process_frame
	report["summary_pass"] = assistant.summary_panel.visible and assistant.summary.length() > 0
	report["typed_summary_pass"] = assistant.summary_text.visible_characters > 0
	await assistant.open_chat()
	for i in 45: await get_tree().process_frame
	var saved: Dictionary = await assistant.client.get_conversation(assistant.job_conversation)
	report["expanded_chat_pass"] = assistant.chat.visible and assistant.chat.current_id == assistant.job_conversation and saved["messages"].size() == 2
	report["image_history_pass"] = saved["messages"][0]["images"].size() == 1
	RenderingServer.force_draw(false)
	assistant.chat.get_texture().get_image().save_png("res://previews/ai_chat_real.png")
	assistant.chat.composer.input.text = "그 도형을 파란색으로 바꾸면 어떤 색의 도형이 돼? 한 문장으로 알려줘."
	assistant.chat.composer.send_button.pressed.emit()
	for i in 20: await get_tree().process_frame
	timeout = Time.get_ticks_msec() + 180000
	while assistant.busy and Time.get_ticks_msec() < timeout: await get_tree().process_frame
	assert(not assistant.busy)
	for i in 90: await get_tree().process_frame
	saved = await assistant.client.get_conversation(assistant.job_conversation)
	report["chat_continuation_pass"] = saved["messages"].size() == 4
	await assistant._select_conversation(assistant.job_conversation)
	for i in 45: await get_tree().process_frame
	report["saved_chat_reopen_pass"] = assistant.chat.current_id == str(saved["id"])
	RenderingServer.force_draw(false)
	assistant.chat.get_texture().get_image().save_png("res://previews/ai_chat_continued.png")
	var file := FileAccess.open("res://previews/ai_flow_verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("ASSISTANT_REAL_UI_FLOW ", JSON.stringify(report))
	var all_pass := true
	for key in report: all_pass = all_pass and report[key]
	get_tree().quit(0 if all_pass else 1)

func _verify() -> void:
	var animations := animation_player.get_animation_list() if animation_player != null else PackedStringArray()
	var report := {"work_area": str(work_area), "animations": animations, "display_mode": "Rigged walk, unshaded"}
	if skeleton != null:
		report["bone_count"] = skeleton.get_bone_count()
	for i in 90:
		await get_tree().physics_frame
	var start_x := pet.position.x
	var thigh := skeleton.find_bone("Thigh.L")
	var arm := skeleton.find_bone("UpperArm.L")
	var leg_before := skeleton.get_bone_pose_rotation(thigh)
	var arm_before := skeleton.get_bone_pose_rotation(arm)
	for i in 90:
		await get_tree().physics_frame
	report["rig_pass"] = skeleton.get_bone_count() == 16 and animation_player != null
	report["animated_leg_pass"] = not leg_before.is_equal_approx(skeleton.get_bone_pose_rotation(thigh))
	report["animated_arm_pass"] = not arm_before.is_equal_approx(skeleton.get_bone_pose_rotation(arm))
	report["unshaded_material_pass"] = unshaded_mesh_count == 1
	report["walk_distance"] = pet.position.x - start_x
	report["walk_pass"] = absf(pet.position.x - start_x) > 30.0
	var min_height := pet.position.y
	var max_height := pet.position.y
	var walk_only := true
	for i in 120:
		await get_tree().physics_frame
		min_height = minf(min_height, pet.position.y)
		max_height = maxf(max_height, pet.position.y)
		walk_only = walk_only and current_animation == "Walk" and pet.grounded
	report["ground_height_variation_px"] = max_height - min_height
	report["steady_walk_pass"] = max_height - min_height < 0.1 and walk_only
	report["invisible_plane_pass"] = hidden_plane != null and not hidden_plane.get_node("Plane").visible and (floor_body.get_child(0) as CollisionShape2D).shape is WorldBoundaryShape2D
	_begin_drag(pet.position + Vector2(0, -100))
	_move_drag(last_mouse + Vector2(-150, -450), 0.5)
	throw_velocity = Vector2.ZERO
	var release_y := pet.position.y
	_release_drag()
	for i in 12:
		await get_tree().physics_frame
	report["drop_distance_0_2s"] = pet.position.y - release_y
	report["fall_speed_0_2s"] = pet.velocity.y
	report["gravity_pass"] = pet.velocity.y > 200.0 and pet.position.y > release_y + 15.0
	for i in 140:
		await get_tree().physics_frame
	report["floor_error"] = absf(pet.position.y - work_area.size.y)
	report["floor_pass"] = report["floor_error"] < 2.0 and pet.grounded
	report["animation_after_landing"] = current_animation
	pet.held = true
	pet.position = Vector2(work_area.size.x - EDGE_MARGIN + 2, work_area.size.y - 0.5)
	pet.grounded = false
	pet.velocity = Vector2.ZERO
	pet.reset_physics_interpolation()
	pet.held = false
	for i in 90:
		await get_tree().physics_frame
	report["turn_pass"] = pet.direction == -1.0 and pet.velocity.x < -20.0
	_begin_drag(pet.position + Vector2(0,-100))
	_move_drag(last_mouse + Vector2(-180,-220), 0.3)
	report["drag_pass"] = dragging and pet.held and pet.position.y < work_area.size.y - 100
	_release_drag()
	report["throw_pass"] = pet.velocity.x < -100 and pet.velocity.y < -100
	for i in 160:
		await get_tree().physics_frame
	RenderingServer.force_draw(false)
	_save_visual_preview("res://previews/current_pet.png")
	var f := FileAccess.open("res://previews/verification.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	print("PET_VERIFICATION ", JSON.stringify(report))
	var all_pass := true
	for key in report:
		if str(key).ends_with("_pass"):
			all_pass = all_pass and report[key]
	get_tree().quit(0 if all_pass else 1)

func _render_original_preview() -> void:
	for i in 30:
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	_save_visual_preview("res://previews/smooth_model.png")
	assert(unshaded_mesh_count == 1, "Joined rigged model must be displayed")
	print("ORIGINAL_MODEL_PREVIEW_OK parts=", unshaded_mesh_count)
	get_tree().quit()

func _assistant_ime_test() -> void:
	var test := preload("res://tests/assistant_ime_flow.gd").new()
	add_child(test)
	await test.run(self)
	get_tree().quit()

func _render_walk_preview() -> void:
	if animation_player == null:
		await _render_original_preview()
		return
	model_pivot.rotation.y = deg_to_rad(55.0)
	_play_animation("Walk")
	animation_player.play(animation_player.assigned_animation, 0.0)
	animation_player.speed_scale = 0.0
	DirAccess.make_dir_recursive_absolute("res://previews/walk_frames")
	var pose_samples: Array = []
	var thigh := skeleton.find_bone("Thigh.L")
	assert(thigh >= 0, "Imported Blender rig is missing its left leg")
	for frame in 24:
		animation_player.seek(frame / 30.0, true)
		animation_player.advance(0.0)
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		pet_viewport.get_texture().get_image().save_png("res://previews/walk_frames/frame_%02d.png" % frame)
		if frame == 0 or frame == 6:
			pose_samples.append(skeleton.get_bone_pose_rotation(thigh))
	assert(not pose_samples[0].is_equal_approx(pose_samples[1]), "Walking must animate the actual leg bones")
	print("CARTOON_WALK_PREVIEW_OK bones=", skeleton.get_bone_count(), " animated_leg=", pose_samples)
	get_tree().quit()
