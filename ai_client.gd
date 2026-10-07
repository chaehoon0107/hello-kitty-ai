extends Node

signal health_changed(data: Dictionary)
signal job_updated(data: Dictionary)
signal history_changed(data: Array)
var base_url := "http://127.0.0.1:18935"
var token := ""
var current_job := ""
var polling := false
var elapsed := 0.0
var healthy := false
var last_health: Dictionary = {}

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.18 and not polling:
		elapsed = 0.0
		_poll()

func _config() -> bool:
	if not FileAccess.file_exists("res://ai/server_info.json"): return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://ai/server_info.json"))
	if not parsed is Dictionary: return false
	token = str(parsed.get("token", ""))
	base_url = "http://127.0.0.1:%d" % int(parsed.get("port", 18935))
	return not token.is_empty()

func request_json(path: String, method := HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
	if token.is_empty() and not _config(): return {"error":"키티가 아직 준비 중이에요"}
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "X-Kitty-Token: " + token])
	var error := request.request(base_url + path, headers, method, JSON.stringify(payload) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		request.queue_free()
		return {"error":"AI와 연결하지 못했어요"}
	var result: Array = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		token = ""
		return {"error":"AI 연결을 기다리고 있어요"}
	if result[1] == 401:
		token = ""
		return {"error":"AI에 다시 연결하고 있어요"}
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary: return parsed
	return {"error":"답변을 읽지 못했어요"}

func _poll() -> void:
	polling = true
	var data := await request_json("/health" if current_job.is_empty() else "/jobs/" + current_job)
	if current_job.is_empty():
		last_health = data
		healthy = data.get("phase", "") == "ready"
		health_changed.emit(data)
	else:
		job_updated.emit(data)
		if data.get("status", "") in ["done", "error", "cancelled"]: current_job = ""
	polling = false

func ask(text: String, image_path: String, conversation_id := "") -> Dictionary:
	var images: Array = []
	if not image_path.is_empty():
		var bytes := FileAccess.get_file_as_bytes(image_path)
		if bytes.size() > 20 * 1024 * 1024: return {"error":"이미지는 20MB 이하로 첨부해 주세요"}
		images.append({"name":image_path.get_file(), "data":Marshalls.raw_to_base64(bytes)})
	var data := await request_json("/ask", HTTPClient.METHOD_POST, {"text":text,"images":images,"conversation_id":conversation_id})
	if data.has("job_id"): current_job = data["job_id"]
	return data

func refresh_history() -> Array:
	var data := await request_json("/conversations")
	var conversations: Array = data.get("conversations", [])
	history_changed.emit(conversations)
	return conversations

func get_conversation(id: String) -> Dictionary:
	return await request_json("/conversations/" + id)

func cancel() -> void:
	if not current_job.is_empty(): await request_json("/cancel/" + current_job, HTTPClient.METHOD_POST)
