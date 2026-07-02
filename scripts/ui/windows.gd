class_name GameWindows
extends CanvasLayer
## All openable windows: bags, character sheet, quest log, talents,
## vendor, trainer, loot and quest-giver dialogs. Built entirely in code.

var bags_win: PanelContainer
var char_win: PanelContainer
var quest_win: PanelContainer
var talent_win: PanelContainer
var vendor_win: PanelContainer
var trainer_win: PanelContainer
var loot_win: PanelContainer
var dialog_win: PanelContainer

var vendor_open := false
var _vendor_npc: Npc = null
var _trainer_npc: Npc = null
var _loot_mob: Mob = null
var _dialog_npc: Npc = null
var _dialog_quest := ""
var _dialog_choice := -1

var bag_grid: GridContainer
var bag_money: Label
var char_box: VBoxContainer
var quest_list_box: VBoxContainer
var quest_detail_box: VBoxContainer
var talent_box: HBoxContainer
var talent_points_l: Label
var vendor_box: VBoxContainer
var trainer_box: VBoxContainer
var loot_box: VBoxContainer
var dialog_box: VBoxContainer


func _ready() -> void:
	layer = 6
	bags_win = _make_window("Bags  (B)", Vector2(1200, 400), Vector2(360, 0))
	bag_grid = GridContainer.new()
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 4)
	bag_grid.add_theme_constant_override("v_separation", 4)
	_win_content(bags_win).add_child(bag_grid)
	bag_money = UI.label("", 14, UI.COL_GOLD)
	_win_content(bags_win).add_child(bag_money)

	char_win = _make_window("Character  (C)", Vector2(14, 150), Vector2(360, 0))
	char_box = _scroll_box(char_win, 560)

	quest_win = _make_window("Quest Log  (L)", Vector2(460, 140), Vector2(660, 0))
	var qsplit := HBoxContainer.new()
	qsplit.add_theme_constant_override("separation", 12)
	_win_content(quest_win).add_child(qsplit)
	quest_list_box = VBoxContainer.new()
	quest_list_box.custom_minimum_size = Vector2(240, 380)
	qsplit.add_child(quest_list_box)
	quest_detail_box = VBoxContainer.new()
	quest_detail_box.custom_minimum_size = Vector2(380, 380)
	qsplit.add_child(quest_detail_box)

	talent_win = _make_window("Talents  (N)", Vector2(310, 130), Vector2(960, 0))
	talent_points_l = UI.label("", 15, UI.COL_GOLD)
	_win_content(talent_win).add_child(talent_points_l)
	talent_box = HBoxContainer.new()
	talent_box.add_theme_constant_override("separation", 14)
	_win_content(talent_win).add_child(talent_box)

	vendor_win = _make_window("Vendor", Vector2(420, 130), Vector2(380, 0))
	vendor_box = _scroll_box(vendor_win, 480)

	trainer_win = _make_window("Trainer", Vector2(420, 130), Vector2(420, 0))
	trainer_box = _scroll_box(trainer_win, 480)

	loot_win = _make_window("Loot", Vector2(660, 340), Vector2(280, 0))
	loot_box = VBoxContainer.new()
	_win_content(loot_win).add_child(loot_box)

	dialog_win = _make_window("Quest", Vector2(540, 180), Vector2(520, 0))
	dialog_box = _scroll_box(dialog_win, 460)

	Events.inventory_changed.connect(func():
		if bags_win.visible: _rebuild_bags()
		if vendor_win.visible: _rebuild_vendor()
		if quest_win.visible: _rebuild_quest_log())
	Events.money_changed.connect(func():
		if bags_win.visible: _rebuild_bags()
		if trainer_win.visible: _rebuild_trainer())
	Events.equipment_changed.connect(func():
		if char_win.visible: _rebuild_character())
	Events.player_stats_changed.connect(func():
		if char_win.visible: _rebuild_character())
	Events.abilities_changed.connect(func():
		if char_win.visible: _rebuild_character()
		if trainer_win.visible: _rebuild_trainer())
	Events.talents_changed.connect(func():
		if talent_win.visible: _rebuild_talents())
	Events.quest_log_changed.connect(func():
		if quest_win.visible: _rebuild_quest_log()
		if dialog_win.visible and _dialog_npc != null: _rebuild_dialog())
	Events.open_vendor.connect(_on_open_vendor)
	Events.open_trainer.connect(_on_open_trainer)
	Events.open_loot.connect(_on_open_loot)
	Events.open_quest_giver.connect(_on_open_quest_giver)


func _make_window(title: String, pos: Vector2, min_size: Vector2) -> PanelContainer:
	var w := UI.panel()
	w.position = pos
	w.custom_minimum_size = min_size
	w.visible = false
	var v := VBoxContainer.new()
	v.name = "V"
	var top := HBoxContainer.new()
	var h := UI.header(title)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(h)
	var x := UI.button("X", func(): w.visible = false)
	top.add_child(x)
	v.add_child(top)
	v.add_child(HSeparator.new())
	var content := VBoxContainer.new()
	content.name = "Content"
	v.add_child(content)
	w.add_child(v)
	add_child(w)
	return w


func _win_content(w: PanelContainer) -> VBoxContainer:
	return w.get_node("V/Content") as VBoxContainer


func _scroll_box(w: PanelContainer, height: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, height)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_win_content(w).add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.free()


func any_open() -> bool:
	for w in [bags_win, char_win, quest_win, talent_win, vendor_win, trainer_win, loot_win, dialog_win]:
		if w.visible:
			return true
	return false


func close_all() -> void:
	for w in [bags_win, char_win, quest_win, talent_win, vendor_win, trainer_win, loot_win, dialog_win]:
		w.visible = false
	vendor_open = false
	Events.close_loot.emit()


func _unhandled_input(event: InputEvent) -> void:
	if Game.pc.is_empty():
		return
	if event.is_action_pressed("toggle_bags"):
		bags_win.visible = not bags_win.visible
		if bags_win.visible:
			_rebuild_bags()
	elif event.is_action_pressed("toggle_character"):
		char_win.visible = not char_win.visible
		if char_win.visible:
			_rebuild_character()
	elif event.is_action_pressed("toggle_quests"):
		quest_win.visible = not quest_win.visible
		if quest_win.visible:
			_rebuild_quest_log()
	elif event.is_action_pressed("toggle_talents"):
		talent_win.visible = not talent_win.visible
		if talent_win.visible:
			_rebuild_talents()
	elif event.is_action_pressed("ui_escape") and any_open():
		close_all()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- bags

func _rebuild_bags() -> void:
	_clear(bag_grid)
	for i in Game.INVENTORY_SLOTS:
		var e = Game.pc["inventory"][i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(50, 50)
		b.add_theme_font_size_override("font_size", 13)
		if e != null:
			var iid := str(e["id"])
			var it := DB.item(iid)
			b.text = UI.item_glyph(iid) + ("\nx%d" % int(e["count"]) if int(e["count"]) > 1 else "")
			b.add_theme_color_override("font_color", DB.quality_color(it.get("quality", "common")))
			b.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.item_tooltip(iid)))
			b.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
			var idx := i
			b.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed:
					if ev.button_index == MOUSE_BUTTON_LEFT:
						if Game.player != null:
							Game.player.use_bag_item(idx)
					elif ev.button_index == MOUSE_BUTTON_RIGHT and vendor_open:
						Game.sell_item(idx))
		bag_grid.add_child(b)
	bag_money.text = "Money: " + Formulas.money_string(int(Game.pc["money"]))
	if vendor_open:
		bag_money.text += "   (right-click to sell)"


# ---------------------------------------------------------------- character

const SLOT_NAMES := {
	"head": "Head", "shoulder": "Shoulders", "chest": "Chest", "legs": "Legs",
	"feet": "Feet", "hands": "Hands", "waist": "Waist", "mainhand": "Main Hand", "ranged": "Ranged"
}


func _rebuild_character() -> void:
	_clear(char_box)
	var cls: Dictionary = DB.classes[Game.pc["class"]]
	var race: Dictionary = DB.races[Game.pc["race"]]
	char_box.add_child(UI.label("%s — Level %d %s %s" % [Game.pc["name"], int(Game.pc["level"]), race["name"], cls["name"]], 15, UI.COL_GOLD))
	char_box.add_child(HSeparator.new())

	char_box.add_child(UI.label("Equipment", 14, UI.COL_GOLD))
	for slot in SLOT_NAMES:
		var iid: String = Game.pc["equipment"].get(slot, "")
		var h := HBoxContainer.new()
		var sl := UI.label(SLOT_NAMES[slot] + ":", 13, Color(0.7, 0.7, 0.7))
		sl.custom_minimum_size.x = 90
		h.add_child(sl)
		if iid != "":
			var b := UI.button(DB.item(iid)["name"])
			b.add_theme_color_override("font_color", DB.quality_color(DB.item(iid).get("quality", "common")))
			var s2: String = slot
			b.pressed.connect(func(): Game.unequip(s2))
			b.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.item_tooltip(iid) + "\n[color=#808080]Click to unequip[/color]"))
			b.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
			h.add_child(b)
		else:
			h.add_child(UI.label("—", 13, Color(0.4, 0.4, 0.4)))
		char_box.add_child(h)

	char_box.add_child(HSeparator.new())
	char_box.add_child(UI.label("Stats", 14, UI.COL_GOLD))
	var s := Game.stats()
	var stat_names := { "str": "Strength", "agi": "Agility", "sta": "Stamina", "int": "Intellect", "spi": "Spirit" }
	for k in stat_names:
		char_box.add_child(UI.label("%s: %d" % [stat_names[k], int(s[k])], 13))
	char_box.add_child(UI.label("Armor: %d" % int(Game.armor()), 13))
	char_box.add_child(UI.label("Attack Power: %d  (Ranged: %d)" % [int(Game.attack_power()), int(Game.ranged_power())], 13))
	char_box.add_child(UI.label("Crit: %.1f%%   Dodge: %.1f%%" % [Game.crit_pct("melee"), Game.dodge_pct()], 13))

	char_box.add_child(HSeparator.new())
	char_box.add_child(UI.label("Professions", 14, UI.COL_GOLD))
	for prof in Game.pc["profs"]:
		char_box.add_child(UI.label("%s: %d / 300" % [prof.capitalize(), int(Game.pc["profs"][prof])], 13))

	char_box.add_child(HSeparator.new())
	char_box.add_child(UI.label("Abilities  (click to use, right-click to add to bar)", 14, UI.COL_GOLD))
	for aid in Game.pc["known"]:
		var a := DB.ability(str(aid))
		if a.is_empty():
			continue
		var b2 := UI.button(a["name"])
		var aid2 := str(aid)
		b2.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				if ev.button_index == MOUSE_BUTTON_LEFT:
					if Game.player != null:
						Game.player.use_ability(aid2)
				elif ev.button_index == MOUSE_BUTTON_RIGHT:
					_add_to_bar(aid2))
		b2.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.ability_tooltip(aid2)))
		b2.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
		char_box.add_child(b2)


func _add_to_bar(aid: String) -> void:
	for i in Game.ACTION_SLOTS:
		if Game.pc["action_bar"][i] == aid:
			return
	for i in Game.ACTION_SLOTS:
		if Game.pc["action_bar"][i] == null:
			Game.set_action_slot(i, aid)
			return
	Events.error_message.emit("Action bar is full.")


# ---------------------------------------------------------------- quest log

var _selected_quest := ""


func _rebuild_quest_log() -> void:
	_clear(quest_list_box)
	_clear(quest_detail_box)
	quest_list_box.add_child(UI.label("Active Quests (%d)" % Game.pc["quests"].size(), 14, UI.COL_GOLD))
	for qid in Game.pc["quests"]:
		var q := DB.quest(str(qid))
		var ready := Game.quest_ready(str(qid))
		var b := UI.button("[%d%s] %s%s" % [int(q.get("req_level", 1)), "+" if q.get("elite", false) else "", q["name"], " ✓" if ready else ""])
		var qid2 := str(qid)
		b.pressed.connect(func():
			_selected_quest = qid2
			_rebuild_quest_detail())
		quest_list_box.add_child(b)
	if _selected_quest != "" and Game.pc["quests"].has(_selected_quest):
		_rebuild_quest_detail()


func _rebuild_quest_detail() -> void:
	_clear(quest_detail_box)
	var q := DB.quest(_selected_quest)
	if q.is_empty():
		return
	quest_detail_box.add_child(UI.label(q["name"] + ("  (Elite)" if q.get("elite", false) else ""), 16, UI.COL_GOLD))
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.custom_minimum_size = Vector2(370, 0)
	txt.add_theme_font_size_override("normal_font_size", 13)
	txt.text = "[color=#e8e0c8]%s[/color]" % q["text"]
	quest_detail_box.add_child(txt)
	quest_detail_box.add_child(HSeparator.new())
	for o in Game.objective_status(_selected_quest):
		quest_detail_box.add_child(UI.label("• %s: %d/%d" % [o["label"], o["cur"], o["need"]], 13,
			Color(0.5, 0.9, 0.5) if o["done"] else Color(0.9, 0.9, 0.9)))
	quest_detail_box.add_child(HSeparator.new())
	_add_reward_lines(quest_detail_box, q)
	var ab := UI.button("Abandon Quest", func():
		Game.abandon_quest(_selected_quest)
		_selected_quest = ""
		_rebuild_quest_log())
	quest_detail_box.add_child(ab)


func _add_reward_lines(box: VBoxContainer, q: Dictionary) -> void:
	var r: Dictionary = q.get("rewards", {})
	box.add_child(UI.label("Rewards: %d XP, %s" % [int(r.get("xp", 0)), Formulas.money_string(int(r.get("money", 0)))], 13, Color(0.8, 0.75, 0.6)))
	for iid in r.get("items", []):
		box.add_child(UI.label("  %s" % DB.item(str(iid))["name"], 13, DB.quality_color(DB.item(str(iid)).get("quality", "common"))))


# ---------------------------------------------------------------- talents

func _rebuild_talents() -> void:
	_clear(talent_box)
	talent_points_l.text = "Unspent talent points: %d   (1 per level from level 10)" % Game.talent_points_left()
	var trees: Dictionary = DB.talents.get(Game.pc["class"], {})
	for tree_name in trees:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(295, 0)
		col.add_child(UI.label("%s  (%d)" % [tree_name, Game.points_in_tree(tree_name)], 15, UI.COL_GOLD))
		col.add_child(HSeparator.new())
		var talents: Array = trees[tree_name]
		for t in talents:
			var ranks := int(Game.pc["talents"].get(t["id"], 0))
			var h := HBoxContainer.new()
			var locked: bool = Game.points_in_tree(tree_name) < (int(t["tier"]) - 1) * 5
			var color := Color(0.5, 0.5, 0.5) if locked else (Color(0.4, 1, 0.4) if ranks > 0 else UI.COL_TEXT)
			var nm := UI.label("T%d  %s  %d/%d" % [int(t["tier"]), t["name"], ranks, int(t["ranks"])], 13, color)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.mouse_filter = Control.MOUSE_FILTER_STOP
			var t2: Dictionary = t
			nm.mouse_entered.connect(func(): Hud.inst.show_tooltip("[b][color=#ffd100]%s[/color][/b]\n[color=#ffe8c0]%s[/color]" % [t2["name"], t2["desc"]]))
			nm.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
			h.add_child(nm)
			var tree2 := str(tree_name)
			var plus := UI.button("+", func():
				if Game.spend_talent(tree2, t2):
					_rebuild_talents())
			plus.disabled = not Game.can_learn_talent(str(tree_name), t)
			h.add_child(plus)
			col.add_child(h)
		talent_box.add_child(col)


# ---------------------------------------------------------------- vendor / trainer

func _on_open_vendor(npc: Npc) -> void:
	_vendor_npc = npc
	vendor_open = true
	vendor_win.visible = true
	bags_win.visible = true
	_rebuild_vendor()
	_rebuild_bags()


func _rebuild_vendor() -> void:
	_clear(vendor_box)
	if _vendor_npc == null:
		return
	vendor_box.add_child(UI.label("%s — %s" % [_vendor_npc.npc_name, _vendor_npc.title], 14, UI.COL_GOLD))
	for iid in _vendor_npc.stock:
		var it := DB.item(str(iid))
		var price := int(it.get("value", 0)) * Game.BUY_PRICE_MULT
		var b := UI.button("%s   —   %s" % [it["name"], Formulas.money_string(price)])
		b.add_theme_color_override("font_color", DB.quality_color(it.get("quality", "common")))
		var iid2 := str(iid)
		b.pressed.connect(func(): Game.buy_item(iid2))
		b.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.item_tooltip(iid2)))
		b.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
		vendor_box.add_child(b)
	vendor_box.add_child(UI.label("Your money: %s" % Formulas.money_string(int(Game.pc["money"])), 13, UI.COL_GOLD))


func _on_open_trainer(npc: Npc) -> void:
	_trainer_npc = npc
	trainer_win.visible = true
	_rebuild_trainer()


func _rebuild_trainer() -> void:
	_clear(trainer_box)
	if _trainer_npc == null:
		return
	trainer_box.add_child(UI.label("%s — %s" % [_trainer_npc.npc_name, _trainer_npc.title], 14, UI.COL_GOLD))
	if _trainer_npc.trainer_class != Game.pc["class"]:
		trainer_box.add_child(UI.label("\"You'd best find a trainer of your own calling, %s.\"" % DB.classes[Game.pc["class"]]["name"], 13))
		return
	var any := false
	for entry in Game.trainable_abilities():
		any = true
		var a := DB.ability(entry["id"])
		var line := "%s  (Level %d)  —  %s" % [a["name"], int(a["level"]), Formulas.money_string(entry["cost"])]
		var b := UI.button(line)
		var aid := str(entry["id"])
		if not entry["level_ok"]:
			b.disabled = true
			b.text += "  [too low level]"
		elif not entry["can_afford"]:
			b.disabled = true
			b.text += "  [too expensive]"
		b.pressed.connect(func():
			if Game.train_ability(aid):
				_rebuild_trainer())
		b.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.ability_tooltip(aid)))
		b.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
		trainer_box.add_child(b)
	if not any:
		trainer_box.add_child(UI.label("\"I have nothing more to teach you... for now.\"", 13))
	trainer_box.add_child(UI.label("Your money: %s" % Formulas.money_string(int(Game.pc["money"])), 13, UI.COL_GOLD))


# ---------------------------------------------------------------- loot

func _on_open_loot(mob: Mob) -> void:
	_loot_mob = mob
	loot_win.visible = true
	_rebuild_loot()


func _rebuild_loot() -> void:
	_clear(loot_box)
	if _loot_mob == null or not is_instance_valid(_loot_mob):
		loot_win.visible = false
		return
	if _loot_mob.loot_money > 0:
		var money := _loot_mob.loot_money
		var mb := UI.button(Formulas.money_string(money))
		mb.pressed.connect(func():
			Game.add_money(money)
			_loot_mob.loot_money = 0
			_rebuild_loot())
		loot_box.add_child(mb)
	for entry in _loot_mob.loot.duplicate():
		var iid := str(entry["id"])
		var count := int(entry["count"])
		var it := DB.item(iid)
		var b := UI.button(it["name"] + (" x%d" % count if count > 1 else ""))
		b.add_theme_color_override("font_color", DB.quality_color(it.get("quality", "common")))
		var e2: Dictionary = entry
		b.pressed.connect(func():
			if Game.add_item(iid, count) == 0:
				_loot_mob.loot.erase(e2)
				_rebuild_loot())
		b.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.item_tooltip(iid)))
		b.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
		loot_box.add_child(b)
	if not _loot_mob.has_loot():
		loot_win.visible = false
		return
	var all_b := UI.button("Take All", func():
		if _loot_mob == null or not is_instance_valid(_loot_mob):
			return
		Game.add_money(_loot_mob.loot_money)
		_loot_mob.loot_money = 0
		for e in _loot_mob.loot.duplicate():
			if Game.add_item(str(e["id"]), int(e["count"])) == 0:
				_loot_mob.loot.erase(e)
		_rebuild_loot())
	loot_box.add_child(all_b)


# ---------------------------------------------------------------- quest giver

func _on_open_quest_giver(npc: Npc) -> void:
	_dialog_npc = npc
	_dialog_quest = ""
	_dialog_choice = -1
	dialog_win.visible = true
	_rebuild_dialog()


func _rebuild_dialog() -> void:
	_clear(dialog_box)
	if _dialog_npc == null:
		return
	if _dialog_quest != "":
		_rebuild_dialog_detail()
		return
	dialog_box.add_child(UI.label("%s" % _dialog_npc.npc_name, 16, UI.COL_GOLD))
	dialog_box.add_child(UI.label("<%s>" % _dialog_npc.title, 12, Color(0.7, 0.7, 0.7)))
	dialog_box.add_child(HSeparator.new())
	var listed := false
	for qid in DB.quests_by_turnin.get(_dialog_npc.npc_id, []):
		if Game.pc["quests"].has(qid):
			var q := DB.quest(str(qid))
			var ready := Game.quest_ready(str(qid))
			var b := UI.button("?  %s%s" % [q["name"], "  (Complete)" if ready else "  (in progress)"])
			b.add_theme_color_override("font_color", UI.COL_GOLD if ready else Color(0.6, 0.6, 0.6))
			var qid2 := str(qid)
			b.pressed.connect(func():
				_dialog_quest = qid2
				_dialog_choice = -1
				_rebuild_dialog())
			dialog_box.add_child(b)
			listed = true
	for qid in DB.quests_by_giver.get(_dialog_npc.npc_id, []):
		if Game.quest_state(str(qid)) == "available":
			var q2 := DB.quest(str(qid))
			var b2 := UI.button("!  %s  [%d%s]" % [q2["name"], int(q2.get("req_level", 1)), "+" if q2.get("elite", false) else ""])
			b2.add_theme_color_override("font_color", UI.COL_GOLD)
			var qid3 := str(qid)
			b2.pressed.connect(func():
				_dialog_quest = qid3
				_dialog_choice = -1
				_rebuild_dialog())
			dialog_box.add_child(b2)
			listed = true
	if not listed:
		dialog_box.add_child(UI.label("\"Safe travels, friend.\"", 13))


func _rebuild_dialog_detail() -> void:
	var q := DB.quest(_dialog_quest)
	var qid := _dialog_quest
	dialog_box.add_child(UI.label(q["name"] + ("  (Elite — bring help!)" if q.get("elite", false) else ""), 16, UI.COL_GOLD))
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.custom_minimum_size = Vector2(470, 0)
	txt.add_theme_font_size_override("normal_font_size", 13)
	txt.text = "[color=#e8e0c8]%s[/color]" % q["text"]
	dialog_box.add_child(txt)
	dialog_box.add_child(HSeparator.new())
	for obj in q["objectives"]:
		var label: String = obj.get("label", "")
		if label == "":
			match str(obj["type"]):
				"kill": label = "Slay %d %s" % [int(obj["count"]), DB.mob(obj["mob"])["name"]]
				"collect": label = "Collect %d %s" % [int(obj["count"]), DB.item(obj["item"])["name"]]
				_: label = str(obj["type"])
		elif obj.has("count"):
			label += " (%d)" % int(obj["count"])
		dialog_box.add_child(UI.label("• " + label, 13))
	dialog_box.add_child(HSeparator.new())
	_add_reward_lines(dialog_box, q)

	var r: Dictionary = q.get("rewards", {})
	var state := Game.quest_state(qid)
	if state == "available":
		if r.has("choice"):
			dialog_box.add_child(UI.label("You will be able to choose one of:", 13, Color(0.8, 0.75, 0.6)))
			for iid in r["choice"]:
				dialog_box.add_child(UI.label("  %s" % DB.item(str(iid))["name"], 13, DB.quality_color(DB.item(str(iid)).get("quality", "common"))))
		var acc := UI.button("Accept", func():
			Game.accept_quest(qid)
			_dialog_quest = ""
			_rebuild_dialog())
		dialog_box.add_child(acc)
	elif Game.pc["quests"].has(qid):
		if Game.quest_ready(qid):
			if r.has("choice"):
				dialog_box.add_child(UI.label("Choose your reward:", 13, UI.COL_GOLD))
				var choices: Array = r["choice"]
				for i in choices.size():
					var iid2 := str(choices[i])
					var cb := UI.button(("> " if _dialog_choice == i else "  ") + DB.item(iid2)["name"])
					cb.add_theme_color_override("font_color", DB.quality_color(DB.item(iid2).get("quality", "common")))
					var idx := i
					cb.pressed.connect(func():
						_dialog_choice = idx
						_rebuild_dialog())
					cb.mouse_entered.connect(func(): Hud.inst.show_tooltip(UI.item_tooltip(iid2)))
					cb.mouse_exited.connect(func(): Hud.inst.hide_tooltip())
					dialog_box.add_child(cb)
			var comp := UI.button("Complete Quest", func():
				if r.has("choice") and _dialog_choice < 0:
					Events.error_message.emit("Choose a reward first.")
					return
				if Game.turn_in_quest(qid, _dialog_choice):
					_dialog_quest = ""
					_rebuild_dialog())
			dialog_box.add_child(comp)
		else:
			dialog_box.add_child(UI.label("\"Come back when it's done.\"", 13))
	var back := UI.button("Back", func():
		_dialog_quest = ""
		_rebuild_dialog())
	dialog_box.add_child(back)
