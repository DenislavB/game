class_name ActorModel
extends Node3D
## Procedural low-poly character/creature model with simple code-driven
## animation (walk, attack, cast, sit, death). No imported assets.

var rig: Node3D
var moving := false
var dead := false
var sitting := false
var casting := false

var _phase := 0.0
var _attack_t := 0.0
var _time := 0.0
var _biped_arms: Array = []      # [arm_l, arm_r] pivots
var _legs: Array = []            # leg pivots (2 or 4)
var _wings: Array = []
var _tail: Node3D = null
var _hand: Node3D = null
var _base_y := 0.0
var _is_quadruped := false


func _mk_rig() -> void:
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Props.mat(color, emissive)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


# ---------------------------------------------------------------- humanoid

func build_humanoid(cfg: Dictionary) -> void:
	_mk_rig()
	var skin: Color = cfg.get("skin", Color("d9a97c"))
	var shirt: Color = cfg.get("shirt", Color("7a5a3a"))
	var pants: Color = cfg.get("pants", Color("4a3a2a"))
	var hunched: bool = cfg.get("posture", "upright") == "hunched"
	var s: float = cfg.get("scale", 1.0)

	# Legs
	for side in [-1, 1]:
		var hip := _pivot(rig, Vector3(side * 0.16, 0.95, 0))
		_part(hip, Props._box(0.2, 0.9, 0.24), pants, Vector3(0, -0.45, 0))
		_part(hip, Props._box(0.24, 0.12, 0.34), Color("3a2a1a"), Vector3(0, -0.92, 0.04))
		_legs.append(hip)

	# Torso
	var torso := _pivot(rig, Vector3(0, 0.95, 0))
	_part(torso, Props._box(0.62, 0.66, 0.34), shirt, Vector3(0, 0.36, 0))
	_part(torso, Props._box(0.66, 0.14, 0.38), Color("5a4428"), Vector3(0, 0.06, 0))  # belt

	# Head
	var head := _pivot(torso, Vector3(0, 0.78, 0))
	_part(head, Props._box(0.34, 0.36, 0.34), skin, Vector3(0, 0.18, 0))
	_part(head, Props._box(0.36, 0.12, 0.36), cfg.get("hair", Color("3a2a1a")), Vector3(0, 0.4, -0.02))
	if cfg.get("tusks", false):
		_part(head, Props._cyl(0.0, 0.045, 0.2, 4), Color("e8e0c8"), Vector3(0.1, 0.06, 0.16), Vector3(180, 0, 0))
		_part(head, Props._cyl(0.0, 0.045, 0.2, 4), Color("e8e0c8"), Vector3(-0.1, 0.06, 0.16), Vector3(180, 0, 0))

	# Arms + hand attachment
	for side in [-1, 1]:
		var shoulder := _pivot(torso, Vector3(side * 0.4, 0.62, 0))
		_part(shoulder, Props._box(0.16, 0.72, 0.2), (skin if side < 0 else skin), Vector3(0, -0.36, 0))
		_part(shoulder, Props._box(0.22, 0.24, 0.26), shirt, Vector3(0, -0.08, 0))  # pauldron
		_biped_arms.append(shoulder)
		if side > 0:
			_hand = _pivot(shoulder, Vector3(0, -0.72, 0))

	if hunched:
		torso.rotation.x = 0.3
		rig.position.y = -0.08
		for arm in _biped_arms:
			arm.scale = Vector3(1.15, 1.1, 1.15)
	rig.scale = Vector3(s, s, s)
	rig.rotation.y = PI  # model is built facing +Z; units face -Z
	_base_y = rig.position.y


func set_weapon(wtype: String) -> void:
	if _hand == null:
		return
	for c in _hand.get_children():
		c.queue_free()
	if wtype == "":
		return
	var w := Props.build_weapon(wtype)
	w.rotation_degrees = Vector3(-90, 0, 0)  # point forward from the fist
	_hand.add_child(w)


# ---------------------------------------------------------------- creatures

func build_creature(shape: String, color: Color, s: float = 1.0) -> void:
	_mk_rig()
	var dark := color.darkened(0.25)
	var light := color.lightened(0.15)
	match shape:
		"boar":
			_part(rig, Props._box(1.2, 0.7, 0.65), color, Vector3(0, 0.75, 0))
			var head := _part(rig, Props._box(0.5, 0.5, 0.45), dark, Vector3(0.75, 0.7, 0))
			_part(head, Props._box(0.2, 0.18, 0.24), color.lightened(0.3), Vector3(0.32, -0.08, 0))
			_part(head, Props._cyl(0.0, 0.04, 0.22, 4), Color("e8e0c8"), Vector3(0.3, -0.1, 0.16), Vector3(0, 0, -110))
			_part(head, Props._cyl(0.0, 0.04, 0.22, 4), Color("e8e0c8"), Vector3(0.3, -0.1, -0.16), Vector3(0, 0, -110))
			_quad_legs(0.45, 0.25, 0.5, dark)
			_is_quadruped = true
		"wolf", "deer":
			_part(rig, Props._box(1.1, 0.5, 0.45), color, Vector3(0, 0.8, 0))
			var head2 := _part(rig, Props._box(0.38, 0.36, 0.34), light, Vector3(0.7, 0.95, 0))
			_part(head2, Props._box(0.24, 0.16, 0.2), dark, Vector3(0.28, -0.06, 0))
			_part(head2, Props._box(0.08, 0.16, 0.06), dark, Vector3(-0.08, 0.24, 0.1))
			_part(head2, Props._box(0.08, 0.16, 0.06), dark, Vector3(-0.08, 0.24, -0.1))
			if shape == "deer":
				_part(head2, Props._cyl(0.02, 0.03, 0.5, 4), Color("c8b890"), Vector3(0, 0.4, 0.12), Vector3(0, 0, 25))
				_part(head2, Props._cyl(0.02, 0.03, 0.5, 4), Color("c8b890"), Vector3(0, 0.4, -0.12), Vector3(0, 0, -25))
			_tail = _pivot(rig, Vector3(-0.6, 0.85, 0))
			_part(_tail, Props._box(0.4, 0.12, 0.12), dark, Vector3(-0.2, 0, 0))
			_quad_legs(0.42, 0.18, 0.62, dark)
			_is_quadruped = true
		"raptor":
			var body := _part(rig, Props._box(0.9, 0.55, 0.5), color, Vector3(0, 0.95, 0))
			body.rotation_degrees = Vector3(0, 0, -12)
			var neck := _part(rig, Props._box(0.28, 0.5, 0.28), color, Vector3(0.45, 1.35, 0))
			neck.rotation_degrees = Vector3(0, 0, -25)
			var head3 := _part(rig, Props._box(0.5, 0.28, 0.26), dark, Vector3(0.75, 1.6, 0))
			_part(head3, Props._box(0.3, 0.1, 0.2), light, Vector3(0.2, -0.12, 0))
			_tail = _pivot(rig, Vector3(-0.45, 1.0, 0))
			_part(_tail, Props._cyl(0.04, 0.16, 1.1, 5), dark, Vector3(-0.55, 0, 0), Vector3(0, 0, 90))
			for side in [-1, 1]:
				var hip := _pivot(rig, Vector3(-0.1, 0.75, side * 0.28))
				_part(hip, Props._box(0.22, 0.75, 0.2), dark, Vector3(0, -0.38, 0))
				_part(hip, Props._box(0.34, 0.1, 0.22), light, Vector3(0.08, -0.72, 0))
				_legs.append(hip)
		"scorpid":
			_part(rig, Props._box(1.1, 0.4, 0.8), color, Vector3(0, 0.35, 0))
			for side in [-1, 1]:
				var claw := _part(rig, Props._box(0.45, 0.25, 0.3), dark, Vector3(0.65, 0.3, side * 0.35))
				claw.rotation_degrees = Vector3(0, side * 20, 0)
			var seg1 := _pivot(rig, Vector3(-0.55, 0.5, 0))
			_part(seg1, Props._sphere(0.18, 5), dark, Vector3(-0.15, 0.25, 0))
			_part(seg1, Props._sphere(0.15, 5), dark, Vector3(-0.2, 0.6, 0))
			_part(seg1, Props._cyl(0.0, 0.08, 0.3, 4), Color("2a2a22"), Vector3(-0.1, 0.9, 0), Vector3(0, 0, -35))
			_tail = seg1
			_quad_legs(0.28, 0.1, 0.55, dark, 3)
			_is_quadruped = true
		"spider":
			_part(rig, Props._sphere(0.5, 6), color, Vector3(-0.2, 0.55, 0))
			_part(rig, Props._sphere(0.3, 6), dark, Vector3(0.35, 0.45, 0))
			for i in 4:
				for side in [-1, 1]:
					var leg := _pivot(rig, Vector3(0.3 - i * 0.22, 0.5, side * 0.2))
					_part(leg, Props._cyl(0.03, 0.04, 0.7, 4), dark, Vector3(0, -0.1, side * 0.3), Vector3(side * 55, 0, 0))
					_legs.append(leg)
			_is_quadruped = true
		"bird":
			_part(rig, Props._box(0.7, 0.55, 0.5), color, Vector3(0, 1.15, 0))
			var neck2 := _part(rig, Props._cyl(0.09, 0.12, 0.8, 5), light, Vector3(0.3, 1.7, 0))
			neck2.rotation_degrees = Vector3(0, 0, -15)
			var head4 := _part(rig, Props._box(0.32, 0.2, 0.2), dark, Vector3(0.5, 2.1, 0))
			_part(head4, Props._cyl(0.0, 0.06, 0.3, 4), Color("d8b050"), Vector3(0.25, 0, 0), Vector3(0, 0, -90))
			_tail = _pivot(rig, Vector3(-0.4, 1.2, 0))
			_part(_tail, Props._box(0.5, 0.08, 0.3), dark, Vector3(-0.25, 0.05, 0))
			for side in [-1, 1]:
				var hip2 := _pivot(rig, Vector3(0, 0.9, side * 0.18))
				_part(hip2, Props._cyl(0.05, 0.06, 0.85, 4), dark, Vector3(0, -0.42, 0))
				_part(hip2, Props._box(0.28, 0.08, 0.16), dark, Vector3(0.06, -0.85, 0))
				_legs.append(hip2)
		"harpy":
			build_humanoid({ "skin": color, "shirt": color.darkened(0.3), "pants": color.darkened(0.4), "hair": color.lightened(0.3) })
			for side in [-1, 1]:
				var wing := _pivot(rig, Vector3(side * 0.3, 1.55, -0.15))
				_part(wing, Props._box(0.9, 0.06, 0.4), color.lightened(0.2), Vector3(side * 0.5, 0.1, -0.1), Vector3(0, 0, side * 15))
				_wings.append(wing)
			return
		"spirit":
			_part(rig, Props._sphere(0.45, 6), color, Vector3(0, 1.1, 0), Vector3.ZERO, true)
			_part(rig, Props._cyl(0.0, 0.4, 0.9, 6), color.darkened(0.2), Vector3(0, 0.45, 0), Vector3(180, 0, 0), true)
			var l := OmniLight3D.new()
			l.light_color = color
			l.omni_range = 6.0
			l.position = Vector3(0, 1.2, 0)
			rig.add_child(l)
		"sheep":
			_part(rig, Props._sphere(0.4, 6), Color("e8e4d8"), Vector3(0, 0.55, 0))
			_part(rig, Props._box(0.25, 0.22, 0.2), Color("2a2a2a"), Vector3(0.4, 0.6, 0))
			_quad_legs(0.3, 0.15, 0.35, Color("2a2a2a"))
			_is_quadruped = true
		"hare":
			_part(rig, Props._sphere(0.25, 5), color, Vector3(0, 0.25, 0))
			_part(rig, Props._sphere(0.16, 5), light, Vector3(0.2, 0.4, 0))
			_part(rig, Props._box(0.05, 0.22, 0.04), color, Vector3(0.16, 0.6, 0.06))
			_part(rig, Props._box(0.05, 0.22, 0.04), color, Vector3(0.16, 0.6, -0.06))
			_is_quadruped = true
		"humanoid", _:
			build_humanoid({ "skin": color, "shirt": color.darkened(0.2), "pants": color.darkened(0.45) })
			return
	rig.scale = Vector3(s, s, s)
	rig.rotation.y = PI / 2.0  # creatures are built facing +X; units face -Z


func _quad_legs(spread_x: float, w: float, len: float, color: Color, pairs: int = 2) -> void:
	for i in pairs:
		var x: float = spread_x - i * spread_x * (2.0 / maxf(pairs - 1, 1.0)) if pairs > 1 else 0.0
		for side in [-1, 1]:
			var hip := _pivot(rig, Vector3(x, len + 0.05, side * 0.28))
			_part(hip, Props._box(w, len, w), color, Vector3(0, -len * 0.5, 0))
			_legs.append(hip)


# ---------------------------------------------------------------- animation

func play_attack() -> void:
	_attack_t = 0.35


func play_death() -> void:
	dead = true
	var tw := create_tween()
	tw.tween_property(rig, "rotation:z", PI / 2.0, 0.4)
	tw.parallel().tween_property(rig, "position:y", _base_y + 0.2, 0.4)


func revive_pose() -> void:
	dead = false
	rig.rotation.z = 0
	rig.position.y = _base_y


func _process(delta: float) -> void:
	if dead:
		return
	_time += delta
	if sitting:
		rig.position.y = _base_y - 0.45
		for leg in _legs:
			leg.rotation.x = 0
			leg.rotation.z = -1.3
		return
	_phase += delta * (11.0 if moving else 0.0)
	var swing := sin(_phase) * (0.65 if moving else 0.0)
	if not moving:
		swing = 0.0
		rig.position.y = _base_y + sin(_time * 2.0) * 0.02
	else:
		rig.position.y = _base_y + absf(sin(_phase)) * 0.05
	var i := 0
	for leg in _legs:
		leg.rotation.z = 0
		leg.rotation.x = swing * (1.0 if i % 2 == 0 else -1.0)
		i += 1
	if _attack_t > 0.0:
		_attack_t -= delta
		var k := sin((0.35 - _attack_t) / 0.35 * PI)
		if _biped_arms.size() > 1:
			_biped_arms[1].rotation.x = -2.2 * k
		else:
			rig.rotation.x = -0.35 * k
	elif casting and _biped_arms.size() > 1:
		_biped_arms[0].rotation.x = lerpf(_biped_arms[0].rotation.x, -2.4, delta * 8.0)
		_biped_arms[1].rotation.x = lerpf(_biped_arms[1].rotation.x, -2.4, delta * 8.0)
	else:
		var j := 0
		for arm in _biped_arms:
			arm.rotation.x = swing * (1.0 if j % 2 == 1 else -1.0) * 0.7
			j += 1
		if not _is_quadruped:
			rig.rotation.x = 0
	for wing in _wings:
		wing.rotation.z = sin(_time * 6.0) * 0.35 * (1 if wing.position.x > 0 else -1)
	if _tail != null:
		_tail.rotation.y = sin(_time * 3.0) * 0.15
