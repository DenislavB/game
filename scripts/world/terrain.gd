class_name ZoneTerrain
extends StaticBody3D
## Heightmap terrain generated from noise, with flattened camp areas and
## roads carved along polylines. Vertex-colored, flat-shaded, low poly.

const STEP := 4.0
const ROAD_W := 4.5
const ROAD_BLEND := 12.0

var zone: Dictionary
var size: float
var noise: FastNoiseLite
var color_noise: FastNoiseLite
var _flatten: Array = []
var _road_segments: Array = []   # [{a: Vector2, b: Vector2, ha: float, hb: float}]


func setup(zone_def: Dictionary) -> void:
	zone = zone_def
	size = float(zone["size"])
	var t: Dictionary = zone["terrain"]

	noise = FastNoiseLite.new()
	noise.seed = int(zone["seed"])
	noise.frequency = float(t["noise_freq"])
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.2

	color_noise = FastNoiseLite.new()
	color_noise.seed = int(zone["seed"]) + 99
	color_noise.frequency = 0.02

	_flatten = zone.get("flatten", [])
	for f in _flatten:
		if not f.has("h"):
			f["h"] = _height_raw(float(f["x"]), float(f["z"]))

	for road in zone.get("roads", []):
		for i in road.size() - 1:
			var a := Vector2(float(road[i][0]), float(road[i][1]))
			var b := Vector2(float(road[i + 1][0]), float(road[i + 1][1]))
			_road_segments.append({
				"a": a, "b": b,
				"ha": _height_no_road(a.x, a.y),
				"hb": _height_no_road(b.x, b.y)
			})

	collision_layer = 1
	collision_mask = 0
	_build_mesh()


func _height_raw(x: float, z: float) -> float:
	var t: Dictionary = zone["terrain"]
	var h := noise.get_noise_2d(x, z) * float(t["height_scale"]) + float(t["base_height"])
	# Raise the outer rim so zones feel enclosed by hills.
	var edge := maxf(absf(x), absf(z)) / (size * 0.5)
	if edge > 0.82:
		h += pow((edge - 0.82) / 0.18, 2.0) * 40.0
	return h


func _height_no_road(x: float, z: float) -> float:
	var h := _height_raw(x, z)
	for f in _flatten:
		var d := Vector2(x - float(f["x"]), z - float(f["z"])).length()
		var r := float(f["r"])
		if d < r * 1.6:
			var k := clampf(1.0 - maxf(d - r, 0.0) / (r * 0.6), 0.0, 1.0)
			h = lerpf(h, float(f["h"]), smoothstep(0.0, 1.0, k))
	return h


func height_at(x: float, z: float) -> float:
	var h := _height_no_road(x, z)
	var best_d := 1e9
	var road_h := 0.0
	for s in _road_segments:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var p := Vector2(x, z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := (p - (a + ab * t)).length()
		if d < best_d:
			best_d = d
			road_h = lerpf(float(s["ha"]), float(s["hb"]), t)
	if best_d < ROAD_W:
		return road_h
	elif best_d < ROAD_BLEND:
		return lerpf(road_h, h, (best_d - ROAD_W) / (ROAD_BLEND - ROAD_W))
	return h


func road_distance(x: float, z: float) -> float:
	var best_d := 1e9
	for s in _road_segments:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var p := Vector2(x, z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best_d = minf(best_d, (p - (a + ab * t)).length())
	return best_d


func _vertex_color(x: float, z: float, h: float, slope: float) -> Color:
	var amb: Dictionary = zone["ambience"]
	var low := Color(amb["ground_low"])
	var high := Color(amb["ground_high"])
	var rock := Color(amb["ground_rock"])
	var road := Color(amb["road"])
	var k := clampf(color_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var c := low.lerp(high, k)
	if slope > 0.55:
		c = c.lerp(rock, clampf((slope - 0.55) / 0.3, 0.0, 1.0))
	var rd := road_distance(x, z)
	if rd < ROAD_W + 1.0:
		c = c.lerp(road, clampf(1.0 - rd / (ROAD_W + 1.0), 0.0, 1.0) * 0.85)
	var wl := float(zone.get("water_level", 0.0))
	if h < wl + 0.6:
		c = c.lerp(Color("7a6a48"), clampf((wl + 0.6 - h) / 2.0, 0.0, 0.8))
	return c


func _build_mesh() -> void:
	var n := int(size / STEP)
	var half := size * 0.5
	# Precompute the height grid.
	var heights: Array = []
	heights.resize(n + 1)
	for i in n + 1:
		var row: PackedFloat32Array = PackedFloat32Array()
		row.resize(n + 1)
		for j in n + 1:
			row[j] = height_at(-half + i * STEP, -half + j * STEP)
		heights[i] = row

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in n:
		for j in n:
			var x0 := -half + i * STEP
			var z0 := -half + j * STEP
			var h00: float = heights[i][j]
			var h10: float = heights[i + 1][j]
			var h01: float = heights[i][j + 1]
			var h11: float = heights[i + 1][j + 1]
			var slope := (absf(h10 - h00) + absf(h01 - h00)) / STEP
			var c := _vertex_color(x0 + STEP * 0.5, z0 + STEP * 0.5, h00, slope)
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + STEP, h10, z0)
			var v01 := Vector3(x0, h01, z0 + STEP)
			var v11 := Vector3(x0 + STEP, h11, z0 + STEP)
			st.set_color(c)
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v00)
			st.add_vertex(v11)
			st.add_vertex(v01)
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)

	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	add_child(cs)
