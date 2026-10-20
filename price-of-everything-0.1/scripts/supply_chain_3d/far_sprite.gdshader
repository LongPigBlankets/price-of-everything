shader_type spatial;
// Multi-angle colour/depth impostor. Depth keeps billboards from cutting into
// hills, covering foreground roads, or making submerged mine benches float.
render_mode unshaded, cull_disabled, fog_disabled, skip_vertex_transform, depth_prepass_alpha, alpha_to_coverage;
#include "res://scripts/supply_chain_3d/detail_mask.gdshaderinc"
uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_art : filter_linear_mipmap, repeat_disable;
uniform float span = 1.0;
uniform vec2 atlas_grid = vec2(16.0, 5.0);
uniform vec2 grade_range = vec2(-100000.0, 100000.0);
uniform float foliage_softness : hint_range(0.0, 1.0) = 0.0;
// 0 = as authored (the company's own and unclassified), 2 = decorative scenery, 3 = an NPC's.
instance uniform float sc_role = 0.0;
uniform float decor_grey = 0.65;
uniform float npc_grey = 0.80;
// Trees take the map sheet's print with the terrain; buildings take the catalogue plate's.
uniform bool landscape = false;
#include "res://scripts/supply_chain_3d/print_look.gdshaderinc"
varying vec2 frame_index;
varying float world_span;
varying vec3 view_point;
varying flat vec2 world_anchor;
void vertex() {
 world_anchor = MODEL_MATRIX[3].xz;
 vec3 direction = normalize(INV_VIEW_MATRIX[2].xyz);
 // Select the source view through the full inverse transform. House height is
 // independent of footprint, so using only yaw would stretch the roof as well
 // as the walls and give the depth card a different silhouette from its mesh.
 mat3 model_basis = mat3(MODEL_MATRIX);
 vec3 local_direction = normalize(inverse(model_basis) * direction);
 float yaw = mod(atan(local_direction.x, local_direction.z) + TAU, TAU);
 float pitch = asin(clamp(local_direction.y, -1.0, 1.0));
 frame_index = vec2(mod(floor(yaw / TAU * atlas_grid.x + 0.5), atlas_grid.x),
   clamp(floor((pitch - 0.30) / (1.35 - 0.30) * (atlas_grid.y - 1.0) + 0.5), 0.0, atlas_grid.y - 1.0));
 // Transform the source image plane and its depth ray together. This reduces
 // to the original camera-facing square for every uniformly scaled asset.
 vec3 local_right = normalize(cross(vec3(0.0, 1.0, 0.0), local_direction));
 vec3 local_up = cross(local_direction, local_right);
 world_span = span * length(model_basis * local_direction);
 vec3 center = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
 VERTEX = center + mat3(VIEW_MATRIX) * model_basis * (local_right * VERTEX.x + local_up * VERTEX.y);
 view_point = VERTEX;
 NORMAL = vec3(0.0, 0.0, 1.0);
}
vec3 to_linear(vec3 c) {
 return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void fragment() {
 bool hidden = lod_hidden(FRAGCOORD.xy) || replaced_by_detail(world_anchor, FRAGCOORD.xy);
 // Whole-card residency rejection is coherent and keeps the steady-state fast path.
 if (lod_side == 0 && local_detail_blend >= 1.0 && hidden) { discard; }
 vec2 atlas_uv = (frame_index + UV) / atlas_grid;
 vec4 paint = texture(artwork, atlas_uv);
 vec4 depth_sample = texture(depth_art, atlas_uv);
 float depth_offset = (depth_sample.a > 0.01 ? depth_sample.r - 0.5 : 0.0) * world_span;
 vec3 at = view_point + vec3(0.0, 0.0, depth_offset);
 vec4 clip = PROJECTION_MATRIX * vec4(at, 1.0);
 DEPTH = OUTPUT_IS_SRGB ? clip.z / clip.w * 0.5 + 0.5 : clip.z / clip.w;
 vec3 world = (INV_VIEW_MATRIX * vec4(at, 1.0)).xyz;
 float y = (world.x + world.z) * 0.40824829 - world.y * 0.81649658;
 float t = clamp((y - grade_range.x) / max(1.0, grade_range.y - grade_range.x), 0.0, 1.0);
 vec3 grade = mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);
 vec3 foliage = vec3(0.49, 0.53, 0.34);
 vec3 colour = mix(paint.rgb, OUTPUT_IS_SRGB ? foliage : to_linear(foliage), foliage_softness);
 float alpha = paint.a;
 float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
 if (sc_role > 1.5) {
  bool npc = sc_role > 2.5;
  vec3 grey = vec3(luma) * (npc ? vec3(1.05, 1.02, 0.95) : vec3(0.98, 0.99, 1.02));
  colour = mix(colour, grey, npc ? npc_grey : decor_grey);
  if (npc) colour = mix(colour, OUTPUT_IS_SRGB ? vec3(0.88, 0.86, 0.80) : to_linear(vec3(0.88, 0.86, 0.80)), 0.18);
 }
 colour *= OUTPUT_IS_SRGB ? grade : to_linear(grade);
 // Decorative scenery steps back furthest at the zooms that show it as a sprite.
 float scenery = sc_role > 1.5 && sc_role < 2.5 ? sc3d_calm : 0.0;
 float npc_ink = sc_role > 2.5 ? sc3d_calm : 0.0;
 vec3 printed = print_paint(OUTPUT_IS_SRGB ? colour : print_to_srgb(colour), FRAGCOORD.xy, landscape, scenery - npc_ink);
 ALBEDO = OUTPUT_IS_SRGB ? printed : print_to_linear(printed);
 ALPHA = alpha;
 ALPHA_SCISSOR_THRESHOLD = 0.025;
 // Forward+ requires an AA edge below the scissor threshold; 1.0 makes
 // opaque sprite interiors translucent. Preserve Compatibility's authored look.
 ALPHA_ANTIALIASING_EDGE = OUTPUT_IS_SRGB ? 1.0 : 0.01;
 ALPHA_TEXTURE_COORDINATE = atlas_uv * vec2(textureSize(artwork, 0));
 // Sample colour/depth before divergent pixel coverage, preserving mip derivatives.
 if (hidden || loading_hidden(world_anchor, FRAGCOORD.xy)) { discard; }
}
