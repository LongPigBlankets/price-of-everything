extends "res://tests/test_base.gd"

const FEATURE := "eula"
const Agreement := preload("res://scripts/demo_eula.gd")
const AgreementScreen := preload("res://scripts/eula_screen.gd")
const Startup := preload("res://scripts/demo_startup.gd")


func _test_eula_first_launch_and_persistent_acceptance() -> void:
	var path := OS.get_temp_dir().path_join("cnc-eula-unit-%d.cfg" % OS.get_process_id())
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_check(not Agreement.is_accepted(path), "eula: missing acceptance requires the agreement")
	_check(Agreement.accept(path) == OK, "eula: explicit acceptance is saved")
	_check(Agreement.is_accepted(path), "eula: acceptance survives reading a fresh record")
	var record := ConfigFile.new()
	_check(record.load(path) == OK, "eula: acceptance is a readable local record")
	_check(not str(record.get_value("agreement", "accepted_at_utc", "")).is_empty(),
		"eula: acceptance records its UTC date")
	_check(not FileAccess.file_exists(path + ".tmp"), "eula: atomic write leaves no temporary record")
	DirAccess.remove_absolute(path)


func _test_eula_changed_terms_require_new_acceptance() -> void:
	var path := OS.get_temp_dir().path_join("cnc-eula-version-%d.cfg" % OS.get_process_id())
	var record := ConfigFile.new()
	record.set_value("agreement", "version", "older-demo")
	record.set_value("agreement", "sha256", Agreement.text().sha256_text())
	record.save(path)
	_check(not Agreement.is_accepted(path), "eula: an older agreement version is not current acceptance")
	record.set_value("agreement", "version", Agreement.VERSION)
	record.set_value("agreement", "sha256", "old-document-hash")
	record.save(path)
	_check(not Agreement.is_accepted(path), "eula: changed document text requires acceptance even within a version")
	_check(Agreement.accept(path) == OK and Agreement.is_accepted(path),
		"eula: reaccepting stores the current terms")
	DirAccess.remove_absolute(path)


func _test_eula_document_is_shipped_before_main_menu() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/demo_startup.tscn",
		"eula: the normal entry point is the agreement gate, not the menu")
	var text := Agreement.text()
	_check(text.contains("Sava Cristian Urigiuc") and text.contains("law of England and Wales"),
		"eula: the displayed agreement includes the approved licensor and governing law")
	_check(text.contains("private, personal use") and text.contains("including monetized ones"),
		"eula: private modifications and monetized gameplay remain permitted")
	_check(not text.contains("Draft for review") and not text.contains("[GOVERNING"),
		"eula: the runtime document contains terms rather than authoring notes")
	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "eula: release preset configuration loads")
	for section: String in ["preset.0", "preset.1", "preset.2"]:
		_check(str(presets.get_value(section, "include_filter", "")).contains("data/legal/demo_eula.txt"),
			"eula: %s includes the plain text document in its release" % section)


func _test_eula_scrollable_document_and_explicit_choices() -> void:
	var screen := AgreementScreen.new()
	add_child(screen)
	for _frame: int in 4:
		await get_tree().process_frame
	var decisions: Array[String] = []
	screen.accept_requested.connect(func() -> void: decisions.append("accept"))
	screen.close_requested.connect(func() -> void: decisions.append("close"))
	_check(screen.document.scroll_active and screen.document.selection_enabled,
		"eula: agreement text can be scrolled and selected")
	_check(screen.document.get_theme_color("default_color") == Color.BLACK,
		"eula: agreement text is black")
	var paper := screen.document.get_theme_stylebox("normal") as StyleBoxFlat
	_check(paper != null and paper.bg_color == Color.WHITE, "eula: agreement paper is white")
	_check(screen.accept_button.get_script() == AgreementScreen.CreamKey
		and screen.close_button.get_script() == AgreementScreen.CreamKey,
		"eula: both actions use the shared DS2 cream keys")
	_check(screen.accept_button.get("title") == "Accept terms" and screen.close_button.get("title") == "Reject and close game",
		"eula: both requested actions stay outside the document")
	var viewport := get_viewport().get_visible_rect()
	_check(viewport.encloses(screen.accept_button.get_global_rect())
		and viewport.encloses(screen.close_button.get_global_rect()),
		"eula: both actions fit on screen after the document wraps")
	var actions_before_scroll := screen.accept_button.get_global_rect()
	var scrollbar := screen.document.get_v_scroll_bar()
	_check(scrollbar.max_value > scrollbar.page, "eula: long agreement scrolls within the available page")
	scrollbar.value = scrollbar.max_value
	await get_tree().process_frame
	_check(screen.accept_button.get_global_rect() == actions_before_scroll,
		"eula: scrolling to the end does not move the acceptance action")
	screen.close_button.pressed.emit()
	_check(decisions == ["close"], "eula: declining does not emit acceptance")
	screen.accept_button.pressed.emit()
	_check(decisions == ["close", "accept"] and screen.accept_button.disabled,
		"eula: acceptance requires the explicit button and prevents a duplicate click")
	screen.show_save_error()
	_check(not screen.accept_button.disabled and screen.get_node("AgreementPanel").is_visible_in_tree(),
		"eula: a failed save leaves the agreement visible and allows retry")
	screen.queue_free()
	await get_tree().process_frame


func _test_eula_save_failure_cannot_open_menu() -> void:
	var startup := Startup.new()
	startup.acceptance_file = OS.get_temp_dir().path_join("cnc-eula-missing-%d-%d/record.cfg" % [
		OS.get_process_id(), Time.get_ticks_usec()])
	add_child(startup)
	await get_tree().process_frame
	var current := get_tree().current_scene
	var screen := startup.get_node("EulaScreen") as AgreementScreen
	screen.accept_button.pressed.emit()
	await get_tree().process_frame
	_check(get_tree().current_scene == current and is_instance_valid(screen),
		"eula: an unwritable acceptance record cannot advance to the menu")
	_check(screen.get_node("AgreementPanel/Content/AcceptanceError").visible and not screen.accept_button.disabled,
		"eula: failed persistence explains the problem and offers retry or close")
	_check(not Agreement.is_accepted(startup.acceptance_file),
		"eula: failed persistence does not grant acceptance")
	startup.queue_free()
	await get_tree().process_frame
