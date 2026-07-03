extends Node
## Game — persistent character state and progression rules.
## The Player node handles moment-to-moment combat; this holds everything
## that must survive zone changes and save/load.

const SAVE_PATH := "user://emberfall_save.json"
const INVENTORY_SLOTS := 24
const ACTION_SLOTS := 10
const BUY_PRICE_MULT := 4

var pc: Dictionary = {}
var player = null                 # runtime Player node (set by Main); untyped on purpose
var zone_node = null              # runtime Zone node (set when a zone builds); untyped on purpose
var current_zone_id: String = ""
var time_of_day := 10.0           # 0-24h; a full day passes in ~20 real minutes
var _talent_cache: Dictionary = {}


func has_character() -> bool:
	return not pc.is_empty()


# ---------------------------------------------------------------- creation

func new_character(char_name: String, race_id: String, class_id: String) -> void:
	var race: Dictionary = DB.races[race_id]
	var inv: Array = []
	inv.resize(INVENTORY_SLOTS)
	var bar: Array = []
	bar.resize(ACTION_SLOTS)
	pc = {
		"name": char_name,
		"race": race_id,
		"class": class_id,
		"level": 1,
		"xp": 0,
		"money": 60,
		"inventory": inv,
		"equipment": {},
		"known": [],
		"action_bar": bar,
		"talents": {},
		"quests": {},
		"done_quests": [],
		"profs": { "mining": 1, "herbalism": 1, "skinning": 1 },
		"zone": race["start_zone"],
		"pos": null,
		"hp": -1,
		"mana": -1,
		"has_pet": false
	}
	# Level 1 class abilities plus the racial.
	for aid in DB.class_abilities(class_id):
		if int(DB.abilities[aid]["level"]) <= 1:
			learn_ability(aid)
	learn_ability(race["racial"]["id"])
	# Starter gear: equip what fits, bag the rest.
	for iid in DB.classes[class_id]["starter_items"]:
		var it: Dictionary = DB.item(iid)
		var slot: String = it.get("slot", "none")
		if slot != "none" and not pc["equipment"].has(slot):
			pc["equipment"][slot] = iid
		else:
			add_item(iid, 1)
	current_zone_id = pc["zone"]


# ---------------------------------------------------------------- stats

func stats() -> Dictionary:
	var cls: Dictionary = DB.classes[pc["class"]]
	var race: Dictionary = DB.races[pc["race"]]
	var out := {}
	for k in ["str", "agi", "sta", "int", "spi"]:
		var v: float = float(cls["base_stats"][k]) \
			+ float(cls["stats_per_level"][k]) * (pc["level"] - 1) \
			+ float(race["stat_bonus"][k])
		for slot in pc["equipment"]:
			var it: Dictionary = DB.item(pc["equipment"][slot])
			v += float(it.get("stats", {}).get(k, 0))
		v *= 1.0 + talent_mod("stat_pct", { "stat": k })
		v += talent_mod("stat_flat", { "stat": k })
		out[k] = maxf(v, 1.0)
	return out


func max_hp() -> int:
	var cls: Dictionary = DB.classes[pc["class"]]
	var s := stats()
	var hp: float = float(cls["base_hp"]) + float(cls["hp_per_level"]) * pc["level"] \
		+ s["sta"] * Formulas.HP_PER_STA
	hp *= 1.0 + talent_mod("max_health_pct")
	return int(hp)


func max_mana() -> int:
	var cls: Dictionary = DB.classes[pc["class"]]
	if resource_type() == "rage":
		return 100
	var s := stats()
	return int(float(cls["base_mana"]) + float(cls["mana_per_level"]) * pc["level"] \
		+ s["int"] * Formulas.MANA_PER_INT)


func resource_type() -> String:
	return DB.classes[pc["class"]]["resource"]


func attack_power() -> float:
	var s := stats()
	var ap := Formulas.melee_attack_power(s["str"], pc["level"])
	ap *= 1.0 + talent_mod("attack_power_pct")
	return ap


func ranged_power() -> float:
	var s := stats()
	return Formulas.ranged_attack_power(s["agi"], pc["level"])


func armor() -> float:
	var s := stats()
	var a: float = s["agi"] * Formulas.ARMOR_PER_AGI
	for slot in pc["equipment"]:
		a += float(DB.item(pc["equipment"][slot]).get("armor", 0))
	a *= float(DB.classes[pc["class"]]["armor_mult"])
	a *= 1.0 + talent_mod("armor_pct")
	return a


func crit_pct(kind: String) -> float:
	# kind: "melee", "ranged", "spell"
	var s := stats()
	var c: float = Formulas.BASE_CRIT + s["agi"] * Formulas.CRIT_PER_AGI
	c += talent_mod("crit_pct")
	match kind:
		"melee":
			c += talent_mod("melee_crit_pct")
		"ranged":
			c += talent_mod("ranged_crit_pct")
		"spell":
			c = Formulas.BASE_CRIT + s["int"] * 0.02 + talent_mod("crit_pct")
	return c


func dodge_pct() -> float:
	var s := stats()
	return s["agi"] * Formulas.DODGE_PER_AGI + talent_mod("dodge_pct")


func weapon(melee: bool = true) -> Dictionary:
	## Returns {"dmg": [lo, hi], "speed": s, "name": n, "ranged": bool}
	var cls: Dictionary = DB.classes[pc["class"]]
	var is_hunter: bool = pc["class"] == "hunter"
	var slot := "ranged" if (is_hunter and not melee) else "mainhand"
	var iid: String = pc["equipment"].get(slot, "")
	if iid != "":
		var it: Dictionary = DB.item(iid)
		if it.has("dmg"):
			return { "dmg": it["dmg"], "speed": float(it["speed"]), "name": it["name"] }
	var wdef: Dictionary = cls["weapon"]
	if is_hunter and melee and cls.has("melee_weapon"):
		wdef = cls["melee_weapon"]
	return { "dmg": wdef["damage"], "speed": float(wdef["speed"]), "name": "Fists" }


# ---------------------------------------------------------------- talents

func talent_mod(mod: String, ctx: Dictionary = {}) -> float:
	var key := mod + "|" + str(ctx.get("ability", "")) + "|" + str(ctx.get("school", "")) + "|" + str(ctx.get("stat", ""))
	if _talent_cache.has(key):
		return _talent_cache[key]
	var total := 0.0
	var trees: Dictionary = DB.talents.get(pc["class"], {})
	for tree_name in trees:
		for t in trees[tree_name]:
			var ranks: int = int(pc["talents"].get(t["id"], 0))
			if ranks == 0:
				continue
			var e: Dictionary = t["effect"]
			if e["mod"] != mod:
				continue
			if e.has("ability") and ctx.get("ability", "") != e["ability"]:
				continue
			if e.has("school") and ctx.get("school", "") != e["school"]:
				continue
			if e.has("stat") and ctx.get("stat", "") != e["stat"]:
				continue
			total += float(e.get("per_rank", 0)) * ranks
	_talent_cache[key] = total
	return total


func talent_points_total() -> int:
	return maxi(0, int(pc["level"]) - 9)


func talent_points_spent() -> int:
	var n := 0
	for id in pc["talents"]:
		n += int(pc["talents"][id])
	return n


func talent_points_left() -> int:
	return talent_points_total() - talent_points_spent()


func points_in_tree(tree_name: String) -> int:
	var n := 0
	for t in DB.talents[pc["class"]].get(tree_name, []):
		n += int(pc["talents"].get(t["id"], 0))
	return n


func can_learn_talent(tree_name: String, talent: Dictionary) -> bool:
	if talent_points_left() <= 0:
		return false
	if int(pc["talents"].get(talent["id"], 0)) >= int(talent["ranks"]):
		return false
	return points_in_tree(tree_name) >= (int(talent["tier"]) - 1) * 5


func spend_talent(tree_name: String, talent: Dictionary) -> bool:
	if not can_learn_talent(tree_name, talent):
		return false
	var id: String = talent["id"]
	pc["talents"][id] = int(pc["talents"].get(id, 0)) + 1
	_talent_cache.clear()
	if talent["effect"]["mod"] == "grants_ability":
		learn_ability(talent["effect"]["ability"])
	Events.talents_changed.emit()
	Events.player_stats_changed.emit()
	return true


# ---------------------------------------------------------------- abilities

func knows(ability_id: String) -> bool:
	return ability_id in pc["known"]


func learn_ability(ability_id: String) -> void:
	if knows(ability_id):
		return
	pc["known"].append(ability_id)
	# Auto-place on the first free action bar slot.
	for i in ACTION_SLOTS:
		if pc["action_bar"][i] == null:
			pc["action_bar"][i] = ability_id
			break
	Events.abilities_changed.emit()
	Events.action_bar_changed.emit()


func set_action_slot(i: int, ability_id) -> void:
	pc["action_bar"][i] = ability_id
	Events.action_bar_changed.emit()


func trainable_abilities() -> Array:
	## [{id, cost, can_afford, level_ok}] — everything this class can ever train.
	var out: Array = []
	for aid in DB.class_abilities(pc["class"]):
		if knows(aid):
			continue
		var a: Dictionary = DB.abilities[aid]
		var cost := Formulas.ability_train_cost(int(a["level"]))
		out.append({
			"id": aid, "cost": cost,
			"can_afford": pc["money"] >= cost,
			"level_ok": pc["level"] >= int(a["level"])
		})
	return out


func train_ability(aid: String) -> bool:
	var a: Dictionary = DB.abilities[aid]
	var cost := Formulas.ability_train_cost(int(a["level"]))
	if pc["level"] < int(a["level"]) or not spend_money(cost):
		return false
	learn_ability(aid)
	Events.game_message.emit("You have learned %s." % a["name"])
	return true


# ---------------------------------------------------------------- money & items

func add_money(copper: int) -> void:
	pc["money"] += copper
	Events.money_changed.emit()


func spend_money(copper: int) -> bool:
	if pc["money"] < copper:
		Events.error_message.emit("You don't have enough money.")
		return false
	pc["money"] -= copper
	Events.money_changed.emit()
	return true


func count_item(item_id: String) -> int:
	var n := 0
	for e in pc["inventory"]:
		if e != null and e["id"] == item_id:
			n += int(e["count"])
	return n


func add_item(item_id: String, count: int = 1) -> int:
	## Returns how many could NOT be added (0 = all fit).
	var it: Dictionary = DB.item(item_id)
	var stack: int = int(it.get("stack", 1))
	var left := count
	# Fill existing stacks first.
	for e in pc["inventory"]:
		if left <= 0:
			break
		if e != null and e["id"] == item_id and int(e["count"]) < stack:
			var take: int = mini(stack - int(e["count"]), left)
			e["count"] = int(e["count"]) + take
			left -= take
	# Then empty slots.
	for i in INVENTORY_SLOTS:
		if left <= 0:
			break
		if pc["inventory"][i] == null:
			var take2: int = mini(stack, left)
			pc["inventory"][i] = { "id": item_id, "count": take2 }
			left -= take2
	if left < count:
		Events.inventory_changed.emit()
	if left > 0:
		Events.error_message.emit("Inventory is full.")
	return left


func remove_item(item_id: String, count: int = 1) -> bool:
	if count_item(item_id) < count:
		return false
	var left := count
	for i in INVENTORY_SLOTS:
		if left <= 0:
			break
		var e = pc["inventory"][i]
		if e != null and e["id"] == item_id:
			var take: int = mini(int(e["count"]), left)
			e["count"] = int(e["count"]) - take
			left -= take
			if int(e["count"]) <= 0:
				pc["inventory"][i] = null
	Events.inventory_changed.emit()
	return true


func remove_slot(i: int, count: int = 1) -> void:
	var e = pc["inventory"][i]
	if e == null:
		return
	e["count"] = int(e["count"]) - count
	if int(e["count"]) <= 0:
		pc["inventory"][i] = null
	Events.inventory_changed.emit()


func equip_from_bag(i: int) -> void:
	var e = pc["inventory"][i]
	if e == null:
		return
	var it: Dictionary = DB.item(e["id"])
	var slot: String = it.get("slot", "none")
	if slot == "none":
		return
	if int(it.get("req_level", 1)) > int(pc["level"]):
		Events.error_message.emit("You must reach level %d to use that." % int(it["req_level"]))
		return
	var old: String = pc["equipment"].get(slot, "")
	pc["equipment"][slot] = e["id"]
	pc["inventory"][i] = ({ "id": old, "count": 1 } if old != "" else null)
	Events.inventory_changed.emit()
	Events.equipment_changed.emit()
	Events.player_stats_changed.emit()


func unequip(slot: String) -> void:
	var iid: String = pc["equipment"].get(slot, "")
	if iid == "":
		return
	if add_item(iid, 1) == 0:
		pc["equipment"].erase(slot)
		Events.equipment_changed.emit()
		Events.player_stats_changed.emit()


func sell_item(i: int) -> void:
	var e = pc["inventory"][i]
	if e == null:
		return
	var it: Dictionary = DB.item(e["id"])
	if it.get("quest_item", false) or int(it.get("value", 0)) <= 0:
		Events.error_message.emit("You cannot sell that.")
		return
	add_money(int(it["value"]) * int(e["count"]))
	pc["inventory"][i] = null
	Events.inventory_changed.emit()


func buy_item(item_id: String) -> void:
	var it: Dictionary = DB.item(item_id)
	var price: int = int(it.get("value", 0)) * BUY_PRICE_MULT
	if pc["money"] < price:
		Events.error_message.emit("You don't have enough money.")
		return
	if add_item(item_id, 1) > 0:
		return
	spend_money(price)


# ---------------------------------------------------------------- XP & leveling

func gain_xp(amount: int) -> void:
	if amount <= 0 or int(pc["level"]) >= Formulas.MAX_LEVEL:
		return
	pc["xp"] = int(pc["xp"]) + amount
	Events.combat_log.emit("You gain %d experience." % amount)
	while int(pc["level"]) < Formulas.MAX_LEVEL and int(pc["xp"]) >= Formulas.xp_to_level(int(pc["level"])):
		pc["xp"] = int(pc["xp"]) - Formulas.xp_to_level(int(pc["level"]))
		pc["level"] = int(pc["level"]) + 1
		_talent_cache.clear()
		Events.player_level_up.emit(int(pc["level"]))
		Events.player_stats_changed.emit()
		Events.game_message.emit("You have reached level %d!" % int(pc["level"]))
		if int(pc["level"]) >= 10 and talent_points_left() > 0:
			Events.game_message.emit("You have unspent talent points. Press N to open talents.")
	Events.player_xp_changed.emit()


# ---------------------------------------------------------------- quests

func quest_state(qid: String) -> String:
	if qid in pc["done_quests"]:
		return "done"
	if pc["quests"].has(qid):
		return "complete" if quest_ready(qid) else "active"
	var q: Dictionary = DB.quest(qid)
	if int(pc["level"]) < int(q.get("req_level", 1)):
		return "unavailable"
	for pre in q.get("prereq", []):
		if not (pre in pc["done_quests"]):
			return "unavailable"
	return "available"


func accept_quest(qid: String) -> void:
	if quest_state(qid) != "available":
		return
	var q: Dictionary = DB.quest(qid)
	var progress: Array = []
	for obj in q["objectives"]:
		progress.append(0)
	pc["quests"][qid] = { "progress": progress }
	for obj in q["objectives"]:
		if obj["type"] == "deliver":
			add_item(obj["item"], 1)
	Events.quest_accepted.emit(qid)
	Events.quest_log_changed.emit()
	Events.game_message.emit("Quest accepted: %s" % q["name"])


func abandon_quest(qid: String) -> void:
	if not pc["quests"].has(qid):
		return
	var q: Dictionary = DB.quest(qid)
	pc["quests"].erase(qid)
	for obj in q["objectives"]:
		if obj["type"] in ["deliver", "collect"]:
			while count_item(obj["item"]) > 0:
				remove_item(obj["item"], count_item(obj["item"]))
	Events.quest_log_changed.emit()


func objective_status(qid: String) -> Array:
	## [{label, cur, need, done}]
	var q: Dictionary = DB.quest(qid)
	var state: Dictionary = pc["quests"].get(qid, { "progress": [] })
	var out: Array = []
	for i in q["objectives"].size():
		var obj: Dictionary = q["objectives"][i]
		var cur := 0
		var need := 1
		var label: String = obj.get("label", "")
		match obj["type"]:
			"kill":
				need = int(obj["count"])
				cur = int(state["progress"][i]) if i < state["progress"].size() else 0
				if label == "":
					label = DB.mob(obj["mob"])["name"] + " slain"
			"collect":
				need = int(obj["count"])
				cur = mini(count_item(obj["item"]), need)
				if label == "":
					label = DB.item(obj["item"])["name"]
			"explore":
				cur = int(state["progress"][i]) if i < state["progress"].size() else 0
			"deliver":
				cur = 1 if count_item(obj["item"]) > 0 else 0
		out.append({ "label": label, "cur": cur, "need": need, "done": cur >= need })
	return out


func quest_ready(qid: String) -> bool:
	for o in objective_status(qid):
		if not o["done"]:
			return false
	return true


func turn_in_quest(qid: String, choice_index: int = -1) -> bool:
	if not pc["quests"].has(qid) or not quest_ready(qid):
		return false
	var q: Dictionary = DB.quest(qid)
	var rewards: Dictionary = q.get("rewards", {})
	# Bag space check for guaranteed reward items.
	for iid in rewards.get("items", []):
		if add_item(iid, 1) > 0:
			return false
	if choice_index >= 0 and rewards.has("choice"):
		if add_item(rewards["choice"][choice_index], 1) > 0:
			return false
	# Consume quest items.
	for obj in q["objectives"]:
		if obj["type"] == "collect":
			remove_item(obj["item"], int(obj["count"]))
		elif obj["type"] == "deliver":
			remove_item(obj["item"], 1)
	pc["quests"].erase(qid)
	pc["done_quests"].append(qid)
	add_money(int(rewards.get("money", 0)))
	gain_xp(int(rewards.get("xp", 0)))
	Events.quest_completed.emit(qid)
	Events.quest_log_changed.emit()
	Events.game_message.emit("Quest completed: %s" % q["name"])
	save_game()
	return true


func on_mob_killed(mob_id: String) -> void:
	for qid in pc["quests"].keys():
		var q: Dictionary = DB.quest(qid)
		var state: Dictionary = pc["quests"][qid]
		for i in q["objectives"].size():
			var obj: Dictionary = q["objectives"][i]
			if obj["type"] == "kill" and obj["mob"] == mob_id:
				var need := int(obj["count"])
				if int(state["progress"][i]) < need:
					state["progress"][i] = int(state["progress"][i]) + 1
					Events.combat_log.emit("%s: %d/%d" % [obj.get("label", "Slain"), int(state["progress"][i]), need])
					Events.quest_progress.emit(qid)
					if quest_ready(qid):
						Events.game_message.emit("%s (Complete)" % q["name"])
			elif obj["type"] == "collect":
				var froms: Array = obj.get("from", [])
				if mob_id in froms and count_item(obj["item"]) < int(obj["count"]):
					if randf() < float(obj.get("chance", 0.5)):
						if add_item(obj["item"], 1) == 0:
							Events.combat_log.emit("%s: %d/%d" % [DB.item(obj["item"])["name"], count_item(obj["item"]), int(obj["count"])])
							Events.quest_progress.emit(qid)
							if quest_ready(qid):
								Events.game_message.emit("%s (Complete)" % q["name"])


func check_explore(pos: Vector3) -> void:
	for qid in pc["quests"].keys():
		var q: Dictionary = DB.quest(qid)
		var state: Dictionary = pc["quests"][qid]
		if q.get("zone", "") != current_zone_id:
			continue
		for i in q["objectives"].size():
			var obj: Dictionary = q["objectives"][i]
			if obj["type"] == "explore" and int(state["progress"][i]) == 0:
				var d := Vector2(pos.x - float(obj["x"]), pos.z - float(obj["z"])).length()
				if d <= float(obj["r"]):
					state["progress"][i] = 1
					Events.game_message.emit("%s" % obj.get("label", "Area explored"))
					Events.quest_progress.emit(qid)
					if quest_ready(qid):
						Events.game_message.emit("%s (Complete)" % q["name"])


func npc_quest_marker(npc_id: String) -> String:
	## "!" available, "?" ready to turn in, "" nothing.
	for qid in DB.quests_by_turnin.get(npc_id, []):
		if pc["quests"].has(qid) and quest_ready(qid):
			return "?"
	for qid in DB.quests_by_giver.get(npc_id, []):
		if quest_state(qid) == "available":
			return "!"
	for qid in DB.quests_by_turnin.get(npc_id, []):
		if pc["quests"].has(qid):
			return "?gray"
	return ""


# ---------------------------------------------------------------- professions

func gain_prof_skill(prof: String, node_def: Dictionary) -> void:
	var skill := int(pc["profs"].get(prof, 1))
	if skill < int(node_def.get("skill_gain_until", 75)) and skill < 300:
		pc["profs"][prof] = skill + 1
		Events.game_message.emit("Your %s skill is now %d." % [prof.capitalize(), skill + 1])


# ---------------------------------------------------------------- save / load

func save_game() -> void:
	if pc.is_empty():
		return
	if player != null and is_instance_valid(player):
		pc["pos"] = [player.global_position.x, player.global_position.y, player.global_position.z]
		pc["hp"] = player.hp
		pc["mana"] = player.resource
	pc["zone"] = current_zone_id
	pc["tod"] = time_of_day
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(pc))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		return false
	pc = parsed
	current_zone_id = pc.get("zone", "sunscorch_mesa")
	time_of_day = float(pc.get("tod", 10.0))
	_talent_cache.clear()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
