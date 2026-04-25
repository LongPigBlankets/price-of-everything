from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Ingredient:
    good: str
    qty: float


@dataclass(frozen=True)
class Good:
    id: str
    internal_name: str
    display_name: str
    category: str
    transport_class: str
    transport_cost: float
    transport_duration: float
    transport_method: str
    good_type: str
    decay_rate: float
    base_price: float
    is_buyable: bool
    is_sellable: bool
    green_sales_premium: float
    is_fossil_fuel: bool
    co2_tax_multiplier: float


@dataclass(frozen=True)
class Recipe:
    id: str
    display_name: str
    building_id: str
    inputs: tuple[Ingredient, ...]
    optional_input: str | None
    optional_production_multiplier: float | None
    energy_req: float
    outputs: tuple[Ingredient, ...]
