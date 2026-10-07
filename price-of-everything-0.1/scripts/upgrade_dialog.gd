extends Control
# The "Upgrade building" dialog's workings: what it shows comes from BuildingWorks.preview_upgrade(),
# and its keys commit through BuildingWorks.start_upgrade() / cancel_upgrade(). Sourcing mirrors
# construction: upgrade from tile stock, order the shortfall from market, or transfer it in.
# The look is scripts/ledger_v3/upgrade_dialog_ds2.gd, which extends this and builds the shell
# (_build_shell) and the card (_rebuild).
#
# A full-rect scrim makes it modal. One instance is reused across buildings via open().

signal closed
signal committed(instance_id: String)

var _instance_id: String = ""
var _preview: Dictionary = {}

var _card: PanelContainer
var _content: VBoxContainer


func _ready() -> void:
	_build_shell()
	visible = false
	# Keep the dialog live while it's open as the upgrade is queued, advances, and completes.
	BuildingWorks.building_upgrade_progress.connect(_on_upgrade_signal)
	BuildingWorks.building_upgraded.connect(_on_upgrade_signal)
	BuildingWorks.building_upgrade_cancelled.connect(_on_upgrade_signal)


# Open for a building instance, rebuilding the card from a fresh preview.
func open(instance_id: String) -> void:
	_instance_id = instance_id
	_preview = BuildingWorks.preview_upgrade(instance_id)
	_rebuild()
	visible = true
	move_to_front()


func close() -> void:
	visible = false
	closed.emit()


# A turn advanced this building's upgrade — refresh the open card so the countdown/state is live.
func _on_upgrade_signal(instance_id: String, _arg = 0) -> void:
	if visible and instance_id == _instance_id:
		_preview = BuildingWorks.preview_upgrade(_instance_id)
		_rebuild()


## Builds the dialog's shell: the scrim, `_card` and `_content`. The look's own.
func _build_shell() -> void:
	pass


func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		position = Vector2.ZERO


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


## Builds the card from `_preview`. The look's own.
func _rebuild() -> void:
	pass


func _cancel() -> void:
	# MatchState emits building_upgrade_cancelled, which the detail panel listens for to refresh.
	if BuildingWorks.cancel_upgrade(_instance_id):
		_toast("Upgrade cancelled — materials returned to the tile.", "show_caution")
	close()


func _commit(mode: String) -> void:
	var result: Dictionary = BuildingWorks.start_upgrade(_instance_id, mode)
	if bool(result.get("ok", false)):
		var status := str(result.get("status", ""))
		if status == BuildingWorks.UPGRADE_STATUS_AWAITING:
			_toast("Upgrade queued — sourcing materials, then %d turns." % int(_preview.get("duration", 3)), "show_caution")
		else:
			_toast("Upgrade started — ready in %d turns." % int(_preview.get("duration", 3)), "show_caution")
		committed.emit(_instance_id)
		close()
		return
	var reason := str(result.get("reason", "Cannot upgrade."))
	if result.has("missing"):
		var parts: PackedStringArray = []
		for gid in (result.get("missing", {}) as Dictionary):
			parts.append("%d× %s" % [int(result["missing"][gid]), Catalog.get_display_name(str(gid))])
		reason += "  Need: " + ", ".join(parts)
	_toast(reason, "show_error")


func _toast(message: String, method_name: String) -> void:
	var toast := get_tree().root.find_child("ToastLayer", true, false)
	if toast != null and toast.has_method(method_name):
		toast.call(method_name, message)
	else:
		push_warning(message)
