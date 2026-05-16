## Takes in token list and produces a `SyntaxTree` representation of the token list using the `parse` function
class_name SceneParser
extends RefCounted

## Names for the possible kind of expressions supported by the parser.
const EXPRESSION_TYPES := {
	CONDITIONAL_TREE = "ConditionalTree",
	CHOICE_BLOCK = "ChoiceBlock",
	DIALOGUE = "Dialogue",
	CHOICE = "Choice",
	COMMAND = SceneLexer.TOKEN_TYPES.COMMAND,
	IF = SceneLexer.TOKEN_TYPES.IF,
	ELSE = SceneLexer.TOKEN_TYPES.ELSE,
	ELIF = SceneLexer.TOKEN_TYPES.ELIF,
}


## Represents a tree of expressions produced from a token list
class SyntaxTree:
	var values : Array = []

	# Starts with -1 instead of 0 so the transpiler will start parsing correctly
	var current_index := -1

	func append_expression(expression: BaseExpression) -> void:
		values.append(expression)

	func move_to_next_expression() -> BaseExpression:
		if not is_at_end():
			current_index += 1
			return self.values[current_index]
		return null

	func peek() -> BaseExpression:
		if not is_at_end():
			return values[current_index + 1]
		return null

	func is_at_end() -> bool:
		return current_index == len(values) - 1


## Represents a simple expression
class BaseExpression:
	var type: String
	var value

	func _init(_type: String, _value) -> void:
		self.type = _type
		self.value = _value

	func _to_string() -> String:
		return "{type: %s, val: %s}" % [type, value]


## Represents an expression that can have arguments
class FunctionExpression:
	extends BaseExpression
	var arguments: Array

	func _init(_type: String, _value: String, _arguments: Array) -> void:
		super(_type, _value)
		self.arguments = _arguments
	
	func _to_string() -> String:
		return "{type: %s, val: %s, args: %s (size: %s)}" % [type, value, "".join(arguments), arguments.size()]



## Represents a labeled block in a choice tree that contains expressions
class ChoiceBlockExpression:
	extends BaseExpression
	var label := ""

	func _init(_type: String, _value: Array, _label: String) -> void:
		super(_type, _value)
		self.label = _label
	
	func _to_string() -> String:
		return "{type: %s, val: %s, label: %s}" % [type, value, label]


## Represents a single expression with a boolean condition and a block containing expressions
class ConditionalExpression:
	extends BaseExpression
	var block: Array

	func _init(_type: String, _value, _block: Array) -> void:
		super(_type, _value)
		self.block = _block
	
	func _to_string() -> String:
		return "{type: %s, val: %s, block: %s}" % [type, value, "".join(block)]


## Represents a tree of ConditionalExpressions
class ConditionalTreeExpression:
	extends BaseExpression
	var if_block: ConditionalExpression
	var elif_block: Array
	var else_block: ConditionalExpression

	func _init(
		_type: String,
		_value: String,
		_if_block: ConditionalExpression,
		_elif_block: Array,
		_else_block: ConditionalExpression
	) -> void:
		super(_type, _value)
		self.if_block = _if_block
		self.elif_block = _elif_block
		self.else_block = _else_block
	
	func _to_string() -> String:
		return "{type: %s, val: %s, if: %s, elif: %s, else: %s}" % [type, value, if_block, "".join(elif_block), else_block]


## Class used to help the process of parsing through the token list
class Parser:
	# Starts with -1 instead of 0 so the parser will start parsing correctly
	var current_index := -1

	var _tokens := []

	var _length := 0

	func _init(tokens: Array) -> void:
		self._tokens = tokens
		self._length = len(self._tokens)

	func get_current_token() -> SceneLexer.Token:
		var token = self._tokens[self.current_index]
		return token if token.type != SceneLexer.TOKEN_TYPES.NEWLINE else null

	func get_previous_token() -> SceneLexer.Token:
		if self.current_index > 0:
			return self._tokens[self.current_index - 1]
		return null

	func move_to_previous_token() -> SceneLexer.Token:
		if self.current_index > 0:
			current_index -= 1
			return self._tokens[self.current_index]
		return null

	func move_to_next_token() -> SceneLexer.Token:
		self.current_index += 1
		return self._tokens[self.current_index]

	func peek() -> SceneLexer.Token:
		if not is_at_end_of_list():
			return self._tokens[self.current_index + 1]
		else:
			return SceneLexer.Token.new("", "")

	func is_at_end_of_list() -> bool:
		return current_index == _length - 1

	## Find expressions until we hit the specified token type or the end of the file
	func find_expressions(stop_at_type: String) -> Array:
		var arguments := []

		while not self.is_at_end_of_list() and self.peek().type != stop_at_type:
			var expression := self.parse_next_token()

			if expression:
				arguments.append(expression)

		return arguments

	## Returns expressions from an indented block
	func parse_indented_block() -> Array:
		var block_content := []

		# Stack starts with 1 because we skip the first BEGIN_BLOCK token
		var indent_stack := 1

		if self.peek().type == SceneLexer.TOKEN_TYPES.BEGIN_BLOCK:
			self.move_to_next_token()

		while not self.is_at_end_of_list():
			var expression := self.parse_next_token()

			if expression == null:
				continue

			if expression.type == SceneLexer.TOKEN_TYPES.BEGIN_BLOCK:
				indent_stack += 1

				# Recursively parse the block
				block_content.append(parse_indented_block())
			elif expression.type == SceneLexer.TOKEN_TYPES.END_BLOCK:
				indent_stack -= 1

				if indent_stack == 0:
					return block_content
				else:
					break
			else:
				block_content.append(expression)

		return []

	## Parse to next token and returns an approriate expression for the syntax tree
	func parse_next_token() -> BaseExpression:
		var current_token := self.move_to_next_token()

		if (
			self.get_previous_token()
			and (
				self.get_previous_token().type
				in [SceneLexer.TOKEN_TYPES.NEWLINE, SceneLexer.TOKEN_TYPES.END_BLOCK]
			)
			and (
				current_token.type
				in [SceneLexer.TOKEN_TYPES.SYMBOL, SceneLexer.TOKEN_TYPES.STRING_LITERAL]
			)
		):
			# Dialogue line with some options (character, expression, etc. )
			if current_token.type == SceneLexer.TOKEN_TYPES.SYMBOL:
				var arguments: Array = find_expressions(SceneLexer.TOKEN_TYPES.STRING_LITERAL)

				# Push the character name to the front
				arguments.push_front(current_token)
				var test = FunctionExpression.new(
					EXPRESSION_TYPES.DIALOGUE, parse_next_token().value, arguments
				)
				return test
			else:
				# Narrator line
				return FunctionExpression.new(EXPRESSION_TYPES.DIALOGUE, current_token.value, [])
		elif current_token.type == SceneLexer.TOKEN_TYPES.COMMAND:
			# Find the arguments until the parser hits newline
			var arguments := self.find_expressions(SceneLexer.TOKEN_TYPES.NEWLINE)

			return FunctionExpression.new(current_token.type, current_token.value, arguments)
		elif current_token.type == SceneLexer.TOKEN_TYPES.CHOICE:
			var choice_blocks := []

			while not self.is_at_end_of_list():
				var token := self.move_to_next_token()

				# The label for the choice block
				if token.type == SceneLexer.TOKEN_TYPES.STRING_LITERAL:
					# Parse the block
					choice_blocks.append(
						ChoiceBlockExpression.new(
							EXPRESSION_TYPES.CHOICE_BLOCK, self.parse_indented_block(), token.value
						)
					)
				elif token.type == SceneLexer.TOKEN_TYPES.END_BLOCK:
					# Return the choice tree
					return BaseExpression.new(EXPRESSION_TYPES.CHOICE, choice_blocks)

			push_error(
				"Reached End of File before the parser could finish going through a choice tree"
			)
			return null
		elif current_token.type == SceneLexer.TOKEN_TYPES.IF:
			# Parse the condition and parse the expression inside the if block
			var if_block := ConditionalExpression.new(
				EXPRESSION_TYPES.IF,
				self.find_expressions(SceneLexer.TOKEN_TYPES.BEGIN_BLOCK),
				parse_indented_block()
			)

			# Use an array because there can be multiple elif's
			var elif_block := []

			# Handle elifs until there are none left
			while self.peek().type == SceneLexer.TOKEN_TYPES.ELIF:
				elif_block.append(
					ConditionalExpression.new(
						EXPRESSION_TYPES.ELIF,
						find_expressions(SceneLexer.TOKEN_TYPES.BEGIN_BLOCK),
						parse_indented_block()
					)
				)

			var else_block: ConditionalExpression

			if self.peek().type == SceneLexer.TOKEN_TYPES.ELSE:
				# Increment the index so this will parse properly
				self.move_to_next_token()

				else_block = ConditionalExpression.new(
					EXPRESSION_TYPES.ELSE, null, parse_indented_block()
				)

			return ConditionalTreeExpression.new(
				EXPRESSION_TYPES.CONDITIONAL_TREE, "", if_block, elif_block, else_block
			)
		elif (
			current_token.type
			in [SceneLexer.TOKEN_TYPES.AND, SceneLexer.TOKEN_TYPES.OR, SceneLexer.TOKEN_TYPES.NOT]
		):
			push_error("Parsing boolean operators is not yet supported...")
			return null
		elif (
			current_token.type
			in [
				SceneLexer.TOKEN_TYPES.SYMBOL,
				SceneLexer.TOKEN_TYPES.STRING_LITERAL,
				SceneLexer.TOKEN_TYPES.BEGIN_BLOCK,
				SceneLexer.TOKEN_TYPES.END_BLOCK
			]
		):
			return BaseExpression.new(current_token.type, current_token.value)
		else:
			return null


## Takes in a token list from the lexer and returns a syntax tree
func parse(tokens: Array) -> SyntaxTree:
	var parser = Parser.new(tokens)

	var tree := SyntaxTree.new()

	while not parser.is_at_end_of_list():
		var expression: BaseExpression = parser.parse_next_token()

		if expression:
			tree.append_expression(expression)

	return tree
