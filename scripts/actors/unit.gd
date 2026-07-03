class_name Unit
extends CharacterBody3D
## Shared base for player, mobs and pets: health, buffs/debuffs, DoTs,
## slows/roots/stuns, absorb shields and floating combat text.

signal died(killer: Node)
signal damaged(amount: int, source: Node)

const GRAVITY := 22.0

var unit_name := ""
var level := 1
var hp := 1
var hp_max := 1
var alive := true
var model: ActorModel
var buffs: Array = []   # see apply_buff() for the entry shape
var is_player_unit := false


func take_damage(amount: float, school: String, source: Node, is_crit: bool = false, ability_name: String = "") -> void:
	if not alive:
		return
	# Absorb shields eat damage first.
	for b in buffs:
		if b.get("absorb", 0.0) > 0.0 and amount > 0.0:
			var absorbed: float = minf(b["absorb"], amount)
			b["absorb"] -= absorbed
			amount -= absorbed
			if b["absorb"] <= 0.0:
				b["t"] = 0.0
	# Damage-taken modifiers (Hunter's Mark debuff, Bear Form buff...).
	amount *= 1.0 + debuff_total("damage_taken_pct")
	amount *= maxf(1.0 + buff_total("damage_taken_pct"), 0.1)
	var final := int(maxf(amount, 0.0))
	hp -= final
	_on_hit_reactions(final, source)
	var txt := str(final) + ("!" if is_crit else "")
	if final == 0 and amount <= 0.0:
		txt = "Absorb"
	Events.combat_text.emit(global_position + Vector3(0, 2.2, 0), txt,
		"crit" if is_crit else ("player_hurt" if is_player_unit else school))
	damaged.emit(final, source)
	# Any damage breaks polymorph and fragile buffs.
	remove_buff("polymorph")
	for b in buffs.duplicate():
		if b.get("breaks_on_hit", false):
			_drop_buff(b)
	if hp <= 0:
		hp = 0
		die(source)


func _on_hit_reactions(_amount: int, _source: Node) -> void:
	pass  # overridden (rage from damage taken, enrage, etc.)


func dodge_value() -> float:
	return 5.0  # overridden by the player (agility + talents)


func armor_value() -> float:
	return Formulas.mob_armor(level)


func heal(amount: float, show_text: bool = true) -> void:
	if not alive:
		return
	var final := mini(int(amount), hp_max - hp)
	if final <= 0:
		return
	hp += final
	if show_text:
		Events.combat_text.emit(global_position + Vector3(0, 2.2, 0), "+%d" % final, "heal")


func die(killer: Node) -> void:
	if not alive:
		return
	alive = false
	buffs.clear()
	Events.buffs_changed.emit(self)
	if model:
		model.play_death()
	died.emit(killer)


# ---------------------------------------------------------------- buffs

func apply_buff(b: Dictionary) -> void:
	## b: {id, name, kind ("buff"/"debuff"), duration, t (runtime), and any of:
	##  stat/amount, dot {tick, interval, school, source}, slow_pct, root, stun,
	##  absorb, max_stacks, breaks_on_hit, damage_mult}
	b["t"] = float(b.get("duration", 10.0))
	for existing in buffs:
		if existing["id"] == b["id"]:
			var max_stacks := int(existing.get("max_stacks", 1))
			if max_stacks > 1 and int(existing.get("stacks", 1)) < max_stacks:
				existing["stacks"] = int(existing.get("stacks", 1)) + 1
			existing["t"] = b["t"]
			# Refresh dot timing.
			if b.has("dot"):
				existing["dot"] = b["dot"]
				existing["dot"]["next"] = float(b["dot"]["interval"])
			Events.buffs_changed.emit(self)
			return
	b["stacks"] = 1
	if b.has("dot"):
		b["dot"]["next"] = float(b["dot"]["interval"])
	buffs.append(b)
	Events.buffs_changed.emit(self)


func remove_buff(id: String) -> void:
	for b in buffs.duplicate():
		if b["id"] == id:
			_drop_buff(b)


func _drop_buff(b: Dictionary) -> void:
	buffs.erase(b)
	Events.buffs_changed.emit(self)


func has_buff(id: String) -> bool:
	for b in buffs:
		if b["id"] == id:
			return true
	return false


func has_flag(flag: String) -> bool:
	## True if any buff/debuff carries the given boolean key (e.g. "fear").
	for b in buffs:
		if b.get(flag, false):
			return true
	return false


func buff_total(stat: String) -> float:
	var total := 0.0
	for b in buffs:
		if b.get("kind", "buff") == "buff" and b.get("stat", "") == stat:
			total += float(b.get("amount", 0)) * int(b.get("stacks", 1))
	return total


func debuff_total(stat: String) -> float:
	var total := 0.0
	for b in buffs:
		if b.get("kind", "") == "debuff" and b.get("stat", "") == stat:
			total += float(b.get("amount", 0)) * int(b.get("stacks", 1))
	return total


func slow_factor() -> float:
	var worst := 0.0
	for b in buffs:
		worst = maxf(worst, float(b.get("slow_pct", 0.0)))
	return 1.0 - worst


func is_rooted() -> bool:
	for b in buffs:
		if b.get("root", false):
			return true
	return false


func is_stunned() -> bool:
	for b in buffs:
		if b.get("stun", false):
			return true
	return false


func tick_buffs(delta: float) -> void:
	for b in buffs.duplicate():
		b["t"] = float(b["t"]) - delta
		if b.has("dot") and alive:
			var dot: Dictionary = b["dot"]
			dot["next"] = float(dot["next"]) - delta
			if float(dot["next"]) <= 0.0:
				dot["next"] = float(dot["next"]) + float(dot["interval"])
				var src = dot.get("source")
				take_damage(float(dot["tick"]), dot.get("school", "physical"),
					src if (src != null and is_instance_valid(src)) else null)
				if not alive:
					return
		if b.has("hot") and alive:
			var hot: Dictionary = b["hot"]
			hot["next"] = float(hot.get("next", 1.0)) - delta
			if float(hot["next"]) <= 0.0:
				hot["next"] = float(hot["next"]) + float(hot.get("interval", 1.0))
				heal(float(hot["tick"]), false)
		if float(b["t"]) <= 0.0:
			_drop_buff(b)


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func face_direction(dir: Vector3, delta: float, turn_speed: float = 10.0) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	var target_yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * turn_speed, 1.0))


func distance_to(other: Node3D) -> float:
	return global_position.distance_to(other.global_position)
