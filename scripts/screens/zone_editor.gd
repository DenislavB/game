class_name ZoneEditor
extends Node3D
## Zone Editor — drag-to-place world editing, in-game.
##
## Pick a zone, fly around it, and place props, buildings, NPCs, mob
## spawns and gather areas straight into the world. Everything edits a
## working copy of the zone's JSON definition and writes back to
## res://data/zones/<id>.json on Save.
##
## Controls:
##   WASD + mouse wheel .... fly / fly speed
##   Hold RMB + drag ....... look around
##   Palette click ......... pick a brush, LMB places, Esc/RMB cancels
##   LMB on an object ...... select it; drag to move it
##   R / Shift+R ........... rotate selection +/- 15 degrees
##   + / - ................. scale selection (props and buildings)
##   Delete ................ remove selection
##   Ctrl+Z ................ undo

signal closed

const FLY_SPEED_MIN := 6.0
const FLY_SPEED_MAX := 120.0
const UNDO_LIMIT := 50

# Palette contents. NPC kinds and mob/gather types come from data.
const PROP_TYPES := ["tree", "pine", "palm", "acacia", "dead_tree", "bush",
	"dry_bush", "flowers", "rock", "cactus", "tent", "totem", "well", "campfire"]
const BUILDING_TYPES := ["human_house", "human_inn", "church", "tower",
	"orc_hut", "orc_hall", "campfire"]
const SCENE_TYPES := ["great_tree", "standing_stones", "ruined_tower",
	"overlook", "waterfall", "abandoned_camp", "wrecked_wagon", "battlefield",
	"fishing_dock", "wayshrine", "farm_plot", "bonfire_ring", "hunters_blind",
	"market_row", "grave_row"]
# New filler/landmark props exposed in the editor palette too.
const EXTRA_PROP_TYPES := ["mushroom", "fern", "tall_grass", "reeds", "cattail",
	"lilypad", "pebbles", "bones", "log", "stump", "sapling", "crate", "barrel",
	"hay_bale", "fence", "signpost", "scarecrow", "standing_stone", "obelisk",
	"statue", "wagon", "market_stall", "banner", "windmill", "pennant"]

var zone_id := ""
var zdef: Dictionary = {}        # working copy; written back on Save
var zone: Zone = null

var cam: Camera3D
var _fly_speed := 30.0
var _looking := false

# One overlay node per editable JSON entry, kept in lockstep.
# Each record: {cat, entry (Dictionary ref into zdef), node}
var _objects: Array = []
var _overlay: Node3D = null

var _brush_cat := ""             # "" = no brush (select mode)
var _brush_type := ""
var _ghost: Node3D = null
var _selected: Dictionary = {}   # record from _objects, {} = none
var _sel_ring: MeshInstance3D = null
var _dragging := false
var _drag_before: Dictionary = {}  # zdef snapshot for the move's undo step

var _undo_stack: Array = []

# UI
var ui: CanvasLayer
var palette_box: VBoxContainer
var info_label: Label
var status_label: Label
var zone_pick: OptionButton
var cat_pick: OptionButton


func _ready() -> void:
	cam = Camera3D.new()
	cam.far = 900.0
	cam.position = Vector3(0, 80, 120)
	cam.rotation_degrees.x = -35
	add_child(cam)
	cam.current = true
	_build_ui()
	var first := ""
	for zid in DB.zones:
		first = str(zid)
		break
	_load_zone(first)


func _exit_tree() -> void:
	if Game.zone_node == zone:
		Game.zone_node = null


# ================================================================ zone load

func _load_zone(zid: String) -> void:
	zone_id = zid
	zdef = (DB.zones[zid] as Dictionary).duplicate(true)
	if zone != null and is_instance_valid(zone):
		zone.queue_free()
	zone = Zone.new()
	add_child(zone)
	zone.build(zid, true)  # terrain/sky/water only; we draw the rest
	_undo_stack.clear()
	_selected = {}
	_cancel_brush()
	_rebuild_overlay()
	_status("Editing %s — %d placeable objects." % [str(zdef.get("name", zid)), _objects.size()])


func _rebuild_overlay() -> void:
	## (Re)draw every editable object from the working definition.
	_objects.clear()
	_selected = {}
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = Node3D.new()
	add_child(_overlay)
	_sel_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.2
	ring.outer_radius = 1.45
	_sel_ring.mesh = ring
	_sel_ring.material_override = Props.mat(Color(1.0, 0.82, 0.0), true)
	_sel_ring.visible = false
	_overlay.add_child(_sel_ring)
	for b in zdef.get("buildings", []):
		_add_object("buildings", b)
	for p in zdef.get("placed_props", []):
		_add_object("placed_props", p)
	for n in zdef.get("npcs", []):
		_add_object("npcs", n)
	for s in zdef.get("spawns", []):
		_add_object("spawns", s)
	for g in zdef.get("gather_nodes", []):
		_add_object("gather_nodes", g)
	for sc in zdef.get("scenes", []):
		_add_object("scenes", sc)


func _add_object(cat: String, entry: Dictionary) -> Dictionary:
	var node := _make_visual(cat, entry)
	_overlay.add_child(node)
	_position_visual(node, entry)
	var rec := { "cat": cat, "entry": entry, "node": node }
	_objects.append(rec)
	return rec


func _make_visual(cat: String, entry: Dictionary) -> Node3D:
	match cat:
		"buildings":
			var btype := str(entry["type"])
			var rng := RandomNumberGenerator.new()
			return Props.build_prop("campfire", rng) if btype == "campfire" else Props.build_building(btype)
		"placed_props":
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = int(entry.get("x", 0)) * 31 + int(entry.get("z", 0))
			return Props.build_prop(str(entry["type"]), rng2)
		"scenes":
			var rng3 := RandomNumberGenerator.new()
			rng3.seed = int(entry.get("x", 0)) * 73856 ^ int(entry.get("z", 0)) * 19349
			return Scenes.build(str(entry["type"]), rng3)
		"npcs":
			return _marker(Color(0.35, 0.95, 0.35), str(entry.get("name", "NPC")), 0.0)
		"spawns":
			return _marker(Color(0.9, 0.25, 0.25),
				"%s x%d" % [str(entry.get("mob", "?")), int(entry.get("count", 1))],
				float(entry.get("r", 10)))
		"gather_nodes":
			return _marker(Color(0.4, 0.7, 1.0),
				"%s x%d" % [str(entry.get("type", "?")), int(entry.get("count", 1))],
				float(entry.get("r", 10)))
	return Node3D.new()


func _marker(color: Color, text: String, radius: float) -> Node3D:
	## Pin + floating label; area entries also show their radius ring.
	var root := Node3D.new()
	var post := MeshInstance3D.new()
	post.mesh = Props._cyl(0.12, 0.3, 2.6, 6)
	post.material_override = Props.mat(color, true)
	post.position.y = 1.3
	root.add_child(post)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 36
	lbl.pixel_size = 0.012
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 3.2
	lbl.modulate = color.lightened(0.3)
	root.add_child(lbl)
	if radius > 0.5:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.15
		torus.outer_radius = radius + 0.15
		ring.mesh = torus
		ring.material_override = Props.mat(Color(color, 0.5))
		ring.position.y = 0.4
		root.add_child(ring)
	return root


func _position_visual(node: Node3D, entry: Dictionary) -> void:
	var x := float(entry.get("x", 0))
	var z := float(entry.get("z", 0))
	node.position = Vector3(x, zone.terrain.height_at(x, z) - 0.05, z)
	node.rotation.y = deg_to_rad(float(entry.get("rot", 0)))
	if entry.has("scale"):
		node.scale = Vector3.ONE * float(entry["scale"])


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_fly_speed = minf(_fly_speed * 1.15, FLY_SPEED_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_fly_speed = maxf(_fly_speed / 1.15, FLY_SPEED_MIN)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and _brush_cat != "":
					_cancel_brush()
				else:
					_looking = mb.pressed
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_on_click(mb.position)
				elif _dragging:
					_end_drag()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _looking:
			cam.rotation.y -= mm.relative.x * 0.0038
			cam.rotation.x = clampf(cam.rotation.x - mm.relative.y * 0.0038, deg_to_rad(-85), deg_to_rad(60))
		elif _dragging and not _selected.is_empty():
			var hit := _ground_at(mm.position)
			if hit != Vector3.INF:
				_move_selected(hit)
		elif _brush_cat != "" and _ghost != null:
			var hit2 := _ground_at(mm.position)
			if hit2 != Vector3.INF:
				_ghost.position = hit2 - Vector3(0, 0.05, 0)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if _brush_cat != "":
				_cancel_brush()
			elif not _selected.is_empty():
				_set_selected({})
			else:
				closed.emit()
		elif k.keycode == KEY_Z and k.ctrl_pressed:
			_undo()
		elif k.keycode == KEY_DELETE and not _selected.is_empty():
			_delete_selected()
		elif k.keycode == KEY_R and not _selected.is_empty():
			_rotate_selected(-15.0 if k.shift_pressed else 15.0)
		elif k.keycode in [KEY_EQUAL, KEY_KP_ADD] and not _selected.is_empty():
			_scale_selected(1.15)
		elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] and not _selected.is_empty():
			_scale_selected(1.0 / 1.15)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += cam.global_transform.basis.x
	if dir.length_squared() > 0.01:
		cam.position += dir.normalized() * _fly_speed * delta
		var half := float(zdef.get("size", 800)) * 0.55
		cam.position.x = clampf(cam.position.x, -half, half)
		cam.position.z = clampf(cam.position.z, -half, half)
		cam.position.y = clampf(cam.position.y, 3.0, 260.0)
	if not _selected.is_empty() and is_instance_valid(_selected["node"]):
		_sel_ring.visible = true
		_sel_ring.position = (_selected["node"] as Node3D).position + Vector3(0, 0.35, 0)
	else:
		_sel_ring.visible = false


# ================================================================ picking

func _ground_at(screen_pos: Vector2) -> Vector3:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 1200.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"] as Vector3


func _on_click(screen_pos: Vector2) -> void:
	if _brush_cat != "":
		var ground := _ground_at(screen_pos)
		if ground != Vector3.INF:
			_place_brush(ground)
		return
	# Select: nearest object to the click ray, generous 3m grab radius.
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best: Dictionary = {}
	var best_d := 3.5
	for rec in _objects:
		var node := rec["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var to_obj := (node.position + Vector3(0, 1.2, 0)) - from
		var along := to_obj.dot(dir)
		if along < 1.0:
			continue
		var d := (to_obj - dir * along).length()
		if d < best_d:
			best_d = d
			best = rec
	_set_selected(best)
	if not best.is_empty():
		_drag_before = zdef.duplicate(true)
		_dragging = true


func _set_selected(rec: Dictionary) -> void:
	_selected = rec
	if rec.is_empty():
		info_label.text = "Nothing selected."
		return
	var e: Dictionary = rec["entry"]
	var what := str(e.get("type", e.get("mob", e.get("name", "object"))))
	info_label.text = "%s [%s]  (%d, %d)\nDrag to move — R rotate, +/- scale, Del remove" \
		% [what, str(rec["cat"]), int(e.get("x", 0)), int(e.get("z", 0))]


# ================================================================ editing ops

func _snapshot(desc: String) -> void:
	_undo_stack.append({ "desc": desc, "zdef": zdef.duplicate(true) })
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty():
		_status("Nothing to undo.")
		return
	var step: Dictionary = _undo_stack.pop_back()
	zdef = step["zdef"]
	_rebuild_overlay()
	_status("Undid: %s" % str(step["desc"]))


func _move_selected(ground: Vector3) -> void:
	var e: Dictionary = _selected["entry"]
	e["x"] = snappedf(ground.x, 0.5)
	e["z"] = snappedf(ground.z, 0.5)
	_position_visual(_selected["node"] as Node3D, e)
	_set_selected(_selected)  # refresh coords in the info line


func _end_drag() -> void:
	_dragging = false
	if _drag_before.is_empty():
		return
	# Only record an undo step if the drag actually moved something.
	if JSON.stringify(_drag_before) != JSON.stringify(zdef):
		_undo_stack.append({ "desc": "move", "zdef": _drag_before })
		if _undo_stack.size() > UNDO_LIMIT:
			_undo_stack.pop_front()
	_drag_before = {}


func _rotate_selected(degrees: float) -> void:
	_snapshot("rotate")
	var e: Dictionary = _selected["entry"]
	e["rot"] = fmod(float(e.get("rot", 0)) + degrees + 360.0, 360.0)
	_position_visual(_selected["node"] as Node3D, e)


func _scale_selected(factor: float) -> void:
	var cat := str(_selected["cat"])
	if cat in ["npcs", "spawns", "gather_nodes"]:
		# Area entries scale their RADIUS instead of a mesh.
		if cat == "npcs":
			return
		_snapshot("resize area")
		var e: Dictionary = _selected["entry"]
		e["r"] = clampf(float(e.get("r", 10)) * factor, 3.0, 120.0)
		_refresh_selected_visual()
		return
	_snapshot("scale")
	var e2: Dictionary = _selected["entry"]
	e2["scale"] = clampf(float(e2.get("scale", 1.0)) * factor, 0.25, 4.0)
	_position_visual(_selected["node"] as Node3D, e2)


func _refresh_selected_visual() -> void:
	## Rebuild just the selected object's node (labels/rings show live data).
	var rec := _selected
	var old := rec["node"] as Node3D
	if is_instance_valid(old):
		old.queue_free()
	var node := _make_visual(str(rec["cat"]), rec["entry"])
	_overlay.add_child(node)
	_position_visual(node, rec["entry"])
	rec["node"] = node
	_set_selected(rec)


func _delete_selected() -> void:
	_snapshot("delete")
	var rec := _selected
	var arr: Array = zdef.get(str(rec["cat"]), [])
	arr.erase(rec["entry"])
	var node := rec["node"] as Node3D
	if is_instance_valid(node):
		node.queue_free()
	_objects.erase(rec)
	_set_selected({})
	_status("Deleted.")


# ================================================================ brush

func _pick_brush(cat: String, type_id: String) -> void:
	_set_selected({})
	_brush_cat = cat
	_brush_type = type_id
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = _make_visual(cat, _brush_entry(Vector3.ZERO))
	_ghost_translucent(_ghost)
	_overlay.add_child(_ghost)
	_status("Placing %s — click to drop, right-click/Esc to stop." % type_id)


func _ghost_translucent(node: Node3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.5, 0.9, 1.0, 0.45)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = m
		if child is Node3D:
			_ghost_translucent(child as Node3D)


func _brush_entry(at: Vector3) -> Dictionary:
	var x := snappedf(at.x, 0.5)
	var z := snappedf(at.z, 0.5)
	match _brush_cat:
		"buildings":
			return { "type": _brush_type, "x": x, "z": z, "rot": 0 }
		"placed_props":
			return { "type": _brush_type, "x": x, "z": z, "rot": 0 }
		"scenes":
			return { "type": _brush_type, "x": x, "z": z, "rot": 0 }
		"npcs":
			return { "id": "npc_%d" % (Time.get_ticks_msec() % 1000000), "name": "New NPC",
				"title": "Villager", "kind": "villager", "x": x, "z": z }
		"spawns":
			var mdef: Dictionary = DB.mob(_brush_type)
			var lo: int = int(mdef.get("level", [1, 1])[0]) if mdef.get("level") is Array else 1
			return { "mob": _brush_type, "x": x, "z": z, "r": 25, "count": 4,
				"level": [lo, lo + 2], "respawn": 45 }
		"gather_nodes":
			return { "type": _brush_type, "x": x, "z": z, "r": 40, "count": 3, "respawn": 180 }
	return {}


func _place_brush(ground: Vector3) -> void:
	_snapshot("place %s" % _brush_type)
	var entry := _brush_entry(ground)
	if not zdef.has(_brush_cat):
		zdef[_brush_cat] = []
	(zdef[_brush_cat] as Array).append(entry)
	var rec := _add_object(_brush_cat, entry)
	_set_selected(rec)
	_status("Placed %s at (%d, %d). Keep clicking to place more." % [_brush_type, int(entry["x"]), int(entry["z"])])


func _cancel_brush() -> void:
	_brush_cat = ""
	_brush_type = ""
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


# ================================================================ UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	var top := UI.panel()
	top.position = Vector2(12, 12)
	ui.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 10)
	top.add_child(top_h)
	top_h.add_child(UI.header("Zone Editor"))
	zone_pick = OptionButton.new()
	for zid in DB.zones:
		zone_pick.add_item("%s (%s)" % [str(DB.zones[zid].get("name", zid)), str(zid)])
		zone_pick.set_item_metadata(zone_pick.item_count - 1, str(zid))
	zone_pick.item_selected.connect(func(i):
		_load_zone(str(zone_pick.get_item_metadata(i))))
	top_h.add_child(zone_pick)
	top_h.add_child(UI.button("Undo (Ctrl+Z)", _undo))
	top_h.add_child(UI.button("Save Zone", _save))
	top_h.add_child(UI.button("Discard Changes", func():
		DB.reload()
		_load_zone(zone_id)))
	top_h.add_child(UI.button("Back to Menu", func(): closed.emit()))

	var side := UI.panel()
	side.position = Vector2(12, 70)
	side.custom_minimum_size = Vector2(250, 0)
	ui.add_child(side)
	var side_v := VBoxContainer.new()
	side.add_child(side_v)
	side_v.add_child(UI.label("Palette", 15, UI.COL_GOLD))
	cat_pick = OptionButton.new()
	for cat_name in ["Props", "Buildings", "Scenes", "NPCs", "Mob Spawns", "Gather Nodes"]:
		cat_pick.add_item(cat_name)
	cat_pick.item_selected.connect(func(_i): _rebuild_palette())
	side_v.add_child(cat_pick)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(230, 430)
	side_v.add_child(sc)
	palette_box = VBoxContainer.new()
	palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(palette_box)

	var bottom := UI.panel()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(12, -110)
	bottom.custom_minimum_size = Vector2(560, 0)
	ui.add_child(bottom)
	var bot_v := VBoxContainer.new()
	bottom.add_child(bot_v)
	info_label = UI.label("Nothing selected.", 13)
	bot_v.add_child(info_label)
	status_label = UI.label("WASD fly, wheel speed, hold RMB to look. Click objects to select and drag.", 12, Color(0.7, 0.7, 0.7))
	bot_v.add_child(status_label)

	_rebuild_palette()


func _rebuild_palette() -> void:
	for c in palette_box.get_children():
		palette_box.remove_child(c)
		c.queue_free()
	var entries: Array = []  # [cat, id, label]
	match cat_pick.selected:
		0:
			for t in PROP_TYPES:
				entries.append(["placed_props", t, t.capitalize()])
			for t in EXTRA_PROP_TYPES:
				entries.append(["placed_props", t, t.capitalize().replace("_", " ")])
		1:
			for t in BUILDING_TYPES:
				entries.append(["buildings", t, t.capitalize()])
		2:
			for t in SCENE_TYPES:
				entries.append(["scenes", t, t.capitalize().replace("_", " ")])
		3:
			entries.append(["npcs", "villager", "New NPC (edit JSON for role)"])
		4:
			var mob_ids: Array = DB.mobs.keys()
			mob_ids.sort()
			for mid in mob_ids:
				entries.append(["spawns", str(mid), str(DB.mobs[mid].get("name", mid))])
		5:
			for gid in DB.professions.get("nodes", {}):
				entries.append(["gather_nodes", str(gid), str(DB.professions["nodes"][gid].get("name", gid))])
	for e in entries:
		var cat := str(e[0])
		var tid := str(e[1])
		var b := UI.button(str(e[2]), func(): _pick_brush(cat, tid))
		palette_box.add_child(b)


func _status(text: String) -> void:
	status_label.text = text


# ================================================================ saving

func _save() -> void:
	DB.zones[zone_id] = zdef.duplicate(true)
	var f := FileAccess.open("res://data/zones/%s.json" % zone_id, FileAccess.WRITE)
	if f == null:
		_status("Could not write zone file (exported builds are read-only).")
		return
	f.store_string(JSON.stringify(zdef, "  ") + "\n")
	f.close()
	_status("Saved data/zones/%s.json" % zone_id)
