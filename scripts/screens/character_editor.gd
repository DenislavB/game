class_name CharacterEditor
extends Node3D
## Dev tool: edit the looks of everything living in the game — race model
## templates (races.json), individual NPCs (zone files, as "appearance"
## overrides) and mobs (mobs.json) — with a live turntable preview.
## Opened from the main menu. Save writes straight back to the JSON files.

signal closed

const WEAPONS := ["none", "sword", "axe", "mace", "staff", "bow", "dagger"]

var mode := "race"
var race_id := "orc"
var skin_index := 0
var preview_class := "warrior"
var preview_weapon := "sword"
var npc_zone := ""
var npc_index := 0
var mob_id := ""

var holder: Node3D
var camera: Camera3D
var _zoom := 4.5
var _dragging := false
var _spin := true

var controls_box: VBoxContainer
var status_label: Label
var mode_buttons: Dictionary = {}


func _ready() -> void:
	_build_stage()
	_build_ui()
	race_id = str(DB.races.keys()[0])
	npc_zone = str(DB.zones.keys()[0])
	mob_id = str(DB.mobs.keys()[0])
	_set_mode("race")


# ================================================================ stage

func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17120e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a6058")
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_energy = 1.1
	key.light_color = Color("fff0dc")
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.5
	rim.light_color = Color("a0b8d8")
	add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = Props._cyl(3.2, 3.4, 0.2, 24)
	floor_mesh.material_override = Props.mat(Color("2a231c"))
	floor_mesh.position.y = -0.1
	add_child(floor_mesh)

	holder = Node3D.new()
	add_child(holder)

	camera = Camera3D.new()
	camera.position = Vector3(0, 1.5, _zoom)
	camera.look_at_from_position(camera.position, Vector3(0, 1.1, 0))
	add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	if _spin and not _dragging:
		holder.rotation.y += delta * 0.4
	camera.position.z = _zoom


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = maxf(_zoom - 0.4, 2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = minf(_zoom + 0.4, 9.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		holder.rotation.y += mm.relative.x * 0.01


# ================================================================ UI shell

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)

	var panel := UI.panel()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -400
	panel.offset_top = 10
	panel.offset_bottom = -10
	panel.offset_right = -10
	layer.add_child(panel)

	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UI.header("Character Editor"))
	v.add_child(UI.label("Drag to rotate, wheel to zoom.", 11, Color(0.6, 0.58, 0.5)))
	v.add_child(HSeparator.new())

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for m in [["race", "Races"], ["npc", "NPCs"], ["mob", "Mobs"]]:
		var mid: String = m[0]
		var b := UI.button(m[1], func(): _set_mode(mid))
		b.custom_minimum_size = Vector2(110, 34)
		tabs.add_child(b)
		mode_buttons[mid] = b
	v.add_child(tabs)
	v.add_child(HSeparator.new())

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 500)
	v.add_child(sc)
	controls_box = VBoxContainer.new()
	controls_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_box.add_theme_constant_override("separation", 6)
	sc.add_child(controls_box)

	v.add_child(HSeparator.new())
	status_label = UI.label("", 12, Color(0.5, 0.9, 0.5))
	v.add_child(status_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	var save_b := UI.button("Save to Disk", func(): _save_current())
	save_b.custom_minimum_size = Vector2(150, 40)
	bottom.add_child(save_b)
	var reload_b := UI.button("Discard Changes", func():
		DB.reload()
		_set_mode(mode)
		_status("Reloaded data from disk."))
	bottom.add_child(reload_b)
	var back_b := UI.button("Back to Menu", func(): closed.emit())
	bottom.add_child(back_b)
	v.add_child(bottom)


func _status(text: String) -> void:
	status_label.text = text


func _set_mode(m: String) -> void:
	mode = m
	var labels := { "race": "Races", "npc": "NPCs", "mob": "Mobs" }
	for k in mode_buttons:
		(mode_buttons[k] as Button).text = ("> " if k == m else "") + str(labels[k])
	_rebuild_controls()
	_rebuild_preview()


func _clear_controls() -> void:
	for c in controls_box.get_children():
		controls_box.remove_child(c)
		c.queue_free()


# ================================================================ shared widgets

func _row(label_text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UI.label(label_text, 13)
	l.custom_minimum_size.x = 130
	h.add_child(l)
	controls_box.add_child(h)
	return h


func _color_row(label_text: String, current: Color, cb: Callable) -> ColorPickerButton:
	var h := _row(label_text)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(90, 28)
	picker.color = current
	picker.edit_alpha = false
	picker.color_changed.connect(cb)
	h.add_child(picker)
	return picker


func _option_row(label_text: String, options: Array, current: String, cb: Callable) -> OptionButton:
	var h := _row(label_text)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(200, 30)
	for i in options.size():
		opt.add_item(str(options[i]), i)
		if str(options[i]) == current:
			opt.select(i)
	opt.item_selected.connect(func(idx: int): cb.call(str(options[idx])))
	h.add_child(opt)
	return opt


func _check_row(label_text: String, current: bool, cb: Callable) -> void:
	var h := _row(label_text)
	var chk := CheckBox.new()
	chk.button_pressed = current
	chk.toggled.connect(cb)
	h.add_child(chk)


func _slider_row(label_text: String, minv: float, maxv: float, current: float, cb: Callable) -> void:
	var h := _row(label_text)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = 0.02
	slider.value = current
	slider.custom_minimum_size = Vector2(160, 24)
	var val_l := UI.label("%.2f" % current, 12)
	slider.value_changed.connect(func(val: float):
		val_l.text = "%.2f" % val
		cb.call(val))
	h.add_child(slider)
	h.add_child(val_l)


# ================================================================ race mode

func _race_model() -> Dictionary:
	var race: Dictionary = DB.races[race_id]
	if not race.has("model"):
		race["model"] = {}
	return race["model"]


func _rebuild_controls() -> void:
	_clear_controls()
	match mode:
		"race":
			_race_controls()
		"npc":
			_npc_controls()
		"mob":
			_mob_controls()


func _race_controls() -> void:
	_option_row("Race", DB.races.keys(), race_id, func(val: String):
		race_id = val
		skin_index = 0
		_rebuild_controls()
		_rebuild_preview())
	controls_box.add_child(HSeparator.new())

	var race: Dictionary = DB.races[race_id]
	var skins: Array = race["skin_colors"]
	for i in skins.size():
		var idx := i
		_color_row("Skin tone %d" % (i + 1), Color(str(skins[i])), func(c: Color):
			skins[idx] = "#" + c.to_html(false)
			_rebuild_preview())
	_option_row("Preview skin", ["1", "2", "3"], str(skin_index + 1), func(val: String):
		skin_index = int(val) - 1
		_rebuild_preview())
	controls_box.add_child(HSeparator.new())

	var m := _race_model()
	_check_row("Hunched posture", str(m.get("posture", "")) == "hunched", func(on: bool):
		if on:
			m["posture"] = "hunched"
		else:
			m.erase("posture")
		_rebuild_preview())
	_option_row("Tusks", ["none", "short", "long"], str(m.get("tusks", "none")), func(val: String):
		if val == "none":
			m.erase("tusks")
		else:
			m["tusks"] = val
		_rebuild_preview())
	_option_row("Ears", ["normal", "long"], str(m.get("ears", "normal")), func(val: String):
		if val == "normal":
			m.erase("ears")
		else:
			m["ears"] = val
		_rebuild_preview())
	_check_row("Beard", m.get("beard", false), func(on: bool):
		if on:
			m["beard"] = true
		else:
			m.erase("beard")
		_rebuild_preview())
	_color_row("Eye color", Color(str(m.get("eye_color", "#1a1a22"))), func(c: Color):
		m["eye_color"] = "#" + c.to_html(false)
		_rebuild_preview())
	_check_row("Glowing eyes", m.get("eye_glow", false), func(on: bool):
		if on:
			m["eye_glow"] = true
		else:
			m.erase("eye_glow")
		_rebuild_preview())
	controls_box.add_child(HSeparator.new())

	var stature: Array = m.get("stature", [1.0, 1.0, 1.0])
	m["stature"] = stature
	var axes := ["Width", "Height", "Depth"]
	for i in 3:
		var ai := i
		_slider_row(axes[i], 0.6, 1.4, float(stature[i]), func(val: float):
			stature[ai] = val
			_rebuild_preview())
	controls_box.add_child(HSeparator.new())

	controls_box.add_child(UI.label("Preview options (not saved)", 12, Color(0.6, 0.58, 0.5)))
	_option_row("Outfit class", DB.classes.keys(), preview_class, func(val: String):
		preview_class = val
		_rebuild_preview())
	_option_row("Weapon", WEAPONS, preview_weapon, func(val: String):
		preview_weapon = val
		_rebuild_preview())


# ================================================================ npc mode

func _current_npc() -> Dictionary:
	var npcs: Array = DB.zones[npc_zone].get("npcs", [])
	if npcs.is_empty():
		return {}
	npc_index = clampi(npc_index, 0, npcs.size() - 1)
	return npcs[npc_index]


func _npc_generated_look(ndef: Dictionary) -> Dictionary:
	## The same procedural look npc.gd would generate, so pickers show reality.
	var race: Dictionary = DB.races.get(ndef.get("race", "human"), DB.races["human"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(ndef.get("id", "")))
	var skins: Array = race["skin_colors"]
	var shirt := Color.from_hsv(rng.randf(), 0.35, 0.55)
	if str(ndef.get("trainer", "")) != "":
		shirt = Color(DB.classes[str(ndef["trainer"])]["color"]).darkened(0.2)
	return {
		"skin": Color(str(skins[rng.randi_range(0, skins.size() - 1)])),
		"shirt": shirt,
		"pants": shirt.darkened(0.5),
		"hair": Color.from_hsv(rng.randf() * 0.15, 0.5, rng.randf_range(0.1, 0.5))
	}


func _npc_controls() -> void:
	_option_row("Zone", DB.zones.keys(), npc_zone, func(val: String):
		npc_zone = val
		npc_index = 0
		_rebuild_controls()
		_rebuild_preview())
	var npcs: Array = DB.zones[npc_zone].get("npcs", [])
	var names: Array = []
	for n in npcs:
		names.append(str(n["name"]))
	if names.is_empty():
		controls_box.add_child(UI.label("No NPCs in this zone.", 13))
		return
	_option_row("NPC", names, str(names[npc_index]), func(val: String):
		npc_index = names.find(val)
		_rebuild_controls()
		_rebuild_preview())
	controls_box.add_child(HSeparator.new())

	var ndef := _current_npc()
	controls_box.add_child(UI.label("%s — %s (%s)" % [ndef.get("name", "?"), ndef.get("title", ""), ndef.get("race", "?")], 13, UI.COL_GOLD))
	if not ndef.has("appearance"):
		ndef["appearance"] = {}
	var app: Dictionary = ndef["appearance"]
	var gen := _npc_generated_look(ndef)
	for entry in [["skin", "Skin"], ["shirt", "Shirt"], ["pants", "Pants"], ["hair", "Hair"]]:
		var key: String = entry[0]
		var current: Color = Color(str(app[key])) if app.has(key) else (gen[key] as Color)
		_color_row(entry[1], current, func(c: Color):
			app[key] = "#" + c.to_html(false)
			_rebuild_preview())
	var reset_b := UI.button("Reset to generated look", func():
		ndef.erase("appearance")
		_rebuild_controls()
		_rebuild_preview())
	controls_box.add_child(reset_b)


# ================================================================ mob mode

func _mob_controls() -> void:
	var names: Array = []
	for id in DB.mobs:
		names.append(str(id))
	_option_row("Mob", names, mob_id, func(val: String):
		mob_id = val
		_rebuild_controls()
		_rebuild_preview())
	controls_box.add_child(HSeparator.new())
	var mdef: Dictionary = DB.mobs[mob_id]
	controls_box.add_child(UI.label("%s  (shape: %s)" % [mdef.get("name", "?"), mdef.get("shape", "?")], 13, UI.COL_GOLD))
	_color_row("Color", Color(str(mdef.get("color", "#888888"))), func(c: Color):
		mdef["color"] = "#" + c.to_html(false)
		_rebuild_preview())
	_slider_row("Scale", 0.4, 2.2, float(mdef.get("scale", 1.0)), func(val: float):
		mdef["scale"] = val
		_rebuild_preview())


# ================================================================ preview

func _rebuild_preview() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var model := ActorModel.new()
	holder.add_child(model)
	match mode:
		"race":
			var race: Dictionary = DB.races[race_id]
			var skins: Array = race["skin_colors"]
			skin_index = clampi(skin_index, 0, skins.size() - 1)
			var cls_color := Color(str(DB.classes[preview_class]["color"]))
			model.build_humanoid({
				"skin": Color(str(skins[skin_index])),
				"shirt": cls_color.darkened(0.35),
				"pants": cls_color.darkened(0.6),
				"features": race.get("model", {})
			})
			if preview_weapon != "none":
				model.set_weapon(preview_weapon)
		"npc":
			var ndef := _current_npc()
			if ndef.is_empty():
				return
			var race2: Dictionary = DB.races.get(str(ndef.get("race", "human")), DB.races["human"])
			var gen := _npc_generated_look(ndef)
			var app: Dictionary = ndef.get("appearance", {})
			model.build_humanoid({
				"skin": Color(str(app["skin"])) if app.has("skin") else (gen["skin"] as Color),
				"shirt": Color(str(app["shirt"])) if app.has("shirt") else (gen["shirt"] as Color),
				"pants": Color(str(app["pants"])) if app.has("pants") else (gen["pants"] as Color),
				"hair": Color(str(app["hair"])) if app.has("hair") else (gen["hair"] as Color),
				"features": race2.get("model", {})
			})
		"mob":
			var mdef: Dictionary = DB.mobs[mob_id]
			model.build_creature(str(mdef.get("shape", "humanoid")),
				Color(str(mdef.get("color", "#888888"))), float(mdef.get("scale", 1.0)))


# ================================================================ saving

func _save_current() -> void:
	match mode:
		"race":
			_save_json("res://data/races.json", DB.races)
		"npc":
			# Strip empty appearance blocks before writing.
			for n in DB.zones[npc_zone].get("npcs", []):
				if n.has("appearance") and (n["appearance"] as Dictionary).is_empty():
					n.erase("appearance")
			_save_json("res://data/zones/%s.json" % npc_zone, DB.zones[npc_zone])
		"mob":
			_save_json("res://data/mobs.json", DB.mobs)


func _save_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status("Could not write %s (exported builds are read-only)." % path)
		return
	f.store_string(JSON.stringify(data, "  ") + "\n")
	f.close()
	_status("Saved %s" % path.get_file())
