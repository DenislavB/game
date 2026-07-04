class_name Mob
extends Unit
## World mob with classic MMO behavior: proximity aggro scaled by level
## difference, chase, leash + evade with full heal, threat between player
## and pet, lootable corpse, timed respawn.

enum State { IDLE, AGGRO, EVADE, DEAD }

const LEASH_RANGE := 60.0
const CORPSE_TIME := 120.0

var mob_id := ""
var def: Dictionary = {}
var elite := false
var aggressive := false
var passive_mob := false
var move_speed := 5.5
var melee_range := 2.6
var aggro_radius := 10.0

var state: int = State.IDLE
var home := Vector3.ZERO
var spawn_center := Vector2.ZERO
var spawn_r := 10.0
var respawn_time := 45.0
var zone: Zone

var threat: Dictionary = {}         # Node -> float
var combat_target: Unit = null
var _wander_t := 0.0
var _wander_dir := Vector3.ZERO
var _attack_t := 1.0
var _aggro_check_t := 0.0
var _cast_t := -1.0
var _corpse_t := 0.0
var _respawn_t := 0.0
var _evade_invuln := false

var loot: Array = []                # [{id, count}]
var loot_money := 0
var skinned := false

var _plate: Node3D
var _hp_bar: MeshInstance3D
var _name_label: Label3D
var _swing_style := "claw"


func setup(id: String, mob_level: int, center: Vector2, r: float, respawn: float, zone_ref: Zone) -> void:
	mob_id = id
	def = DB.mob(id)
	level = mob_level
	elite = def.get("elite", false)
	aggressive = def.get("aggressive", false)
	passive_mob = def.get("passive", false)
	move_speed = float(def.get("speed", 5.5))
	aggro_radius = float(def.get("aggro_radius", 10.0))
	spawn_center = center
	spawn_r = r
	respawn_time = respawn
	zone = zone_ref
	unit_name = def["name"]
	hp_max = Formulas.mob_health(level, elite)
	hp = hp_max

	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var s := float(def.get("scale", 1.0))
	cap.radius = 0.65 * s
	cap.height = 1.9 * s
	cs.shape = cap
	cs.position.y = 0.95 * s
	add_child(cs)
	melee_range = 2.2 + 0.8 * s

	model = ActorModel.new()
	add_child(model)
	var shape_name: String = def.get("shape", "humanoid")
	model.build_creature(shape_name, Color(def.get("color", "#888888")), s)
	if shape_name == "humanoid":
		var weapons := ["sword", "axe", "mace"]
		var wtype: String = weapons[hash(id) % weapons.size()]
		model.set_weapon(wtype)
		_swing_style = { "sword": "slash", "axe": "chop", "mace": "smash" }.get(wtype, "slash")
	else:
		_swing_style = "claw"
	_build_nameplate(s)


func _build_nameplate(s: float) -> void:
	_plate = Node3D.new()
	_plate.position.y = 2.5 * s
	add_child(_plate)
	_name_label = Label3D.new()
	_name_label.text = "%s (%d)%s" % [unit_name, level, " ++" if elite else ""]
	_name_label.font_size = 34
	_name_label.pixel_size = 0.008
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.modulate = Color("ff4a4a") if aggressive else Color("ffd100")
	if elite:
		_name_label.modulate = Color("ffb040") if aggressive else Color("ffd100")
	if passive_mob:
		_name_label.modulate = Color("9ad04a")
	_name_label.visibility_range_end = 55.0
	_name_label.outline_size = 6
	_plate.add_child(_name_label)

	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 0.14)
	bg.mesh = q
	var bgm := StandardMaterial3D.new()
	bgm.albedo_color = Color(0.1, 0.1, 0.1)
	bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bgm.billboard_keep_scale = true
	bg.material_override = bgm
	bg.position.y = -0.28
	bg.visibility_range_end = 45.0
	_plate.add_child(bg)

	_hp_bar = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.36, 0.10)
	_hp_bar.mesh = q2
	var fgm := StandardMaterial3D.new()
	fgm.albedo_color = Color("c03030")
	fgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fgm.billboard_keep_scale = true
	fgm.render_priority = 1
	_hp_bar.material_override = fgm
	_hp_bar.position.y = -0.28
	_hp_bar.visibility_range_end = 45.0
	_plate.add_child(_hp_bar)


func place_at_spawn(rng: RandomNumberGenerator) -> void:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * spawn_r
	var x := spawn_center.x + cos(a) * d
	var z := spawn_center.y + sin(a) * d
	global_position = Vector3(x, zone.ground_height(x, z) + 0.5, z)
	home = global_position
	rotation.y = rng.randf() * TAU


# ---------------------------------------------------------------- threat

func add_threat(source: Node, amount: float) -> void:
	if not alive or _evade_invuln:
		return
	# Critters and prey animals bolt instead of fighting back.
	if passive_mob:
		if not has_flag("fear"):
			apply_buff({ "id": "scared", "name": "Fleeing", "kind": "debuff",
				"duration": 6.0, "fear": true })
		return
	threat[source] = float(threat.get(source, 0.0)) + amount
	if state != State.AGGRO:
		state = State.AGGRO


func _on_hit_reactions(amount: int, source: Node) -> void:
	if source != null and is_instance_valid(source) and source is Unit and not (source is Mob):
		add_threat(source, float(amount))


func _pick_target() -> void:
	var best: Node = null
	var best_threat := -1.0
	for src in threat.keys():
		if src == null or not is_instance_valid(src) or not src.alive:
			threat.erase(src)
			continue
		var t: float = threat[src]
		if best == null or t > best_threat * 1.3:
			best = src
			best_threat = t
	combat_target = best


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_dead_tick(delta)
		return
	tick_buffs(delta)
	if not alive:
		return
	_hp_bar.scale.x = maxf(float(hp) / float(hp_max), 0.001)

	if has_buff("polymorph"):
		heal(hp_max * delta * 0.1, false)
		_sheep_tick(delta)
		return
	if has_flag("fear"):
		_flee_tick(delta)
		return
	if is_stunned():
		velocity.x = 0
		velocity.z = 0
		apply_gravity(delta)
		move_and_slide()
		return

	match state:
		State.IDLE:
			_idle_tick(delta)
		State.AGGRO:
			_aggro_tick(delta)
		State.EVADE:
			_evade_tick(delta)
	model.moving = Vector2(velocity.x, velocity.z).length() > 0.5


func _sheep_tick(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.0, 2.5)
		var a := randf() * TAU
		_wander_dir = Vector3(cos(a), 0, sin(a))
	velocity.x = _wander_dir.x * 2.0
	velocity.z = _wander_dir.z * 2.0
	face_direction(_wander_dir, delta)
	apply_gravity(delta)
	move_and_slide()
	model.moving = true


func _flee_tick(delta: float) -> void:
	# Feared: run screaming away from the player.
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var away: Vector3 = global_position - (p.global_position as Vector3)
	away.y = 0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	velocity.x = away.x * move_speed
	velocity.z = away.z * move_speed
	face_direction(away, delta)
	apply_gravity(delta)
	move_and_slide()
	model.moving = true


func _idle_tick(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(6.0, 16.0)
		if randf() < 0.6:
			var a := randf() * TAU
			_wander_dir = Vector3(cos(a), 0, sin(a))
			var next := global_position + _wander_dir * 6.0
			if Vector2(next.x - home.x, next.z - home.z).length() > spawn_r + 8.0:
				_wander_dir = (home - global_position).normalized()
		else:
			_wander_dir = Vector3.ZERO
	if _wander_t > 3.0:
		_wander_dir = Vector3.ZERO
	if _wander_dir != Vector3.ZERO and not is_rooted():
		velocity.x = _wander_dir.x * move_speed * 0.35
		velocity.z = _wander_dir.z * move_speed * 0.35
		face_direction(_wander_dir, delta)
	else:
		velocity.x = 0
		velocity.z = 0
	apply_gravity(delta)
	move_and_slide()

	# Proximity aggro, classic style: higher-level mobs aggro from further away.
	if aggressive and not passive_mob:
		_aggro_check_t -= delta
		if _aggro_check_t <= 0.0:
			_aggro_check_t = 0.4
			var p = Game.player
			if p != null and is_instance_valid(p) and p.alive:
				var diff := level - int(Game.pc["level"])
				var radius: float = aggro_radius * clampf(1.0 + float(diff) * 0.08, 0.5, 1.6)
				if distance_to(p) < radius:
					add_threat(p, 1.0)
					Events.combat_log.emit("%s attacks you!" % unit_name)


func _aggro_tick(delta: float) -> void:
	_pick_target()
	if combat_target == null:
		_start_evade()
		return
	if Vector2(global_position.x - home.x, global_position.z - home.z).length() > LEASH_RANGE:
		_start_evade()
		return

	var to_target := combat_target.global_position - global_position
	var dist := to_target.length()
	face_direction(to_target, delta)
	_attack_t -= delta

	var caster: Dictionary = def.get("caster", {})
	if not caster.is_empty() and dist > melee_range and dist < float(caster.get("range", 20)):
		# Ranged caster: stand and cast bolts.
		velocity.x = 0
		velocity.z = 0
		if _cast_t < 0.0 and _attack_t <= 0.0:
			_cast_t = float(caster.get("cast_time", 2.0))
			var cschool := str(caster.get("school", "fire"))
			model.start_cast("cast_" + cschool, UI.school_color(cschool))
		if _cast_t >= 0.0:
			_cast_t -= delta
			if _cast_t < 0.0:
				model.stop_cast()
				model.play_attack("bolt")
				_attack_t = 1.2
				var dmg := Formulas.mob_damage(level, elite)
				var roll := randf_range(dmg.x, dmg.y) * 1.15
				var school := str(caster.get("school", "fire"))
				FX.bolt(get_parent(), global_position + Vector3(0, 1.6, 0),
					combat_target.global_position + Vector3(0, 1.2, 0), UI.school_color(school))
				SFX.play_at("spell_%s" % school, global_position + Vector3(0, 1.6, 0), get_parent())
				combat_target.take_damage(roll, school, self)
	elif dist > melee_range:
		_interrupt_own_cast()
		if is_rooted():
			velocity.x = 0
			velocity.z = 0
		else:
			var dir := to_target.normalized()
			var spd := move_speed * slow_factor()
			velocity.x = dir.x * spd
			velocity.z = dir.z * spd
	else:
		_interrupt_own_cast()
		velocity.x = 0
		velocity.z = 0
		if _attack_t <= 0.0:
			_attack_t = Formulas.mob_attack_speed()
			_swing_at(combat_target)
	apply_gravity(delta)
	move_and_slide()


func _interrupt_own_cast() -> void:
	if _cast_t >= 0.0:
		_cast_t = -1.0
		model.stop_cast()


func _swing_at(target: Unit) -> void:
	model.play_attack(_swing_style)
	SFX.play_at("swing", global_position + Vector3(0, 1.2, 0), get_parent())
	var outcome := Formulas.attack_roll(level, target.level, target.dodge_value(), 5.0)
	match outcome:
		"miss":
			Events.combat_text.emit(target.global_position + Vector3(0, 2.2, 0), "Miss", "mob_miss")
		"dodge":
			Events.combat_text.emit(target.global_position + Vector3(0, 2.2, 0), "Dodge", "mob_miss")
		_:
			var dmg := Formulas.mob_damage(level, elite)
			var roll := randf_range(dmg.x, dmg.y)
			if outcome == "crit":
				roll *= 2.0
			roll *= 1.0 - Formulas.armor_reduction(target.armor_value(), level)
			roll *= 1.0 + debuff_total("damage_done_pct")
			target.take_damage(roll, "physical", self, outcome == "crit")


func _start_evade() -> void:
	state = State.EVADE
	threat.clear()
	combat_target = null
	_evade_invuln = true
	buffs.clear()


func _evade_tick(delta: float) -> void:
	var to_home := home - global_position
	if Vector2(to_home.x, to_home.z).length() < 2.0:
		state = State.IDLE
		_evade_invuln = false
		hp = hp_max
		velocity = Vector3.ZERO
		return
	var dir := to_home.normalized()
	velocity.x = dir.x * move_speed * 1.4
	velocity.z = dir.z * move_speed * 1.4
	face_direction(to_home, delta)
	apply_gravity(delta)
	move_and_slide()


func take_damage(amount: float, school: String, source: Node, is_crit: bool = false, ability_name: String = "") -> void:
	if _evade_invuln:
		Events.combat_text.emit(global_position + Vector3(0, 2.2, 0), "Evade", "mob_miss")
		return
	super.take_damage(amount, school, source, is_crit, ability_name)
	# Damage has a chance to break fear early.
	if alive and has_flag("fear") and randf() < 0.25:
		for b in buffs.duplicate():
			if b.get("fear", false):
				_drop_buff(b)


# ---------------------------------------------------------------- death & loot

func die(killer: Node) -> void:
	super.die(killer)
	state = State.DEAD
	velocity = Vector3.ZERO
	threat.clear()
	combat_target = null
	_corpse_t = CORPSE_TIME
	_respawn_t = respawn_time
	_plate.visible = false
	_roll_loot()
	skinned = false
	# XP and quest credit go to the player whether the killing blow came
	# from the player or their pet.
	var player_kill := killer != null and is_instance_valid(killer) and killer is Unit and (killer as Unit).is_player_unit
	if player_kill:
		Game.gain_xp(Formulas.mob_xp(level, int(Game.pc["level"]), elite))
		Game.on_mob_killed(mob_id)
	Events.combat_log.emit("%s dies." % unit_name)
	Events.mob_killed.emit(self)


func _roll_loot() -> void:
	loot.clear()
	loot_money = 0
	var table: Dictionary = DB.loot_tables.get(def.get("loot", "none"), {})
	if table.is_empty():
		return
	var money: Array = table.get("money", [0, 0])
	loot_money = randi_range(int(money[0]), int(money[1]))
	for entry in table.get("entries", []):
		if randf() >= float(entry.get("chance", 1.0)):
			continue
		var item_id: String
		if entry.has("pool"):
			item_id = entry["pool"][randi_range(0, entry["pool"].size() - 1)]
		else:
			item_id = entry["item"]
		var count := 1
		if entry.has("count"):
			count = randi_range(int(entry["count"][0]), int(entry["count"][1]))
		loot.append({ "id": item_id, "count": count })


func has_loot() -> bool:
	return not loot.is_empty() or loot_money > 0


func can_skin() -> bool:
	return not alive and not has_loot() and def.get("skinnable", false) and not skinned


func do_skin() -> void:
	skinned = true
	var skill := int(Game.pc["profs"].get("skinning", 1))
	var needed := level * 5
	if skill < needed - 25:
		Events.error_message.emit("Your skinning skill is too low (needs ~%d)." % needed)
		skinned = false
		return
	var leather := "light_leather" if level <= 12 else "medium_leather"
	var count := randi_range(1, 2)
	if Game.add_item(leather, count) == 0:
		Events.game_message.emit("You skin the %s: %s x%d." % [unit_name, DB.item(leather)["name"], count])
		Game.gain_prof_skill("skinning", { "skill_gain_until": needed + 40 })
		_corpse_t = minf(_corpse_t, 4.0)
	else:
		skinned = false


func _dead_tick(delta: float) -> void:
	_corpse_t -= delta
	_respawn_t -= delta
	if has_loot() and _corpse_t <= 4.0:
		_corpse_t = 30.0  # keep unlooted corpses around a while longer
	if _corpse_t <= 0.0:
		visible = false
		collision_layer = 0
	# Respawn once the timer is up and the corpse is gone or empty;
	# force it eventually even if the corpse was never looted.
	if _respawn_t <= 0.0 and (_corpse_t <= 0.0 or not has_loot() or _respawn_t < -240.0):
		_respawn()


func _respawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	place_at_spawn(rng)
	hp = hp_max
	alive = true
	visible = true
	collision_layer = 4
	state = State.IDLE
	loot.clear()
	loot_money = 0
	_plate.visible = true
	model.revive_pose()
