## Auto-loaded node that handles global variables
extends Node


var test_data_dictionary = { }

const SAVE_FILE_LOCATION := "user://2DVisualNovelDemo.save"

func add_variable(_name: String, value) -> void:
	var save_file := FileAccess.open(SAVE_FILE_LOCATION, FileAccess.READ_WRITE)

	var json = JSON.new()
	var error = json.parse(save_file.get_as_text())

	var data: Dictionary = (
		json.data
		if error == OK
		else { variables = { } }
	)

	if _name != "":
		if not data.has("variables"):
			data["variables"] = { }

		data["variables"][_name] = _evaluate(value)

	save_file.store_line(JSON.stringify(data))
	save_file.close()
	return


func get_stored_variables_list() -> Dictionary:
	# Stop if the save file doesn't exist
	if not FileAccess.file_exists(SAVE_FILE_LOCATION):
		return { }

	var save_file = FileAccess.open(SAVE_FILE_LOCATION, FileAccess.READ)
	var save_file_string = save_file.get_as_text()
	var test_json_conv = JSON.new()
	var parse_error = test_json_conv.parse(save_file_string)
	if parse_error != OK:
		print("JSON Parse Error: ", test_json_conv.get_error_message(), " at line ", test_json_conv.get_error_line())
		return { }

	var data: Dictionary = test_json_conv.data

	save_file.close()

	return data


# Used to evaluate the variables' values
func _evaluate(input):
	var script = GDScript.new()
	script.set_source_code("func eval():\n\treturn " + input)
	script.reload()
	var obj = RefCounted.new()
	obj.set_script(script)
	return obj.eval()

func add_marked_textures(key: int, value: Dictionary):
	test_data_dictionary[key] = value
