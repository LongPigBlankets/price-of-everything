#!/usr/bin/env python3
"""Controlled tariff sensitivity on recorded game costs; not provider simulation."""
import argparse
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def coefficient(terrain, urban_count=0, large_port_city=False, adjacent_city=False):
    if terrain == 'mountain':
        return 2.5
    if terrain == 'urban':
        if large_port_city:
            return 1.05
        return 1.25 if urban_count >= 4 else 1.5
    if terrain in ('rural', 'hill'):
        return 1.75 if adjacent_city else 2.0
    raise ValueError(f'No proposed service rule for {terrain}')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ad-valorem', type=float, default=.005)
    parser.add_argument('--solid-heavy', type=float, default=.045)
    parser.add_argument('--ultra-heavy', type=float, default=.58)
    args = parser.parse_args()
    if not (0 <= args.ad_valorem <= 1 and args.solid_heavy >= 0 and args.ultra_heavy >= 0):
        parser.error('Rates must be nonnegative; ad valorem is a fraction between zero and one')
    goods = {r['ID']: r for r in csv.DictReader((ROOT / 'data/Goods - goodsMVP.csv').open())}
    source = (ROOT / 'scripts/economy_config.gd').read_text()
    block = source.split('const TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS := {', 1)[1].split('}', 1)[0]
    rates = {k: float(v) for k, v in re.findall(r'"([a-z_]+)":\s*([\d.]+)', block)}
    def snapshot(route, version, stage=''):
        return json.loads((ROOT / f'tests/snapshots/pepper_valley_motors{route}_v{version}{stage}.json').read_text())
    motor = snapshot('', 5)
    chain = snapshot('', 7, '_furnace')
    rail_motor = snapshot('_rail_three_owned', 5)
    rail_chain = snapshot('_rail_three_owned', 7, '_furnace')
    motor_inputs = {'g_006': 32, 'g_007': 32}
    motor_outputs = {'g_008': 33}
    furnace_inputs = {'g_004': 37, 'g_001': 20}
    furnace_outputs = {'g_006': 44}
    def value(manifest):
        return sum(q * float(goods[g]['base_price']) for g, q in manifest.items())
    def fee(manifest, weights, density):
        av = args.ad_valorem * value(manifest)
        weight = density * sum(q * weights[goods[g]['transport_class']] for g, q in manifest.items())
        return {'ad_valorem': av, 'weight_location': weight, 'total': av + weight}
    m = motor['means']; c = chain['means']
    motor_margin = m['goods_receipts'] - m['goods_purchases'] - m['factory_costs']
    chain_margin = c['middleman_goods_receipts_reference'] - c['middleman_goods_purchases_reference'] - c['factory_costs']
    furnace_margin = chain_margin - motor_margin
    profiles = {'existing_transport_rates': rates}
    # Explicit trial, not an approved live tariff: keep bulk goods affordable,
    # recover more logistics cost on ultra-heavy goods such as motors.
    candidate = dict(rates, solid_heavy=args.solid_heavy, ultra_heavy=args.ultra_heavy)
    profiles['bulk_preserving_trial'] = candidate
    results = {}
    for profile, weights in profiles.items():
        rows = []
        for density in (1.05, 1.25, 1.5, 1.75, 2.0, 2.5):
            mi, mo = fee(motor_inputs, weights, density), fee(motor_outputs, weights, density)
            fi, fo = fee(furnace_inputs, weights, density), fee(furnace_outputs, weights, density)
            mf, ff = mi['total'] + mo['total'], fi['total'] + fo['total']
            rows.append({'coefficient': density, 'motor_input_fee': mi, 'motor_output_fee': mo,
                         'furnace_input_fee': fi, 'furnace_output_fee': fo,
                         'motor_total_fee': mf, 'furnace_total_fee': ff, 'combined_fee': mf+ff,
                         'motor_profit': motor_margin-mf, 'furnace_incremental_profit': furnace_margin-ff,
                         'combined_profit': chain_margin-mf-ff})
        results[profile] = rows
    density = 1.5
    motor_av = args.ad_valorem * (value(motor_inputs) + value(motor_outputs))
    furnace_av = args.ad_valorem * (value(furnace_inputs) + value(furnace_outputs))
    base_mw = sum(q*rates[goods[g]['transport_class']] for manifest in (motor_inputs,motor_outputs) for g,q in manifest.items())
    base_fw = sum(q*rates[goods[g]['transport_class']] for manifest in (furnace_inputs,furnace_outputs) for g,q in manifest.items())
    min_scale_for_rail_advantage = (rail_motor['means']['direct_logistics'] - motor_av)/(density*base_mw)
    min_scale_for_chain_rail_advantage = (chain_margin - rail_chain['means']['direct_operating_contribution'] - motor_av - furnace_av)/(density*(base_mw+base_fw))
    max_scale_for_furnace_growth = (furnace_margin-furnace_av)/(density*base_fw)
    # Location precedence and city size boundary are part of this analysis contract.
    assert coefficient('mountain', adjacent_city=True)==2.5
    assert coefficient('urban', 3)==1.5 and coefficient('urban', 4)==1.25
    assert coefficient('urban', 7, True)==1.05
    assert coefficient('hill', adjacent_city=True)==1.75 and coefficient('rural')==2
    trial = results['bulk_preserving_trial'][2]
    economic_checks = {
        'uniform_scale_cannot_satisfy_both_chain_targets': min_scale_for_chain_rail_advantage > max_scale_for_furnace_growth,
        'motor_provider_beats_starting_rail': trial['motor_profit'] > rail_motor['means']['direct_operating_contribution'],
        'furnace_improves_provider_at_pepper': trial['furnace_incremental_profit'] > 0,
        'integrated_rail_chain_beats_provider': trial['combined_profit'] < rail_chain['means']['direct_operating_contribution'],
        'furnace_improves_provider_at_every_coefficient': all(row['furnace_incremental_profit'] > 0 for row in results['bulk_preserving_trial']),
    }
    progression = {}
    for stage in ('output', 'research'):
        r = snapshot('_rail_three_owned', 5, '_' + stage)['means']
        outputs = {'g_008': 36}
        f = fee(motor_inputs, candidate, 1.5)['total'] + fee(outputs, candidate, 1.5)['total']
        progression[stage] = {'dynamic_middleman_fee': f,
            'dynamic_middleman_profit': r['goods_receipts']-r['goods_purchases']-r['factory_costs']-f,
            'direct_rail_profit': r['direct_operating_contribution']}
    report = {'status':'tariff experiment only; no live tariffs or provider simulation changed',
        'formula':f'sum(quantity * ({args.ad_valorem} * catalogue market base price + weight_rate * location_coefficient)) over building inputs and outputs',
        'parameters':vars(args), 'economic_checks':economic_checks,
        'storage':'included; no fixed storage or per-building charge added',
        'independent_buildings':True, 'price_basis':'catalogue base prices, same for fee valuation in either direction; actual goods trades retain bid/ask spread',
        'locations':'Pepper Valley has 2 named urban tiles, coefficient 1.5. Port Lightning has 4 named urban tiles, coefficient 1.25. Large-port-city eligibility remains an explicit authoring decision; no guessed threshold applied.',
        'coefficient_sweep_scope':'Fee sensitivity at unchanged Pepper Valley production costs; not simulation of other locations.',
        'source_snapshots':['pepper_valley_motors_v5.json','pepper_valley_motors_rail_three_owned_v5.json','pepper_valley_motors_v7_furnace.json','pepper_valley_motors_rail_three_owned_v7_furnace.json'],
        'profiles':profiles,'results':results, 'single_factory_progression': progression,
        'before_provider_logistics':{'motor':motor_margin,'furnace_increment':furnace_margin,'combined':chain_margin},
        'direct_profits':{'motor_roads':m['direct_operating_contribution'],'motor_rail':rail_motor['means']['direct_operating_contribution'],'chain_roads':c['direct_operating_contribution'],'chain_rail':rail_chain['means']['direct_operating_contribution']},
        'uniform_scale_bounds_at_pepper':{'scale_needed_for_starting_rail_to_beat_provider':min_scale_for_rail_advantage,'scale_needed_for_integrated_chain_rail_to_beat_provider':min_scale_for_chain_rail_advantage,'maximum_scale_for_nonnegative_furnace_increment':max_scale_for_furnace_growth},
        'maximum_solid_heavy_rate_for_nonnegative_furnace':{str(d):(furnace_margin-furnace_av)/(101*d) for d in (1.05,1.25,1.5,1.75,2,2.5)}}
    suffix = '' if (args.ad_valorem, args.solid_heavy, args.ultra_heavy) == (.005, .045, .58) else f'_av{args.ad_valorem}_heavy{args.solid_heavy}_ultra{args.ultra_heavy}'
    out=ROOT/f'reports/balance/middleman_dynamic_fee_2026-09-19{suffix}.json'
    out.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'pepper':{k:v[2] for k,v in results.items()}, 'scale_bounds':report['uniform_scale_bounds_at_pepper']},indent=2))

if __name__=='__main__':
    main()
