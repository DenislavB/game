class_name Props
## Procedural low-poly props and buildings assembled from primitives.
## Everything is flat-shaded with a muted, classic-MMO-inspired palette.

static var _mats: Dictionary = {}


static func mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + ("e" if emissive else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.4
	_mats[key] = m
	return m


static func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emissive)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


static func _cyl(top: float, bottom: float, height: float, sides: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


static func _sphere(r: float, segs: int = 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(3, segs / 2)
	return s


static func _collider(parent: Node3D, shape: Shape3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	body.collision_layer = 1
	parent.add_child(body)


static func _trunk_collider(parent: Node3D, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_collider(parent, shape, Vector3(0, height * 0.5, 0))


# ------------------------------------------------------------------ nature

static func build_prop(type: String, rng: RandomNumberGenerator, color_hint: String = "") -> Node3D:
	var n := Node3D.new()
	var s := rng.randf_range(0.8, 1.3)
	match type:
		"tree":
			_mesh(n, _cyl(0.25, 0.4, 3.0, 5), Color("6a4a30"), Vector3(0, 1.5, 0))
			_mesh(n, _sphere(2.2, 7), Color("4e7a30").lerp(Color("6a9440"), rng.randf()), Vector3(0, 4.2, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
			_trunk_collider(n, 0.45, 3.0)
		"pine":
			_mesh(n, _cyl(0.2, 0.35, 2.2, 5), Color("5a3f2a"), Vector3(0, 1.1, 0))
			_mesh(n, _cyl(0.0, 1.9, 3.0, 7), Color("3c6032"), Vector3(0, 3.4, 0))
			_mesh(n, _cyl(0.0, 1.4, 2.4, 7), Color("446c38"), Vector3(0, 5.2, 0))
			_mesh(n, _cyl(0.0, 0.9, 1.8, 7), Color("4c783e"), Vector3(0, 6.6, 0))
			_trunk_collider(n, 0.4, 2.5)
		"palm":
			_mesh(n, _cyl(0.18, 0.3, 4.0, 5), Color("7a5c38"), Vector3(0, 2.0, 0), Vector3(0, 0, rng.randf_range(-8, 8)))
			for i in 6:
				var a := TAU * i / 6.0
				_mesh(n, _box(2.2, 0.08, 0.5), Color("4e8a3a"), Vector3(cos(a) * 1.0, 4.1, sin(a) * 1.0), Vector3(0, -rad_to_deg(a), -18))
			_trunk_collider(n, 0.35, 4.0)
		"acacia":
			_mesh(n, _cyl(0.18, 0.3, 3.4, 5), Color("6a4a30"), Vector3(0, 1.7, 0), Vector3(0, 0, rng.randf_range(-10, 10)))
			_mesh(n, _cyl(2.8, 3.4, 0.7, 8), Color("5e7a34"), Vector3(0, 3.8, 0))
			_trunk_collider(n, 0.35, 3.4)
		"dead_tree":
			_mesh(n, _cyl(0.12, 0.32, 3.2, 5), Color("5a4a3a"), Vector3(0, 1.6, 0), Vector3(0, 0, rng.randf_range(-6, 6)))
			_mesh(n, _cyl(0.06, 0.14, 1.6, 4), Color("5a4a3a"), Vector3(0.5, 2.8, 0), Vector3(0, 0, -40))
			_mesh(n, _cyl(0.05, 0.12, 1.2, 4), Color("5a4a3a"), Vector3(-0.4, 2.3, 0.2), Vector3(15, 0, 38))
			_trunk_collider(n, 0.35, 3.0)
		"cactus":
			_mesh(n, _cyl(0.35, 0.4, 2.6, 6), Color("3e7038"), Vector3(0, 1.3, 0))
			_mesh(n, _cyl(0.18, 0.2, 1.1, 5), Color("46783e"), Vector3(0.55, 1.6, 0), Vector3(0, 0, -30))
			_mesh(n, _cyl(0.16, 0.18, 0.9, 5), Color("46783e"), Vector3(-0.5, 1.2, 0), Vector3(0, 0, 32))
			_trunk_collider(n, 0.45, 2.6)
		"rock":
			var c := Color(color_hint) if color_hint != "" else Color("7a7a6a")
			var r := rng.randf_range(0.5, 1.6)
			_mesh(n, _sphere(r, 5), c, Vector3(0, r * 0.35, 0), Vector3(rng.randf_range(0, 30), rng.randf_range(0, 180), 0), Vector3(1.3, 0.7, 1.0))
			if r > 0.9:
				var shape := SphereShape3D.new()
				shape.radius = r * 0.8
				_collider(n, shape, Vector3(0, r * 0.3, 0))
		"bush":
			_mesh(n, _sphere(0.8, 6), Color("46743a"), Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1.2, 0.7, 1.1))
			_mesh(n, _sphere(0.5, 5), Color("528242"), Vector3(0.5, 0.4, 0.3))
		"dry_bush":
			_mesh(n, _sphere(0.7, 5), Color("8a7a42"), Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.1))
		"flowers":
			for i in rng.randi_range(3, 5):
				var p := Vector3(rng.randf_range(-0.6, 0.6), 0.25, rng.randf_range(-0.6, 0.6))
				_mesh(n, _cyl(0.02, 0.02, 0.5, 4), Color("4a7a34"), p)
				var fc := [Color("d8d8f0"), Color("e0c050"), Color("c05858")][rng.randi_range(0, 2)]
				_mesh(n, _sphere(0.12, 5), fc, p + Vector3(0, 0.28, 0))
		"campfire":
			for i in 5:
				var a2 := TAU * i / 5.0
				_mesh(n, _sphere(0.25, 5), Color("6a6a62"), Vector3(cos(a2) * 0.6, 0.12, sin(a2) * 0.6))
			_mesh(n, _cyl(0.0, 0.35, 0.8, 6), Color("ff8020"), Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE, true)
			var light := OmniLight3D.new()
			light.light_color = Color("ffa040")
			light.omni_range = 9.0
			light.position = Vector3(0, 1.2, 0)
			n.add_child(light)
		_:
			_mesh(n, _box(0.5, 0.5, 0.5), Color.MAGENTA, Vector3(0, 0.25, 0))
	n.scale = Vector3(s, s, s)
	return n


# ------------------------------------------------------------------ buildings

static func build_building(type: String) -> Node3D:
	var n := Node3D.new()
	match type:
		"orc_hut":
			_mesh(n, _cyl(2.6, 2.9, 2.6, 8), Color("8a5c34"), Vector3(0, 1.3, 0))
			_mesh(n, _cyl(0.1, 3.6, 2.6, 8), Color("6a3c24"), Vector3(0, 3.9, 0))
			_mesh(n, _box(1.2, 1.8, 0.2), Color("3a2a1a"), Vector3(0, 0.9, 2.85))
			var sh := CylinderShape3D.new()
			sh.radius = 2.8
			sh.height = 4.0
			_collider(n, sh, Vector3(0, 2, 0))
		"orc_hall":
			_mesh(n, _box(9, 3.4, 7), Color("7a5030"), Vector3(0, 1.7, 0))
			_mesh(n, _cyl(0.2, 6.4, 3.2, 4), Color("5a3020"), Vector3(0, 5.0, 0), Vector3(0, 45, 0))
			_mesh(n, _box(1.6, 2.4, 0.3), Color("3a2a1a"), Vector3(0, 1.2, 3.6))
			for sx in [-1, 1]:
				_mesh(n, _cyl(0.25, 0.3, 4.4, 5), Color("4a3020"), Vector3(sx * 4.8, 2.2, 3.4))
			var sh2 := BoxShape3D.new()
			sh2.size = Vector3(9, 4, 7)
			_collider(n, sh2, Vector3(0, 2, 0))
		"human_house":
			_mesh(n, _box(5, 2.8, 4.2), Color("c8b898"), Vector3(0, 1.4, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(5.6, 2.0, 4.8)
			_mesh(n, roof, Color("8a4a34"), Vector3(0, 3.8, 0))
			_mesh(n, _box(1.0, 1.8, 0.2), Color("4a3626"), Vector3(0.8, 0.9, 2.15))
			_mesh(n, _box(0.9, 0.9, 0.15), Color("87b2c8"), Vector3(-1.2, 1.5, 2.14))
			var sh3 := BoxShape3D.new()
			sh3.size = Vector3(5, 3, 4.2)
			_collider(n, sh3, Vector3(0, 1.5, 0))
		"human_inn":
			_mesh(n, _box(8, 3.6, 6), Color("b8a888"), Vector3(0, 1.8, 0))
			_mesh(n, _box(7.6, 0.4, 5.6), Color("6a4a30"), Vector3(0, 3.0, 0))
			var roof2 := PrismMesh.new()
			roof2.size = Vector3(8.8, 2.6, 6.8)
			_mesh(n, roof2, Color("7a4030"), Vector3(0, 4.9, 0))
			_mesh(n, _box(1.4, 2.0, 0.2), Color("4a3626"), Vector3(0, 1.0, 3.05))
			_mesh(n, _box(0.9, 0.9, 0.15), Color("e8c860"), Vector3(2.2, 2.0, 3.04))
			_mesh(n, _box(0.9, 0.9, 0.15), Color("e8c860"), Vector3(-2.2, 2.0, 3.04))
			var sh4 := BoxShape3D.new()
			sh4.size = Vector3(8, 4, 6)
			_collider(n, sh4, Vector3(0, 2, 0))
		"church":
			_mesh(n, _box(6, 4, 9), Color("d8ccb0"), Vector3(0, 2, 0))
			var roof3 := PrismMesh.new()
			roof3.size = Vector3(6.6, 2.4, 9.6)
			_mesh(n, roof3, Color("6a5a4a"), Vector3(0, 5.2, 0))
			_mesh(n, _box(2.2, 6.5, 2.2), Color("d8ccb0"), Vector3(0, 3.25, 5.2))
			_mesh(n, _cyl(0.05, 1.7, 2.2, 4), Color("6a5a4a"), Vector3(0, 7.6, 5.2), Vector3(0, 45, 0))
			_mesh(n, _box(1.4, 2.4, 0.2), Color("4a3626"), Vector3(0, 1.2, 6.35))
			var sh5 := BoxShape3D.new()
			sh5.size = Vector3(6, 5, 12)
			_collider(n, sh5, Vector3(0, 2.5, -0.5))
		"tower":
			_mesh(n, _cyl(2.2, 2.6, 8, 8), Color("9a9a8a"), Vector3(0, 4, 0))
			_mesh(n, _cyl(0.1, 3.0, 2.4, 8), Color("6a4a3a"), Vector3(0, 9.2, 0))
			_mesh(n, _box(1.1, 1.9, 0.3), Color("4a3626"), Vector3(0, 0.95, 2.5))
			var sh6 := CylinderShape3D.new()
			sh6.radius = 2.5
			sh6.height = 9.0
			_collider(n, sh6, Vector3(0, 4.5, 0))
		"well":
			_mesh(n, _cyl(1.0, 1.1, 1.0, 8), Color("8a8a7a"), Vector3(0, 0.5, 0))
			_mesh(n, _cyl(0.9, 0.9, 0.15, 8), Color("3a6a8a"), Vector3(0, 0.95, 0))
			for sx2 in [-1, 1]:
				_mesh(n, _box(0.15, 1.6, 0.15), Color("6a4a30"), Vector3(sx2 * 0.9, 1.4, 0))
			_mesh(n, _cyl(0.0, 1.5, 0.8, 6), Color("6a4a30"), Vector3(0, 2.5, 0))
			var sh7 := CylinderShape3D.new()
			sh7.radius = 1.1
			sh7.height = 1.2
			_collider(n, sh7, Vector3(0, 0.6, 0))
		"tent":
			var t := PrismMesh.new()
			t.size = Vector3(3.6, 2.4, 4.2)
			_mesh(n, t, Color("9a7a4a"), Vector3(0, 1.2, 0))
			var sh8 := BoxShape3D.new()
			sh8.size = Vector3(3.4, 2.2, 4.0)
			_collider(n, sh8, Vector3(0, 1.1, 0))
		"totem":
			_mesh(n, _cyl(0.4, 0.5, 4.2, 6), Color("7a4a2a"), Vector3(0, 2.1, 0))
			_mesh(n, _box(1.6, 0.5, 0.5), Color("8a5a30"), Vector3(0, 3.6, 0))
			_mesh(n, _box(0.9, 0.6, 0.6), Color("a86a30"), Vector3(0, 2.6, 0))
			_mesh(n, _sphere(0.35, 5), Color("d8b050"), Vector3(0, 4.3, 0))
			_trunk_collider(n, 0.55, 4.2)
		_:
			pass
	return n


# ------------------------------------------------------------------ gathering

static func build_gather_node(shape: String, color: Color) -> Node3D:
	var n := Node3D.new()
	match shape:
		"vein":
			_mesh(n, _sphere(0.9, 5), Color("6a6a5a"), Vector3(0, 0.35, 0), Vector3(0, 20, 0), Vector3(1.3, 0.7, 1.0))
			for i in 3:
				var a := TAU * i / 3.0 + 0.4
				_mesh(n, _box(0.25, 0.5, 0.25), color, Vector3(cos(a) * 0.5, 0.75, sin(a) * 0.5), Vector3(20, rad_to_deg(a), 15), Vector3.ONE, true)
		"herb":
			_mesh(n, _cyl(0.03, 0.03, 0.6, 4), Color("4a7a34"), Vector3(0, 0.3, 0))
			_mesh(n, _sphere(0.22, 5), color, Vector3(0, 0.65, 0), Vector3.ZERO, Vector3.ONE, true)
			_mesh(n, _sphere(0.14, 5), color, Vector3(0.25, 0.4, 0.1))
	return n


# ------------------------------------------------------------------ weapons

static func build_weapon(wtype: String) -> Node3D:
	var n := Node3D.new()
	match wtype:
		"sword":
			_mesh(n, _box(0.09, 1.1, 0.03), Color("c8c8d0"), Vector3(0, 0.75, 0))
			_mesh(n, _box(0.3, 0.08, 0.06), Color("8a6a30"), Vector3(0, 0.2, 0))
			_mesh(n, _cyl(0.04, 0.04, 0.3, 5), Color("5a3a20"), Vector3(0, 0.05, 0))
		"axe":
			_mesh(n, _cyl(0.045, 0.045, 1.2, 5), Color("6a4a2a"), Vector3(0, 0.6, 0))
			_mesh(n, _box(0.35, 0.3, 0.05), Color("b0b0b8"), Vector3(0.18, 1.05, 0))
		"mace":
			_mesh(n, _cyl(0.045, 0.045, 1.0, 5), Color("6a4a2a"), Vector3(0, 0.5, 0))
			_mesh(n, _sphere(0.18, 5), Color("9a9aa2"), Vector3(0, 1.0, 0))
		"staff":
			_mesh(n, _cyl(0.05, 0.05, 1.8, 5), Color("5a3a22"), Vector3(0, 0.9, 0))
			_mesh(n, _sphere(0.16, 6), Color("60c0e8"), Vector3(0, 1.85, 0), Vector3.ZERO, Vector3.ONE, true)
		"bow":
			_mesh(n, _box(0.05, 0.55, 0.05), Color("7a5a30"), Vector3(0, 0.45, 0.12), Vector3(30, 0, 0))
			_mesh(n, _box(0.05, 0.55, 0.05), Color("7a5a30"), Vector3(0, -0.45, 0.12), Vector3(-30, 0, 0))
			_mesh(n, _box(0.015, 1.25, 0.015), Color("d8d8d8"), Vector3(0, 0, 0.26))
		"dagger":
			_mesh(n, _box(0.06, 0.55, 0.02), Color("c8c8d0"), Vector3(0, 0.4, 0))
			_mesh(n, _cyl(0.035, 0.035, 0.2, 5), Color("5a3a20"), Vector3(0, 0.05, 0))
	return n
