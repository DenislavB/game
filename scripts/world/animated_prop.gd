class_name AnimatedProp
extends Node3D
## A self-animating prop part — the moving piece of an otherwise static
## prop (a turning windmill sail, a swaying banner, a bobbing mote). Add
## the mesh(es) as children of this node, set mode/speed/amount, and it
## drives itself. Cheap: no allocation per frame, just a couple of trig
## calls, and it respects the reduced-motion nature of a sparse world.

enum Mode { SPIN, SWAY, BOB }

@export var mode: Mode = Mode.SWAY
var speed := 1.0
var amount := 0.15       # radians for SWAY, metres for BOB
var _t := 0.0
var _base_rot_z := 0.0
var _base_y := 0.0


func _ready() -> void:
	_base_rot_z = rotation.z
	_base_y = position.y
	_t = randf() * TAU   # desync identical props so they don't move in lockstep


func _process(delta: float) -> void:
	_t += delta * speed
	match mode:
		Mode.SPIN:
			rotation.z = _base_rot_z + _t
		Mode.SWAY:
			rotation.z = _base_rot_z + sin(_t) * amount
		Mode.BOB:
			position.y = _base_y + sin(_t) * amount


static func make(mode_: Mode, speed_: float, amount_: float) -> AnimatedProp:
	var a := AnimatedProp.new()
	a.mode = mode_
	a.speed = speed_
	a.amount = amount_
	return a
