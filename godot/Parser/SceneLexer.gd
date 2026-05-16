## Reads a scene _text file and turns it into a list of `Token` objects, using its `tokenize()` method.
class_name SceneLexer
extends RefCounted

# The constants below list reserved keywords and built-in commands.
const BUILT_IN_COMMANDS := {
	BACKGROUND = "background",
	MARK = "mark",
	SCENE = "scene",
	PASS = "pass",
	JUMP = "jump",
	TRANSITION = "transition",
	SET = "set",
	SONG = "song",
	SHOW = "show",
}
const CONDITIONAL_STATEMENTS := ["if", "elif", "else"]
const BOOLEAN_OPERATORS := ["and", "or", "not"]
const CHOICE_KEYWORD := "choice"

## Mapping of types we can assign to `Token.type`.
const TOKEN_TYPES := {
	SYMBOL = "Symbol",
	COMMAND = "Command",
	STRING_LITERAL = "String",
	CHOICE = "Choice",
	IF = "If",
	ELIF = "Elif",
	ELSE = "Else",
	BEGIN_BLOCK = "BeginBlock",
	END_BLOCK = "EndBlock",
	NEWLINE = "Newline",
	COMMENT = "Comment",
	AND = "And",
	OR = "Or",
	NOT = "Not"
}

# We allow lower and uppercase letters, numbers, and underscores in identifiers.
var symbol_regex := RegEx.new()


func _init() -> void:
	symbol_regex.compile("[_a-zA-Z0-9]")


## Represents a single token.
class Token:
	var type: String
	var value = ""

	func _init(_type: String, _value) -> void:
		self.type = _type
		self.value = _value

	func _to_string() -> String:
		return "{ type = \"%s\", value = \"%s\" }" % [self.type, self.value]


## Stores a scene file's content and provides functions to read it character by.
## character.
class DialogueScript:
	var _text: String
	var _current_index := 0
	var _current_indent_level := 0
	var _length := 0

	func _init(text: String) -> void:
		self._text = text
		self._length = len(text)

	## Returns the character at the current lexer position.
	func get_current_character() -> String:
		return self._text[self._current_index]

	## Returns the previously read character.
	func get_previous_character() -> String:
		if self._current_index > 0:
			return self._text[self._current_index - 1]
		else:
			return ""

	## Returns the character at the next lexer position without advancing the
	## current lexer position.
	func get_next_character() -> String:
		if self._current_index + 1 < len(_text):
			return _text[self._current_index + 1]
		else:
			push_error("End of File encountered. Cannot peek.")
			return ""

	## Advances the current lexer position by one and returns the character at
	## the new position.
	func move_to_next_character() -> String:
		if self._current_index + 1 < len(_text):
			self._current_index += 1
			return self._text[self._current_index]
		else:
			push_error("End of File encountered. Cannot move next.")
			return ""

	## Decrement the current lexer position and returns the character at that
	## position.
	func move_to_previous_character() -> String:
		if self._current_index - 1 >= 0:
			self._current_index -= 1
			return self._text[self._current_index]
		else:
			push_error("Can't go back beyond the first character of the script")
			return ""

	func is_at_end_of_file() -> bool:
		return self._current_index == len(_text) - 1


## Reads a text file and returns its content.
func read_file_content(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Could not find the script with path: %s" % path)
		return ""

	var file := FileAccess.open(path, FileAccess.READ)
	var script := file.get_as_text()
	file.close()
	return script


## Turns the `input_text` into an array of `Token` objects.
func tokenize(input_text: String) -> Array[Token]:
	var tokens : Array[Token] = []
	var script := DialogueScript.new(input_text)

	while not script.is_at_end_of_file():
		var character: String = script.get_current_character()

		if character == " ":
			pass
		# Add a NEWLINE token and handle indentation.
		elif character == "\n":
			tokens.append(Token.new(TOKEN_TYPES.NEWLINE, ""))

			# Get the indentation level for the current line.
			var line_indent_level := 0
			while script.get_next_character() == "\t":
				line_indent_level += 1
				script.move_to_next_character()

			var is_empty_line := script.get_next_character() in [" ", "\n"]
			if not is_empty_line:
				if line_indent_level > script._current_indent_level:
					push_error("Invalid indent level.")
				elif line_indent_level == script._current_indent_level:
					pass
				else:
					# Emit token(s) indicating the end of a block if the line's
					# indent is lower than the currently tracked indent level.
					for _i in range(script._current_indent_level - line_indent_level):
						script._current_indent_level -= 1
						tokens.append(Token.new(TOKEN_TYPES.END_BLOCK, ""))
		# Handle string literals.
		elif character == "\"":
			tokens.append(_tokenize_string_literal(script))
			# Begin a nested block.
		elif character == ":":
			if script.get_previous_character() == ":":
				push_error("Invalid block declaration syntax.")

			script._current_indent_level += 1

			tokens.append(Token.new(TOKEN_TYPES.BEGIN_BLOCK, ""))
		# Handle comments.
		elif character == "#":
			tokens.append(_tokenize_comment(script))
		# Handle symbols.
		elif character.is_valid_identifier():
			tokens.append(_tokenize_symbol(script))
		else:
			if character == "	":
				push_warning("unneeded indent found at: %s" % character.unicode_at(0))
			else:
				push_error("Found unidentified character: %s : %s" % [character, character.unicode_at(0)])

		script.move_to_next_character()

	if tokens.back().type != TOKEN_TYPES.NEWLINE:
		# Add a NEWLINE token so the final line is always properly delimited.
		tokens.append(Token.new(TOKEN_TYPES.NEWLINE, ""))
	return tokens


func _tokenize_comment(script: DialogueScript) -> Token:
	var comment_value := ""

	while not script.is_at_end_of_file():
		var character = script.move_to_next_character()
		# End the comment.
		if character == "\n":
			script.move_to_previous_character()
			return Token.new(TOKEN_TYPES.COMMENT, comment_value)
		else:
			comment_value += character

	# In case we reach End of File.
	return Token.new(TOKEN_TYPES.COMMENT, comment_value)


func _tokenize_symbol(script: DialogueScript) -> Token:
	# Store the symbol's first character because that's been checked to be a
	# valid identifier (isn't a digit).
	var symbol := "%s" % script.get_current_character()

	while not script.is_at_end_of_file():
		var character = script.move_to_next_character()

		# Only add characters that match the regex.
		if symbol_regex.search(character):
			symbol += character
		elif character in ["	", " ", "\n", "\r", ":"]:
			script.move_to_previous_character()
			break
		else:
			push_error("Invalid character %s inside symbol (%s)" % [character, character.unicode_at(0)])
			return Token.new("", "")

	if symbol in BUILT_IN_COMMANDS.values():
		return Token.new(TOKEN_TYPES.COMMAND, symbol)
	elif (
		symbol in CONDITIONAL_STATEMENTS
		or symbol in BOOLEAN_OPERATORS
		or symbol == CHOICE_KEYWORD
	):
		return Token.new(TOKEN_TYPES[symbol.to_upper()], "")
	else:
		return Token.new(TOKEN_TYPES.SYMBOL, symbol)


func _tokenize_string_literal(script: DialogueScript) -> Token:
	var value := ""

	# Try to find the matching double quotes for the string.
	while not script.is_at_end_of_file():
		var character: String = script.move_to_next_character()

		if character == "\"":
			# Continue if the double quotes is escaped.
			if script.get_previous_character() == "\\":
				value += character
				continue

			value = value.c_unescape()

			return Token.new(TOKEN_TYPES.STRING_LITERAL, value)
		else:
			if character == "\n":
				script.move_to_previous_character()
				break

			value += character

	# Throw if no matching quotes is found by the end of the line or we reached
	# the end of the file.
	push_error("Unterminated string")
	return Token.new("", "")
