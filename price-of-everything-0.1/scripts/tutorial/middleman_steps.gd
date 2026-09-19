extends RefCounted
## A short introduction using the real Pepper Valley business; no gifts or resets.
static func steps() -> Array:
	return [
		{"id":"middleman_welcome","chapter":"Pepper Valley Motors","title":"Your inland motor business",
		"body":"Your powered factory buys steel and copper wiring, makes motors and sells them through the middleman. Each factory trades independently. The truck on the gold hex represents the middleman.",
		"setup":[{"action":"focus_building_on_tile","tile":"tile_5_4","building_id":"b_007"}],"spotlight":{"kind":"none","ref":""},"done":{"decide":{}},"advance":"next"},
		{"id":"middleman_funding","chapter":"One operating cycle","title":"Fund inputs before sales",
		"body":"Open Logistics costs & funding to review the cash and fee estimates. Input purchases and factory running costs need cash upfront, or an available loan. The middleman fee includes transport and operating storage. Sales are paid after production and cannot fund that same batch.",
		"setup":[],"spotlight":{"kind":"node_name","ref":"MiddlemanServiceCard"},"done":{"decide":{}},"advance":"next"},
		{"id":"middleman_run","chapter":"One operating cycle","title":"Run your first turn",
		"body":"End the turn to buy inputs, produce motors and receive the sale proceeds. Grid power, labour and maintenance remain factory costs. If production fails after purchase, paid inputs remain private to this factory for its next attempt.",
		"setup":[],"spotlight":{"kind":"node_name","ref":"EndTurnButton"},"no_dim":true,"done":{"decide":{"kind":"turn_advanced"}},"advance":"auto"},
		{"id":"middleman_accounts","chapter":"Read the result","title":"Check the money that moved",
		"body":"Open Money to compare material purchases, motor sales, factory costs and the single Middleman fee. A loan is financing, not profit. Current market prices can change next turn's margin.",
		"setup":[],"spotlight":{"kind":"none","ref":""},"done":{"decide":{}},"advance":"next"},
		{"id":"middleman_done","chapter":"Expand when funded","title":"A second factory is a second business",
		"body":"Build another motor factory in Pepper Valley when you can afford construction and its operating cash. Construction materials use normal delivery; after completion the new factory uses the middleman. Its inputs and sales remain independent. Later, compare direct trading when scale and infrastructure make it worthwhile.",
		"setup":[],"spotlight":{"kind":"none","ref":""},"done":{"decide":{}},"advance":"next"},
	]
