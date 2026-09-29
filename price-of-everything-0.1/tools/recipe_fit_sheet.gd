extends Node
## A sheet comparing how recipes of every size are drawn in the construct panel's DS2 look: for each recipe, its
## catalogue tag condensed and expanded, and the build order's enamel sign, under a caption with its goods and
## the icon size the fit chose (build_order.fit_plan). Iron Furnace (two inputs, the largest icons) first.
##   RECIPE_FIT_OUT=<png> <godot> --path . res://tools/recipe_fit_sheet.tscn --quit-after 3000 -- --no-telemetry
## Renders in a SubViewport at two pixels a logical pixel (default out: /tmp/poe_recipe_fit_sheet.png).

const Catalogue := preload("res://scripts/construct_ds2/catalogue.gd")
const BuildOrder := preload("res://scripts/construct_ds2/build_order.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const RECIPES := ["r_005", "r_020", "r_029", "r_063", "r_205", "r_012", "r_107"]
const SIGN := Vector2(721.0, 216.0) / 1.875
const SIGN_ROOM := Vector2(721.0 / 1.875 - 20.0, 216.0 / 1.875 - 14.0)
const LOGICAL := Vector2i(1560, 1400)


func _ready() -> void:
	var out := OS.get_environment("RECIPE_FIT_OUT")
	if out == "":
		out = "/tmp/poe_recipe_fit_sheet.png"
	var vp := SubViewport.new()
	vp.size = LOGICAL * 2
	vp.size_2d_override = LOGICAL
	vp.size_2d_override_stretch = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var back := Control.new()
	back.size = Vector2(LOGICAL)
	back.theme = DS.theme
	back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back.draw.connect(func() -> void:
		var tex := Plate.tex("construct_hoarding")
		var x := 0.0
		while x < back.size.x:
			back.draw_texture_rect_region(tex, Rect2(x, 0, 600, back.size.y), Rect2(0, 0, 1200, minf(back.size.y * 2.0, tex.get_height())))
			x += 600.0)
	vp.add_child(back)
	var col := VBoxContainer.new()
	col.position = Vector2(20, 14)
	col.add_theme_constant_override("separation", 10)
	back.add_child(col)
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", 16)
	for spec: Array in [["Catalogue tag, condensed", 536.0], ["Catalogue tag, expanded", 536.0], ["Build order sign", SIGN.x]]:
		var h := Parts.caption(str(spec[0]), 18)
		h.custom_minimum_size.x = float(spec[1])
		heads.add_child(h)
	col.add_child(heads)
	for rid: String in RECIPES:
		var recipe := Catalog.get_recipe(rid)
		var bid := str(Catalog.get_building_by_internal_name(str(recipe.get("building_id", ""))).get("id", ""))
		if bid == "":
			for b: Dictionary in Catalog.all_buildings():
				for r: Dictionary in Catalog.all_recipes_for_building(str(b.id)):
					if str(r.recipe_id) == rid:
						bid = str(b.id)
		var flow := BuildOrder.recipe_flow(recipe)
		var n_in: int = (flow.inputs as Array).size()
		var n_out: int = (flow.outputs as Array).size()
		var power := int(flow.power_in)
		var tag_c: Dictionary = BuildOrder.fit_plan(n_in, n_out, BuildOrder.RecipeArrow.width_for(0), Catalogue.TAG_ROOM)
		var tag_e: Dictionary = BuildOrder.fit_plan(n_in, n_out, BuildOrder.RecipeArrow.width_for(power), Catalogue.TAG_ROOM)
		var sign: Dictionary = BuildOrder.fit_plan(n_in, n_out, BuildOrder.RecipeArrow.width_for(power), SIGN_ROOM)
		var caption := Parts.body("%s: %d in, %d out.   Tag %s / %s.   Sign %s." % [BuildOrder.BuildingNaming.name_for(bid, rid), n_in, n_out,
			_plan_words(tag_c), _plan_words(tag_e), _plan_words(sign)])
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(caption)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(_holder(Catalogue.recipe_tag(bid, recipe, true, func() -> void: pass), Catalogue.TAG))
		row.add_child(_holder(Catalogue.recipe_tag(bid, recipe, false, func() -> void: pass), Catalogue.TAG))
		var sign_box := BuildOrder.enamel_recipe(recipe, SIGN)
		var holder := _holder(sign_box, Vector2(SIGN.x, Catalogue.TAG.y))
		sign_box.position.y = (Catalogue.TAG.y - SIGN.y) * 0.5
		row.add_child(holder)
		col.add_child(row)
	for _i in 8:
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	vp.get_texture().get_image().save_png(out)
	print("[FIT_SHEET] %s" % out)
	get_tree().quit(0)


func _holder(c: Control, size: Vector2) -> Control:
	var h := Control.new()
	h.custom_minimum_size = size
	h.add_child(c)
	return h


func _plan_words(plan: Dictionary) -> String:
	var s := "%d px" % int(plan.icon)
	if int(plan.out_icon) != int(plan.icon):
		s += " (out %d)" % int(plan.out_icon)
	if bool(plan.grid_in) or bool(plan.grid_out):
		s += ", two rows"
	return s
