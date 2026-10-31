extends RefCounted
## The licence dialog (docs/pacing-labour-mining-licensing-spec.md §10.6), shared by both research views: licensing
## in a ready group member, with its price and its payback at the company's buildings, or licensing out an in-house
## process, with its price, what it does to the market and the patent window left.

const Licensing := preload("res://scripts/research_licensing.gd")


## What the dialog for `title` offers: "in", "out" or "" (nothing to do).
static func action_for(title: String) -> String:
	if ResearchState.is_licence_ready(title):
		return "in"
	if Licensing.license_out_refusal(title) == "":
		return "out"
	return ""


## The dialog's title, text, OK key and whether OK may be pressed, for `title` and `action`.
static func content(title: String, action: String) -> Dictionary:
	var lines: Array = []
	if action == "in":
		var group := ResearchState.licence_group_of(title)
		var terms := Licensing.terms_for(title)
		lines.append("%s licence group: %d of %d held." % [Licensing.group_name(group), Licensing.held_count(group),
			Licensing.members(group).size()])
		var gain := Licensing.estimate_return(title)
		if str(terms.kind) == "flat":
			var price := float(terms.price)
			lines.append("Costs %s once, about %s a turn over %d turns." % [Licensing._money(price),
				Licensing._money(roundf(price / float(EconomyConfig.LICENCE_ROYALTY_TURNS))), EconomyConfig.LICENCE_ROYALTY_TURNS])
		else:
			var revenue := float(Production.last_turn_summary.get("goods_sales_revenue", 0.0)) \
				+ float(Production.last_turn_summary.get("power_sales_revenue", 0.0))
			lines.append("Costs %s of company revenue a turn for %d turns, about %s a turn now, used or not." % [
				Licensing._pct(float(terms.rate)), int(terms.turns), Licensing._money(roundf(revenue * float(terms.rate)))])
		lines.append("Returns about %s a turn at your buildings." % Licensing._money(roundf(maxf(0.0, gain))) if gain > 0.5
			else "Returns nothing yet: none of your buildings uses it.")
		lines.append(str(ResearchState.get_unlock_def(title).get("description", "")))
		var why := Licensing.license_refusal(title)
		if why != "":
			lines.append(why + ".")
		return {"title": "License %s" % title, "text": "\n\n".join(lines), "ok": "License", "enabled": why == ""}
	if action == "out":
		var rate := Licensing.license_out_rate(title)
		lines.append("Sold once for %s: %s of your average revenue over the last %d turns." % [
			Licensing._money(Licensing.license_out_price(title)), Licensing._pct(rate), EconomyConfig.LICENCE_OUT_REVENUE_TURNS])
		if Licensing.goods_touched(title).is_empty():
			lines.append("It makes nothing sold at market, so selling it costs nothing there.")
		else:
			lines.append("Local firms then compete: the sale price of %s falls %d%% for %d turns." % [Licensing.goods_text(title),
				absi(int(EconomyConfig.LICENCE_OUT_PRICE_PCT)), EconomyConfig.LICENCE_OUT_PRICE_TURNS])
		lines.append("Patent window: %d turns left." % Licensing.patent_turns_left(title))
		return {"title": "License out %s" % title, "text": "\n\n".join(lines), "ok": "License out", "enabled": true}
	return {}


## Opens the dialog for `title` over `parent`, or does nothing when there is nothing to do. `done` is called after
## a licence is bought or sold.
static func open(parent: Node, title: String, done: Callable = Callable()) -> ConfirmationDialog:
	var action := action_for(title)
	if action == "" or parent == null:
		return null
	var c := content(title, action)
	var dialog := ConfirmationDialog.new()
	dialog.name = "LicenceDialog"
	dialog.title = str(c.title)
	dialog.dialog_text = str(c.text)
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(460, 0)
	dialog.ok_button_text = str(c.ok)
	dialog.get_ok_button().disabled = not bool(c.enabled)
	if DS.theme != null:
		dialog.theme = DS.theme
	dialog.confirmed.connect(func() -> void:
		var ok := Licensing.license(title) if action == "in" else Licensing.license_out(title)
		dialog.queue_free()
		if ok and done.is_valid():
			done.call())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	parent.add_child(dialog)
	dialog.popup_centered()
	return dialog
