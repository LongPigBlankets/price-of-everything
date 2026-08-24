"""Scale build_qty_* so each building's turn-1 construction cost lands on the owner's target.

Uniform scaling of the existing kit, then a small integer refinement — the SHAPE of each
recipe (which goods, in what proportion) is authored balance and is left alone; only the
amounts move.
"""
import csv, io, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSVP = os.path.join(ROOT, 'data', 'Buildings - buildingsMVP.csv')
# Turn-1 buy prices, dumped by tools/build_cost_table.tscn (Godot user:// dir).
TSV = os.environ.get('BUILD_COSTS_TSV', os.path.join(ROOT, 'artifacts', 'build_costs_turn1.tsv'))

# Owner's targets, 2026-08-23. Midpoint where a range was given.
TARGETS = {
    'high_tech_manufactory': 1325,   # owner: 1250-1400
    'assembly_plant': 1100,
    'electrolyser': 1000,
    'furnace': 450,
    'mine': 450,
    'eaf': 800,
    'chem_plant': 800,
    'petro_refinery': 800,
    'poly_plant': 800,
    'water_pump': 200,
    'oil_well': 250,
    'fracking_oil_well': 250,
    'onshore_wind_farm': 600,
    'offshore_wind_farm': 800,
    'power_plant': 500,
    'solar_farm': 500,
    'offshore_oil_platform': 850,
    'industrial_factory': 500,
    'battery': 350,
    'heat_battery': 350,
}

# turn-1 buy price by good DISPLAY name, straight out of the engine's own table
price_by_display = {}
for row in csv.DictReader(io.open(TSV, encoding='utf-8'), delimiter='\t'):
    for part in (row['kit'] or '').split(', '):
        if '=' not in part:
            continue
        left, _ = part.rsplit('=', 1)
        _, rest = left.split('x ', 1)
        good, price = rest.split(' @')
        price_by_display[good] = float(price)

goods = list(csv.DictReader(io.open(os.path.join(ROOT, 'data', 'Goods - goodsMVP.csv'), encoding='utf-8')))
price = {}
for g in goods:
    d = g.get('display_name', '')
    if d in price_by_display:
        price[g['internal_name']] = price_by_display[d]

rows = list(csv.DictReader(io.open(CSVP, encoding='utf-8')))
fields = list(rows[0].keys())


def kit_of(row):
    out = []
    for i in range(1, 8):
        m = row.get('build_material_%d' % i) or ''
        q = row.get('build_qty_%d' % i) or ''
        if m and q.strip():
            out.append((i, m, int(q)))
    return out


def cost_of(kit):
    return sum(q * price.get(m, 0.0) for _, m, q in kit)


report = []
for row in rows:
    name = row.get('internal_name', '')
    if name not in TARGETS:
        continue
    cash = float(row.get('build_cost_money') or 0)
    kit = kit_of(row)
    before = cost_of(kit) + cash
    target_mats = TARGETS[name] - cash
    cur = cost_of(kit)
    if cur <= 0:
        continue
    factor = target_mats / cur
    scaled = [(i, m, max(1, int(round(q * factor)))) for i, m, q in kit]

    # Refine: nudge single units, cheapest goods first, while it closes the gap.
    for _ in range(400):
        err = target_mats - cost_of(scaled)
        if abs(err) < 0.5:
            break
        best, best_err = None, abs(err)
        for idx, (i, m, q) in enumerate(scaled):
            p = price.get(m, 0.0)
            if p <= 0:
                continue
            for step in (1, -1):
                nq = q + step
                if nq < 1:
                    continue
                trial = abs(err - step * p)
                if trial < best_err - 1e-9:
                    best, best_err = (idx, nq), trial
        if best is None:
            break
        idx, nq = best
        i, m, _q = scaled[idx]
        scaled[idx] = (i, m, nq)

    for i, m, q in scaled:
        row['build_qty_%d' % i] = str(q)
    after = cost_of(scaled) + cash
    report.append((row.get('display_name', name), before, TARGETS[name], after, factor,
                   sum(q for _, _, q in kit), sum(q for _, _, q in scaled)))

if '--write' in sys.argv:
    with io.open(CSVP, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)
    print('WROTE', CSVP)

print('%-28s %8s %8s %8s %7s %7s' % ('BUILDING', 'BEFORE', 'TARGET', 'AFTER', 'FACTOR', 'UNITS'))
for n, b, t, a, f, u0, u1 in report:
    print('%-28s %8.0f %8d %8.0f %6.2fx %4d->%-4d' % (n, b, t, a, f, u0, u1))
