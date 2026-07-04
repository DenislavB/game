class_name Scenes
## Composite "set-pieces": named clusters of props and primitives that tell
## a small environmental story or form a landmark you can navigate toward.
## A zone JSON lists them in a "scenes" array ({type, x, z, rot}); the zone
## builder drops each at ground height. Everything is deterministic from a
## seeded RNG so a given scene looks the same every load.
##
## Two flavours live here:
##   * Vistas  — big, silhouette-readable landmarks (great tree, waterfall
##               overlook, standing stones, ruined tower).
##   * Scenes  — human-scale tableaus with implied history (abandoned camp,
##               wrecked wagon, battlefield, farm plot, fishing dock).

const P := preload("res://scripts/world/props.gd")


static func build(type: String, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	match type:
		"abandoned_camp":
			_abandoned_camp(n, rng)
		"wrecked_wagon":
			_wrecked_wagon(n, rng)
		"battlefield":
			_battlefield(n, rng)
		"standing_stones":
			_standing_stones(n, rng)
		"ruined_tower":
			_ruined_tower(n, rng)
		"fishing_dock":
			_fishing_dock(n, rng)
		"wayshrine":
			_wayshrine(n, rng)
		"farm_plot":
			_farm_plot(n, rng)
		"overlook":
			_overlook(n, rng)
		"great_tree":
			_great_tree(n, rng)
		"bonfire_ring":
			_bonfire_ring(n, rng)
		"hunters_blind":
			_hunters_blind(n, rng)
		"market_row":
			_market_row(n, rng)
		"grave_row":
			_grave_row(n, rng)
		_:
			pass
	return n


static func _add(parent: Node3D, type: String, rng: RandomNumberGenerator, pos: Vector3, rot_y := 0.0, color := "") -> Node3D:
	var p := P.build_prop(type, rng, color)
	p.position = pos
	p.rotation.y = deg_to_rad(rot_y)
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ scenes

static func _abandoned_camp(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A cold camp someone left in a hurry: dead fire, a slumping tent,
	# a couple of crates and scattered bones.
	var ring := Node3D.new()  # a burnt-out fire: charred stones, no flame
	for i in 5:
		var a := TAU * i / 5.0
		P._mesh(ring, P._sphere(0.22, 5), Color("3a3632"), Vector3(cos(a) * 0.55, 0.1, sin(a) * 0.55))
	P._mesh(ring, P._cyl(0.05, 0.1, 0.5, 5), Color("2a2622"), Vector3(0.1, 0.2, 0), Vector3(0, 0, 70))  # charred log
	n.add_child(ring)
	var tent := P.build_building("tent")
	tent.position = Vector3(-2.6, 0, -1.2)
	tent.rotation.y = deg_to_rad(rng.randf_range(120, 200))
	tent.rotation.z = deg_to_rad(-8)  # collapsing
	n.add_child(tent)
	_add(n, "crate", rng, Vector3(2.2, 0, 0.5), rng.randf() * 90)
	_add(n, "barrel", rng, Vector3(2.6, 0, -0.9))
	_add(n, "bones", rng, Vector3(-1.0, 0, 2.2), rng.randf() * 180)
	_add(n, "log", rng, Vector3(1.4, 0, 2.4), 20)


static func _wrecked_wagon(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A cart tipped on its side, cargo spilled across the road.
	var wagon := _add(n, "wagon", rng, Vector3(0, 0.4, 0), 0)
	wagon.rotation.z = deg_to_rad(62)  # tipped over
	_add(n, "crate", rng, Vector3(2.0, 0, 0.6), 25)
	_add(n, "crate", rng, Vector3(2.8, 0, -0.4), -15)
	_add(n, "barrel", rng, Vector3(1.4, 0, -1.6)).rotation.z = deg_to_rad(80)
	_add(n, "pebbles", rng, Vector3(1.0, 0, 1.6))
	for i in rng.randi_range(2, 4):
		_add(n, "bones", rng, Vector3(rng.randf_range(-2, 3), 0, rng.randf_range(-2, 3)), rng.randf() * 180)


static func _battlefield(n: Node3D, rng: RandomNumberGenerator) -> void:
	# Old carnage: weapons stuck in the dirt, a broken banner, scattered bone.
	var wtypes := ["sword", "axe", "mace"]
	for i in rng.randi_range(5, 8):
		var w := P.build_weapon(wtypes[rng.randi() % wtypes.size()])
		w.position = Vector3(rng.randf_range(-6, 6), 0.1, rng.randf_range(-6, 6))
		w.rotation = Vector3(deg_to_rad(rng.randf_range(150, 210)), rng.randf() * TAU, deg_to_rad(rng.randf_range(-20, 20)))
		n.add_child(w)
	for i in rng.randi_range(3, 5):
		_add(n, "bones", rng, Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)), rng.randf() * 180)
	var banner := _add(n, "banner", rng, Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), rng.randf() * 90, "#3a4a6a")
	banner.rotation.z = deg_to_rad(rng.randf_range(18, 32))  # leaning, defeated
	_add(n, "log", rng, Vector3(4, 0, -3), 40)


static func _standing_stones(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A druidic ring — a proper vista and a natural quest/landmark spot.
	var count := 6
	var radius := 6.0
	for i in count:
		var a := TAU * i / count
		_add(n, "standing_stone", rng, Vector3(cos(a) * radius, 0, sin(a) * radius), rad_to_deg(a) + 90, "#5f5f58")
	# A low central altar.
	P._mesh(n, P._cyl(1.2, 1.4, 0.6, 8), Color("55554e"), Vector3(0, 0.3, 0))
	P._mesh(n, P._cyl(1.0, 1.0, 0.15, 8), Color("6a6a60"), Vector3(0, 0.65, 0))


static func _ruined_tower(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A broken watchtower — a tall snapped shell with rubble around the base.
	P._mesh(n, P._cyl(2.4, 2.8, 6.5, 8), Color("8a8478"), Vector3(0, 3.25, 0))
	# Jagged broken top: a few blocks of crenellation, uneven heights.
	for i in 6:
		var a := TAU * i / 6.0
		if rng.randf() < 0.6:
			P._mesh(n, P._box(0.7, rng.randf_range(0.5, 1.4), 0.7), Color("8a8478"),
				Vector3(cos(a) * 2.2, 6.6, sin(a) * 2.2))
	P._mesh(n, P._box(1.2, 2.0, 0.3), Color("3a2e22"), Vector3(0, 1.0, 2.7))  # doorway
	var sh := CylinderShape3D.new()
	sh.radius = 2.7
	sh.height = 6.5
	P._collider(n, sh, Vector3(0, 3.25, 0))
	for i in rng.randi_range(4, 7):
		_add(n, "rock", rng, Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)), 0, "#8a8478")


static func _fishing_dock(n: Node3D, rng: RandomNumberGenerator) -> void:
	# Planks reaching out over the water on posts, with a barrel and net.
	var length := 8
	for i in length:
		P._mesh(n, P._box(2.0, 0.15, 1.2), Color("6a4a30"), Vector3(0, 0.1, -i * 1.2))
		if i % 2 == 0:
			for sx in [-0.9, 0.9]:
				P._mesh(n, P._cyl(0.12, 0.14, 2.0, 5), Color("5a3a24"), Vector3(sx, -0.9, -i * 1.2))
	_add(n, "barrel", rng, Vector3(0.6, 0.2, -0.4))
	_add(n, "crate", rng, Vector3(-0.5, 0.2, -1.4), 30)
	# A little rowboat tied at the end.
	var boat := Node3D.new()
	P._mesh(boat, P._box(1.0, 0.5, 2.6), Color("7a5636"), Vector3(0, 0, 0))
	P._mesh(boat, P._box(0.7, 0.3, 2.2), Color("3a2a1a"), Vector3(0, 0.2, 0))
	boat.position = Vector3(1.6, -0.3, -length * 1.2 + 0.5)
	boat.rotation.y = deg_to_rad(20)
	n.add_child(boat)


static func _wayshrine(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A little roadside shrine with a soft light — a rest/landmark beat.
	P._mesh(n, P._box(1.4, 0.4, 1.4), Color("8a8478"), Vector3(0, 0.2, 0))
	P._mesh(n, P._box(0.9, 1.6, 0.9), Color("9a9488"), Vector3(0, 1.2, 0))
	P._mesh(n, P._cyl(0.0, 0.8, 0.7, 4), Color("6a5a4a"), Vector3(0, 2.35, 0), Vector3(0, 45, 0))
	P._mesh(n, P._sphere(0.22, 6), Color("ffe8a0"), Vector3(0, 2.0, 0), Vector3.ZERO, Vector3.ONE, true)
	var light := OmniLight3D.new()
	light.light_color = Color("ffe0a0")
	light.omni_range = 7.0
	light.position = Vector3(0, 2.0, 0)
	n.add_child(light)
	_add(n, "flowers", rng, Vector3(1.0, 0, 0.6))
	_add(n, "flowers", rng, Vector3(-0.9, 0, 0.7))


static func _farm_plot(n: Node3D, rng: RandomNumberGenerator) -> void:
	# Tilled rows, a scarecrow, hay bales and a fence — signs of settlement.
	for i in 5:
		P._mesh(n, P._box(6.0, 0.15, 0.5), Color("5a3f28"), Vector3(0, 0.08, -3 + i * 1.3))
	_add(n, "scarecrow", rng, Vector3(0, 0, 0.5), 180)
	_add(n, "hay_bale", rng, Vector3(3.4, 0, 2.5), rng.randf() * 90)
	_add(n, "hay_bale", rng, Vector3(4.4, 0, 1.8), rng.randf() * 90)
	for i in 4:
		_add(n, "fence", rng, Vector3(-4.0 + i * 2.3, 0, -3.5), 0)


static func _overlook(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A vista point: a cairn, a bench, and a signpost inviting you to stop.
	P._mesh(n, P._sphere(0.7, 6), Color("7a7266"), Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
	P._mesh(n, P._sphere(0.5, 6), Color("8a8276"), Vector3(0, 1.0, 0))
	P._mesh(n, P._sphere(0.32, 6), Color("9a9286"), Vector3(0, 1.5, 0))  # a stacked cairn
	# Bench.
	var bench := Node3D.new()
	P._mesh(bench, P._box(1.8, 0.12, 0.5), Color("6a4a30"), Vector3(0, 0.5, 0))
	P._mesh(bench, P._box(1.8, 0.5, 0.12), Color("6a4a30"), Vector3(0, 0.75, -0.2))
	for bx in [-0.7, 0.7]:
		P._mesh(bench, P._box(0.12, 0.5, 0.4), Color("5a3a24"), Vector3(bx, 0.25, 0))
	bench.position = Vector3(2.2, 0, 0.5)
	bench.rotation.y = deg_to_rad(-30)
	n.add_child(bench)
	_add(n, "signpost", rng, Vector3(-2.0, 0, 0.5), 40)


static func _great_tree(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A giant landmark tree, several times taller than the ambient trees,
	# with a knot of exposed roots and a canopy visible across the zone.
	P._mesh(n, P._cyl(1.1, 1.8, 9.0, 7), Color("5a3f2a"), Vector3(0, 4.5, 0))
	for i in 6:
		var a := TAU * i / 6.0
		P._mesh(n, P._cyl(0.3, 0.6, 2.4, 5), Color("5a3f2a"), Vector3(cos(a) * 1.2, 0.6, sin(a) * 1.2), Vector3(40, -rad_to_deg(a), 0))
	var canopy := Color("3e6a2c").lerp(Color("5a8a38"), rng.randf())
	P._mesh(n, P._sphere(5.5, 8), canopy, Vector3(0, 10.5, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
	P._mesh(n, P._sphere(3.6, 7), canopy.lightened(0.08), Vector3(-3.0, 9.0, 1.5))
	P._mesh(n, P._sphere(3.4, 7), canopy.darkened(0.08), Vector3(3.2, 9.4, -1.2))
	var sh := CylinderShape3D.new()
	sh.radius = 1.7
	sh.height = 9.0
	P._collider(n, sh, Vector3(0, 4.5, 0))
	for i in rng.randi_range(3, 5):
		_add(n, "mushroom", rng, Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)))


static func _bonfire_ring(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A big central bonfire with log seats — a gathering place / rest spot.
	var fire := P.build_prop("campfire", rng)
	fire.scale = Vector3(2.2, 2.4, 2.2)
	n.add_child(fire)
	for i in 5:
		var a := TAU * i / 5.0
		_add(n, "log", rng, Vector3(cos(a) * 3.2, 0, sin(a) * 3.2), rad_to_deg(a))


static func _hunters_blind(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A raised lookout platform on stilts with a ladder.
	for sx in [-1.4, 1.4]:
		for sz in [-1.4, 1.4]:
			P._mesh(n, P._cyl(0.12, 0.15, 3.0, 5), Color("5a3a24"), Vector3(sx, 1.5, sz))
	P._mesh(n, P._box(3.4, 0.2, 3.4), Color("6a4a30"), Vector3(0, 3.0, 0))
	P._mesh(n, P._box(3.4, 0.6, 0.12), Color("6a4a30"), Vector3(0, 3.4, 1.6))
	P._mesh(n, P._box(0.12, 0.6, 3.4), Color("6a4a30"), Vector3(-1.6, 3.4, 0))
	# A canted roof.
	P._mesh(n, P._box(3.6, 0.12, 3.6), Color("4a3a2a"), Vector3(0, 4.4, 0), Vector3(-10, 0, 0))
	# Ladder.
	for i in 5:
		P._mesh(n, P._box(0.8, 0.06, 0.06), Color("4a3a2a"), Vector3(0, 0.4 + i * 0.55, 1.7))
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.0, 0.4, 3.0)
	P._collider(n, sh, Vector3(0, 3.0, 0))


static func _market_row(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A short row of stalls with crates and barrels — a busy town corner.
	var awnings := ["#b04838", "#3a6a8a", "#6a8a3a"]
	for i in 3:
		_add(n, "market_stall", rng, Vector3(i * 4.0, 0, 0), 0, awnings[i % 3])
	_add(n, "crate", rng, Vector3(1.8, 0, 1.2), 20)
	_add(n, "barrel", rng, Vector3(5.6, 0, 1.4))
	_add(n, "crate", rng, Vector3(9.0, 0, 1.0), -25)
	_add(n, "barrel", rng, Vector3(3.2, 0, -1.6))


static func _grave_row(n: Node3D, rng: RandomNumberGenerator) -> void:
	# A small graveyard: headstones in rows with a lantern post.
	for row in 2:
		for col in 4:
			if rng.randf() < 0.85:
				var hx := -3.0 + col * 2.0
				var hz := -1.5 + row * 3.0
				P._mesh(n, P._box(0.7, 1.0, 0.18), Color("7a7268"), Vector3(hx, 0.5, hz),
					Vector3(0, 0, rng.randf_range(-6, 6)))
				P._mesh(n, P._cyl(0.0, 0.42, 0.3, 4), Color("6a6258"), Vector3(hx, 1.05, hz))
	_add(n, "signpost", rng, Vector3(3.5, 0, 0), 0)
	P._mesh(n, P._sphere(0.18, 6), Color("ffd070"), Vector3(3.5, 2.0, 0), Vector3.ZERO, Vector3.ONE, true)
