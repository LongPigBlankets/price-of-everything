extends Node
## Telemetry PoC probe: fire the sample envelope through HTTPRequest from the
## engine, proving the exported-build path (bundled TLS to script.google.com,
## 302-as-success). See docs/telemetry-spec.md §6.2. Run:
##   <godot> --headless --path . res://tools/telemetry/poc_send.tscn
## Prints "TELEMETRY POC PASS/FAIL" and quits (exit code 0 on pass).

const URL := "https://script.google.com/macros/s/AKfycbw8dUX-A_dSKmI2GB4_2AbRXbGnOKTbP8mpEa17t6wBBAg4Y0LcCnS_xJNH3EeNRwdr/exec"
const ENVELOPE_PATH := "res://tools/telemetry/sample_envelope.json"

func _ready() -> void:
	var raw := FileAccess.get_file_as_string(ENVELOPE_PATH)
	var payload: Dictionary = JSON.parse_string(raw)
	payload["session_id"] = "godotprobe000000000000000000poc1"
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 15.0
	http.max_redirects = 0   # observe the raw 302 — the spec's success signal
	add_child(http)
	http.request_completed.connect(_on_done)
	var err := http.request(URL, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		print("TELEMETRY POC FAIL: request() returned error ", err)
		get_tree().quit(1)
		return
	await get_tree().create_timer(25.0).timeout
	print("TELEMETRY POC FAIL: no response within 25 s")
	get_tree().quit(2)

func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8().strip_edges()
	# With max_redirects = 0 Godot reports RESULT_REDIRECT_LIMIT_REACHED (12) on a
	# 302, not RESULT_SUCCESS — the response code is the success signal, not the enum.
	var passed := code == 302 or (result == HTTPRequest.RESULT_SUCCESS and code == 200)
	print("TELEMETRY POC ", "PASS" if passed else "FAIL",
			": result=", result, " http=", code, " body=", text.left(80))
	get_tree().quit(0 if passed else 1)
