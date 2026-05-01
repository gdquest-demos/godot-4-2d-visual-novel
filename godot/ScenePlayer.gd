## Loads and plays a scene's dialogue sequences, delegating to other nodes to display images or text.
class_name ScenePlayer
extends Node

signal scene_finished
signal restart_requested
signal transition_finished

const KEY_END_OF_SCENE := -1
const KEY_RESTART_SCENE := -2

## Maps transition keys to a corresponding function to call.
const TRANSITIONS := {
	fade_in = "_appear_async",
	fade_out = "_disappear_async",
}

var _scene_data := {}

@onready var _text_box := $TextBox
@onready var _character_displayer := $CharacterDisplayer
@onready var _anim_player: AnimationPlayer = $FadeAnimationPlayer
@onready var _background := $Background
@onready var _bgm := $BGM


func run_scene() -> void:
	var key = 0
	while key != KEY_END_OF_SCENE:
		var node: SceneTranspiler.BaseNode = _scene_data[key]
		var character: Character = (
			ResourceDB.get_character(node.character)
			if "character" in node and node.character != ""
			else ResourceDB.get_narrator()
		)

		if node is SceneTranspiler.MarkCommandNode:
			var BG = _background.texture
			var left = _character_displayer._left_sprite.texture
			var right = _character_displayer._right_sprite.texture
			var container = {
				"BG" : BG,
				"L" : left,
				"R" : right
			}
			Variables.add_marked_textures(key, container)

		if node is SceneTranspiler.BackgroundCommandNode:
			var bg: Background = ResourceDB.get_background(node.background)
			_background.texture = bg.texture

		if node is SceneTranspiler.SongCommandNode:
			var bgm: Song = ResourceDB.get_song(node.song)
			_bgm.stream = bgm.song
			_bgm.play()
		
		if node is SceneTranspiler.ShowCommandNode:
			var side: String = node.side
			var animation: String = node.animation
			var expression: String = node.expression
			_character_displayer.display(character, expression, side, animation)
			##Make await conditional based on if we want to wait for the next node
			if _scene_data[node.next] is SceneTranspiler.ShowCommandNode:
				key = node.next
				continue
			else:
				await _character_displayer.display_finished

		# Changes a character's expression and readies their line for display
		if "line" in node && "character" in node && node.character != "":
			var expression: String = node.expression
			_character_displayer.display(character, expression)

		if "line" in node and node.line == "":
			key = node.next
			continue
			

		# Normal text reply.
		if "line" in node && node.line != "":
			if !_text_box.visible:
				_text_box.show()
			_text_box.display(node.line, character.display_name)
			await _text_box.next_requested
			key = node.next

		# Transition animation.
		elif "transition" in node:
			if node.transition != "":
				call(TRANSITIONS[node.transition])
				await self.transition_finished
			else:
				##TODO: if the next node doesn't have a line in it, do not display the text box.
				#call("default")
				default()
				await transition_finished
			key = node.next

		# Manage variables
		elif node is SceneTranspiler.SetCommandNode:
			Variables.add_variable(node.symbol, node.value)
			key = node.next

		# Change to another scene
		elif node is SceneTranspiler.SceneCommandNode:
			if node.scene_path == "next_scene":
				key = KEY_END_OF_SCENE
			else:
				key = node.next

		# Choices.
		elif node is SceneTranspiler.ChoiceTreeNode:
			# Temporary fix for the buttons not showing when there are consecutive choice nodes
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame

			_text_box.display_choice(node.choices)

			key = await _text_box.choice_made

			if key == KEY_RESTART_SCENE:
				restart_requested.emit()
				return
		elif node is SceneTranspiler.ConditionalTreeNode:
			var variables_list: Dictionary = Variables.get_stored_variables_list()

			# Evaluate the if's condition
			if (
				variables_list["variables"].has(node.if_block.condition.value)
				and variables_list["variables"][node.if_block.condition.value]
			):
				key = node.if_block.next
			else:
				# Have to use this flag because we can't `continue` out of the
				# elif loop
				var elif_condition_fulfilled := false

				# Evaluate the elif's conditions
				for block in node.elif_blocks:
					if (
						variables_list["variables"].has(block.condition.value)
						and variables_list["variables"][block.condition.value]
					):
						key = block.next
						elif_condition_fulfilled = true
						break

				if not elif_condition_fulfilled:
					if node.else_block:
						# Go to else
						key = node.else_block.next
					else:
						# Move on
						key = node.next

		# Ensures we don't get stuck in an infinite loop if there's no line to display.
		else:
			##If the next key is in the stored texture reload dictionary, immediately set all that and clear the dialogue box.
			if node.next in Variables.test_data_dictionary.keys():
				await _text_box.fade_out_async()
				#TODO: perform fade outs for the background and characters as well.
				load_textures_from_mark(node.next)
				_text_box.clear()
				_text_box.hide()
			key = node.next

	_character_displayer.hide()
	scene_finished.emit()

func load_textures_from_mark(key:int):
	_background.texture = Variables.test_data_dictionary[key]["BG"]
	_character_displayer._left_sprite.texture = Variables.test_data_dictionary[key]["L"]
	_character_displayer._right_sprite.texture = Variables.test_data_dictionary[key]["R"]


func load_scene(dialogue: SceneTranspiler.DialogueTree) -> void:
	# The main script
	_scene_data = dialogue.nodes


func _appear_async() -> void:
	_anim_player.play("fade_in")
	await _anim_player.animation_finished
	#await _text_box.fade_in_async().completed
	await _text_box.fade_in_async()
	transition_finished.emit()

func default() -> void:
	_anim_player.play("default")
	await _anim_player.animation_finished
	await _text_box.fade_in_async()
	transition_finished.emit()

func _disappear_async() -> void:
	#await _text_box.fade_out_async().completed
	await _text_box.fade_out_async()
	_anim_player.play("fade_out")
	await _anim_player.animation_finished
	transition_finished.emit()


## Saves a dictionary representing a scene to the disk using `var2str`.
func _store_scene_data(_data: Dictionary, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(var_to_str(_scene_data))
	file.close()
