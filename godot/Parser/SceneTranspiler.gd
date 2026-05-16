## Receives a `SceneParser.SyntaxTree` and produces a `DialogueTree`, an object
## representing a scene, which a `ScenePlayer` instance can read.
##
## Use the `transpile()` method to get a `DialogueTree`.
class_name SceneTranspiler
extends RefCounted

# We assign a number to every step in a generated `DialogueTree`.
# We use the numbers below to offset the index number of choices and conditional
# blocks. This helps us to group them in the `DialogueTree.nodes` dictionary.
const UNIQUE_CHOICE_ID_MODIFIER = 1000000000
const UNIQUE_CONDITIONAL_ID_MODIFIER = 2100000000

const ERROR_NONEXISTENT_JUMP_POINT := -3

# A mapping of named jump points to a corresponding node in the tree.
var _jump_points := {}
# Store jump nodes with unknown jump points
var _unresolved_jump_nodes := []


## A tree of nodes representing a scene. It stores nodes in its `nodes` dictionary.
## See the node types below.
class DialogueTree:
	var nodes := {}
	var index := 0

	## Add a new node to the tree and assign it a unique index in the tree
	func append_node(node: BaseNode) -> void:
		nodes[index] = node
		index += 1


## Base type for all other node types below.
class BaseNode:
	var next: int

	func _init(_next: int) -> void:
		self.next = _next


## Node with a line of text optional parameters.
class DialogueNode:
	extends BaseNode

	var line: String
	var character: String
	var expression: String
	var animation: String
	var side: String

	func _init(_next: int, _line: String) -> void:
		super(next)
		self.next = _next
		self.line = _line


## Node type for a command that changes the displayed background, with an
## optional transition animation.
class BackgroundCommandNode:
	extends BaseNode

	var background: String
	var transition: String

	func _init(_next: int, _background: String) -> void:
		super(_next)
		self.background = _background
	
	func _to_string() -> String:
		return "{next: %s, bg: %s, tr: %s}" % [next, background, transition]

class SongCommandNode:
	extends BaseNode
	
	var song: String
	
	func _init(_next: int, _song: String) -> void:
		super(_next)
		song = _song

## Node type for a command that makes the game jump to another scene (or restart
## the current one).
class SceneCommandNode:
	extends BaseNode

	var scene_path: String

	func _init(_next: int, _scene_path: String) -> void:
		super(_next)
		self.scene_path = _scene_path

class ShowCommandNode:
	extends BaseNode
	
	var character: String
	var expression: String
	var animation: String
	var side: String

	func _init(_next: int, _character: String, _expression:String) -> void:
		super(_next)
		character = _character
		expression = _expression

## Node type for a command that runs a scene transition animation, like a fade
## to black.
class TransitionCommandNode:
	extends BaseNode

	var transition: String

	func _init(_next: int, _transition: String) -> void:
		super(_next)
		self.transition = _transition


## Node type representing a player choice.
class ChoiceTreeNode:
	extends BaseNode

	var choices: Array

	func _init(_next: int, _choices: Array) -> void:
		super(_next)
		self.next = _next
		self.choices = _choices


## Represents one conditional block, starting with an `if`, `elif`, or `else`
## keyword.
class ConditionalBlockNode:
	extends BaseNode

	var condition: SceneParser.BaseExpression

	func _init(_next: int, _condition: SceneParser.BaseExpression) -> void:
		super(_next)
		self.condition = _condition


## Node type representing a tree of if, elifs, and else blocks in the script.
class ConditionalTreeNode:
	extends BaseNode

	var if_block: ConditionalBlockNode
	# There can be multiple `elif` blocks in a row, which is why we store them
	# in an array.
	var elif_blocks: Array
	var else_block: ConditionalBlockNode

	func _init(_next: int, _if_block: ConditionalBlockNode) -> void:
		super(_next)
		self.if_block = _if_block


## Represents a command that creates or modify a persistent variable. These
## variables are saved in the player's save file.
class SetCommandNode:
	extends BaseNode

	var symbol: String
	var value

	func _init(_next: int, _symbol: String, _value) -> void:
		super(_next)
		self.symbol = _symbol
		self.value = _value


## Node type for a command that will advance to any existing jump point.
class JumpCommandNode:
	extends BaseNode

	var jump_point: String

	func _init(_next: int) -> void:
		super(_next)

class MarkCommandNode:
	extends BaseNode
	
	func _init(_next: int) -> void:
		super(_next)


## Node type for a command that will break out of any running code block.
class PassCommandNode:
	extends BaseNode

	func _init(_next: int) -> void:
		super(_next)


## Takes in a syntax tree from the SceneParser and turns it into a
## `DialogueTree` for the `ScenePlayer` to play.
func transpile(syntax_tree: SceneParser.SyntaxTree, start_index: int) -> DialogueTree:
	var dialogue_tree := DialogueTree.new()
	dialogue_tree.index = start_index

	while not syntax_tree.is_at_end():
		var expression: SceneParser.BaseExpression = syntax_tree.move_to_next_expression()

		if expression.type == SceneParser.EXPRESSION_TYPES.COMMAND:
			var node := _transpile_command(dialogue_tree, expression)
			# There's currently no proper error handling for commands, we skip invalid ones.
			if node == null:
				continue
			dialogue_tree.append_node(node)


		elif expression.type == SceneParser.EXPRESSION_TYPES.DIALOGUE:
			# A dialogue node only needs the dialogue text, anything else is optional
			var node := _transpile_dialogue(dialogue_tree, expression)
			dialogue_tree.append_node(node)

		elif expression.type == SceneParser.EXPRESSION_TYPES.CHOICE:
			var choices := []

			# Stores the position for the choice tree node which has pointers to the actual choice
			# blocks that are stored at a unique place
			var original_value: int = dialogue_tree.index

			# Store the choice nodes at a normally unreacheable place in the dialogue tree
			dialogue_tree.index += UNIQUE_CHOICE_ID_MODIFIER
			for block in expression.value:
				var subtree := SceneParser.SyntaxTree.new()
				subtree.values = block.value

				dialogue_tree.index += 1

				# Any jump points, variables that get declared in the block's tree don't need to be
				# handled since the jump_points, variables are constants that are shared between all
				# DialogueTree instances
				# We pass in the current index tree's index here so the subtree can transpile
				# properly
				var block_dialogue_tree: DialogueTree = transpile(subtree, dialogue_tree.index)

				# Add the pointer to this code block in the choice tree
				choices.append({label = block.label, target = dialogue_tree.index})

				# Add the block's tree's nodes to the main dialogue tree
				_copy_nodes(original_value, block_dialogue_tree.nodes.keys(), dialogue_tree, block_dialogue_tree)

			# Reset the index
			dialogue_tree.index = original_value
			dialogue_tree.append_node(ChoiceTreeNode.new(dialogue_tree.index + 1, choices))

		# Parsing sequences of conditional blocks (if, elif, else)
		elif expression.type == SceneParser.EXPRESSION_TYPES.CONDITIONAL_TREE:
			# TODO: If the conditional is incorrect, it's the parser that should error out.
			if expression.if_block == null:
				push_error("Invalid conditional tree")
				continue

			# We parse conditional trees by calling the `transpile()` method recursively.
			# This is because conditional trees can contain about anything.
			#
			# We first store the index of the conditional tree.
			var original_value := dialogue_tree.index

			# We then offset the conditional nodes at a normally unreacheable
			# place in the dialogue tree, apart from the choice nodes
			dialogue_tree.index += UNIQUE_CONDITIONAL_ID_MODIFIER + 1

			# The conditional tree only needs a pointer to the `if` block to be
			# proper, elifs and else are optional
			var tree_node = ConditionalTreeNode.new(
				original_value + 1,
				ConditionalBlockNode.new(
					# The pointer to the if block's index in the dialogue tree
					dialogue_tree.index,
					# The if's condition
					expression.if_block.value.front()
					)
				)

			# Transpile the if block
			var if_subtree := SceneParser.SyntaxTree.new()
			if_subtree.values = expression.if_block.block
			var if_block_dialogue_tree: DialogueTree = transpile(if_subtree, dialogue_tree.index)

			# Add the if block's tree's nodes to the main dialogue tree
			_copy_nodes(original_value, if_block_dialogue_tree.nodes.keys(), dialogue_tree, if_block_dialogue_tree)

			# Transpile the elif blocks
			if not expression.elif_block.is_empty():
				var elif_blocks := []

				for elif_block in expression.elif_block:
					var elif_subtree := SceneParser.SyntaxTree.new()
					elif_subtree.values = elif_block.block
					var elif_block_dialogue_tree: DialogueTree = transpile(
						elif_subtree, dialogue_tree.index
					)

					# Store pointer to the elif block in the choice tree node
					elif_blocks.append(ConditionalBlockNode.new(dialogue_tree.index, elif_block.value.front()))
					# copy the elif block's tree nodes to the main dialogue tree
					_copy_nodes(original_value, elif_block_dialogue_tree.nodes.keys(), dialogue_tree, elif_block_dialogue_tree)
				tree_node.elif_blocks = elif_blocks

			# Transpile the else block
			if expression.else_block != null:
				var else_subtree := SceneParser.SyntaxTree.new()
				else_subtree.values = expression.else_block.block

				var else_block_dialogue_tree: DialogueTree = transpile(
					else_subtree, dialogue_tree.index
				)
				# Store pointer to the else block in the choice tree node
				tree_node.else_block = ConditionalBlockNode.new(dialogue_tree.index, null)
				# Add the else block's tree's nodes to the main dialogue tree
				_copy_nodes(original_value, else_block_dialogue_tree.nodes.keys(), dialogue_tree, else_block_dialogue_tree)
			# Reset the index
			dialogue_tree.index = original_value
			dialogue_tree.append_node(tree_node)

		else:
			push_error("Unrecognized expression of type: %s with value: %s" % [expression.type, expression.value])

	return dialogue_tree


# Transpiles a command expression and returns the approriate command node type.
func _transpile_command(dialogue_tree: DialogueTree, expression: SceneParser.BaseExpression) -> BaseNode:
	var command_node: BaseNode = null

	if expression.value == SceneLexer.BUILT_IN_COMMANDS.BACKGROUND:
		var background: String = expression.arguments[0].value
		command_node = BackgroundCommandNode.new(dialogue_tree.index + 1, background)
		
		if expression.arguments.size() > 1:
			command_node.transition = expression.arguments[1].value
		else:
			command_node.transition = ""

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.SHOW:
		var character = expression.arguments[0].value
		var emotion = expression.arguments[1].value
		var animation = expression.arguments[2].value if len(expression.arguments) > 2 else ""
		var side = expression.arguments[3].value if len(expression.arguments) > 3 else ""
		command_node = ShowCommandNode.new(dialogue_tree.index + 1, character, emotion)
		command_node.animation = animation
		command_node.side = side

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.SCENE:
		# For now, the command only works when next_scene is used as an argument.
		var new_scene: String = expression.arguments[0].value
		command_node = SceneCommandNode.new(dialogue_tree.index + 1, new_scene)

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.PASS:
		# Using `pass` is just syntactic sugar since a `pass` node
		# is always appended at the end of each code block anyways
		# to allow the blocks to escape to its parent properly when
		# it's finished.
		pass

	##TODO: recreate the jump from the associated point
	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.JUMP:
		# Jump to an existing jump point
		var jump_point: String = expression.arguments[0].value
		if _jump_points.has(jump_point):
			var target: int = _get_jump_point(jump_point)
			command_node = JumpCommandNode.new(target)
		# Store as an unresolved jump node
		# TODO: remove allowing for unresolved jumps?
		else:
			var jump_node := JumpCommandNode.new(-1)
			jump_node.jump_point = jump_point
			command_node = jump_node
			# Pass in the instance by reference so we can modify this later
			_unresolved_jump_nodes.append(jump_node)

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.TRANSITION:
		var transition: String = expression.arguments[0].value
		command_node = TransitionCommandNode.new(dialogue_tree.index + 1, transition)

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.SET:
		var symbol: String = expression.arguments[0].value
		var value = expression.arguments[1].value
		command_node = SetCommandNode.new(dialogue_tree.index + 1, symbol, value)

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.MARK:
		var new_jump_point: String = expression.arguments[0].value
		_add_jump_point(new_jump_point, dialogue_tree.index)
		# Handle any unresolved jump nodes that point to this jump point
		# Use a `temp` variable because modifying an array while also looping
		# through it can get buggy.
		var temp := _unresolved_jump_nodes
		for jump_node in _unresolved_jump_nodes:
			if jump_node.jump_point == new_jump_point:
				jump_node.next = dialogue_tree.index
				temp.erase(jump_node)
		_unresolved_jump_nodes = temp
		command_node = MarkCommandNode.new(dialogue_tree.index + 1)

	elif expression.value == SceneLexer.BUILT_IN_COMMANDS.SONG:
		var song: String = expression.arguments[0].value
		command_node = SongCommandNode.new(dialogue_tree.index + 1, song)

	else:
		push_error("Unrecognized command type `%s`" % expression.value)

	return command_node


func _transpile_dialogue(dialogue_tree: DialogueTree, expression: SceneParser.BaseExpression) -> DialogueNode:
	var node := DialogueNode.new(dialogue_tree.index + 1, expression.value)
	node.character = (
		expression.arguments[0].value
		if not expression.arguments.is_empty()
		else ""
		)
	node.expression = expression.arguments[1].value if len(expression.arguments) > 1 else ""
	node.animation = expression.arguments[2].value if len(expression.arguments) > 2 else ""
	node.side = expression.arguments[3].value if len(expression.arguments) > 3 else ""
	return node


## Adds node from a source tree to a target tree
func _copy_nodes(
	original_value: int, nodes: Array, target_tree: DialogueTree, source_tree: DialogueTree
) -> void:
	# Append a `pass` node to the end of the block to make sure it'll properly
	# end and continue to its parent block.
	source_tree.append_node(PassCommandNode.new(original_value + 1))
	nodes.append(source_tree.nodes.keys().back())

	# Add the source tree's nodes to the target tree
	for node in nodes:
		target_tree.nodes[node] = source_tree.nodes[node]
		target_tree.index += 1


func _add_jump_point(name: String, index: int) -> void:
	if _jump_points.has(name):
		push_error("Jump point %s already exists. Can't re-create it." % name)
		return

	_jump_points[name] = index


func _get_jump_point(name: String) -> int:
	if _jump_points.has(name):
		return _jump_points[name]

	# -3 because -1, -2 are already used in the ScenePlayer interpreter
	return ERROR_NONEXISTENT_JUMP_POINT
