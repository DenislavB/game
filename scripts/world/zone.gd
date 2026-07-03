class_name Zone
extends Node3D
## Builds a full playable zone from its JSON definition: terrain, sky, water,
## props, buildings, NPCs, mob spawns, gathering nodes and exits.

var zone_def: Dictionary
var terrain: ZoneTerrain
var mobs_root: Node3D
var rest_spots: Array = []  # Vector3 positions of campfires/inns (Well Rested)
var _rng := RandomNumberGenerator.new()

# Day/night cycle
const DAY_SPEED := 24.0 / 1200.0  # full day in 20 real minutes
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _day_sun_color: Color
var _day_sun_energy := 1.2
var _day_sky_top: Color
var _day_sky_horizon: Color
var _day_fog: Color


func build(zone_id: String) -> void:
	zone_def = DB.zones[zone_id]
	Game.current_zone_id = zone_id
	Game.zone_node = self
	_rng.seed = int(zone_def["seed"]) + 7

	terrain = ZoneTerrain.new()
	terrain.setup(zone_def)
	add_child(terrain)

	_build_environment()
	_build_water()
	_scatter_props()
	_place_buildings()
	_place_npcs()
	_spawn_mobs()
	_place_gather_nodes()
	_place_exits()


func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func graveyard_position() -> Vector3:
	var g: Dictionary = zone_def["graveyard"]
	return _on_ground(float(g["x"]), float(g["z"]))


func entrance_position(key: String) -> Transform3D:
	var e: Dictionary = zone_def.get("entrances", {}).get(key, zone_def["player_start"])
	var pos := _on_ground(float(e["x"]), float(e["z"]))
	var t := Transform3D(Basis(Vector3.UP, deg_to_rad(float(e.get("rot", 0)))), pos)
	return t


func start_position() -> Transform3D:
	var e: Dictionary = zone_def["player_start"]
	var pos := _on_ground(float(e["x"]), float(e["z"]))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(e.get("rot", 0)))), pos)


func _on_ground(x: float, z: float, lift: float = 0.3) -> Vector3:
	return Vector3(x, terrain.height_at(x, z) + lift, z)


# ---------------------------------------------------------------- atmosphere

func _build_environment() -> void:
	var amb: Dictionary = zone_def["ambience"]
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(amb["sky_top"])
	sky_mat.sky_horizon_color = Color(amb["sky_horizon"])
	sky_mat.ground_bottom_color = Color(amb["ground_low"]).darkened(0.3)
	sky_mat.ground_horizon_color = Color(amb["sky_horizon"])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	# Classic short draw distance feel: heavy distance fog.
	env.fog_enabled = true
	env.fog_light_color = Color(amb["fog"])
	env.fog_density = float(amb["fog_density"])
	env.fog_sky_affect = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(amb["sun_color"])
	sun.light_energy = float(amb["sun_energy"])
	sun.rotation_degrees = Vector3(float(amb.get("sun_angle", -50)), -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	# Remember the zone's daytime look; _process blends toward night.
	_sun = sun
	_env = env
	_sky_mat = sky_mat
	_day_sun_color = Color(amb["sun_color"])
	_day_sun_energy = float(amb["sun_energy"])
	_day_sky_top = Color(amb["sky_top"])
	_day_sky_horizon = Color(amb["sky_horizon"])
	_day_fog = Color(amb["fog"])


func _process(delta: float) -> void:
	Game.time_of_day = fmod(Game.time_of_day + delta * DAY_SPEED, 24.0)
	if _sun == null:
		return
	var h := Game.time_of_day
	# 0 at night, 1 at high noon, smooth dawn (5-8h) and dusk (17-20h).
	var daylight := clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0)
	if h < 5.0 or h > 20.0:
		daylight = 0.0
	var night_top := Color("0d1626")
	var night_horizon := Color("1a2a40")
	var night_fog := Color("141c2a")
	_sun.rotation_degrees.x = lerpf(-8.0, -70.0, daylight)
	_sun.light_energy = lerpf(0.12, _day_sun_energy, daylight)
	_sun.light_color = Color("8090c0").lerp(_day_sun_color, daylight)
	_env.ambient_light_energy = lerpf(0.35, 1.0, daylight)
	_env.fog_light_color = night_fog.lerp(_day_fog, daylight)
	_sky_mat.sky_top_color = night_top.lerp(_day_sky_top, daylight)
	_sky_mat.sky_horizon_color = night_horizon.lerp(_day_sky_horizon, daylight)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(zone_def["size"], zone_def["size"])
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(zone_def["ambience"]["water_color"], 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.metallic = 0.3
	mi.material_override = m
	mi.position.y = float(zone_def.get("water_level", 0.0))
	add_child(mi)


# ---------------------------------------------------------------- placement

func _clear_of_camps(x: float, z: float, margin: float = 8.0) -> bool:
	for f in zone_def.get("flatten", []):
		var d := Vector2(x - float(f["x"]), z - float(f["z"])).length()
		if d < float(f["r"]) + margin and not f.has("h_keep_props"):
			return false
	return true


func _good_prop_spot(x: float, z: float) -> bool:
	if not _clear_of_camps(x, z):
		return false
	if terrain.road_distance(x, z) < 8.0:
		return false
	return true


func _random_point(cx: float, cz: float, r: float) -> Vector2:
	var a := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * r
	var half := float(zone_def["size"]) * 0.5 - 25.0
	return Vector2(clampf(cx + cos(a) * d, -half, half), clampf(cz + sin(a) * d, -half, half))


func _scatter_props() -> void:
	var half := float(zone_def["size"]) * 0.5 - 25.0
	for pset in zone_def.get("props", []):
		var count := int(pset["count"])
		var color_hint: String = pset.get("color", "")
		for i in count:
			var p: Vector2
			if pset.has("x"):
				p = _random_point(float(pset["x"]), float(pset["z"]), float(pset["r"]))
			else:
				p = Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
			if not _good_prop_spot(p.x, p.y):
				continue
			var h := terrain.height_at(p.x, p.y)
			if h < float(zone_def.get("water_level", 0.0)) + 0.5:
				continue
			var prop := Props.build_prop(pset["type"], _rng, color_hint)
			prop.position = Vector3(p.x, h - 0.1, p.y)
			prop.rotation.y = _rng.randf() * TAU
			add_child(prop)


func _place_buildings() -> void:
	for b in zone_def.get("buildings", []):
		var btype := str(b["type"])
		# Campfires are props, not structures — zone files list them among
		# buildings for placement, so route them to the right factory.
		var node := Props.build_prop("campfire", _rng) if btype == "campfire" else Props.build_building(btype)
		var x := float(b["x"])
		var z := float(b["z"])
		if btype in ["campfire", "human_inn", "orc_hall"]:
			rest_spots.append(Vector3(x, 0, z))
		node.position = Vector3(x, terrain.height_at(x, z) - 0.05, z)
		node.rotation.y = deg_to_rad(float(b.get("rot", 0)))
		if b.has("scale"):
			node.scale = Vector3.ONE * float(b["scale"])
		add_child(node)


func _place_npcs() -> void:
	for ndef in zone_def.get("npcs", []):
		var npc := Npc.new()
		add_child(npc)
		npc.setup(ndef)
		var x := float(ndef["x"])
		var z := float(ndef["z"])
		npc.global_position = _on_ground(x, z)
		npc.rotation.y = deg_to_rad(float(ndef.get("rot", 0)))


func _spawn_mobs() -> void:
	mobs_root = Node3D.new()
	mobs_root.name = "Mobs"
	add_child(mobs_root)
	for spawn in zone_def.get("spawns", []):
		for i in int(spawn["count"]):
			var mob := Mob.new()
			mobs_root.add_child(mob)
			var level := _rng.randi_range(int(spawn["level"][0]), int(spawn["level"][1]))
			mob.setup(spawn["mob"], level, Vector2(float(spawn["x"]), float(spawn["z"])),
				float(spawn["r"]), float(spawn.get("respawn", 45)), self)
			mob.place_at_spawn(_rng)


func _place_gather_nodes() -> void:
	for gdef in zone_def.get("gather_nodes", []):
		var type_def: Dictionary = DB.professions["nodes"][gdef["type"]]
		for i in int(gdef["count"]):
			for attempt in 12:
				var p := _random_point(float(gdef["x"]), float(gdef["z"]), float(gdef["r"]))
				if not _good_prop_spot(p.x, p.y):
					continue
				var h := terrain.height_at(p.x, p.y)
				if h < float(zone_def.get("water_level", 0.0)) + 0.5:
					continue
				var gnode := GatherNode.new()
				add_child(gnode)
				gnode.setup(gdef["type"], type_def, float(gdef.get("respawn", 180)))
				gnode.global_position = Vector3(p.x, h, p.y)
				break


func _place_exits() -> void:
	for e in zone_def.get("exits", []):
		var area := Area3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = float(e["r"])
		shape.height = 30.0
		cs.shape = shape
		area.add_child(cs)
		area.collision_layer = 0
		area.collision_mask = 2  # player layer
		var x := float(e["x"])
		var z := float(e["z"])
		area.position = _on_ground(x, z, 5.0)
		var to: String = e["to"]
		var spawn: String = e["spawn"]
		area.body_entered.connect(func(body):
			if body == Game.player:
				Events.request_zone_travel.emit(to, spawn))
		add_child(area)
		# Signpost so the exit is findable.
		var post := Node3D.new()
		var sign_mesh := MeshInstance3D.new()
		sign_mesh.mesh = Props._cyl(0.08, 0.1, 3.0, 5)
		sign_mesh.material_override = Props.mat(Color("6a4a2a"))
		sign_mesh.position.y = 1.5
		post.add_child(sign_mesh)
		var board := MeshInstance3D.new()
		board.mesh = Props._box(1.6, 0.4, 0.08)
		board.material_override = Props.mat(Color("8a6a3a"))
		board.position.y = 2.6
		post.add_child(board)
		var label := Label3D.new()
		label.text = e.get("label", to)
		label.font_size = 40
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 3.4
		label.modulate = Color("ffe8a0")
		post.add_child(label)
		# Place the sign just off the exit trigger, toward the zone center.
		var dir := Vector2(x, z).normalized()
		var sx := x - dir.x * (float(e["r"]) + 3.0)
		var sz := z - dir.y * (float(e["r"]) + 3.0)
		post.position = _on_ground(sx, sz, 0.0)
		add_child(post)
