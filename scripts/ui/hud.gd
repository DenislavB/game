class_name Hud
extends CanvasLayer
## In-game HUD: unit frames, action bar, cast bar, XP bar, buffs,
## quest tracker, floating combat text, combat log and death overlay.

static var inst: Hud = null

var root: Control
var player_name_l: Label
var player_hp: ProgressBar
var player_res: ProgressBar
var player_hp_l: Label
var player_res_l: Label
var player_level_l: Label

var target_frame: PanelContainer
var target_name_l: Label
var target_hp: ProgressBar
var target_hp_l: Label
var target_debuffs_l: Label

var pet_frame: PanelContainer
var pet_hp: ProgressBar

var buff_row: HBoxContainer
var tracker_box: VBoxContainer
var action_slots: Array = []       # [{button, cd_rect, cd_label, key_label, glyph}]
var xp_bar: ProgressBar
var xp_label: Label

var cast_panel: PanelContainer
var cast_bar: ProgressBar
var cast_label: Label
var _cast_time_left := 0.0
var _cast_total := 0.0

var error_label: Label
var _error_t := 0.0
var msg_label: Label
var _msg_t := 0.0
var splash_label: Label
var _splash_t := 0.0

var log_box: VBoxContainer
var _floaties: Array = []
var death_overlay: Control
var tooltip: PanelContainer
var tooltip_text: RichTextLabel


func _ready() -> void:
	inst = self
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_player_frame()
	_build_target_frame()
	_build_pet_frame()
	_build_buff_row()
	_build_tracker()
	_build_action_bar()
	_build_cast_bar()
	_build_messages()
	_build_log()
	_build_death_overlay()
	_build_tooltip()

	Events.cast_started.connect(_on_cast_started)
	Events.cast_stopped.connect(func(): cast_panel.visible = false)
	Events.error_message.connect(_on_error)
	Events.game_message.connect(_on_message)
	Events.combat_text.connect(_on_combat_text)
	Events.combat_log.connect(_on_log)
	Events.zone_changed.connect(_on_zone_changed)
	Events.quest_log_changed.connect(_refresh_tracker)
	Events.quest_progress.connect(func(_q): _refresh_tracker())
	Events.action_bar_changed.connect(_refresh_action_bar)
	Events.player_died.connect(func(): death_overlay.visible = true)
	Events.player_respawned.connect(func(): death_overlay.visible = false)
	_refresh_action_bar()
	_refresh_tracker()


# ---------------------------------------------------------------- builders

func _bar_text(bar: ProgressBar) -> Label:
	var l := UI.label("", 11)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(l)
	return l


func _build_player_frame() -> void:
	var p := UI.panel()
	p.position = Vector2(14, 12)
	p.custom_minimum_size = Vector2(240, 0)
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	player_level_l = UI.label("1", 15, UI.COL_GOLD)
	player_name_l = UI.label("Name", 15)
	h.add_child(player_level_l)
	h.add_child(player_name_l)
	v.add_child(h)
	player_hp = UI.bar(UI.COL_HP)
	player_hp_l = _bar_text(player_hp)
	v.add_child(player_hp)
	player_res = UI.bar(UI.COL_MANA, 14)
	player_res_l = _bar_text(player_res)
	v.add_child(player_res)
	p.add_child(v)
	root.add_child(p)


func _build_target_frame() -> void:
	target_frame = UI.panel()
	target_frame.position = Vector2(280, 12)
	target_frame.custom_minimum_size = Vector2(240, 0)
	var v := VBoxContainer.new()
	target_name_l = UI.label("Target", 15)
	v.add_child(target_name_l)
	target_hp = UI.bar(Color(0.7, 0.15, 0.15))
	target_hp_l = _bar_text(target_hp)
	v.add_child(target_hp)
	target_debuffs_l = UI.label("", 11, Color(0.9, 0.5, 0.9))
	v.add_child(target_debuffs_l)
	target_frame.add_child(v)
	target_frame.visible = false
	root.add_child(target_frame)


var pet_name_l: Label


func _build_pet_frame() -> void:
	pet_frame = UI.panel()
	pet_frame.position = Vector2(14, 110)
	pet_frame.custom_minimum_size = Vector2(150, 0)
	var v := VBoxContainer.new()
	pet_name_l = UI.label("Pet", 12, Color(0.5, 0.9, 0.5))
	v.add_child(pet_name_l)
	pet_hp = UI.bar(UI.COL_HP, 10)
	v.add_child(pet_hp)
	pet_frame.add_child(v)
	pet_frame.visible = false
	root.add_child(pet_frame)


func _build_buff_row() -> void:
	buff_row = HBoxContainer.new()
	buff_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	buff_row.offset_left = -460
	buff_row.offset_top = 12
	buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_row.alignment = BoxContainer.ALIGNMENT_END
	buff_row.custom_minimum_size = Vector2(450, 40)
	root.add_child(buff_row)


func _build_tracker() -> void:
	var p := PanelContainer.new()
	var sb := UI.panel_style(false)
	sb.bg_color = Color(0, 0, 0, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -280
	p.offset_top = 70
	p.custom_minimum_size = Vector2(266, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker_box = VBoxContainer.new()
	tracker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tracker_box)
	root.add_child(p)


func _build_action_bar() -> void:
	var wrap := VBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	wrap.offset_left = -290
	wrap.offset_top = -110
	root.add_child(wrap)

	xp_bar = UI.bar(UI.COL_XP, 8)
	xp_bar.custom_minimum_size = Vector2(580, 8)
	xp_label = UI.label("", 10)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(xp_bar)
	wrap.add_child(xp_label)

	var bar_box := HBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 4)
	wrap.add_child(bar_box)
	for i in Game.ACTION_SLOTS:
		var slot := _make_action_slot(i)
		bar_box.add_child(slot["button"])
		action_slots.append(slot)


func _make_action_slot(i: int) -> Dictionary:
	var b := Button.new()
	b.custom_minimum_size = Vector2(54, 54)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.08, 0.95)
	sb.border_color = UI.COL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.25, 0.2, 0.12)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.pressed.connect(func():
		if Game.player != null:
			Game.player.use_action_slot(i))
	b.mouse_entered.connect(func(): _slot_tooltip(i))
	b.mouse_exited.connect(hide_tooltip)

	var key := UI.label(str((i + 1) % 10), 10, Color(0.8, 0.8, 0.8))
	key.position = Vector2(4, 2)
	b.add_child(key)

	var cd := ColorRect.new()
	cd.color = Color(0, 0, 0, 0.65)
	cd.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cd)
	var cdl := UI.label("", 15, Color(1, 0.9, 0.4))
	cdl.set_anchors_preset(Control.PRESET_CENTER)
	cdl.offset_left = -8
	cdl.offset_top = -10
	cdl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cdl)
	return { "button": b, "cd_rect": cd, "cd_label": cdl }


func _slot_tooltip(i: int) -> void:
	var id = Game.pc["action_bar"][i]
	if id != null and str(id) != "":
		show_tooltip(UI.ability_tooltip(str(id)))


func _refresh_action_bar() -> void:
	if Game.pc.is_empty():
		return
	for i in action_slots.size():
		var id = Game.pc["action_bar"][i]
		var b: Button = action_slots[i]["button"]
		if id == null or str(id) == "":
			b.text = ""
			b.remove_theme_color_override("font_color")
		else:
			b.text = UI.ability_glyph(str(id))
			b.add_theme_color_override("font_color", UI.school_color(DB.ability(str(id)).get("school", "")))


func _build_cast_bar() -> void:
	cast_panel = UI.panel()
	cast_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cast_panel.offset_left = -160
	cast_panel.offset_top = -190
	cast_panel.custom_minimum_size = Vector2(320, 0)
	var v := VBoxContainer.new()
	cast_label = UI.label("Casting", 13, UI.COL_GOLD)
	cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cast_label)
	cast_bar = UI.bar(Color(0.9, 0.7, 0.2), 14)
	v.add_child(cast_bar)
	cast_panel.add_child(v)
	cast_panel.visible = false
	root.add_child(cast_panel)


func _build_messages() -> void:
	error_label = UI.label("", 20, Color(1, 0.25, 0.25))
	error_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	error_label.offset_left = -300
	error_label.offset_top = 120
	error_label.custom_minimum_size = Vector2(600, 30)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(error_label)

	msg_label = UI.label("", 18, UI.COL_GOLD)
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.offset_left = -300
	msg_label.offset_top = 160
	msg_label.custom_minimum_size = Vector2(600, 30)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(msg_label)

	splash_label = UI.label("", 42, Color(1, 0.9, 0.5))
	splash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	splash_label.offset_left = -400
	splash_label.offset_top = 220
	splash_label.custom_minimum_size = Vector2(800, 60)
	splash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash_label.add_theme_constant_override("outline_size", 8)
	splash_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	root.add_child(splash_label)


func _build_log() -> void:
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.offset_left = 14
	log_box.offset_top = -200
	log_box.custom_minimum_size = Vector2(400, 180)
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)


func _build_death_overlay() -> void:
	death_overlay = Control.new()
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.visible = false
	var tint := ColorRect.new()
	tint.color = Color(0.3, 0, 0, 0.35)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.add_child(tint)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -120
	v.offset_top = -50
	v.add_child(UI.label("You have died.", 30, Color(1, 0.4, 0.4)))
	var b := UI.button("Release Spirit", func():
		if Game.player:
			Game.player.respawn_at_graveyard())
	v.add_child(b)
	death_overlay.add_child(v)
	root.add_child(death_overlay)


func _build_tooltip() -> void:
	tooltip = UI.panel()
	tooltip.visible = false
	tooltip.custom_minimum_size = Vector2(280, 0)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = RichTextLabel.new()
	tooltip_text.bbcode_enabled = true
	tooltip_text.fit_content = true
	tooltip_text.custom_minimum_size = Vector2(264, 0)
	tooltip_text.add_theme_font_size_override("normal_font_size", 13)
	tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tooltip_text)
	root.add_child(tooltip)


func show_tooltip(bbcode: String) -> void:
	tooltip_text.text = bbcode
	tooltip.visible = true


func hide_tooltip() -> void:
	tooltip.visible = false


# ---------------------------------------------------------------- events

func _on_cast_started(label_text: String, duration: float) -> void:
	cast_panel.visible = true
	cast_label.text = label_text
	_cast_total = duration
	_cast_time_left = duration


func _on_error(text: String) -> void:
	error_label.text = text
	error_label.modulate.a = 1.0
	_error_t = 2.0


func _on_message(text: String) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	_msg_t = 3.5
	_on_log(text)


func _on_zone_changed(zone_id: String) -> void:
	var z: Dictionary = DB.zones.get(zone_id, {})
	splash_label.text = z.get("name", zone_id)
	splash_label.modulate.a = 0.0
	_splash_t = 5.0
	_refresh_tracker()


func _on_log(text: String) -> void:
	var l := UI.label(text, 12, Color(0.95, 0.9, 0.75, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_child(l)
	if log_box.get_child_count() > 9:
		log_box.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(l, "modulate:a", 0.0, 2.0)
	tw.tween_callback(l.queue_free)


func _on_combat_text(world_pos: Vector3, text: String, kind: String) -> void:
	var color := Color.WHITE
	var size := 16
	match kind:
		"crit":
			color = Color(1, 0.6, 0.1)
			size = 24
		"heal": color = Color(0.3, 1, 0.3)
		"player_hurt": color = Color(1, 0.3, 0.3)
		"miss", "mob_miss": color = Color(0.8, 0.8, 0.8)
		"levelup":
			color = Color(1, 0.85, 0.2)
			size = 30
		"fire": color = Color(1, 0.55, 0.2)
		"frost": color = Color(0.5, 0.75, 1)
		"arcane": color = Color(0.85, 0.55, 1)
		"nature": color = Color(0.5, 0.9, 0.4)
		"shadow": color = Color(0.7, 0.45, 0.9)
		"holy": color = Color(1, 0.9, 0.55)
	var l := UI.label(text, size, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	_floaties.append({ "label": l, "pos": world_pos, "t": 0.0 })


func _refresh_tracker() -> void:
	for c in tracker_box.get_children():
		c.queue_free()
	if Game.pc.is_empty():
		return
	if not Game.pc["quests"].is_empty():
		tracker_box.add_child(UI.label("Quests", 15, UI.COL_GOLD))
	var shown := 0
	for qid in Game.pc["quests"]:
		if shown >= 6:
			break
		shown += 1
		var q := DB.quest(qid)
		var ready := Game.quest_ready(qid)
		var title: String = q["name"] + (" (Complete)" if ready else "")
		tracker_box.add_child(UI.label(title, 13, Color(1, 0.85, 0.4) if ready else Color(0.95, 0.9, 0.7)))
		if not ready:
			for o in Game.objective_status(qid):
				var line: String = " - %s: %d/%d" % [o["label"], o["cur"], o["need"]]
				tracker_box.add_child(UI.label(line, 12, Color(0.6, 0.6, 0.6) if o["done"] else Color(0.85, 0.85, 0.85)))


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or Game.pc.is_empty():
		return
	# Player frame
	player_name_l.text = str(Game.pc["name"])
	player_level_l.text = "[%d] " % int(Game.pc["level"])
	player_hp.max_value = p.hp_max
	player_hp.value = p.hp
	player_hp_l.text = "%d / %d" % [p.hp, p.hp_max]
	player_res.max_value = p.resource_max
	player_res.value = p.resource
	player_res_l.text = "%d / %d" % [int(p.resource), int(p.resource_max)]
	var fill: StyleBoxFlat = player_res.get_theme_stylebox("fill")
	fill.bg_color = UI.COL_RAGE if p.res_type == "rage" else UI.COL_MANA

	# Target frame
	var t = p.target
	if t != null and is_instance_valid(t):
		target_frame.visible = true
		var lvl := int(t.level)
		var elite_tag: String = " ++" if (t is Mob and t.elite) else ""
		target_name_l.text = "[%d] %s%s" % [lvl, t.unit_name, elite_tag]
		var diff := lvl - int(Game.pc["level"])
		var c := Color(1, 1, 0.3)
		if diff >= 5: c = Color(1, 0.2, 0.2)
		elif diff >= 3: c = Color(1, 0.5, 0.2)
		elif diff <= -8: c = Color(0.6, 0.6, 0.6)
		elif diff <= -3: c = Color(0.3, 0.9, 0.3)
		target_name_l.add_theme_color_override("font_color", c)
		target_hp.max_value = t.hp_max
		target_hp.value = t.hp
		target_hp_l.text = "%d%%" % int(100.0 * t.hp / maxf(t.hp_max, 1))
		var names: Array = []
		for b in t.buffs:
			names.append(str(b["name"]))
		target_debuffs_l.text = ", ".join(names)
	else:
		target_frame.visible = false

	# Pet frame
	if p.pet != null and is_instance_valid(p.pet) and p.pet.alive:
		pet_frame.visible = true
		pet_name_l.text = p.pet.unit_name
		pet_hp.max_value = p.pet.hp_max
		pet_hp.value = p.pet.hp
	else:
		pet_frame.visible = false

	# XP bar
	var need := Formulas.xp_to_level(int(Game.pc["level"]))
	xp_bar.max_value = need
	xp_bar.value = int(Game.pc["xp"])
	if int(Game.pc["level"]) >= Formulas.MAX_LEVEL:
		xp_label.text = "Level 60"
	else:
		xp_label.text = "XP: %d / %d" % [int(Game.pc["xp"]), need]

	_update_buff_row(p)
	_update_action_cooldowns(p)
	_update_cast_bar(delta)
	_update_floaties(delta)
	_fade_messages(delta)

	if tooltip.visible:
		var vp := root.get_viewport_rect().size
		var pos := root.get_local_mouse_position() + Vector2(18, 18)
		pos.x = minf(pos.x, vp.x - tooltip.size.x - 8)
		pos.y = minf(pos.y, vp.y - tooltip.size.y - 8)
		tooltip.position = pos


var _buff_row_t := 0.0


func _update_buff_row(p) -> void:
	_buff_row_t -= get_process_delta_time()
	if _buff_row_t > 0.0:
		return
	_buff_row_t = 0.3
	for c in buff_row.get_children():
		buff_row.remove_child(c)
		c.free()
	for b in p.buffs:
		var bp := PanelContainer.new()
		var sb := UI.panel_style()
		sb.set_content_margin_all(4)
		bp.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		var nm := UI.label(str(b["name"]).substr(0, 8), 10, Color(0.7, 1, 0.7))
		var tm := UI.label("%ds" % int(b["t"]), 10, Color(0.8, 0.8, 0.8))
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		v.add_child(tm)
		bp.add_child(v)
		buff_row.add_child(bp)


func _update_action_cooldowns(p) -> void:
	for i in action_slots.size():
		var slot: Dictionary = action_slots[i]
		var id = Game.pc["action_bar"][i]
		var cd_rect: ColorRect = slot["cd_rect"]
		var cd_label: Label = slot["cd_label"]
		if id == null or str(id) == "":
			cd_rect.visible = false
			cd_label.text = ""
			continue
		var aid := str(id)
		var a := DB.ability(aid)
		var left: float = p.ability_cooldown_left(aid)
		var frac := 0.0
		if left > 0.0:
			var total := maxf(float(a.get("cooldown", 1)), 0.01)
			frac = clampf(left / total, 0.0, 1.0)
			cd_label.text = str(int(ceil(left))) if left > 1.5 else ""
		else:
			cd_label.text = ""
			if a.get("gcd", true) and p.gcd_t > 0.0:
				frac = clampf(p.gcd_t / Formulas.GCD, 0.0, 1.0)
		if frac > 0.0:
			cd_rect.visible = true
			var h: float = 54.0 * frac
			cd_rect.offset_top = -h
			cd_rect.offset_bottom = 0
		else:
			cd_rect.visible = false


func _update_cast_bar(delta: float) -> void:
	if not cast_panel.visible:
		return
	_cast_time_left = maxf(_cast_time_left - delta, 0.0)
	cast_bar.max_value = _cast_total
	cast_bar.value = _cast_total - _cast_time_left


func _update_floaties(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for f in _floaties.duplicate():
		f["t"] += delta
		var l: Label = f["label"]
		if f["t"] > 1.4:
			l.queue_free()
			_floaties.erase(f)
			continue
		var wp: Vector3 = f["pos"] + Vector3(0, f["t"] * 1.2, 0)
		if cam.is_position_behind(wp):
			l.visible = false
			continue
		l.visible = true
		l.position = cam.unproject_position(wp) - l.size * 0.5
		l.modulate.a = clampf(2.8 - f["t"] * 2.0, 0.0, 1.0)


func _fade_messages(delta: float) -> void:
	if _error_t > 0.0:
		_error_t -= delta
		if _error_t <= 0.5:
			error_label.modulate.a = maxf(_error_t * 2.0, 0.0)
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.8:
			msg_label.modulate.a = maxf(_msg_t * 1.25, 0.0)
	if _splash_t > 0.0:
		_splash_t -= delta
		if _splash_t > 4.0:
			splash_label.modulate.a = minf((5.0 - _splash_t) * 2.0, 1.0)
		elif _splash_t < 1.5:
			splash_label.modulate.a = maxf(_splash_t / 1.5, 0.0)
		else:
			splash_label.modulate.a = 1.0
