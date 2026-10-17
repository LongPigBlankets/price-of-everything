"""Independent geometric checks on the serialized 3D water bake (Shapely)."""
import json
from pathlib import Path
from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]

def polygon(flat):
    return Polygon(list(zip(flat[::2], flat[1::2])))

def verify():
    source = json.loads((ROOT/'data/hills_baked.json').read_text())
    data = json.loads((ROOT/'data/supply_chain_water.json').read_text())
    old = unary_union([polygon(r['p']).buffer(0) for r in source['sea'] if r['b'] == 5]
                      + [polygon(r['p']).buffer(0) for r in source['polys'] + source['lakes']])
    coast = unary_union([polygon(p) for p in data['coast']])
    outward_error = coast.difference(old.buffer(20.002)).area
    inward_error = old.buffer(-5.002).difference(coast).area
    assert outward_error < .01 and inward_error < .01
    lakes = unary_union([polygon(r['p']) for r in data['lakes']])
    clipped = unary_union([polygon(p) for tile in data['tiles'].values() for p in tile['lakes']])
    tile_cut_error = clipped.symmetric_difference(lakes).area
    assert tile_cut_error < 2, tile_cut_error  # coordinate quantization, on a ~4M u² surface
    foam = unary_union([polygon(p['p']) for tile in data['tiles'].values()
                        for p in tile['ink'] if p['tone'] == 'lake_foam'])
    false_interior_shore = foam.intersection(lakes.buffer(-.81)).area
    assert false_interior_shore < .01, false_interior_shore
    result = {'coast_outside_20u_area': outward_error, 'coast_inside_5u_area': inward_error,
              'lake_tile_cut_error_area': tile_cut_error, 'false_interior_shore_area': false_interior_shore,
              'minimum_terrain_lip': min(c['minimum_lip'] for c in data['lake_checks']),
              'lake_sources': len(data['lake_checks']), 'islets': data['islets']}
    assert result['minimum_terrain_lip'] >= 1
    print(json.dumps(result, indent=2))
    path = ROOT.parent/'outputs/supply-chain-3d/water-greenery/validation/water-geography.json'
    path.write_text(json.dumps(result, indent=2)+'\n')

if __name__ == '__main__': verify()
