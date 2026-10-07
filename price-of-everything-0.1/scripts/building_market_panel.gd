extends RefCounted
## The buildings for sale: every building another company owns, no infrastructure, as a row model each, and
## the purchase. The market's Buildings tab (scripts/market_ds2/lots_tab.gd) lists and buys them through here.

const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")  # per-building deterministic sale price


## Every building for sale (other companies', no infrastructure), on `tile_filter` when given, sorted by owner
## then name: a row model each.
static func lots(tile_filter: String = "") -> Array:
	var out: Array = []
	for instance_id in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[instance_id]
		if tile_filter != "" and str(b.get("tile_id", "")) != tile_filter:
			continue
		if BuildingState.is_player_owned(b):
			continue
		if _is_infrastructure(b):
			continue  # ports / airports etc. aren't productive buildings for sale
		out.append(_row_vm(b))
	# Group by owner, then by building name — a stable, readable order for one long list.
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var c := String(x.owner).naturalnocasecmp_to(String(y.owner))
		if c == 0:
			c = String(x.name).naturalnocasecmp_to(String(y.name))
		return c < 0)
	return out

static func _row_vm(b: Dictionary) -> Dictionary:
	var instance_id := str(b.get("instance_id", ""))
	var building_id := str(b.get("building_id", ""))
	var tile_id := str(b.get("tile_id", ""))
	var recipe_id := str(b.get("recipe_id", ""))
	var owner := str(b.get("owner", ""))
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var bdata: Dictionary = Catalog.get_building(building_id)

	var name_str := BuildingNaming.label_for_tile(tile_id, instance_id, building_id, recipe_id)
	var tile_name := Catalog.tile_name(tile_id)
	var tile_text := tile_name if tile_name != "" else _short_tile(tile_id)

	# Output good + its base recipe quantity. NPC buildings are inert, so the raw recipe
	# qty is the honest, owner-agnostic value (no player modifiers/levels applied). Power
	# isn't a tradeable good, so it shows no Output icon.
	var out_gid := BuildingStatus.primary_output_good_id(recipe)
	var out_internal := BuildingStatus.primary_output_internal(recipe)
	var out_qty := BuildingStatus.primary_output_qty(recipe)
	var out_name := BuildingStatus.primary_output_display_name(recipe)
	if out_internal == "power":
		out_gid = ""
		out_qty = 0

	# Search haystack: name, output good, recipe, tile id + name, owner.
	var blob := (name_str + " " + out_name + " " + str(recipe.get("display_name", "")) \
		+ " " + tile_id + " " + tile_name + " " + owner).to_lower()

	# Price is computed once here so the £ on the button is exactly what gets charged on buy,
	# even if the market ticks while the panel is open.
	return {
		"instance_id": instance_id,
		"building_id": building_id, "binternal": str(bdata.get("internal_name", "")),
		"name": name_str, "tile": tile_text, "tile_id": tile_id, "owner": owner,
		"out_good_id": out_gid, "out_internal": out_internal, "out_qty": out_qty,
		"price": MatchState.building_purchase_price(b),
		# Filter fields.
		"category": str(bdata.get("category", "production")),
		"level": int(b.get("level", 1)),
		"powered": int(recipe.get("energy_req", 0)) > 0,          # consumes power
		"unconnected": not Power.is_supplied(tile_id),            # tile has no power cables
		"near_port": BuildingPrice.is_near_port(tile_id),
		"blob": blob,
	}

static func _is_infrastructure(b: Dictionary) -> bool:
	var bdata: Dictionary = Catalog.get_building(str(b.get("building_id", "")))
	return str(bdata.get("category", "production")) == "infrastructure"

## Buys a lot at `price` (the figure its key showed): the charge, the transfer and the toast. False when it is
## gone or can't be paid for.
static func buy_lot(instance_id: String, building_name: String, price: int) -> bool:
	if instance_id == "" or not BuildingState.buildings.has(instance_id):
		return false
	# Pay for it. deduct_money is atomic — false means the player can't afford it, so reuse the
	# same insufficient-money toast as building (now on the left), with buy-specific text.
	if not MatchState.deduct_money(float(price)):
		MatchState.build_rejected_no_funds.emit("Not enough money to buy %s — need £%d, you have £%.0f" % [
			building_name, price, MatchState.money])
		return false
	# Ownership transfer is immediate; production picks it up next turn. building_owner_changed
	# drives the ledger refresh and drops the lot from the for-sale list.
	BuildingState.set_building_owner(instance_id, MatchState.LOCAL_PLAYER)
	MatchState.request_toast("Purchased %s for £%d" % [building_name, price], "success")
	Audio.transaction()
	return true

static func _short_tile(tile_id: String) -> String:
	return tile_id.trim_prefix("tile_") if tile_id.begins_with("tile_") else tile_id
