#!/usr/bin/env python3
"""Build data/start_buildings.json — the NPC-owned buildings every match starts with.

Each road region (data/road_regions.json) gets a themed pool of pre-existing
buildings sized by its identity, owned by one NPC company per region, with a
valid recipe per building (mines/wells matched to the tile's deposits) and a
market phase tag 1-5 (the later purchase-market rotation). Counts:

  capital_port        25  (manufacturing + metallurgy + electrochemistry)
  dense_city          15  (theme axes; agri quota moves to industry when all-urban)
  sparse_city          7  (one axis + farms/forest)
  dense_rural         21  (10 farms, 10 forests, 1 manufacturing)
  sparse_rural       7-13 (4-7 farms, 3-6 forests, mines on deposits;
                           Peatsfield additionally petrochem — shale oil)
  mountain_range     2-4  (mines on deposit tiles, the mining axis's home)

Recipes are validated the same way Catalog's promotion gate does (building
alias resolves + every input/output good exists), so nothing here can be a
dead recipe at runtime. Forests (b_015) are only placed on rural/hill tiles
south of the old-growth auto-seed band (row > 6) so the two systems never
stack blobs on one tile.

Deterministic — no randomness; per-region FNV offsets pick phases and counts.

Usage:  python scripts/build_start_buildings.py
"""

import csv
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGIONS_PATH = os.path.join(ROOT, "data", "road_regions.json")
TILES_PATH = os.path.join(ROOT, "data", "tile_properties.csv")
RECIPES_PATH = os.path.join(ROOT, "data", "recipes_all.csv")
GOODS_PATH = os.path.join(ROOT, "data", "Goods - goodsMVP.csv")
BUILDINGS_PATH = os.path.join(ROOT, "data", "Buildings - buildingsMVP.csv")
OUT_PATH = os.path.join(ROOT, "data", "start_buildings.json")

# Mirrors Catalog.BUILDING_ALIAS (catalog.gd).
BUILDING_ALIAS = {
    
    "factory": "industrial_factory",
    "industrial_goods_factory": "industrial_factory",
    "consumer_goods_factory": "consumer_factory",
    "water_well": "water_pump",
    "desal_plant": "desal",
    "water_treatment_plant": "water_recycling",
    "hydro_dam": "hydro_power_plant",
    "forest": "new_forest",
}

OLD_GROWTH_MAX_ROW = 6  # world_map.NORTH_OLD_GROWTH_MAX_ROW — b_016 auto-seed band

# Mining/oil-extraction policy: a deposit may be exploited from game start ONLY
# if it is a "small" deposit (amount 500 or 1000) OR it is the nearest deposit
# to a port city. Every other deposit (the 2000/5000 finds, and the unsized
# placeholders) stays in the ground for the player to discover by surveying —
# otherwise pre-placing a mine on every deposit defeats the survey mechanic.
EXPLOITABLE_AMOUNTS = {500, 1000}
PORT_CITY_TILES = ["tile_5_10", "tile_11_17", "tile_24_7", "tile_22_16"]  # ports.csv tile_id

MINE_RECIPE_BY_DEPOSIT = {
    "coal": "r_001",
    "iron_ore": "r_002",
    "copper_ore": "r_006",
    "basic_salt": "r_010",
    "bauxite_ore": "r_015",
    "ree_ore": "r_017",
    "sand": "r_018",
    "limestone": "r_019",
    "alloy_ore": "r_134",
    "sulphur": "r_179",
}

# Theme axis -> ordered (building internal_name, recipe_id) pool, cycled.
AXIS_POOLS = {
    "metallurgy": [("furnace", "r_005"), ("furnace", "r_003"), ("eaf", "r_076"), ("furnace", "r_053")],
    "metallurgy_copper": [("furnace", "r_007"), ("industrial_factory", "r_008"), ("eaf", "r_085"), ("furnace", "r_007")],
    "manufacturing": [("industrial_factory", "r_126"), ("industrial_factory", "r_009"), ("assembly_plant", "r_057"), ("consumer_factory", "r_166"), ("industrial_factory", "r_008")],
    "electrochemistry": [("chem_plant", "r_012"), ("electrolyser", "r_079"), ("chem_plant", "r_046"), ("electrolyser", "r_039")],
    "petrochem": [("petro_refinery", "r_180"), ("poly_plant", "r_024"), ("petro_refinery", "r_022"), ("poly_plant", "r_028")],
}
FLAGSHIP = ("high_tech_manufactory", "r_127")  # capital only, pinned to phase 5
# Agri goods (food/biomass/wood) aren't in goodsMVP yet, so every farm/forest
# recipe fails the promotion gate — seed them recipe-less (old-growth precedent)
# until the agri goods land.
FARM = ("farm", "")
FOREST = ("new_forest", "")
SUPPORT_WATER = ("water_pump", "r_011")   # needs a water deposit on the tile
SUPPORT_DESAL = ("desal", "r_051")
SUPPORT_POWER = ("power_plant", "r_004")

# Dense-city theme axes (designer-ruled four + deposit-grounded proposals).
DENSE_AXES = {
    "capital_port": ["manufacturing", "metallurgy", "electrochemistry"],
    "vandel_port": ["manufacturing", "metallurgy"],
    "arin_city": ["petrochem", "electrochemistry"],
    "stoneshore": ["metallurgy"],
    "kingstown": ["metallurgy"],
    "copperstown": ["metallurgy_copper"],
    "teganfort": ["metallurgy", "manufacturing"],
    "patran_city": ["manufacturing", "metallurgy"],
    "gold_arm": ["electrochemistry", "manufacturing"],
    "port_lightning": ["electrochemistry", "manufacturing"],
    "asp_city": ["manufacturing"],
    "blackfarm": ["petrochem"],
    "fort_silversworth": ["manufacturing"],
}
SPARSE_AXES = {
    "ashmouth": "petrochem",
    "arinnal": "electrochemistry",
    "crying_shore": "electrochemistry",
    "leathertown": "metallurgy",
    "lightning_bourne": "metallurgy",
    "tomash": "metallurgy",
    "long_valley": "metallurgy",
    "snare_harbour": "metallurgy",
    # everything else defaults to manufacturing
}

OWNER_SUFFIX = {
    "metallurgy": "Ironworks",
    "metallurgy_copper": "Copperworks",
    "manufacturing": "Manufacturing Co.",
    "electrochemistry": "Electrochemical Works",
    "petrochem": "Petrochemical Co.",
}

PETROCHEM_RURAL_EXCEPTION = "peatsfield"  # designer: peatlands may run petrochem


def fnv(text):
    h = 0xCBF29CE484222325
    for ch in text.encode("utf-8"):
        h = ((h ^ ch) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def load_goods():
    names = set()
    with open(GOODS_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            name = (row.get("internal_name") or "").strip()
            if name:
                names.add(name)
    return names


def load_buildings():
    by_internal = {}
    with open(BUILDINGS_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            internal = (row.get("internal_name") or "").strip()
            if internal:
                by_internal[internal] = row["ID"].strip()
    return by_internal


def load_recipes(goods, buildings_by_internal):
    """recipe_id -> resolved building b_id, only recipes the promotion gate keeps."""
    valid = {}
    with open(RECIPES_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rid = (row.get("recipe_id") or "").strip()
            internal = (row.get("building_id") or "").strip()
            if not rid or not internal:
                continue
            internal = BUILDING_ALIAS.get(internal, internal)
            b_id = buildings_by_internal.get(internal)
            if not b_id:
                continue
            ok = True
            for i in range(1, 7):
                g = (row.get("input_%d" % i) or "").strip()
                if g and g not in goods:
                    ok = False
            for i in range(1, 6):
                g = (row.get("output_%d" % i) or "").strip()
                if g and g not in goods:
                    ok = False
            if ok:
                valid[rid] = b_id
    return valid


def load_tiles():
    tiles = {}
    with open(TILES_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            deposits = []      # token names (water included), for type checks
            amounts = []       # (token, amount-or-None) for non-water tokens
            for raw in (row.get("deposits") or "").split("|"):
                raw = raw.strip()
                if not raw:
                    continue
                token = raw.split("(")[0].strip()
                deposits.append(token)
                if token == "water":
                    continue
                amount = None
                if "(" in raw and raw.endswith(")"):
                    inner = raw[raw.index("(") + 1:-1]
                    if inner.isdigit():
                        amount = int(inner)
                amounts.append((token, amount))
            tiles[row["id"].strip()] = {
                "type": (row.get("type") or "").strip().lower(),
                "deposits": deposits,
                "amounts": amounts,
            }
    return tiles


def _tile_rc(tile_id):
    parts = tile_id.split("_")
    return int(parts[1]), int(parts[2])


def compute_exploitable(tiles):
    """tile_id -> set of deposit tokens that may carry a mine/well at game start."""
    # Nearest non-water-deposit tile to each port city (offset-grid distance is
    # plenty for a "nearest" pick and keeps this deterministic + reviewable).
    port_nearest = set()
    deposit_tiles = [t for t, d in tiles.items()
                     if any(tok != "water" for tok in d["deposits"])]
    for port in PORT_CITY_TILES:
        pc, pr = _tile_rc(port)
        best, best_d = None, 1e30
        for t in deposit_tiles:
            if t == port:
                continue
            c, r = _tile_rc(t)
            d = (c - pc) ** 2 + (r - pr) ** 2
            if d < best_d or (d == best_d and t < best):
                best, best_d = t, d
        if best:
            port_nearest.add(best)

    out = {}
    for tile_id, data in tiles.items():
        tokens = set()
        for token, amount in data["amounts"]:
            if amount in EXPLOITABLE_AMOUNTS or tile_id in port_nearest:
                tokens.add(token)
        if tokens:
            out[tile_id] = tokens
    return out, port_nearest


class RegionBuilder:
    def __init__(self, key, region, tiles, recipes, buildings_by_internal, exploitable):
        self.key = key
        self.region = region
        self.recipes = recipes
        self.by_internal = buildings_by_internal
        self.entries = []
        self.per_tile = {}
        info = [(t, tiles.get(t, {"type": "?", "deposits": []})) for t in region["tiles"]]
        self.urban = [t for t, d in info if d["type"] == "urban"]
        self.rural = [t for t, d in info if d["type"] == "rural"]
        self.rural_hill = [t for t, d in info if d["type"] in ("rural", "hill")]
        self.land = [t for t, d in info if d["type"] in ("urban", "rural", "hill", "mountain")]
        # Only deposits the policy lets us exploit (compute_exploitable); the rest
        # stay unsurveyed in the ground.
        self.deposit_tiles = [(t, sorted(exploitable[t])) for t, d in info if t in exploitable]
        self.water_tiles = [t for t, d in info if "water" in d["deposits"]]
        self.tiles = tiles
        self._rr = {}

    def _row(self, tile_id):
        return int(tile_id.split("_")[2])

    def _take(self, pool_key, candidates):
        """Round-robin a tile from candidates, capping 8 entries per tile."""
        if not candidates:
            return None
        idx = self._rr.get(pool_key, 0)
        for _ in range(len(candidates)):
            tile = candidates[idx % len(candidates)]
            idx += 1
            if self.per_tile.get(tile, 0) < 8:
                self._rr[pool_key] = idx
                return tile
        return None

    def add(self, internal, recipe_id, tile):
        if tile is None:
            return False
        b_id = self.by_internal.get(internal)
        if not b_id:
            return False
        if recipe_id != "" and self.recipes.get(recipe_id) != b_id:
            return False
        self.per_tile[tile] = self.per_tile.get(tile, 0) + 1
        self.entries.append({"building": b_id, "recipe": recipe_id, "tile": tile})
        return True

    def add_axis(self, axis, count, prefer_tiles=None):
        pool = AXIS_POOLS[axis]
        added = 0
        i = self._rr.get("axis_" + axis, 0)
        guard = 0
        while added < count and guard < count * 4:
            guard += 1
            internal, rid = pool[i % len(pool)]
            i += 1
            tile = self._take("industry", prefer_tiles if prefer_tiles else (self.urban or self.land))
            if self.add(internal, rid, tile):
                added += 1
        self._rr["axis_" + axis] = i
        return added

    def add_support(self, count):
        added = 0
        i = self._rr.get("support_kind", 0)
        for _ in range(count):
            kind = i % 3
            i += 1
            if kind == 0 and self.water_tiles:
                if self.add(*SUPPORT_WATER, self._take("support_w", self.water_tiles)):
                    added += 1
                    continue
            tile = self._take("support", self.urban or self.land)
            pick = SUPPORT_DESAL if kind == 1 else SUPPORT_POWER
            if self.add(*pick, tile):
                added += 1
        self._rr["support_kind"] = i
        return added

    def add_farms(self, count):
        added = 0
        i = self._rr.get("farm_recipe", 0)
        for _ in range(count):
            tile = self._take("farm", self.rural or self.rural_hill or self.land)
            if self.add(*FARM, tile):
                added += 1
                i += 1
        self._rr["farm_recipe"] = i
        return added

    def add_forests(self, count):
        eligible = [t for t in self.rural_hill if self._row(t) > OLD_GROWTH_MAX_ROW]
        added = 0
        for _ in range(count):
            tile = self._take("forest", eligible)
            if tile is not None and self.add(*FOREST, tile):
                added += 1
        # No eligible tile (northern regions: old-growth band) -> farms instead.
        if added < count:
            added += self.add_farms(count - added)
        return added

    def add_mines(self, cap):
        # Oil extraction (well/frack) counts as mining and is allowed wherever the
        # oil deposit is exploitable; petrochem REFINING stays theme-gated (it
        # comes from the petrochem axis pool, never from here).
        added = 0
        for tile, deposits in self.deposit_tiles:
            if added >= cap:
                break
            for dep in deposits:
                if added >= cap:
                    break
                if dep == "crude_oil":
                    if self.add("oil_well", "r_014", tile):
                        added += 1
                elif dep == "shale_oil":
                    if self.add("fracking_oil_well", "r_177", tile):
                        added += 1
                elif dep in MINE_RECIPE_BY_DEPOSIT:
                    if self.add("mine", MINE_RECIPE_BY_DEPOSIT[dep], tile):
                        added += 1
        return added


def build_region(key, region, tiles, recipes, by_internal, exploitable):
    rb = RegionBuilder(key, region, tiles, recipes, by_internal, exploitable)
    identity = region["identity"]
    h = fnv(key)

    if identity in ("dense_city", "sparse_city"):
        axes = DENSE_AXES.get(key, [SPARSE_AXES.get(key, "manufacturing")])
        if isinstance(axes, str):
            axes = [axes]
        is_capital = key == "capital_port"
        total_industry = 20 if is_capital else (9 if identity == "dense_city" else 3)
        support = 5 if is_capital else (2 if identity == "dense_city" else 1)
        agri = 0 if is_capital else (4 if identity == "dense_city" else 3)
        # Mines on exploitable in-region deposits replace industry slots (cap 2).
        mined = rb.add_mines(2)
        total_industry = max(0, total_industry - mined)
        if is_capital:
            rb.add(*FLAGSHIP, rb._take("industry", rb.urban))
            total_industry -= 1
        per_axis = max(1, total_industry // len(axes))
        for i, axis in enumerate(axes):
            want = per_axis if i < len(axes) - 1 else total_industry - per_axis * (len(axes) - 1)
            rb.add_axis(axis, want)
        rb.add_support(support)
        if agri > 0:
            farm_q = agri if rb.rural else 0
            if farm_q > 0:
                got = rb.add_farms(max(1, farm_q - 1))
                if farm_q - got > 0:
                    rb.add_forests(farm_q - got)
            else:
                rb.add_axis(axes[0], agri // 2)
                rb.add_support(agri - agri // 2)
        owner_axis = axes[0]
    elif identity == "dense_rural":
        rb.add_farms(10)
        rb.add_forests(10)
        rb.add_axis("manufacturing", 1, rb.rural_hill or rb.land)
        owner_axis = "agri"
    elif identity == "sparse_rural":
        rb.add_farms(4 + h % 4)
        rb.add_forests(3 + (h >> 8) % 4)
        rb.add_mines(2)
        if key == PETROCHEM_RURAL_EXCEPTION:
            # Shale-oil country: the one rural region allowed petrochem refining.
            rb.add_axis("petrochem", 1, rb.rural_hill or rb.land)
        owner_axis = "agri"
    else:  # mountain_range
        rb.add_mines(3)
        rb.add_forests(1)
        owner_axis = "mining"
    return rb, owner_axis


def owner_name(region, owner_axis):
    name = region["name"]
    if owner_axis == "agri":
        return "%s Agricultural Cooperative" % name
    if owner_axis == "mining":
        return "%s Mining Syndicate" % name
    return "%s %s" % (name, OWNER_SUFFIX.get(owner_axis, "Industries"))


def assign_phases(key, entries):
    """Stride entries across phases 1-5 from a per-region offset: consecutive
    same-type groups spread out, so every phase carries a mix of types."""
    offset = fnv(key) % 5
    for i, e in enumerate(entries):
        e["phase"] = (offset + i) % 5 + 1
    # Flagships are late-cycle prizes.
    for e in entries:
        if e["building"] == "b_010":
            e["phase"] = 5


def main():
    goods = load_goods()
    by_internal = load_buildings()
    recipes = load_recipes(goods, by_internal)
    tiles = load_tiles()
    exploitable, port_nearest = compute_exploitable(tiles)
    with open(REGIONS_PATH, encoding="utf-8") as f:
        regions = json.load(f)["regions"]

    out = {"version": 1, "generated_by": "scripts/build_start_buildings.py", "regions": {}}
    total = 0
    phase_counts = {}
    type_by_phase = {}
    for key in regions:
        rb, owner_axis = build_region(key, regions[key], tiles, recipes, by_internal, exploitable)
        assign_phases(key, rb.entries)
        out["regions"][key] = {
            "name": regions[key]["name"],
            "owner": owner_name(regions[key], owner_axis),
            "buildings": rb.entries,
        }
        total += len(rb.entries)
        for e in rb.entries:
            phase_counts[e["phase"]] = phase_counts.get(e["phase"], 0) + 1
            type_by_phase.setdefault(e["phase"], set()).add(e["building"])

    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("regions: %d  buildings: %d" % (len(out["regions"]), total))
    print("  port-nearest exploited tiles: %s" % ", ".join(sorted(port_nearest)))
    for p in sorted(phase_counts):
        print("  phase %d: %3d entries, %2d building types" % (p, phase_counts[p], len(type_by_phase[p])))


if __name__ == "__main__":
    main()
