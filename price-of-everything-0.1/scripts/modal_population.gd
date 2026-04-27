extends Control

# --- UI References ---
@onready var bottom_menu = $BottomMenu
@onready var generic_modal = $GenericModal
@onready var title_label: Label = $GenericModal/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $GenericModal/ModalLayout/HeaderRow/CloseButton
@onready var item_list: VBoxContainer = $GenericModal/ModalLayout/ScrollContainer/ItemList

# --- Data Storage ---
var buildings_data: Array = []

func _ready():
	# 1. Connect the Close button
	close_button.pressed.connect(_on_close_modal)
	
	# 2. Connect the 6 bottom menu buttons
	$BottomMenu/ConstructButton.pressed.connect(_on_construct_pressed)
	$BottomMenu/ResourcesButton.pressed.connect(func(): _open_dummy_modal("Resources"))
	$BottomMenu/BuildingsButton.pressed.connect(func(): _open_dummy_modal("Buildings"))
	$BottomMenu/MarketButton.pressed.connect(func(): _open_dummy_modal("Market"))
	$BottomMenu/PoliticsButton.pressed.connect(func(): _open_dummy_modal("Politics"))
	$BottomMenu/TechButton.pressed.connect(func(): _open_dummy_modal("Tech"))
	
	# 3. Load the CSV data into memory at startup
	_load_buildings_csv()

# --- CSV Parsing ---
func _load_buildings_csv():
	var file_path = "res://data/Buildings - buildingsMVP.csv"
	if not FileAccess.file_exists(file_path):
		push_error("Could not find buildings CSV at " + file_path)
		return
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	var _headers = file.get_csv_line() # The underscore mutes the warning
	
	while not file.eof_reached():
		var line = file.get_csv_line()
		
		# Ensure the line isn't empty (prevents trailing blank line errors)
		if line.size() > 6 and line[0] != "":
			buildings_data.append({
				"id": line[0],
				"name": line[2], # display_name
				"cost": line[6]  # build_cost_money
			})
	file.close()

# --- Button Logic ---
func _on_construct_pressed():
	# Show modal and set title
	title_label.text = "Construct Building"
	generic_modal.show()
	
	# Clear old items to prevent duplicates if clicked twice
	for child in item_list.get_children():
		child.queue_free()
		
	# Populate the VBoxContainer with our CSV data
	for building in buildings_data:
		var btn = Button.new()
		# Format the text to show the name and cost
		btn.text = "%s ($%s)" % [building["name"], building["cost"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		# Optional: Connect this newly created button to a function
		btn.pressed.connect(func(): print("Selected to build: ", building["name"]))
		
		item_list.add_child(btn)

func _open_dummy_modal(modal_name: String):
	title_label.text = modal_name
	generic_modal.show()
	
	# Clear old items since this is a dummy modal
	for child in item_list.get_children():
		child.queue_free()
		
	var lbl = Label.new()
	lbl.text = "Content for " + modal_name + " goes here."
	item_list.add_child(lbl)

func _on_close_modal():
	generic_modal.hide()
