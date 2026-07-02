class_name ActorModel
extends Node3D
## Procedural low-poly character/creature model with simple code-driven
## animation (walk, attack, cast, sit, death). No imported assets.
##
## Frame convention: the finished model ALWAYS faces the node's -Z
## (Godot forward). Humanoids are authored in -Z directly; quadrupeds
## are authored along +X and the rig is yawed 90 degrees.

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
var _death_axis := "z"           # humanoids topple sideways (z), creatures roll (x)

# Gear visual part references (humanoids only)
var _chest_meshes: Array = []
var _leg_meshes: Array = []
var _boot_meshes: Array = []
var _glove_meshes: Array = []
var _pauldrons: Array = []
var _helm: MeshInstance3D = null
var _belt_mesh: MeshInstance3D = null
var _buckle: MeshInstance3D = null
var _def_shirt := Color("7a5a3a")
var _def_pants := Color("4a3a2a")
var _def_skin := Color("d9a97c")


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
	var hair: Color = cfg.get("hair", Color("3a2a1a"))
	var hunched: bool = cfg.get("posture", "upright") == "hunched"
	var orc: bool = cfg.get("tusks", false)
	var s: float = cfg.get("scale", 1.0)
	_def_shirt = shirt
	_def_pants = pants
	_def_skin = skin
	var boot_col := Color("3a2c1e")

	# --- Legs (front of the model is -Z) ---
	for side in [-1, 1]:
		var hip := _pivot(rig, Vector3(side * 0.17, 0.95, 0))
		_leg_meshes.append(_part(hip, Props._box(0.22, 0.5, 0.24), pants, Vector3(0, -0.25, 0)))
		_leg_meshes.append(_part(hip, Props._box(0.18, 0.42, 0.2), pants.darkened(0.15), Vector3(0, -0.68, 0)))
		_boot_meshes.append(_part(hip, Props._box(0.21, 0.16, 0.3), boot_col, Vector3(0, -0.88, -0.05)))
		_legs.append(hip)

	# --- Torso ---
	var torso := _pivot(rig, Vector3(0, 0.95, 0))
	_chest_meshes.append(_part(torso, Props._box(0.5, 0.26, 0.3), shirt.darkened(0.12), Vector3(0, 0.14, 0)))
	_chest_meshes.append(_part(torso, Props._box(0.62, 0.48, 0.36), shirt, Vector3(0, 0.47, 0)))
	_belt_mesh = _part(torso, Props._box(0.54, 0.12, 0.33), Color("5a4428"), Vector3(0, 0.0, 0))
	_buckle = _part(torso, Props._box(0.12, 0.09, 0.04), Color("c8a040"), Vector3(0, 0.0, -0.18))
	_buckle.visible = false

	# --- Head (face details at -Z so front/back is unmistakable) ---
	var head := _pivot(torso, Vector3(0, 0.71, 0))
	_part(head, Props._cyl(0.09, 0.11, 0.12, 6), skin.darkened(0.1), Vector3(0, 0.05, 0))  # neck
	_part(head, Props._box(0.32, 0.34, 0.34), skin, Vector3(0, 0.28, 0))                    # skull
	_part(head, Props._box(0.05, 0.05, 0.02), Color("1a1a22"), Vector3(0.08, 0.32, -0.175))  # eyes
	_part(head, Props._box(0.05, 0.05, 0.02), Color("1a1a22"), Vector3(-0.08, 0.32, -0.175))
	_part(head, Props._box(0.06, 0.09, 0.05), skin.darkened(0.12), Vector3(0, 0.26, -0.19))  # nose
	_part(head, Props._box(0.34, 0.1, 0.32), hair, Vector3(0, 0.47, 0.02))                   # hair top
	_part(head, Props._box(0.3, 0.2, 0.08), hair, Vector3(0, 0.32, 0.17))                    # hair back
	if orc:
		_part(head, Props._box(0.28, 0.11, 0.12), skin.darkened(0.08), Vector3(0, 0.13, -0.13))  # jaw
		_part(head, Props._cyl(0.0, 0.04, 0.16, 4), Color("e8e0c8"), Vector3(0.09, 0.2, -0.19))  # tusks point up
		_part(head, Props._cyl(0.0, 0.04, 0.16, 4), Color("e8e0c8"), Vector3(-0.09, 0.2, -0.19))
	_helm = _part(head, Props._box(0.37, 0.24, 0.38), Color("8a8a92"), Vector3(0, 0.44, 0))
	_helm.visible = false

	# --- Arms + hand attachment ---
	for side in [-1, 1]:
		var shoulder := _pivot(torso, Vector3(side * 0.41, 0.66, 0))
		var pauldron := _part(shoulder, Props._box(0.26, 0.18, 0.3), shirt.darkened(0.2), Vector3(side * 0.02, 0.04, 0))
		pauldron.visible = cfg.get("dressed", true)  # NPCs/mobs look dressed; player earns them
		_pauldrons.append(pauldron)
		_part(shoulder, Props._box(0.16, 0.36, 0.18), shirt, Vector3(0, -0.2, 0))            # sleeve
		_part(shoulder, Props._box(0.13, 0.34, 0.15), skin, Vector3(0, -0.53, 0))            # forearm
		_glove_meshes.append(_part(shoulder, Props._box(0.14, 0.13, 0.16), skin, Vector3(0, -0.75, 0)))
		_biped_arms.append(shoulder)
		if side > 0:
			_hand = _pivot(shoulder, Vector3(0, -0.78, -0.02))

	if hunched:
		torso.rotation.x = -0.26  # lean forward (toward -Z)
		head.rotation.x = 0.18
		rig.position.y = -0.07
		for arm in _biped_arms:
			arm.scale = Vector3(1.15, 1.1, 1.15)
	rig.scale = Vector3(s, s, s)
	_death_axis = "z"
	_base_y = rig.position.y


func set_weapon(wtype: String) -> void:
	if _hand == null:
		return
	for c in _hand.get_children():
		c.queue_free()
	if wtype == "":
		return
	var w := Props.build_weapon(wtype)
	w.rotation_degrees = Vector3(-75, 0, 0)  # blade forward (-Z), angled slightly up
	_hand.add_child(w)


func apply_equipment(equip: Dictionary) -> void:
	## Reflect equipped armor on the model. Colors come from each item's
	## "color" field in items.json (fallback: a neutral leather tone).
	_tint(_chest_meshes, equip.get("chest", ""), [_def_shirt.darkened(0.12), _def_shirt])
	_tint(_leg_meshes, equip.get("legs", ""), [_def_pants, _def_pants.darkened(0.15), _def_pants, _def_pants.darkened(0.15)])
	_tint(_boot_meshes, equip.get("feet", ""), [Color("3a2c1e"), Color("3a2c1e")])
	_tint(_glove_meshes, equip.get("hands", ""), [_def_skin, _def_skin])
	# Waist: colored belt + a buckle when something is equipped.
	var waist: String = equip.get("waist", "")
	_belt_mesh.material_override = Props.mat(_item_color(waist, Color("5a4428")))
	_buckle.visible = waist != ""
	# Shoulders: hidden until you earn some, then chunky and colored.
	var shoulder_item: String = equip.get("shoulder", "")
	for p in _pauldrons:
		p.visible = shoulder_item != ""
		if shoulder_item != "":
			p.material_override = Props.mat(_item_color(shoulder_item, Color("6a5a45")))
			p.scale = Vector3(1.25, 1.25, 1.25)
	# Helm.
	var head_item: String = equip.get("head", "")
	_helm.visible = head_item != ""
	if head_item != "":
		_helm.material_override = Props.mat(_item_color(head_item, Color("8a8a92")))


func _item_color(item_id: String, fallback: Color) -> Color:
	if item_id == "":
		return fallback
	var it := DB.item(item_id)
	if it.has("color"):
		return Color(it["color"])
	return Color("7a6a55")


func _tint(meshes: Array, item_id: String, fallbacks: Array) -> void:
	for i in meshes.size():
		var c: Color = fallbacks[i % fallbacks.size()] if item_id == "" else _item_color(item_id, fallbacks[0])
		if item_id != "" and i % 2 == 1:
			c = c.darkened(0.12)
		(meshes[i] as MeshInstance3D).material_override = Props.mat(c)


# ---------------------------------------------------------------- creatures

func build_creature(shape: String, color: Color, s: float = 1.0) -> void:
	_mk_rig()
	var dark := color.darkened(0.25)
	var light := color.lightened(0.15)
	var eye := Color("18181f")
	match shape:
		"boar":
			_part(rig, Props._box(1.2, 0.7, 0.65), color, Vector3(0, 0.75, 0))
			_part(rig, Props._box(0.9, 0.12, 0.2), dark, Vector3(-0.05, 1.12, 0))  # mane ridge
			var head := _part(rig, Props._box(0.5, 0.5, 0.45), dark, Vector3(0.75, 0.7, 0))
			_part(head, Props._box(0.2, 0.18, 0.24), color.lightened(0.3), Vector3(0.32, -0.08, 0))
			_part(head, Props._box(0.04, 0.06, 0.06), eye, Vector3(0.25, 0.12, 0.16))
			_part(head, Props._box(0.04, 0.06, 0.06), eye, Vector3(0.25, 0.12, -0.16))
			_part(head, Props._cyl(0.0, 0.04, 0.22, 4), Color("e8e0c8"), Vector3(0.3, -0.1, 0.16), Vector3(0, 0, -110))
			_part(head, Props._cyl(0.0, 0.04, 0.22, 4), Color("e8e0c8"), Vector3(0.3, -0.1, -0.16), Vector3(0, 0, -110))
			_quad_legs(0.45, 0.25, 0.5, dark)
			_is_quadruped = true
		"wolf", "deer":
			_part(rig, Props._box(1.1, 0.5, 0.45), color, Vector3(0, 0.8, 0))
			var head2 := _part(rig, Props._box(0.38, 0.36, 0.34), light, Vector3(0.7, 0.95, 0))
			_part(head2, Props._box(0.24, 0.16, 0.2), dark, Vector3(0.28, -0.06, 0))
			_part(head2, Props._box(0.04, 0.05, 0.05), eye, Vector3(0.16, 0.08, 0.14))
			_part(head2, Props._box(0.04, 0.05, 0.05), eye, Vector3(0.16, 0.08, -0.14))
			_part(head2, Props._box(0.08, 0.16, 0.06), dark, Vector3(-0.08, 0.24, 0.1))
			_part(head2, Props._box(0.08, 0.16, 0.06), dark, Vector3(-0.08, 0.24, -0.1))
			if shape == "deer":
				_part(head2, Props._cyl(0.02, 0.03, 0.5, 4), Color("c8b890"), Vector3(0, 0.4, 0.12), Vector3(0, 0, 25))
				_part(head2, Props._cyl(0.02, 0.03, 0.5, 4), Color("c8b890"), Vector3(0, 0.4, -0.12), Vector3(0, 0, -25))
			_tail = _pivot(rig, Vector3(-0.6, 0.85, 0))
			_part(_tail, Props._box(0.4, 0.12, 0.12), dark, Vector3(-0.2, 0.06, 0), Vector3(0, 0, 20))
			_quad_legs(0.42, 0.18, 0.62, dark)
			_is_quadruped = true
		"raptor":
			var body := _part(rig, Props._box(0.9, 0.55, 0.5), color, Vector3(0, 0.95, 0))
			body.rotation_degrees = Vector3(0, 0, -12)
			var neck := _part(rig, Props._box(0.28, 0.5, 0.28), color, Vector3(0.45, 1.35, 0))
			neck.rotation_degrees = Vector3(0, 0, -25)
			var head3 := _part(rig, Props._box(0.5, 0.28, 0.26), dark, Vector3(0.75, 1.6, 0))
			_part(head3, Props._box(0.3, 0.1, 0.2), light, Vector3(0.2, -0.12, 0))
			_part(head3, Props._box(0.04, 0.05, 0.04), eye, Vector3(0.1, 0.08, 0.12))
			_part(head3, Props._box(0.04, 0.05, 0.04), eye, Vector3(0.1, 0.08, -0.12))
			# Little forearms
			_part(rig, Props._box(0.08, 0.3, 0.08), dark, Vector3(0.42, 1.0, 0.22), Vector3(-30, 0, 0))
			_part(rig, Props._box(0.08, 0.3, 0.08), dark, Vector3(0.42, 1.0, -0.22), Vector3(30, 0, 0))
			_tail = _pivot(rig, Vector3(-0.45, 1.0, 0))
			_part(_tail, Props._cyl(0.04, 0.16, 1.1, 5), dark, Vector3(-0.55, 0, 0), Vector3(0, 0, 90))
			for side in [-1, 1]:
				var hip := _pivot(rig, Vector3(-0.1, 0.75, side * 0.28))
				_part(hip, Props._box(0.22, 0.75, 0.2), dark, Vector3(0, -0.38, 0))
				_part(hip, Props._box(0.34, 0.1, 0.22), light, Vector3(0.08, -0.72, 0))
				_legs.append(hip)
		"scorpid":
			_part(rig, Props._box(1.1, 0.4, 0.8), color, Vector3(0, 0.35, 0))
			_part(rig, Props._box(0.7, 0.1, 0.6), dark, Vector3(-0.1, 0.58, 0))  # carapace ridge
			for side in [-1, 1]:
				var claw := _part(rig, Props._box(0.45, 0.25, 0.3), dark, Vector3(0.65, 0.3, side * 0.35))
				claw.rotation_degrees = Vector3(0, side * 20, 0)
				_part(claw, Props._box(0.2, 0.15, 0.1), light, Vector3(0.28, 0, side * 0.08))
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
			for e in 3:
				_part(rig, Props._sphere(0.045, 4), Color("c03030"), Vector3(0.58, 0.5 + e * 0.07, 0.1 - e * 0.1))
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
			_part(head4, Props._box(0.035, 0.04, 0.03), eye, Vector3(0.1, 0.05, 0.1))
			_part(head4, Props._box(0.035, 0.04, 0.03), eye, Vector3(0.1, 0.05, -0.1))
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
				var wing := _pivot(rig, Vector3(side * 0.3, 1.55, 0.15))
				_part(wing, Props._box(0.9, 0.06, 0.4), color.lightened(0.2), Vector3(side * 0.5, 0.1, 0.1), Vector3(0, 0, side * 15))
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
	rig.rotation.y = PI / 2.0  # creatures are authored facing +X; rotate to face -Z
	_death_axis = "x"          # after the yaw, X is the creature's roll axis


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
	tw.tween_property(rig, "rotation:" + _death_axis, PI / 2.0, 0.4)
	tw.parallel().tween_property(rig, "position:y", _base_y + 0.2, 0.4)


func revive_pose() -> void:
	dead = false
	rig.rotation.x = 0
	rig.rotation.z = 0
	rig.position.y = _base_y


func _process(delta: float) -> void:
	if dead:
		return
	_time += delta
	if sitting:
		rig.position.y = _base_y - 0.45
		for leg in _legs:
			leg.rotation.x = 1.3  # legs out in front (-Z)
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
		leg.rotation.x = swing * (1.0 if i % 2 == 0 else -1.0)
		i += 1
	if _attack_t > 0.0:
		_attack_t -= delta
		var k := sin((0.35 - _attack_t) / 0.35 * PI)
		if _biped_arms.size() > 1:
			# Positive X rotation swings the arm forward (toward -Z).
			_biped_arms[1].rotation.x = 2.2 * k
		else:
			# Quadruped lunge: pitch about the creature's lateral axis.
			rig.rotation.z = -0.35 * k
	elif casting and _biped_arms.size() > 1:
		_biped_arms[0].rotation.x = lerpf(_biped_arms[0].rotation.x, 2.4, delta * 8.0)
		_biped_arms[1].rotation.x = lerpf(_biped_arms[1].rotation.x, 2.4, delta * 8.0)
	else:
		var j := 0
		for arm in _biped_arms:
			arm.rotation.x = swing * (1.0 if j % 2 == 1 else -1.0) * 0.7
			j += 1
		if _is_quadruped:
			rig.rotation.z = 0
	for wing in _wings:
		wing.rotation.z = sin(_time * 6.0) * 0.35 * (1 if wing.position.x > 0 else -1)
	if _tail != null:
		_tail.rotation.y = sin(_time * 3.0) * 0.15
