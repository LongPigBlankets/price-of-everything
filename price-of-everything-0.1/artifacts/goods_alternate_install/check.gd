extends SceneTree
const Icons = preload("res://good_icons.gd")
var checks := 0
func check(ok: bool, message: String) -> void:
 if not ok:
  push_error(message)
  quit(1)
  assert(ok, message)
 checks += 1
func _initialize() -> void:
 var cases = JSON.parse_string(FileAccess.get_file_as_string("res://cases.json"))
 for item in cases:
  var tex = load(item.path) as Texture2D
  check(tex != null and tex.get_size() == Vector2(item.size,item.size), item.path)
  check(tex.get_image().has_mipmaps(), "No mipmaps: " + item.path)
 for tier in ["medium", "small", "very_small"]:
  var path = Icons.resolve_path("g_056", "ice_car", tier)
  check(path == "res://assets/icons/goods/%s/g_056_ice_car.png" % tier, "Main diesel priority")
  check(Icons.texture_for("g_056", "ice_car", tier).resource_path == path, "Path/texture agreement")
 check(Icons.resolve_path("", "fixture_priority", "small") == "res://assets/icons/goods/medium/fixture_priority.png", "Main in another tier must beat alternate")
 var fallback = "res://assets/icons/goods/alternate_icons/medium/fixture_fallback.png"
 check(Icons.resolve_path("", "fixture_fallback", "very_small") == fallback, "Alternate tier fallback")
 check(Icons.texture_for("", "fixture_fallback", "very_small").resource_path == fallback, "Alternate texture load")
 check(Icons.resolve_path("fixture_id", "unknown") == "res://assets/icons/goods/alternate_icons/small/fixture_id.png", "ID-only fallback")
 check(Icons.resolve_path("unknown", "fixture_name") == "res://assets/icons/goods/alternate_icons/small/fixture_name.png", "Name-only fallback")
 check(Icons.resolve_path("unknown", "unknown") == "", "Missing path")
 check(Icons.texture_for("unknown", "unknown") == null, "Missing texture")
 Icons.warm_async([{"id":"", "internal_name":"fixture_fallback"}])
 Icons.warm([{"id":"", "internal_name":"fixture_fallback"}])
 check(Icons.texture_for("", "fixture_fallback").resource_path == fallback, "Warm fallback")
 print("PASS: %d alternate loader and imported texture checks" % checks)
 quit(0)
