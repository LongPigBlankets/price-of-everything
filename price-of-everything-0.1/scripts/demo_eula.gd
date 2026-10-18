extends RefCounted
## The displayed terms and their local acceptance record. Separate from match saves:
## loading an old game must neither accept nor revoke the current agreement.

const AppPaths := preload("res://scripts/app_paths.gd")
const TEXT_PATH := "res://data/legal/demo_eula.txt"
const VERSION := "2026-10-18"


static func text() -> String:
	return FileAccess.get_file_as_string(TEXT_PATH).strip_edges()


static func acceptance_path() -> String:
	return AppPaths.saves_dir().path_join("demo_eula.cfg")


static func is_accepted(path: String = "") -> bool:
	var document := text()
	if document.is_empty():
		return false
	var record := ConfigFile.new()
	if record.load(acceptance_path() if path.is_empty() else path) != OK:
		return false
	return record.get_value("agreement", "version", "") == VERSION \
		and record.get_value("agreement", "sha256", "") == document.sha256_text()


static func accept(path: String = "") -> Error:
	var document := text()
	if document.is_empty():
		return ERR_FILE_CORRUPT
	var destination := acceptance_path() if path.is_empty() else path
	var record := ConfigFile.new()
	record.set_value("agreement", "version", VERSION)
	record.set_value("agreement", "sha256", document.sha256_text())
	record.set_value("agreement", "accepted_at_utc", Time.get_datetime_string_from_system(true))
	var temporary := destination + ".tmp"
	var error := record.save(temporary)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary, destination)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error
