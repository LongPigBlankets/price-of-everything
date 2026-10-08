extends RefCounted
## Orthographic orbit rig, independent of the regular map's Camera2D.
const HOME_YAW := PI / 4.0
const HOME_PITCH := 0.6154797
const MIN_PITCH := 0.30
const MAX_PITCH := 1.35
const MIN_SIZE := 240.0
const MAX_SIZE := 14000.0
var yaw := HOME_YAW
var pitch := HOME_PITCH
var span := 1800.0
var target := Vector3.ZERO

func apply(camera: Camera3D) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = span
	camera.near = 1.0
	camera.far = 40000.0
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = target + direction * 16000.0
	camera.look_at(target, Vector3.UP)
	camera.force_update_transform()

func orbit(delta: Vector2) -> void:
	yaw = wrapf(yaw - delta.x * 0.006, -PI, PI)
	pitch = clampf(pitch + delta.y * 0.005, MIN_PITCH, MAX_PITCH)

func pan(delta: Vector2, viewport_height: float) -> void:
	var scale := span / maxf(1.0, viewport_height)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	target -= right * delta.x * scale
	target -= forward * delta.y * scale / maxf(0.25, sin(pitch))

func capture() -> Dictionary:
	return {"yaw": yaw, "pitch": pitch, "span": span, "target": target}

func restore(state: Dictionary) -> void:
	yaw = wrapf(float(state.get("yaw", HOME_YAW)), -PI, PI)
	pitch = clampf(float(state.get("pitch", HOME_PITCH)), MIN_PITCH, MAX_PITCH)
	span = clampf(float(state.get("span", 1800.0)), MIN_SIZE, MAX_SIZE)
	target = state.get("target", Vector3.ZERO)
