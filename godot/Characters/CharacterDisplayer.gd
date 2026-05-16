## Displays and animates [Character] portraits, for example, entering from the left or the right.
## Place it behind a [TextBox].
class_name CharacterDisplayer
extends Node

## Emitted when the characters finished displaying or finished their animation.
signal display_finished

## Maps animation text ids to a function that animates a character sprite.
const ANIMATIONS := {"enter": "_enter", "leave": "_leave", "test": "_test"}
const SIDE := {LEFT = "left", RIGHT = "right"}
const SIDE_POSITION := {LEFT = Vector2(330.836, 655.203), RIGHT = Vector2(1592.01, 655.203)}
const COLOR_WHITE_TRANSPARENT = Color(1.0, 1.0, 1.0, 0.0)

## Keeps track of the character displayed on either side.
var _displayed := { left = null, right = null }

var _tween: Tween
@onready var _left_sprite: Sprite2D = $Left
@onready var _right_sprite: Sprite2D = $Right

func _ready() -> void:
	_left_sprite.hide()
	_right_sprite.hide()
	#_tween.finished.connect(_on_tween_finished)

func _unhandled_input(event: InputEvent) -> void:
	# If the player presses enter before the character animations ended, we seek to the end.
	if event.is_action_pressed("ui_accept") and _tween and _tween.is_running():
		_tween.custom_step(100.0)
		_tween.kill()


func display(character: Character, expression := "", side: String = SIDE.LEFT, animation := "") -> void:
#	assert(side in SIDE.values())
	# Keeps track of a character that's already displayed on a given side
	var sprite: Sprite2D = _left_sprite if side == SIDE.LEFT else _right_sprite
	if character == _displayed.left:
		sprite = _left_sprite
	elif character == _displayed.right:
		sprite = _right_sprite
	else:
		_displayed[side] = character

	sprite.texture = character.get_image(expression)

	if animation != "":
		call(ANIMATIONS[animation], side, sprite)

	sprite.show()


## Fades in and moves the character to the anchor position.
func _enter(from_side: String, sprite: Sprite2D) -> void:
	var offset := -200 if from_side == SIDE.LEFT else 200

	var start := sprite.position + Vector2(offset, 0.0)
	var end := SIDE_POSITION.LEFT if from_side == SIDE.LEFT else SIDE_POSITION.RIGHT
	_tween = create_tween()
	_tween.finished.connect(_on_tween_finished)
	_tween.set_parallel(true)
	_tween.tween_property(
		sprite,
		"position",
		end,
		0.5,
	).from(start).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	_tween.tween_property(sprite, "modulate", Color.WHITE, 0.25).from(COLOR_WHITE_TRANSPARENT)

	# Set up the sprite
	# We don't use Tween.seek(0.0) here since that could conflict with running tweens and make them jitter back and forth
	sprite.position = start
	sprite.modulate = COLOR_WHITE_TRANSPARENT
	return


func _leave(from_side: String, sprite: Sprite2D) -> void:
	var offset := -200 if from_side == SIDE.LEFT else 200

	var start := sprite.position
	var end := sprite.position + Vector2(offset, 0.0)

	_tween = create_tween()
	_tween.finished.connect(_on_tween_finished)
	_tween.set_parallel(true)
	_tween.tween_property(
		sprite,
		"position",
		end,
		0.5,
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT).from(start)
	_tween.tween_property(
		sprite,
		"modulate",
		COLOR_WHITE_TRANSPARENT,
		0.25,
	).set_delay(.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR).from(Color.WHITE)
	_tween.start()
	_tween.seek(0.0)

func _on_tween_finished() -> void:
	display_finished.emit()
