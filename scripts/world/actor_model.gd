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
var _attack_dur := 0.32
var _attack_style := "slash"
var _cast_style := "bolt"
var _time := 0.0
var _biped_arms: Array = []      # [arm_l, arm_r] shoulder pivots
var _biped_elbows: Array = []    # elbow pivots, index-matched to _biped_arms (humanoid only)
var _legs: Array = []            # leg/hip pivots (2 or 4)
var _biped_knees: Array = []     # knee pivots, index-matched to _legs (humanoid only)
var _wings: Array = []
var _tail: Node3D = null
var _hand: Node3D = null
var _base_y := 0.0
var _is_quadruped := false
var _death_axis := "z"           # humanoids topple sideways (z), creatures roll (x)

var _head_pivot: Node3D = null
var _torso_pivot: Node3D = null
var _torso_base_x := 0.0         # hunched races lean forward at rest
var _orb: MeshInstance3D = null  # glowing hand orb shown while casting

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
	# Race feature block (from races.json "model"): posture, tusks
	# ("short"/"long"), ears ("long"), beard, stature [x,y,z], eye_color/glow.
	var feat: Dictionary = cfg.get("features", {})
	var hunched: bool = feat.get("posture", cfg.get("posture", "upright")) == "hunched"
	var tusks: String = str(feat.get("tusks", "short" if cfg.get("tusks", false) else ""))
	var s: float = cfg.get("scale", 1.0)
	_def_shirt = shirt
	_def_pants = pants
	_def_skin = skin
	var boot_col := Color("3a2c1e")

	# --- Legs (front of the model is -Z). Each leg is hip -> knee -> foot
	# so it can bend at the knee instead of swinging as one rigid bar.
	for side in [-1, 1]:
		var hip := _pivot(rig, Vector3(side * 0.17, 0.95, 0))
		_leg_meshes.append(_part(hip, Props._box(0.22, 0.46, 0.24), pants, Vector3(0, -0.23, 0)))
		var knee := _pivot(hip, Vector3(0, -0.46, 0))
		_leg_meshes.append(_part(knee, Props._box(0.18, 0.42, 0.2), pants.darkened(0.15), Vector3(0, -0.21, 0)))
		_boot_meshes.append(_part(knee, Props._box(0.21, 0.16, 0.3), boot_col, Vector3(0, -0.44, -0.05)))
		_legs.append(hip)
		_biped_knees.append(knee)

	# --- Torso ---
	var torso := _pivot(rig, Vector3(0, 0.95, 0))
	_torso_pivot = torso
	_chest_meshes.append(_part(torso, Props._box(0.5, 0.26, 0.3), shirt.darkened(0.12), Vector3(0, 0.14, 0)))
	_chest_meshes.append(_part(torso, Props._box(0.62, 0.48, 0.36), shirt, Vector3(0, 0.47, 0)))
	_belt_mesh = _part(torso, Props._box(0.54, 0.12, 0.33), Color("5a4428"), Vector3(0, 0.0, 0))
	_buckle = _part(torso, Props._box(0.12, 0.09, 0.04), Color("c8a040"), Vector3(0, 0.0, -0.18))
	_buckle.visible = false

	# --- Head (face details at -Z so front/back is unmistakable) ---
	var head := _pivot(torso, Vector3(0, 0.71, 0))
	_head_pivot = head
	var eye_col := Color(str(feat.get("eye_color", "#1a1a22")))
	var eye_glow: bool = feat.get("eye_glow", false)
	_part(head, Props._cyl(0.09, 0.11, 0.12, 6), skin.darkened(0.1), Vector3(0, 0.05, 0))  # neck
	_part(head, Props._box(0.32, 0.34, 0.34), skin, Vector3(0, 0.28, 0))                    # skull
	_part(head, Props._box(0.05, 0.05, 0.02), eye_col, Vector3(0.08, 0.32, -0.175), Vector3.ZERO, eye_glow)
	_part(head, Props._box(0.05, 0.05, 0.02), eye_col, Vector3(-0.08, 0.32, -0.175), Vector3.ZERO, eye_glow)
	_part(head, Props._box(0.06, 0.09, 0.05), skin.darkened(0.12), Vector3(0, 0.26, -0.19))  # nose
	_part(head, Props._box(0.34, 0.1, 0.32), hair, Vector3(0, 0.47, 0.02))                   # hair top
	_part(head, Props._box(0.3, 0.2, 0.08), hair, Vector3(0, 0.32, 0.17))                    # hair back
	if tusks != "":
		_part(head, Props._box(0.28, 0.11, 0.12), skin.darkened(0.08), Vector3(0, 0.13, -0.13))  # jaw
		var tl := 0.16 if tusks == "short" else 0.3
		var tr := 0.04 if tusks == "short" else 0.05
		var tx := 0.09 if tusks == "short" else 0.12
		_part(head, Props._cyl(0.0, tr, tl, 4), Color("e8e0c8"), Vector3(tx, 0.2, -0.19), Vector3(0, 0, -12))
		_part(head, Props._cyl(0.0, tr, tl, 4), Color("e8e0c8"), Vector3(-tx, 0.2, -0.19), Vector3(0, 0, 12))
	if str(feat.get("ears", "")) == "long":
		_part(head, Props._box(0.05, 0.2, 0.07), skin, Vector3(0.2, 0.4, 0.04), Vector3(0, 0, -28))
		_part(head, Props._box(0.05, 0.2, 0.07), skin, Vector3(-0.2, 0.4, 0.04), Vector3(0, 0, 28))
	if feat.get("beard", false):
		_part(head, Props._box(0.26, 0.24, 0.1), hair, Vector3(0, 0.06, -0.14))   # beard
		_part(head, Props._box(0.3, 0.06, 0.08), hair, Vector3(0, 0.2, -0.16))    # moustache
	_helm = _part(head, Props._box(0.37, 0.24, 0.38), Color("8a8a92"), Vector3(0, 0.44, 0))
	_helm.visible = false

	# --- Arms + hand attachment. Each arm is shoulder -> elbow -> hand so
	# swings and casts can bend naturally instead of windmilling straight.
	for side in [-1, 1]:
		var shoulder := _pivot(torso, Vector3(side * 0.41, 0.66, 0))
		var pauldron := _part(shoulder, Props._box(0.26, 0.18, 0.3), shirt.darkened(0.2), Vector3(side * 0.02, 0.04, 0))
		pauldron.visible = cfg.get("dressed", true)  # NPCs/mobs look dressed; player earns them
		_pauldrons.append(pauldron)
		_part(shoulder, Props._box(0.16, 0.34, 0.18), shirt, Vector3(0, -0.17, 0))           # upper arm / sleeve
		var elbow := _pivot(shoulder, Vector3(0, -0.34, 0))
		_part(elbow, Props._box(0.13, 0.32, 0.15), skin, Vector3(0, -0.16, 0))               # forearm
		_glove_meshes.append(_part(elbow, Props._box(0.14, 0.13, 0.16), skin, Vector3(0, -0.3, 0)))
		_biped_arms.append(shoulder)
		_biped_elbows.append(elbow)
		if side > 0:
			_hand = _pivot(elbow, Vector3(0, -0.32, -0.02))

	if hunched:
		torso.rotation.x = -0.26  # lean forward (toward -Z)
		head.rotation.x = 0.18
		rig.position.y = -0.07
		for arm in _biped_arms:
			arm.scale = Vector3(1.15, 1.1, 1.15)
	_torso_base_x = torso.rotation.x
	# --- Free-form detail parts (Spore-style, placed in the Character Editor) ---
	for part in feat.get("parts", []):
		_add_detail_part(part)

	var stature: Array = feat.get("stature", [1.0, 1.0, 1.0])
	rig.scale = Vector3(float(stature[0]) * s, float(stature[1]) * s, float(stature[2]) * s)
	_death_axis = "z"
	_base_y = rig.position.y


func _add_detail_part(part: Dictionary) -> void:
	## part: {shape, attach ("head"/"torso"), color "#hex", pos [x,y,z],
	##        rot [x,y,z] degrees, size [x,y,z], mirror bool}
	var parent := _head_pivot if str(part.get("attach", "head")) == "head" else _torso_pivot
	if parent == null:
		return
	var color := Color(str(part.get("color", "#e8e0c8")))
	var size_a: Array = part.get("size", [0.1, 0.1, 0.1])
	var size := Vector3(float(size_a[0]), float(size_a[1]), float(size_a[2]))
	var pos_a: Array = part.get("pos", [0, 0, 0])
	var pos := Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
	var rot_a: Array = part.get("rot", [0, 0, 0])
	var rot := Vector3(float(rot_a[0]), float(rot_a[1]), float(rot_a[2]))
	var mesh: Mesh
	match str(part.get("shape", "box")):
		"sphere":
			mesh = Props._sphere(maxf(size.x, 0.01), 6)
		"cone":
			mesh = Props._cyl(0.0, maxf(size.x, 0.01), maxf(size.y, 0.01), 5)
		"cylinder":
			mesh = Props._cyl(maxf(size.x, 0.01), maxf(size.x, 0.01), maxf(size.y, 0.01), 6)
		_:
			mesh = Props._box(maxf(size.x, 0.01), maxf(size.y, 0.01), maxf(size.z, 0.01))
	_part(parent, mesh, color, pos, rot)
	if part.get("mirror", false):
		# Mirrored twin across the X axis (tusks, horns, ears...).
		_part(parent, mesh, color, Vector3(-pos.x, pos.y, pos.z), Vector3(rot.x, -rot.y, -rot.z))


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
	if _belt_mesh == null:
		return  # creature model (e.g. druid form) — nothing to dress
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
		"bear":
			_part(rig, Props._box(1.3, 0.85, 0.8), color, Vector3(0, 0.9, 0))
			_part(rig, Props._box(0.7, 0.25, 0.6), dark, Vector3(-0.25, 1.35, 0))  # shoulder hump
			var bhead := _part(rig, Props._box(0.5, 0.45, 0.48), color, Vector3(0.85, 1.05, 0))
			_part(bhead, Props._box(0.24, 0.2, 0.26), light, Vector3(0.3, -0.1, 0))  # snout
			_part(bhead, Props._box(0.06, 0.05, 0.08), Color("2a1a12"), Vector3(0.44, -0.08, 0))  # nose tip
			_part(bhead, Props._box(0.045, 0.05, 0.05), eye, Vector3(0.22, 0.1, 0.15))
			_part(bhead, Props._box(0.045, 0.05, 0.05), eye, Vector3(0.22, 0.1, -0.15))
			_part(bhead, Props._box(0.1, 0.12, 0.08), dark, Vector3(-0.1, 0.26, 0.16))  # ears
			_part(bhead, Props._box(0.1, 0.12, 0.08), dark, Vector3(-0.1, 0.26, -0.16))
			_quad_legs(0.5, 0.28, 0.55, dark)
			_is_quadruped = true
		"cat":
			_part(rig, Props._box(1.15, 0.42, 0.38), color, Vector3(0, 0.72, 0))
			var chead := _part(rig, Props._box(0.34, 0.3, 0.32), color, Vector3(0.68, 0.85, 0))
			_part(chead, Props._box(0.18, 0.12, 0.18), light, Vector3(0.22, -0.06, 0))  # muzzle
			_part(chead, Props._box(0.04, 0.045, 0.045), Color("d8e850"), Vector3(0.14, 0.08, 0.11))
			_part(chead, Props._box(0.04, 0.045, 0.045), Color("d8e850"), Vector3(0.14, 0.08, -0.11))
			_part(chead, Props._box(0.08, 0.12, 0.05), dark, Vector3(-0.06, 0.2, 0.1))  # ears
			_part(chead, Props._box(0.08, 0.12, 0.05), dark, Vector3(-0.06, 0.2, -0.1))
			_tail = _pivot(rig, Vector3(-0.55, 0.78, 0))
			_part(_tail, Props._cyl(0.03, 0.05, 0.8, 4), dark, Vector3(-0.4, 0.1, 0), Vector3(0, 0, 75))
			_quad_legs(0.42, 0.14, 0.55, dark)
			_is_quadruped = true
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
#
# Rotation.x convention on every shoulder/elbow/hip/knee pivot: 0 = hanging
# straight down, positive = swings forward toward -Z (the model's front).
# Elbows flex forward-only (>= 0), knees backward-only (<= 0).
#
# Attack styles animate the WHOLE body — torso twist ("tw"), torso pitch
# ("tp", negative leans forward), and a root lunge ("lg", forward) — so they
# read clearly even from the behind-the-back gameplay camera. Directional
# strikes run windup -> hit -> recover; flourishes rise and fall on a sine.
#
# Pose keys: lx/lz/le = left shoulder X/Z + elbow, rx/rz/re = right side,
# tw = torso yaw, tp = torso pitch delta, lg = forward lunge (meters).
# Shoulder Z sign: arm swings OUT from the body when lz < 0 / rz > 0.

const ATTACK_POSES := {
	"slash": {
		"w": { "rx": -0.4, "rz": 1.0, "re": 1.2, "lx": 0.3, "tw": 0.5, "tp": 0.05 },
		"h": { "rx": 1.5, "rz": -0.6, "re": 0.15, "lx": -0.3, "tw": -0.55, "tp": -0.12, "lg": 0.3 }
	},
	"chop": {
		"w": { "rx": -2.6, "re": 0.8, "lx": -0.5, "tw": 0.15, "tp": 0.2 },
		"h": { "rx": 1.7, "re": 0.1, "lx": 0.3, "tw": -0.15, "tp": -0.35, "lg": 0.3 }
	},
	"smash": {
		"w": { "lx": -2.6, "rx": -2.6, "le": 0.6, "re": 0.6, "tp": 0.25 },
		"h": { "lx": 1.6, "rx": 1.6, "le": 0.15, "re": 0.15, "tp": -0.45, "lg": 0.35 }
	},
	"stab": {
		"w": { "rx": 0.3, "re": 2.0, "lx": 0.5, "le": 0.4, "tw": 0.4, "lg": -0.1 },
		"h": { "rx": 1.2, "re": 0.05, "lx": -0.2, "tw": -0.35, "lg": 0.45 }
	},
	"claw": {
		"w": { "lx": 0.2, "lz": -1.1, "le": 0.9, "rx": 0.2, "rz": 1.1, "re": 0.9, "tp": 0.08 },
		"h": { "lx": 1.3, "lz": 0.3, "le": 0.4, "rx": 1.3, "rz": -0.3, "re": 0.4, "tp": -0.15, "lg": 0.25 }
	},
	"slam_ground": {
		"w": { "lx": -2.4, "rx": -2.4, "le": 0.5, "re": 0.5, "tp": 0.22 },
		"h": { "lx": 1.5, "rx": 1.5, "le": 0.2, "re": 0.2, "tp": -0.5, "lg": 0.15 }
	},
	"bolt": {
		"w": { "rx": 0.4, "re": 1.8, "lx": 0.9, "le": 0.3, "tw": 0.45, "tp": 0.06 },
		"h": { "rx": 1.6, "re": 0.05, "lx": -0.2, "tw": -0.4, "tp": -0.1, "lg": 0.3 }
	}
}

const FLOURISH_POSES := {
	"buff_self": { "lx": 2.2, "rx": 2.2, "le": 0.3, "re": 0.3, "lz": -0.5, "rz": 0.5, "tp": 0.12 },
	"heal": { "lx": 1.1, "rx": 1.1, "le": 0.6, "re": 0.6, "lz": 0.25, "rz": -0.25, "tp": -0.1 },
	"burst": { "lx": 0.5, "rx": 0.5, "le": 0.1, "re": 0.1, "lz": -1.3, "rz": 1.3, "tp": -0.1 }
}


func play_attack(style: String = "slash") -> void:
	_attack_style = style
	_attack_dur = _duration_for(style)
	_attack_t = _attack_dur


func start_cast(style: String = "bolt", color: Color = Color(0.65, 0.8, 1.0)) -> void:
	casting = true
	_cast_style = style
	_make_orb(color)


func stop_cast() -> void:
	casting = false
	_free_orb()


func _make_orb(color: Color) -> void:
	_free_orb()
	if _hand == null:
		return
	_orb = MeshInstance3D.new()
	_orb.mesh = Props._sphere(0.12, 6)
	_orb.material_override = Props.mat(color, true)
	_orb.position = Vector3(0, -0.06, -0.1)
	_hand.add_child(_orb)


func _free_orb() -> void:
	if _orb != null and is_instance_valid(_orb):
		_orb.queue_free()
	_orb = null


func _duration_for(style: String) -> float:
	match style:
		"chop", "slam_ground": return 0.55
		"smash", "spin": return 0.6
		"stab": return 0.3
		"claw": return 0.4
		"shoot": return 0.55
		_: return 0.45  # slash, bolt, heal, burst, buff_self


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
		var si := 0
		for leg in _legs:
			leg.rotation.x = 1.2  # thighs out in front (-Z)
			if si < _biped_knees.size():
				_biped_knees[si].rotation.x = -1.1  # shins bent under, cross-legged
			si += 1
		return

	_phase += delta * (11.0 if moving else 0.0)
	if not moving:
		rig.position.y = _base_y + sin(_time * 2.0) * 0.02
	else:
		rig.position.y = _base_y + absf(sin(_phase)) * 0.06

	_animate_legs()

	var attacking := _attack_t > 0.0
	if attacking:
		_attack_t -= delta
		var k := clampf(1.0 - _attack_t / _attack_dur, 0.0, 1.0)
		if _biped_arms.size() > 1:
			_apply_attack_pose(_attack_style, k)
		else:
			# Quadruped lunge: pitch about the creature's lateral axis.
			rig.rotation.z = -0.35 * sin(k * PI)
	elif casting:
		_apply_cast_pose(_cast_style, delta)
	else:
		_animate_arms_idle(delta)
		if _is_quadruped:
			rig.rotation.z = 0

	# Ease the body back to rest when no attack owns it.
	if not attacking:
		rig.position.z = lerpf(rig.position.z, 0.0, delta * 8.0)
		if _torso_pivot != null:
			var lean := -0.16 if moving else sin(_time * 2.0) * 0.02
			_torso_pivot.rotation.y = lerp_angle(_torso_pivot.rotation.y, 0.0, delta * 8.0)
			_torso_pivot.rotation.x = lerp_angle(_torso_pivot.rotation.x, _torso_base_x + lean, delta * 6.0)
	if not (attacking and _attack_style in ["spin", "shoot"]):
		rig.rotation.y = lerp_angle(rig.rotation.y, 0.0, delta * 6.0)

	for wing in _wings:
		wing.rotation.z = sin(_time * 6.0) * 0.35 * (1 if wing.position.x > 0 else -1)
	if _tail != null:
		_tail.rotation.y = sin(_time * 3.0) * 0.15


func _animate_legs() -> void:
	var hip_amt := 0.85 if moving else 0.0
	var knee_amt := 1.1 if moving else 0.0
	var use_knees := _biped_knees.size() == _legs.size() and not _biped_knees.is_empty()
	var i := 0
	for leg in _legs:
		var theta := _phase if i % 2 == 0 else _phase + PI
		leg.rotation.x = sin(theta) * hip_amt
		if use_knees:
			# Bends through the swing half of the stride (foot in the air),
			# straightens through stance (foot planted, pushing).
			_biped_knees[i].rotation.x = -maxf(0.0, cos(theta)) * knee_amt
		i += 1


func _animate_arms_idle(delta: float) -> void:
	var j := 0
	for arm in _biped_arms:
		var theta := _phase + PI if j % 2 == 0 else _phase
		if moving:
			# Runner's pump: bent elbows driving back and forth.
			arm.rotation.x = sin(theta) * 0.9
			arm.rotation.z = lerp_angle(arm.rotation.z, 0.0, delta * 6.0)
			if j < _biped_elbows.size():
				_biped_elbows[j].rotation.x = 0.75 + 0.25 * sin(theta)
		else:
			arm.rotation.x = lerp_angle(arm.rotation.x, 0.0, delta * 6.0)
			arm.rotation.z = lerp_angle(arm.rotation.z, 0.0, delta * 6.0)
			if j < _biped_elbows.size():
				_biped_elbows[j].rotation.x = lerp_angle(_biped_elbows[j].rotation.x, 0.1, delta * 6.0)
		j += 1


# ---------------------------------------------------------------- pose engine

func _blend_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in ["lx", "lz", "le", "rx", "rz", "re", "tw", "tp", "lg"]:
		out[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), t)
	return out


func _apply_pose(p: Dictionary) -> void:
	_set_arm(0, float(p.get("lx", 0.0)), float(p.get("le", 0.0)), float(p.get("lz", 0.0)))
	_set_arm(1, float(p.get("rx", 0.0)), float(p.get("re", 0.0)), float(p.get("rz", 0.0)))
	if _torso_pivot != null:
		_torso_pivot.rotation.y = float(p.get("tw", 0.0))
		_torso_pivot.rotation.x = _torso_base_x + float(p.get("tp", 0.0))
	rig.position.z = -float(p.get("lg", 0.0))


func _set_arm(idx: int, shoulder_x: float, elbow_x: float, shoulder_z: float = 0.0) -> void:
	if idx < _biped_arms.size():
		_biped_arms[idx].rotation.x = shoulder_x
		_biped_arms[idx].rotation.z = shoulder_z
	if idx < _biped_elbows.size():
		_biped_elbows[idx].rotation.x = elbow_x


func _lerp_arm(idx: int, shoulder_x: float, elbow_x: float, t: float, shoulder_z: float = 0.0) -> void:
	if idx < _biped_arms.size():
		var arm: Node3D = _biped_arms[idx]
		arm.rotation.x = lerp_angle(arm.rotation.x, shoulder_x, t)
		arm.rotation.z = lerp_angle(arm.rotation.z, shoulder_z, t)
	if idx < _biped_elbows.size():
		var elbow: Node3D = _biped_elbows[idx]
		elbow.rotation.x = lerp_angle(elbow.rotation.x, elbow_x, t)


# ---------------------------------------------------------------- attack styles

func _apply_attack_pose(style: String, k: float) -> void:
	var neutral := {}
	if ATTACK_POSES.has(style):
		# Windup (0-0.4, ease out) -> strike (0.4-0.65, sharp) -> recover.
		var poses: Dictionary = ATTACK_POSES[style]
		var windup: Dictionary = poses["w"]
		var hit: Dictionary = poses["h"]
		if k < 0.4:
			var t := k / 0.4
			_apply_pose(_blend_pose(neutral, windup, t * (2.0 - t)))
		elif k < 0.65:
			var t2 := (k - 0.4) / 0.25
			_apply_pose(_blend_pose(windup, hit, t2 * t2))
		else:
			var t3 := (k - 0.65) / 0.35
			_apply_pose(_blend_pose(hit, neutral, smoothstep(0.0, 1.0, t3)))
		return
	if FLOURISH_POSES.has(style):
		_apply_pose(_blend_pose(neutral, FLOURISH_POSES[style], sin(k * PI)))
		return
	match style:
		"shoot":
			_shoot_pose(k)
		"spin":
			rig.rotation.y = TAU * smoothstep(0.0, 1.0, k)
			var f := sin(k * PI)
			_apply_pose(_blend_pose(neutral,
				{ "lx": 0.4, "rx": 0.4, "lz": -1.3, "rz": 1.3, "le": 0.2, "re": 0.2, "tp": -0.05 }, f))
		_:
			_apply_pose(_blend_pose(neutral, ATTACK_POSES["bolt"]["h"], sin(k * PI)))


func _shoot_pose(k: float) -> void:
	## Archer: turn side-on, extend the bow arm, draw with the other
	## hand, release, then square back up. Very distinct silhouette.
	var stance := { "lx": 1.4, "le": 0.05, "rx": 1.1, "re": 0.3 }
	var drawn := { "lx": 1.4, "le": 0.05, "rx": 0.8, "re": 1.6, "tw": 0.12 }
	var released := { "lx": 1.4, "le": 0.05, "rx": 1.45, "re": 0.05, "tw": -0.08 }
	if k < 0.2:
		var t := k / 0.2
		rig.rotation.y = lerpf(0.0, 0.7, smoothstep(0.0, 1.0, t))
		_apply_pose(_blend_pose({}, stance, t))
	elif k < 0.6:
		rig.rotation.y = 0.7
		_apply_pose(_blend_pose(stance, drawn, smoothstep(0.0, 1.0, (k - 0.2) / 0.4)))
	elif k < 0.75:
		rig.rotation.y = 0.7
		var t2 := (k - 0.6) / 0.15
		_apply_pose(_blend_pose(drawn, released, t2 * t2))
	else:
		var t3 := (k - 0.75) / 0.25
		rig.rotation.y = lerpf(0.7, 0.0, smoothstep(0.0, 1.0, t3))
		_apply_pose(_blend_pose(released, {}, smoothstep(0.0, 1.0, t3)))


# ---------------------------------------------------------------- cast styles
#
# Held continuously (via start_cast/stop_cast) for the duration of a cast
# bar or channel; eases toward the pose every frame so it reads as a
# sustained stance. A glowing orb pulses in the casting hand throughout.

func _apply_cast_pose(style: String, delta: float) -> void:
	if _biped_arms.size() < 2:
		return
	if _orb != null and is_instance_valid(_orb):
		_orb.scale = Vector3.ONE * (0.85 + 0.35 * sin(_time * 7.0))
	var t := delta * 8.0
	match style:
		"heal":
			_lerp_arm(0, 1.1, 0.6, t, 0.25)
			_lerp_arm(1, 1.1, 0.6, t, -0.25)
		"burst":
			_lerp_arm(0, 0.5, 0.1, t, -1.3)
			_lerp_arm(1, 0.5, 0.1, t, 1.3)
		"channel_bolt":
			_lerp_arm(0, 1.2, 0.3, t)
			_lerp_arm(1, 1.4, 0.3, t)
		"channel_heal":
			_lerp_arm(0, 2.0, 0.3, t, -0.4)
			_lerp_arm(1, 2.0, 0.3, t, 0.4)
		"channel_drain":
			_lerp_arm(0, 1.1, 0.5, t)
			_lerp_arm(1, 1.3, 0.4, t)
		"summon":
			_lerp_arm(0, 2.2, 0.3, t, -0.5)
			_lerp_arm(1, 2.2, 0.3, t, 0.5)
		"gather":
			# Kneel down and work at the node.
			rig.position.y = lerpf(rig.position.y, _base_y - 0.35, t)
			var gi := 0
			for leg in _legs:
				leg.rotation.x = lerp_angle(leg.rotation.x, 0.5, t)
				if gi < _biped_knees.size():
					_biped_knees[gi].rotation.x = lerp_angle(_biped_knees[gi].rotation.x, -1.7, t)
				gi += 1
			_lerp_arm(0, 1.1, 0.7, t)
			_lerp_arm(1, 1.1, 0.7, t)
		_:  # "bolt" and unmatched: hands raised forward, aiming
			_lerp_arm(0, 1.3, 0.35, t)
			_lerp_arm(1, 1.5, 0.35, t)
