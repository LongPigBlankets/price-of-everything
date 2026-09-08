extends Node
const Dialog := preload("res://scripts/exit_feedback_dialog.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("[feedback check] ", "PASS " if ok else "FAIL ", message)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TelemetryState.enabled = false
	preload("res://scripts/app_paths.gd")._base = "/tmp/exit-feedback-check"
	get_window().size = Vector2i(1280, 720)
	var dialog := Dialog.new()
	add_child(dialog)
	check(dialog.submit_button.disabled, "rating required before submit")
	var buttons := dialog.find_children("*", "Button", true, false)
	for button: Button in buttons:
		if button.text == "Good":
			button.button_pressed = true
			button.pressed.emit()
	check(dialog.rating == "Good" and not dialog.submit_button.disabled, "rating enables submit")
	check(get_tree().paused, "gameplay paused while answering")
	var response: Dictionary = {}
	dialog.submitted.connect(func(rating: String, comment: String) -> void: response.assign({"rating": rating, "comment": comment}))
	dialog.comment.text = "  More factories, please.  "
	dialog.submit_button.pressed.emit()
	check(response.get("rating") == "Good" and response.get("comment") == "More factories, please.", "submit captures rating and optional comment")
	check(TelemetryState.queue_exit_feedback("Good", "More factories, please."), "feedback durably queued without network")
	check(not TelemetryState.queue_exit_feedback("invalid", ""), "invalid ratings rejected")
	var dir := preload("res://scripts/app_paths.gd").telemetry_outbox_dir()
	var files := DirAccess.get_files_at(dir)
	var path := ""
	for file: String in files:
		if file.begins_with("feedback_") and file.ends_with(".json"):
			path = dir.path_join(file)
	check(TelemetryState._watermark_of(FileAccess.get_file_as_string(path)) == -1, "feedback cannot advance turn delivery watermark")
	var request := HTTPRequest.new()
	TelemetryState.add_child(request)
	TelemetryState._on_upload_done(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "ok".to_utf8_buffer(), request, path)
	check(FileAccess.file_exists(path), "old receiver response retains feedback for retry")
	request = HTTPRequest.new()
	TelemetryState.add_child(request)
	TelemetryState._on_upload_done(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "feedback_ok".to_utf8_buffer(), request, path)
	check(not FileAccess.file_exists(path), "explicit feedback acknowledgement clears queued response")
	PlayerProfile.mark_exit_feedback_submitted()
	PlayerProfile.exit_feedback_submitted = false
	PlayerProfile._load()
	check(PlayerProfile.exit_feedback_submitted, "submitted flag survives profile reload")
	dialog.submit_button.disabled = false
	if DisplayServer.get_name() != "headless":
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/exit-feedback.png")
	get_tree().quit(1 if failures else 0)
