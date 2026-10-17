"""Install reversible visual experiments into an existing disposable APFS clone.

python3 tools/supply_chain_3d/prepare_density_trial.py /private/tmp/stoneshore-density-trials
Only supply-chain presentation files in that clone are changed. No simulation,
regular-map sources, authored geography or production bakes are edited.
"""
from pathlib import Path
import argparse
import shutil
import hashlib

source = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path)
args = parser.parse_args()
destination = args.destination.resolve()
assert destination != source and str(destination).startswith('/private/tmp/stoneshore-density-trials')

def edit(relative, changes):
    text = (source / relative).read_text()
    for before, after in changes:
        assert before in text, (relative, before)
        text = text.replace(before, after)
    (destination / relative).write_text(text)

trial = 'preload("res://tools/supply_chain_3d/density_trial.gd")'
coastal = 'preload("res://tools/supply_chain_3d/coastal_road_trial.gd")'
housing = 'preload("res://tools/supply_chain_3d/housing_trial.gd")'
for name in ['density_trial.gd', 'shore_trial_ground.gd', 'coastal_road_trial.gd', 'housing_trial.gd', 'compare_stoneshore.gd', 'compare_stoneshore.tscn']:
    shutil.copy2(source / 'tools/supply_chain_3d' / name, destination / 'tools/supply_chain_3d' / name)
edit('project.godot', [('config/name="Carbon and Capital V0.4.2"', 'config/name="Stoneshore Density Trials"')])
edit('scripts/supply_chain_3d/board.gd', [
    ('\tvar started := Time.get_ticks_usec()\n\tvar stage := started', f'\t{trial}.configure()\n\tvar started := Time.get_ticks_usec()\n\tvar stage := started'),
    ('\tvar water := Legacy._water_test(terrain)', f'\tif show_all_tiles: extra_tiles = {trial}.scope()\n\tvar water := Legacy._water_test(terrain)'),
    ('\tpreload("res://scripts/supply_chain_3d/road_placement.gd").new().fit(', f'\t{trial}.populate(model)\n\tpreload("res://scripts/supply_chain_3d/road_placement.gd").new().fit('),
])
edit('scripts/supply_chain_3d/coast.gd', [
    ('var ground := Ground.new()', 'var ground := preload("res://tools/supply_chain_3d/shore_trial_ground.gd").new()\n\tground.historical = source'),
])
edit('scripts/supply_chain_3d/authored_region.gd', [
    ('\tpaths.sort_custom(', f'\tpaths = {trial}.paths(paths)\n\tpaths.sort_custom('),
    ('static func road_widths(road_class: String) -> Array:\n', f'static func road_widths(road_class: String) -> Array:\n\tif {coastal}.enabled(): return {coastal}.widths(road_class)\n\tif {trial}.mode == "hybrid": return [7.2, 6.8, 6.4, 6.0]\n'),
])
edit('scripts/supply_chain_3d/road_markings.gd', [
    ('static func lane_lines(level: int, half_width: float) -> Array:\n', f'static func lane_lines(level: int, half_width: float) -> Array:\n\tif {coastal}.enabled(): return {coastal}.lane_lines(level, half_width)\n\tif {trial}.mode == "hybrid": return [[0.0, true]] if level >= 2 else []\n'),
    ('if int(p.way.level) < 2: continue', f'if int(p.way.level) < 2 and not {coastal}.enabled(): continue'),
])
edit('scripts/supply_chain_3d/road_placement.gd', [
    ('\tvar civic_spaces := {}', '\tvar civic_spaces := {}\n\tvar housing_counts := {}\n\tvar office_counts := {}'),
    ('\t\tvar placed := frontage(s, model.tiles[s.tile].center)', f'\t\tvar is_office: bool = s.has("decor_family") and not Civic.is_space(s)\n\t\tif {housing}.enabled() and is_office and int(office_counts.get(str(s.tile), 0)) >= int({housing}.OFFICE_LIMIT.get(str(s.tile), 99)):\n\t\t\tmodel.standing.erase(s); omitted += 1; continue\n\t\tvar placed := frontage(s, model.tiles[s.tile].center)'),
    ('\t\tif Civic.is_space(s): civic_spaces[space_key] = true', '\t\tif Civic.is_space(s): civic_spaces[space_key] = true\n\t\tif is_office: office_counts[str(s.tile)] = int(office_counts.get(str(s.tile), 0)) + 1'),
    ('\t\tvar space_key := str(s.tile) + ":" + str(s.get("decor_family", ""))', f'\t\tif {housing}.enabled() and s.get("infill", false) and int(housing_counts.get(str(s.tile), 0)) >= {housing}.HOUSE_LIMIT:\n\t\t\tmodel.standing.erase(s); omitted += 1; continue\n\t\tvar space_key := str(s.tile) + ":" + str(s.get("decor_family", "")) + ":" + str(s.get("space_slot", ""))'),
    ('\t\tif str(s.kind) == "house": restored += 1', f'\t\tif {housing}.is_housing(s): housing_counts[str(s.tile)] = int(housing_counts.get(str(s.tile), 0)) + 1\n\t\tif str(s.kind) == "house": restored += 1'),
    ('\tfor scale in ([1.0] if s.has("decor_family") and not Civic.is_space(s) else [1.0, 0.8]):', '\tfor scale in ([1.0] if s.get("fixed_housing_scale", false) or (s.has("decor_family") and not Civic.is_space(s)) else [1.0, 0.8]):'),
    ('\tvar low := INF\n\tvar high := -INF', f'\tif {housing}.enabled() and not {housing}.clears_trees(poly, iid): return false\n\tvar low := INF\n\tvar high := -INF'),
    ('s.side = module.side', 's.side = module.side * float(s.get("trial_scale", 1.0))'),
    ('\t\tif Civic.is_space(s): continue #', f'\t\tif {trial}.mode == "hybrid" or s.get("infill", false): continue\n\t\tif Civic.is_space(s): continue #'),
    ('\tvar low := INF\n\tvar high := -INF', f'\tvar clearance := 1.5 if {trial}.mode == "hybrid" else 4.0\n\tvar low := INF\n\tvar high := -INF'),
    ('clear_lots(a, b, 4.0, iid)', 'clear_lots(a, b, clearance, iid)'),
    ('< half + 4.0: return false', '< half + clearance: return false'),
    ('\t\t\t\tfor along in [0.0, -0.65, 0.65]:\n\t\t\t\t\ts.pos', f'\t\t\t\tfor along in [0.0, -0.65, 0.65]:\n\t\t\t\t\tfor depth in ([0, 1, 2] if s.get("infill", false) or ({trial}.mode in ["hybrid", "coastal_housing"] and Civic.is_space(s)) else [0]):\n\t\t\t\t\t\ts.pos'),
    ('(dim.z * 0.5 + half + 7.0)', f'(dim.z * 0.5 + half + (3.0 if {trial}.mode == "hybrid" else (5.0 if s.get("fixed_housing_scale", false) else 7.0)) + depth * (dim.z + 3.0))'),
    ('\n\t\t\t\t\ts.yaw', '\n\t\t\t\t\t\ts.yaw'),
    ('\n\t\t\t\t\tif s.has(', '\n\t\t\t\t\t\tif s.has('),
    ('\n\t\t\t\t\tif clear_plot(', '\n\t\t\t\t\t\tif clear_plot('),
])
edit('scripts/supply_chain_3d/tree_layout.gd', [
    ('\tif str(tile.type) in ["sea", "deep_sea", "mountain"]: return []', f'\tif {coastal}.enabled(): return {coastal}.trees(tid, tile, relief, standing, roads, lines, rivers)\n\tif str(tile.type) in ["sea", "deep_sea", "mountain"]: return []'),
    ('for spot in Legacy._tree_spots(tid, str(tile.type)):', f'for spot in {trial}.tree_spots(tid, tile, roads, Legacy._tree_spots(tid, str(tile.type))):'),
    ('else 8.0))', f'else (3.0 if {trial}.mode == "hybrid" else 8.0)))'),
    ('\t\tif not blocked: result.append(', '\t\tfor tree in result:\n\t\t\tblocked = blocked or p.distance_to(tree.pos) < 15.0\n\t\tif not blocked: result.append('),
])
edit('scripts/supply_chain_3d/terrain_paint.gd', [
    ('\t\tfor e in relief.get("land", []):', f'\t\tif {coastal}.enabled():\n\t\t\tfor ring in {coastal}.water_bands(tile): _polygon(ring.p, ring.colour)\n\t\tfor e in relief.get("land", []):'),
])
edit('scripts/supply_chain_3d/water_art.gd', [
    ('\t\tfor seg in coast:', f'\t\tfor seg in ([] if {coastal}.enabled() else coast):'),
])
# Helper changes and runtime-selected variants must never reuse one another's bakes.
helper_hash = hashlib.sha256(b''.join((source / 'tools/supply_chain_3d' / name).read_bytes() for name in ['density_trial.gd', 'shore_trial_ground.gd', 'coastal_road_trial.gd', 'housing_trial.gd'])).hexdigest()
edit('scripts/supply_chain_3d/bake_cache.gd', [
    ('var files: Array = [SCHEMA, REVISIONS[layer], Engine.get_version_info().string]', f'var files: Array = [SCHEMA, REVISIONS[layer], Engine.get_version_info().string, "{helper_hash}", Array(OS.get_cmdline_user_args()).filter(func(arg: String) -> bool: return arg.begins_with("--density-variant="))]'),
])
print('Prepared density trials in', destination)
