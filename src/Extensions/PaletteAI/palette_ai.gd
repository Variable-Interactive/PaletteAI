extends ConfirmationDialog

const GENERATE_PALETTE_ICON := preload("res://assets/generate_palette.png")
const Matrix = preload("res://addons/NeuralNetwork/Classes/Matrix.gd")
const Network = preload("res://addons/NeuralNetwork/Classes/Network.gd")

# some references to nodes that will be created later
var net
var api: Node
var row_column_value_slider: TextureProgressBar
var rows: int = 8
var columns: int = 8
var generated_palette: Dictionary
var colors :PackedColorArray

var palette_panel: Control
var palette_ai_button: Button

@onready var palette_colors_preview: TextureRect = %PaletteColorsPreview
@onready var row_column_option: OptionButton = %RowColumn
@onready var palette_name: LineEdit = %PaletteName


# This script acts as a setup for the extension
func _enter_tree() -> void:
	api = get_node_or_null("/root/ExtensionsApi")
	palette_panel = get_tree().current_scene.find_child("Palettes")
	palette_ai_button = Button.new()
	palette_ai_button.name = "PaletteAI"
	palette_ai_button.custom_minimum_size = Vector2(22, 22)
	palette_ai_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	palette_ai_button.tooltip_text = "Download and import a palette from Lospec"
	palette_ai_button.pressed.connect(func(): popup_centered())
	var texture_rect := TextureRect.new()
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	texture_rect.anchor_left = 0
	texture_rect.anchor_top = 0
	texture_rect.anchor_right = 1
	texture_rect.anchor_bottom = 1
	texture_rect.texture = GENERATE_PALETTE_ICON
	palette_ai_button.add_child(texture_rect)
	palette_panel.find_child("PaletteButtons").add_child(palette_ai_button)

	row_column_value_slider = api.general.create_value_slider()
	%PaletteOption.add_child(row_column_value_slider)
	row_column_value_slider.value_changed.connect(_on_row_column_value_value_changed)
	row_column_value_slider.min_value = 1
	row_column_value_slider.value = 10  # an appropriate value (to make things look nicer)
	row_column_value_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _on_about_to_popup() -> void:
	var tools_autoload = get_node_or_null("/root/Tools")
	%Left.color = tools_autoload.get_assigned_color(1)
	%Right.color = tools_autoload.get_assigned_color(2)
	generate_palette(%Left.color, %Right.color)


func _on_confirmed() -> void:
	if palette_name.text == "":
		palette_name.text = "untitled"
	api.palette.create_palette_from_data(palette_name.text, generated_palette)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if FileAccess.file_exists("user://PaletteAI/Ai.tscn"):
		net = ResourceLoader.load("user://PaletteAI/Ai.tscn")
	else:
		net = Network.new([6, 16, 16, 3])


func get_training_data() -> Array[Array]:
	var data: Array[Array] = []
	var palette = get_node_or_null("/root/Palettes").current_palette
	var keys: Array = palette.colors.keys()
	keys.sort()
	for i: int in keys.size():
		if i + 2 < keys.size():
			var first_color: Color = palette.colors[keys[i]].color
			var second_color: Color = palette.colors[keys[i] + 1].color
			var input_matrix = Matrix.new(6, 1)
			input_matrix.set_index(0, 0, first_color.r)
			input_matrix.set_index(1, 0, first_color.g)
			input_matrix.set_index(2, 0, first_color.b)
			input_matrix.set_index(3, 0, second_color.r)
			input_matrix.set_index(4, 0, second_color.g)
			input_matrix.set_index(5, 0, second_color.b)

			var expected_color: Color = palette.colors[keys[i] + 2].color
			var expected_matrix = Matrix.new(3, 1)
			expected_matrix.set_index(0, 0, expected_color.r)
			expected_matrix.set_index(1, 0, expected_color.g)
			expected_matrix.set_index(2, 0, expected_color.b)
			data.append([input_matrix, expected_matrix])
	data.shuffle()
	return data


func generate_palette(
	color_a: Color,
	color_b: Color,
	width: int = 8,
	height: int = 8,
	new_colors: int = 100
) -> void:
	var palette_colors := PackedColorArray()
	var serialize_data := {"comment": "Ai palette", "colors": [], "width": width, "height": height}
	serialize_data.colors.push_back({"color": color_a, "index": 0})
	serialize_data.colors.push_back({"color": color_b, "index": 1})
	palette_colors.append_array([color_a, color_b])
	var current_color := color_b
	var input: Array[float] = [color_a.r, color_a.g, color_a.b, color_b.r, color_b.g, color_b.b]
	for i in new_colors:
		var next_color: PackedFloat32Array = net.feedforward(input).to_array()
		for _a in 3:
			input.pop_front()
		input.append_array(next_color)
		var color = Color(next_color[0], next_color[1], next_color[2])
		if current_color.is_equal_approx(color):
			break
		if !color in palette_colors:
			palette_colors.append(color)
			current_color = color
			serialize_data.colors.push_back({"color": color, "index": i + 2})
	generated_palette = serialize_data
	colors = palette_colors
	update_preview()


func train_on_current_palette():
	var data = get_training_data()
	data.shuffle()
	net.SGD(data, 100, 5, 10)


func _on_row_column_item_selected(_index: int) -> void:
	update_preview()


func _on_row_column_value_value_changed(_value: float) -> void:
	update_preview()


func update_preview() -> void:
	if colors.is_empty():
		return
	var colors_size := colors.size()
	var image_preview: Image
	row_column_value_slider.max_value = colors_size
	var i := 0
	match row_column_option.selected:
		0:  # Rows
			rows = row_column_value_slider.value
			columns = ceili(float(colors_size) / rows)
			image_preview = Image.create(columns, rows, false, Image.FORMAT_RGBA8)
			for x in image_preview.get_width():
				for y in image_preview.get_height():
					if i >= colors_size:
						break
					image_preview.set_pixel(x, y, colors[i])
					i += 1
		1:  # Columns
			columns = row_column_value_slider.value
			rows = ceili(float(colors_size) / columns)
			image_preview = Image.create(columns, rows, false, Image.FORMAT_RGBA8)
			for y in image_preview.get_height():
				for x in image_preview.get_width():
					if i >= colors_size:
						break
					image_preview.set_pixel(x, y, colors[i])
					i += 1
	palette_colors_preview.texture = ImageTexture.create_from_image(image_preview)


func _exit_tree() -> void:  # Extension is being uninstalled or disabled
	# remember to remove things that you added using this extension
	DirAccess.make_dir_recursive_absolute("user://PaletteAI")


func _on_left_color_changed(color: Color) -> void:
	generate_palette(%Left.color, %Right.color)


func _on_right_color_changed(color: Color) -> void:
	generate_palette(%Left.color, %Right.color)


func _on_train_pressed() -> void:
	$VBoxContainer/Train.text = "Training Started: This will take a few minutes"
	$VBoxContainer/Train.disabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	train_on_current_palette()
	generate_palette(%Left.color, %Right.color)
	$VBoxContainer/Train.disabled = false
	$VBoxContainer/Train.text = "Train on Pixelorama's current palette"
