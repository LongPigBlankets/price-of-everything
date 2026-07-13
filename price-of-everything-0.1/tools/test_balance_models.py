#!/usr/bin/env python3
"""Focused regression checks for the offline balance models."""

from __future__ import annotations

import unittest

import balance_success_metrics as success
import manage_balance_v4_data as preset
import recipe_rebalance as model
import systemic_recipe_formula as systemic


class BalanceModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.goods, cls.buildings, _raw, cls.recipes = model.load()
        cls.recipe_by_id = {recipe["recipe_id"]: recipe for recipe in cls.recipes}
        cls.ranks = model.rank_map()
        cls.success = success.build_metrics()

    def test_stoichiometric_joint_output_ratios(self):
        self.assertEqual(
            systemic.output_ratio(self.recipe_by_id["r_012"]),
            [("chlorine", 1), ("sodium_hydroxide", 2), ("hydrogen", 1)],
        )
        self.assertEqual(
            systemic.output_ratio(self.recipe_by_id["r_079"]),
            [("hydrogen", 2), ("oxygen", 1)],
        )
        self.assertEqual(
            systemic.output_ratio(self.recipe_by_id["r_080"]),
            [("hydrogen", 2), ("oxygen", 1)],
        )

    def test_multi_output_recipes_enter_canonical_price_model(self):
        canonical = systemic.canonical_recipes(self.recipes, self.ranks)
        self.assertEqual(canonical["hydrogen"]["recipe_id"], "r_079")
        self.assertEqual(canonical["chlorine"]["recipe_id"], "r_012")
        self.assertEqual(canonical["sodium_hydroxide"]["recipe_id"], "r_012")

    def test_joint_cost_weights_are_output_quantity_times_price(self):
        outputs = [("hydrogen", 2.0), ("oxygen", 1.0)]
        prices = {"hydrogen": 3.0, "oxygen": 2.0}
        weights = systemic.output_value_weights(outputs, prices)
        self.assertAlmostEqual(weights["hydrogen"], 6.0 / 8.0)
        self.assertAlmostEqual(weights["oxygen"], 2.0 / 8.0)

    def test_power_scenarios_use_named_base_recipes_and_export_floor(self):
        rows, _fields = model.power_opportunity_scenarios(self.goods, self.buildings, self.recipes)
        by_name = {row["scenario"]: row for row in rows}
        self.assertEqual(by_name["grid purchase"]["short_run_opportunity_cost_per_power"], model.GRID)
        self.assertEqual(by_name["foregone grid sale"]["short_run_opportunity_cost_per_power"], model.GRID_SELL)
        self.assertEqual(by_name["coal power"]["source_recipe_id"], "r_004")
        self.assertEqual(by_name["oil power"]["source_recipe_id"], "r_181")
        self.assertEqual(by_name["oil power"]["fuel_inputs"], "processed_oil 6")
        for name in ("coal power", "oil power", "onshore wind + lithium battery"):
            self.assertGreaterEqual(by_name[name]["short_run_opportunity_cost_per_power"], model.GRID_SELL)

    def test_firmed_wind_includes_battery_housing_and_locked_cells(self):
        rows, _fields = model.power_opportunity_scenarios(self.goods, self.buildings, self.recipes)
        wind = next(row for row in rows if row["scenario"] == "onshore wind + lithium battery")
        self.assertEqual(wind["source_recipe_id"], "r_037")
        self.assertEqual(wind["battery_buildings"], 1)
        self.assertEqual(wind["lithium_cells_locked"], 5)
        self.assertGreater(wind["battery_housing_capital"], 0.0)
        self.assertGreater(wind["battery_cell_locked_capital"], 0.0)
        self.assertGreater(wind["long_run_opportunity_cost_per_power"], wind["short_run_opportunity_cost_per_power"])

    def test_imputed_cost_preserves_explicit_power_scenario(self):
        costs = model.imputed(self.goods, self.buildings, self.recipes, model.GRID_SELL)
        self.assertEqual(costs["power"], model.GRID_SELL)

    def test_flash_copper_keeps_approved_36_ingot_batch(self):
        recipe = self.recipe_by_id["r_020"]
        self.assertEqual(model.output_qty(recipe, "copper_ingots"), 36.0)
        canonical = systemic.canonical_recipes(self.recipes, self.ranks)
        floors = systemic.supply_quantity_floors(canonical)
        prices, _iterations = systemic.solve_prices(
            self.goods, self.buildings, self.recipes, self.ranks, canonical, floors
        )
        plan = systemic.plan_recipe(
            recipe,
            self.buildings[recipe["_building"]],
            self.goods,
            prices,
            self.ranks,
            canonical,
            floors,
        )
        self.assertEqual(plan["suggested_outputs"], "copper_ingots:36")
        self.assertEqual(plan["output_rounding"], "approved industrial batch")

    def test_lfp_keeps_approved_eight_by_eight_batch_and_profitable_policy(self):
        recipe = self.recipe_by_id["r_099"]
        self.assertEqual(dict(model.pairs(recipe, "input", "qty", 6))["lithium_carbonate"], 8.0)
        self.assertEqual(model.output_qty(recipe, "lithium_battery"), 8.0)
        target, low, high, policy, _rank = model.target(recipe, self.ranks)
        self.assertEqual((target, low, high), (45.0, 30.0, 60.0))
        self.assertIn("outperform conventional lithium-ion", policy)

        canonical = systemic.canonical_recipes(self.recipes, self.ranks)
        floors = systemic.supply_quantity_floors(canonical)
        prices, _iterations = systemic.solve_prices(
            self.goods, self.buildings, self.recipes, self.ranks, canonical, floors
        )
        plan = systemic.plan_recipe(
            recipe,
            self.buildings[recipe["_building"]],
            self.goods,
            prices,
            self.ranks,
            canonical,
            floors,
        )
        self.assertEqual(plan["suggested_outputs"], "lithium_battery:8")
        self.assertEqual(plan["output_rounding"], "approved industrial batch")

    def test_v4_approved_recipe_batches_are_deployed(self):
        expected_inputs = {
            "r_044": {"silica": 10.0, "coal": 20.0},
            "r_102": {"basic_salt": 4.0, "aluminium": 2.0, "graphite": 1.0},
            "r_136": {"iron_ingots": 6.0, "oxygen": 2.0, "steel": 4.0, "pure_water": 4.0},
        }
        expected_outputs = {
            "r_012": {"chlorine": 22.0, "sodium_hydroxide": 44.0, "hydrogen": 22.0},
            "r_020": {"copper_ingots": 36.0},
            "r_031": {"iron_ingots": 80.0},
            "r_032": {"lithium_battery": 6.0},
            "r_044": {"metallurgical_silicon": 20.0},
            "r_076": {"steel": 50.0},
            "r_078": {"hydrogen": 16.0, "graphite": 8.0},
            "r_079": {"hydrogen": 14.0, "oxygen": 7.0},
            "r_080": {"hydrogen": 22.0, "oxygen": 11.0},
            "r_081": {"polysilicon": 6.0},
            "r_082": {"alumina": 54.0},
            "r_099": {"lithium_battery": 8.0},
            "r_102": {"sodium_battery": 6.0},
            "r_116": {"industrial_acids": 36.0},
            "r_136": {"iron_battery": 6.0},
        }
        for recipe_id, expected in expected_inputs.items():
            self.assertEqual(dict(model.pairs(self.recipe_by_id[recipe_id], "input", "qty", 6)), expected)
        for recipe_id, expected in expected_outputs.items():
            self.assertEqual(dict(model.pairs(self.recipe_by_id[recipe_id], "output", "output_qty", 5)), expected)
        self.assertEqual(model.f(self.recipe_by_id["r_102"].get("energy_req")), 2.0)
        self.assertEqual(model.f(self.recipe_by_id["r_136"].get("energy_req")), 5.0)
        for recipe_id in ("r_102", "r_136"):
            recipe = self.recipe_by_id[recipe_id]
            self.assertEqual(
                tuple(model.i(recipe[column]) for column in (
                    "labour_unskilled_required", "labour_skilled_required", "labour_h_skilled_required"
                )),
                model.MIN_STAFF,
            )

    def test_v4_battery_installed_cell_capital_declines_by_chemistry(self):
        lithium = 18 * model.f(self.goods["lithium_battery"].get("base_price"))
        sodium = 24 * model.f(self.goods["sodium_battery"].get("base_price"))
        iron_air = 60 * model.f(self.goods["iron_battery"].get("base_price"))
        self.assertEqual((lithium, sodium, iron_air), (450.0, 360.0, 300.0))
        self.assertGreater(lithium, sodium)
        self.assertGreater(sodium, iron_air)

    def test_v4_runtime_data_manifest_is_fully_deployed(self):
        manifest = preset.load_manifest(preset.DEFAULT_MANIFEST)
        counts, details = preset.inspect(manifest)
        self.assertEqual(details, [])
        self.assertEqual(counts, {"deployed": 65, "reverted": 0, "conflict": 0})

    def test_live_extraction_startup_revenue_uses_per_good_penalties_and_rounding(self):
        expected = {
            "r_001": 16.800,
            "r_002": 16.436,
            "r_006": 16.250,
            "r_010": 19.000,
            "r_015": 19.550,
            "r_016": 22.704,
            "r_017": 15.200,
            "r_018": 16.800,
            "r_019": 16.650,
            "r_134": 16.354,
            "r_179": 19.240,
        }
        self.assertEqual(
            model.EXTRACTION_PENALTY_PCT,
            {
                "coal": -30.0,
                "iron_ore": -30.0,
                "copper_ore": -30.0,
                "limestone": -30.0,
                "sand": -30.0,
                "basic_salt": -30.0,
                "ree_ore": -30.0,
                "alloy_ore": -30.0,
                "sulphur": -15.0,
                "bauxite_ore": -15.0,
            },
        )
        for recipe_id, revenue in expected.items():
            self.assertAlmostEqual(
                model.extraction_startup_revenue(self.recipe_by_id[recipe_id], self.goods),
                revenue,
                places=3,
            )

    def test_steel_one_level_chain_beats_separate_buildings(self):
        steel = next(
            row for row in self.success["one_level"]
            if row["root_recipe_id"] == "r_003" and row["integrated_input"] == "iron_ingots"
        )
        self.assertEqual(steel["supplier_recipe_id"], "r_005")
        self.assertGreater(steel["integration_gain"], 0.0)

    def test_named_examples_and_threshold_counts_are_complete(self):
        self.assertEqual({row["recipe_id"] for row in self.success["examples"]}, set(success.NAMED_EXAMPLES.values()))
        for scenario in success.FULL_POWER_SCENARIOS:
            rows = [row for row in self.success["full"] if row["power_scenario"] == scenario]
            counts = [sum(row[f"over_{threshold}"] for row in rows) for threshold in success.THRESHOLDS]
            self.assertEqual(len(rows), 136)
            self.assertEqual(counts, sorted(counts, reverse=True))


if __name__ == "__main__":
    unittest.main()
