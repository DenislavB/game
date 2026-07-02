class_name Player
extends Unit
## The player character. Classic MMO control scheme:
## W/S move, A/D turn (Q/E strafe), hold right mouse to mouse-turn,
## left mouse orbits the camera, Tab targets, 1-0 use the action bar.

const TURN_SPEED := 2.6
const BACKPEDAL_MULT := 0.55
const JUMP_VELOCITY := 8.0
const INTERACT_RANGE := 5.0

var resource := 0.0
var resource_max := 100.0
var res_type := "mana"
var in_combat := false
var target: Unit = null

var gcd_t := 0.0
var cooldowns: Dictionary = {}       # ability id -> seconds remaining
var casting_id := ""
var cast_t := 0.0
var cast_total := 0.0
var channel_id := ""
var channel_t := 0.0
var channel_tick_t := 0.0
var auto_attack_on := false
var swing_t := 0.5
var ranged_swing_t := 0.5
var sitting := false
var potion_cd := 0.0
var pet: Pet = null
var poly_target: Mob = null
var _flurry_swings := 0

var _last_mana_spend := -10.0
var _regen_t := 0.0
var _combat_scan_t := 0.0
var _explore_t := 0.0
var _autosave_t := 30.0
var _time := 0.0

# Camera
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var _cam_orbit_offset := 0.0
var _zoom := 7.0
var _drag_button := 0
var _drag_moved := 0.0
var _drag_start_pos := Vector2.ZERO
var _drag_time := 0.0


func _ready() -> void:
	is_player_unit = true
	unit_name = Game.pc["name"]
	level = int(Game.pc["level"])
	res_type = Game.resource_type()
	collision_layer = 2
	collision_mask = 1

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.95
	add_child(cs)

	var race: Dictionary = DB.races[Game.pc["race"]]
	var cls: Dictionary = DB.classes[Game.pc["class"]]
	model = ActorModel.new()
	add_child(model)
	model.build_humanoid({
		"skin": Color(race["skin_colors"][0]),
		"shirt": Color(cls["color"]).darkened(0.35),
		"pants": Color(cls["color"]).darkened(0.6),
		"posture": race.get("posture", "upright"),
		"tusks": Game.pc["race"] == "orc"
	})
	_update_weapon_visual()
	Events.equipment_changed.connect(_update_weapon_visual)

	# Camera rig
	cam_yaw = Node3D.new()
	cam_yaw.position.y = 1.7
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_yaw.add_child(cam_pitch)
	cam_pitch.rotation_degrees.x = -12
	spring = SpringArm3D.new()
	spring.spring_length = _zoom
	spring.collision_mask = 1
	spring.margin = 0.3
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.far = 700.0
	spring.add_child(camera)
	camera.current = true

	recompute_vitals(true)
	if int(Game.pc.get("hp", -1)) > 0:
		hp = mini(int(Game.pc["hp"]), hp_max)
		resource = minf(float(Game.pc.get("mana", 0)), resource_max)
	Events.player_level_up.connect(_on_level_up)
	Events.player_stats_changed.connect(func(): recompute_vitals(false))
	if Game.pc.get("has_pet", false) and Game.knows("call_pet"):
		call_deferred("_summon_pet")


func _update_weapon_visual() -> void:
	var w := Game.weapon(true)
	var iid: String = Game.pc["equipment"].get("mainhand", "")
	var wtype: String = DB.item(iid).get("wtype", "sword") if iid != "" else \
		DB.classes[Game.pc["class"]]["weapon"].get("type", "sword")
	if Game.pc["class"] == "hunter":
		var rid: String = Game.pc["equipment"].get("ranged", "")
		wtype = DB.item(rid).get("wtype", "bow") if rid != "" else "bow"
	model.set_weapon(wtype)


func recompute_vitals(refill: bool) -> void:
	level = int(Game.pc["level"])
	var old_max := hp_max
	hp_max = Game.max_hp()
	resource_max = float(Game.max_mana())
	if refill:
		hp = hp_max
		resource = resource_max if res_type == "mana" else 0.0
	else:
		hp = clampi(hp + maxi(hp_max - old_max, 0), 1, hp_max)
		resource = clampf(resource, 0, resource_max)


func dodge_value() -> float:
	return Game.dodge_pct()


func armor_value() -> float:
	return Game.armor() * maxf(1.0 + buff_total("armor_pct") + debuff_total("armor_pct"), 0.0)


func attack_power_value(ranged: bool) -> float:
	var ap := Game.ranged_power() if ranged else Game.attack_power()
	ap += buff_total("attack_power") + (buff_total("ranged_power") if ranged else 0.0)
	ap *= 1.0 + buff_total("attack_power_pct")
	return ap


# ================================================================= input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _drag_button != 0:
		var mm := event as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		var dx: float = -mm.relative.x * 0.0045
		var dy: float = -mm.relative.y * 0.0045
		if _drag_button == MOUSE_BUTTON_RIGHT:
			rotation.y += dx
			cam_yaw.rotation.y = 0.0
			_cam_orbit_offset = 0.0
		else:
			_cam_orbit_offset += dx
			cam_yaw.rotation.y = _cam_orbit_offset
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x + dy, deg_to_rad(-80), deg_to_rad(35))
	elif event.is_action_pressed("target_nearest"):
		_tab_target()
	elif event.is_action_pressed("sit"):
		set_sitting(not sitting)
	elif event.is_action_pressed("ui_escape"):
		if casting_id != "" or channel_id != "":
			_cancel_cast()
		elif target != null:
			set_target(null)
	else:
		for i in range(1, 11):
			if event.is_action_pressed("action_%d" % i):
				use_action_slot(i - 1)
				return


func _mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom - 0.8, 1.6)
			spring.spring_length = _zoom
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom + 0.8, 16.0)
			spring.spring_length = _zoom
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if event.pressed and _drag_button == 0:
				_drag_button = event.button_index
				_drag_moved = 0.0
				_drag_time = _time
				_drag_start_pos = event.position
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif not event.pressed and event.button_index == _drag_button:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				get_viewport().warp_mouse(_drag_start_pos)
				var was_click: bool = _drag_moved < 6.0 and _time - _drag_time < 0.35
				var btn := _drag_button
				_drag_button = 0
				if was_click:
					_world_click(_drag_start_pos, btn == MOUSE_BUTTON_RIGHT)


func _world_click(screen_pos: Vector2, is_interact: bool) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 4 | 8)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var obj = hit["collider"]
	# Static colliders of NPCs/gather nodes are the bodies themselves.
	if obj is Npc:
		set_target(null)
		if is_interact:
			if distance_to(obj) > INTERACT_RANGE:
				Events.error_message.emit("You are too far away.")
			else:
				obj.interact()
	elif obj is GatherNode:
		if is_interact:
			_try_gather(obj)
	elif obj is Mob:
		var mob: Mob = obj
		set_target(mob)
		if is_interact:
			if not mob.alive:
				_try_loot(mob)
			else:
				start_attack()


func _tab_target() -> void:
	if Game.zone_node == null:
		return
	var mobs: Array = []
	for m in Game.zone_node.mobs_root.get_children():
		if m is Mob and m.alive and distance_to(m) < 35.0:
			var to_m: Vector3 = (m.global_position - global_position).normalized()
			if -global_transform.basis.z.dot(to_m) > 0.1:
				mobs.append(m)
	if mobs.is_empty():
		return
	mobs.sort_custom(func(a, b): return distance_to(a) < distance_to(b))
	var idx := mobs.find(target)
	set_target(mobs[(idx + 1) % mobs.size()])


func set_target(u: Unit) -> void:
	target = u
	Events.target_changed.emit(u)


func start_attack() -> void:
	if target == null or not (target is Mob) or not target.alive:
		return
	auto_attack_on = true
	if pet != null and is_instance_valid(pet) and pet.alive:
		pet.command_attack(target as Mob)


# ================================================================= main loop

func _physics_process(delta: float) -> void:
	_time += delta
	gcd_t = maxf(gcd_t - delta, 0.0)
	potion_cd = maxf(potion_cd - delta, 0.0)
	for id in cooldowns.keys():
		cooldowns[id] = float(cooldowns[id]) - delta
		if float(cooldowns[id]) <= 0.0:
			cooldowns.erase(id)
	tick_buffs(delta)
	if not alive:
		return
	_tick_regen(delta)
	_tick_combat_scan(delta)
	_tick_cast(delta)
	_movement(delta)
	_tick_autoattack(delta)

	_explore_t -= delta
	if _explore_t <= 0.0:
		_explore_t = 0.7
		Game.check_explore(global_position)
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = 30.0
		Game.save_game()

	if target != null and (not is_instance_valid(target) or (target is Mob and not target.visible)):
		set_target(null)


func _movement(delta: float) -> void:
	if is_stunned() or sitting:
		velocity.x = 0
		velocity.z = 0
		apply_gravity(delta)
		move_and_slide()
		if sitting and (Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back")):
			set_sitting(false)
		return

	var fb := Input.get_axis("move_back", "move_forward")
	var turn := Input.get_axis("turn_right", "turn_left")
	var strafe := Input.get_axis("strafe_left", "strafe_right")
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rmb:
		strafe += -turn  # A/D strafe while mouse-turning, classic style
	else:
		rotation.y += turn * TURN_SPEED * delta

	var moving_input := absf(fb) > 0.01 or absf(strafe) > 0.01
	if moving_input:
		_break_cast_on_move()
		if not rmb and absf(fb) > 0.01:
			# Swing the orbited camera back behind the character.
			_cam_orbit_offset = lerp_angle(_cam_orbit_offset, 0.0, delta * 5.0)
			cam_yaw.rotation.y = _cam_orbit_offset

	var speed := Formulas.RUN_SPEED
	speed *= 1.0 + Game.talent_mod("move_speed_pct") + buff_total("move_speed_pct")
	speed *= slow_factor()
	if is_rooted():
		speed = 0.0

	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var dir := fwd * fb + right * strafe
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var mult := BACKPEDAL_MULT if fb < -0.01 else 1.0
	velocity.x = dir.x * speed * mult
	velocity.z = dir.z * speed * mult
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	apply_gravity(delta)
	move_and_slide()
	model.moving = Vector2(velocity.x, velocity.z).length() > 0.5


func set_sitting(v: bool) -> void:
	if v and in_combat:
		return
	sitting = v
	model.sitting = v
	if not v:
		remove_buff("food")
		remove_buff("drink")


func _tick_regen(delta: float) -> void:
	_regen_t -= delta
	if _regen_t > 0.0:
		return
	_regen_t = 2.0
	var s := Game.stats()
	if res_type == "mana":
		if _time - _last_mana_spend > Formulas.FIVE_SECOND_RULE:
			resource = minf(resource + Formulas.mana_regen_per_tick(s["spi"]), resource_max)
		else:
			resource = minf(resource + Formulas.mana_regen_per_tick(s["spi"]) * Game.talent_mod("combat_regen_pct"), resource_max)
	else:
		if not in_combat:
			resource = maxf(resource - 3.0, 0.0)
	if not in_combat and not has_buff("food"):
		heal(Formulas.health_regen_per_tick(s["spi"], level) * (2.0 if sitting else 1.0), false)
	# Spirit Bond talent: passive regen while the pet is alive.
	var sb := Game.talent_mod("regen_with_pet_pct")
	if sb > 0.0 and pet != null and is_instance_valid(pet) and pet.alive:
		heal(hp_max * sb * 0.2, false)


func _tick_combat_scan(delta: float) -> void:
	_combat_scan_t -= delta
	if _combat_scan_t > 0.0:
		return
	_combat_scan_t = 0.5
	var was := in_combat
	in_combat = false
	if Game.zone_node != null:
		for m in Game.zone_node.mobs_root.get_children():
			if m is Mob and m.alive and m.state == Mob.State.AGGRO and (m.threat.has(self) or m.threat.has(pet)):
				in_combat = true
				break
	if was and not in_combat:
		Events.combat_log.emit("You leave combat.")
	elif not was and in_combat:
		set_sitting(false)
		Events.combat_log.emit("You enter combat.")


func _on_hit_reactions(amount: int, _source: Node) -> void:
	if res_type == "rage" and amount > 0:
		gain_rage(Formulas.rage_from_damage_taken(amount, level))
	if sitting:
		set_sitting(false)
	# Cheetah-style aspects break when struck.
	if amount > 0 and casting_id != "":
		pass  # no cast pushback in v1


func gain_rage(amount: float) -> void:
	if res_type != "rage":
		return
	resource = clampf(resource + amount, 0.0, 100.0)


# ================================================================= auto attack

func _tick_autoattack(delta: float) -> void:
	var haste := 1.0 + buff_total("attack_speed_pct")
	if _flurry_swings > 0:
		haste += Game.talent_mod("flurry_haste_pct")
	swing_t -= delta * haste
	ranged_swing_t -= delta * haste
	if not auto_attack_on or target == null or not is_instance_valid(target) or not target.alive:
		auto_attack_on = false
		return
	if not (target is Mob):
		return
	var dist := distance_to(target)
	var is_hunter: bool = Game.pc["class"] == "hunter"
	var melee_ok: bool = dist <= (target as Mob).melee_range + 0.6

	if melee_ok:
		if swing_t <= 0.0:
			if not _facing(target):
				swing_t = 0.5  # retry shortly instead of spamming every frame
				return
			swing_t = Game.weapon(true)["speed"]
			_melee_swing(false)
	elif is_hunter and dist >= 6.0 and dist <= 30.0 + Game.talent_mod("ranged_range_bonus"):
		var standing := Vector2(velocity.x, velocity.z).length() < 0.5
		if ranged_swing_t <= 0.0 and standing:
			if not _facing(target):
				ranged_swing_t = 0.5
				return
			ranged_swing_t = Game.weapon(false)["speed"]
			_melee_swing(true)


func _facing(u: Unit) -> bool:
	var to_u := (u.global_position - global_position).normalized()
	if -global_transform.basis.z.dot(to_u) < 0.0:
		Events.error_message.emit("You are facing the wrong way!")
		return false
	return true


func _melee_swing(ranged: bool) -> void:
	model.play_attack()
	var mob := target as Mob
	var kind := "ranged" if ranged else "melee"
	var crit := Game.crit_pct(kind)
	var outcome := Formulas.attack_roll(level, mob.level, 5.0, crit)
	if outcome == "miss":
		Events.combat_text.emit(mob.global_position + Vector3(0, 2.2, 0), "Miss", "miss")
		Events.combat_log.emit("Your attack misses %s." % mob.unit_name)
		return
	if outcome == "dodge":
		Events.combat_text.emit(mob.global_position + Vector3(0, 2.2, 0), "Dodge", "miss")
		Events.combat_log.emit("%s dodges your attack." % mob.unit_name)
		return
	var dmg := _weapon_damage(mob, 1.0, 0.0, ranged, outcome == "crit", "physical")
	mob.take_damage(dmg, "physical", self, outcome == "crit")
	if res_type == "rage":
		gain_rage(Formulas.rage_from_damage_dealt(dmg, level) + Game.talent_mod("rage_on_hit"))
	if outcome == "crit":
		_flurry_swings = 3
		var hoc := Game.talent_mod("heal_on_crit_pct")
		if hoc > 0.0:
			heal(hp_max * hoc, false)
	elif _flurry_swings > 0:
		_flurry_swings -= 1
	# Keep the pet on our target.
	if pet != null and is_instance_valid(pet) and pet.alive:
		pet.command_attack(mob)


func _weapon_damage(mob: Mob, weapon_pct: float, flat_bonus: float, ranged: bool, is_crit: bool, _school: String) -> float:
	var w := Game.weapon(not ranged)
	var base := randf_range(float(w["dmg"][0]), float(w["dmg"][1]))
	base += Formulas.weapon_damage_bonus(attack_power_value(ranged), float(w["speed"]))
	base = base * weapon_pct + flat_bonus
	base *= 1.0 + Game.talent_mod("ranged_damage_pct" if ranged else "melee_damage_pct")
	base *= _global_damage_mult(mob)
	if is_crit:
		var cb := 2.0 + Game.talent_mod("crit_damage_pct") + (Game.talent_mod("ranged_crit_bonus_pct") if ranged else 0.0)
		base *= cb
	var armor := Formulas.mob_armor(mob.level) * maxf(1.0 + mob.debuff_total("armor_pct"), 0.0)
	if ranged and Game.talent_mod("trueshot") > 0.0:
		armor *= 0.8
	base *= 1.0 - Formulas.armor_reduction(armor, level)
	return base


func _global_damage_mult(mob: Mob) -> float:
	var m := 1.0
	if Game.talent_mod("deathwish") > 0.0:
		m *= 1.15
	if Game.talent_mod("trueshot") > 0.0:
		pass  # +10% applied to ranged only below
	if mob.def.get("family", "") == "beast":
		m *= 1.0 + Game.talent_mod("beast_damage_pct")
	if Game.talent_mod("predators_wrath") > 0.0 and float(mob.hp) / float(mob.hp_max) < 0.35:
		m *= 1.15
	if has_buff("enrage"):
		m *= 1.0 + Game.talent_mod("enrage_damage_pct")
	return m


# ================================================================= abilities

func use_action_slot(slot: int) -> void:
	var id = Game.pc["action_bar"][slot]
	if id == null or str(id) == "":
		return
	use_ability(str(id))


func ability_cooldown_left(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


func use_ability(id: String) -> void:
	if not alive or is_stunned():
		return
	if not Game.knows(id):
		return
	var a := DB.ability(id)
	if casting_id != "" or channel_id != "":
		return
	var uses_gcd: bool = a.get("gcd", true)
	if uses_gcd and gcd_t > 0.0:
		return
	if cooldowns.has(id):
		Events.error_message.emit("That ability is not ready yet.")
		return
	if a.get("out_of_combat_only", false) and in_combat:
		Events.error_message.emit("You can't do that while in combat.")
		return

	var needs_enemy := _needs_enemy(a)
	var mob: Mob = target as Mob if target is Mob else null
	if needs_enemy:
		if mob == null or not mob.alive:
			Events.error_message.emit("You have no target.")
			return
		var dist := distance_to(mob)
		var rng: float = float(a.get("range", 0)) + _range_bonus(a)
		if rng > 0 and dist > rng + 0.6:
			Events.error_message.emit("Out of range.")
			return
		if a.has("min_range") and dist < float(a["min_range"]):
			Events.error_message.emit("Target too close.")
			return
		if not _facing(mob):
			return
		if a.has("requires_target_hp_below"):
			if float(mob.hp) / float(mob.hp_max) > float(a["requires_target_hp_below"]):
				Events.error_message.emit("Your target is not weak enough yet.")
				return

	if not _can_pay_cost(a):
		return

	if uses_gcd:
		gcd_t = Formulas.GCD
		Events.gcd_started.emit(Formulas.GCD)

	var cast_time := maxf(float(a.get("cast", 0)) + Game.talent_mod("cast_time", { "ability": id }), 0.0)
	if cast_time > 0.0:
		casting_id = id
		cast_total = cast_time
		cast_t = cast_time
		model.casting = true
		Events.cast_started.emit(a["name"], cast_time)
	elif a.has("channel"):
		_pay_cost(a)
		_start_cooldown(id, a)
		channel_id = id
		channel_t = float(a["channel"]["duration"])
		channel_tick_t = channel_t / float(a["channel"]["ticks"])
		model.casting = true
		Events.cast_started.emit(a["name"], channel_t)
	else:
		_pay_cost(a)
		_start_cooldown(id, a)
		_resolve_ability(id, a)


func _needs_enemy(a: Dictionary) -> bool:
	if a.get("aoe_at", "") == "self":
		return false
	if a.has("buff") or a.has("special") and str(a.get("special")) in \
			["conjure_food", "conjure_water", "call_pet", "evocation", "second_wind", "blink", "bestial_wrath", "mend_pet"]:
		return false
	if a.has("generates_rage") and not a.has("weapon_pct") and str(a.get("special", "")) != "charge":
		return false
	return a.has("weapon_pct") or a.has("flat") or a.has("dot") or a.has("debuff") \
		or a.has("slow") or a.has("root") or a.has("stun") or a.has("channel") \
		or str(a.get("special", "")) in ["charge", "polymorph"]


func _range_bonus(a: Dictionary) -> float:
	var b := Game.talent_mod("range_bonus", { "school": a.get("school", "") })
	if a.get("ranged", false) or a.has("min_range"):
		b += Game.talent_mod("ranged_range_bonus")
	return b


func _ability_cost(a: Dictionary) -> float:
	var cost: Dictionary = a.get("cost", {})
	if cost.has("rage"):
		return maxf(float(cost["rage"]) + Game.talent_mod("ability_cost", { "ability": _aid(a) }), 0.0)
	if cost.has("mana"):
		var c := float(cost["mana"]) + float(cost.get("mana_per_level", 0)) * maxf(level - int(a["level"]), 0)
		c *= 1.0 - Game.talent_mod("cost_reduction_pct", { "school": a.get("school", "") })
		if a.has("min_range"):
			c *= 1.0 - Game.talent_mod("cost_reduction_pct", { "school": "all_shots" })
		if Game.talent_mod("arcane_power") > 0.0:
			c *= 1.2
		return c
	return 0.0


func _aid(a: Dictionary) -> String:
	for id in DB.abilities:
		if DB.abilities[id] == a:
			return id
	return ""


func _can_pay_cost(a: Dictionary) -> bool:
	var cost: Dictionary = a.get("cost", {})
	if cost.has("health_pct"):
		return true
	var c := _ability_cost(a)
	if has_buff("clearcast") and cost.has("mana"):
		return true
	if cost.has("rage") and resource < c:
		Events.error_message.emit("Not enough rage.")
		return false
	if cost.has("mana") and resource < c:
		Events.error_message.emit("Not enough mana.")
		return false
	return true


func _pay_cost(a: Dictionary) -> void:
	var cost: Dictionary = a.get("cost", {})
	if cost.has("health_pct"):
		hp = maxi(hp - int(hp_max * float(cost["health_pct"])), 1)
	if cost.has("mana"):
		if has_buff("clearcast"):
			remove_buff("clearcast")
		else:
			resource = maxf(resource - _ability_cost(a), 0.0)
			_last_mana_spend = _time
	elif cost.has("rage"):
		var c := _ability_cost(a)
		if cost.get("consume_all_rage", false):
			_extra_rage_spent = resource - c
			resource = 0.0
		else:
			resource = maxf(resource - c, 0.0)


var _extra_rage_spent := 0.0


func _start_cooldown(id: String, a: Dictionary) -> void:
	var cd := maxf(float(a.get("cooldown", 0)) + Game.talent_mod("ability_cooldown", { "ability": id }), 0.0)
	if cd > 0.0:
		cooldowns[id] = cd
		Events.cooldown_started.emit(id, cd)


func _tick_cast(delta: float) -> void:
	if casting_id != "":
		cast_t -= delta
		Events.cast_progress.emit(1.0 - cast_t / cast_total)
		if cast_t <= 0.0:
			var id := casting_id
			casting_id = ""
			model.casting = false
			Events.cast_stopped.emit()
			if id == "_gather":
				if _gathering_node != null and is_instance_valid(_gathering_node) \
						and distance_to(_gathering_node) <= INTERACT_RANGE + 1.0:
					_gathering_node.complete_gather()
				_gathering_node = null
				return
			var a := DB.ability(id)
			# Re-validate target at cast completion.
			if _needs_enemy(a) and (target == null or not is_instance_valid(target) or not target.alive):
				return
			_pay_cost(a)
			_start_cooldown(id, a)
			if a.has("channel"):
				channel_id = id
				channel_t = float(a["channel"]["duration"])
				channel_tick_t = channel_t / float(a["channel"]["ticks"])
				model.casting = true
				Events.cast_started.emit(a["name"], channel_t)
			else:
				_resolve_ability(id, a)
	elif channel_id != "":
		channel_t -= delta
		channel_tick_t -= delta
		var a2 := DB.ability(channel_id)
		if channel_tick_t <= 0.0:
			channel_tick_t += float(a2["channel"]["duration"]) / float(a2["channel"]["ticks"])
			_channel_tick(channel_id, a2)
		if channel_t <= 0.0:
			channel_id = ""
			model.casting = false
			Events.cast_stopped.emit()


func _break_cast_on_move() -> void:
	if casting_id != "" or channel_id != "":
		_cancel_cast()


func _cancel_cast() -> void:
	if casting_id != "":
		casting_id = ""
		model.casting = false
		Events.cast_stopped.emit()
	if channel_id != "":
		channel_id = ""
		model.casting = false
		Events.cast_stopped.emit()
	if _gathering_node != null:
		_gathering_node = null


# ================================================================= resolution

func _resolve_ability(id: String, a: Dictionary) -> void:
	model.play_attack()
	var mob: Mob = target as Mob if target is Mob else null
	match str(a.get("special", "")):
		"charge":
			_do_charge(mob, a)
			return
		"blink":
			_do_blink()
			return
		"conjure_food":
			Game.add_item("conjured_bread", 5)
			return
		"conjure_water":
			Game.add_item("conjured_water", 5)
			return
		"call_pet":
			_summon_pet()
			return
		"polymorph":
			_do_polymorph(mob, a)
			return
		"second_wind":
			apply_buff({ "id": "second_wind", "name": "Second Wind", "kind": "buff", "duration": 10.0,
				"hot": { "tick": hp_max * 0.02, "interval": 1.0 } })
			return
		"bestial_wrath":
			if pet != null and is_instance_valid(pet) and pet.alive:
				pet.apply_buff({ "id": "bestial_wrath", "name": "Bestial Wrath", "kind": "buff", "duration": 18.0 })
			else:
				Events.error_message.emit("You have no pet.")
			return
		_:
			pass

	if a.has("generates_rage"):
		var bonus := 0.0
		if id == "bloodrage":
			bonus = Game.talent_mod("bloodrage_rage")
		gain_rage(float(a["generates_rage"]) + bonus)

	# Self buffs (Battle Shout, aspects, armors, Ice Barrier...)
	if a.has("buff"):
		_apply_self_buff(id, a)
	if a.has("absorb"):
		var amount := float(a["absorb"]) + float(a.get("absorb_per_level", 0)) * maxf(level - int(a["level"]), 0)
		apply_buff({ "id": id, "name": a["name"], "kind": "buff",
			"duration": float(a.get("buff_duration", 60)), "absorb": amount })

	# Gather targets.
	var victims: Array = []
	if a.get("aoe_at", "") == "self":
		victims = _mobs_within(float(a["aoe"]))
	elif mob != null and mob.alive:
		victims = [mob]
		if a.has("multi_targets"):
			for m in _mobs_within(12.0):
				if m != mob and victims.size() < int(a["multi_targets"]):
					victims.append(m)
	if victims.is_empty():
		return

	for v in victims:
		_apply_ability_to(v as Mob, id, a)
	if not victims.is_empty():
		start_attack()


func _apply_ability_to(mob: Mob, id: String, a: Dictionary) -> void:
	if mob == null or not is_instance_valid(mob) or not mob.alive:
		return
	var school: String = a.get("school", "physical")
	var lvl_scale := maxf(level - int(a["level"]), 0)
	var dmg_mult := 1.0 + Game.talent_mod("ability_damage_pct", { "ability": id })

	if a.has("weapon_pct") or a.has("flat"):
		var flat := 0.0
		if a.has("flat"):
			flat = randf_range(float(a["flat"][0]), float(a["flat"][1])) + float(a.get("flat_per_level", 0)) * lvl_scale
		if id == "execute":
			flat += _extra_rage_spent * float(a.get("bonus_per_extra_rage", 2.0))
			_extra_rage_spent = 0.0
		if school == "physical":
			var ranged: bool = a.get("ranged", false)
			var crit := Game.crit_pct("ranged" if ranged else "melee")
			var outcome := Formulas.attack_roll(level, mob.level, 5.0, crit)
			if outcome == "miss" or outcome == "dodge":
				Events.combat_text.emit(mob.global_position + Vector3(0, 2.2, 0), outcome.capitalize(), "miss")
			else:
				var dmg := _weapon_damage(mob, float(a.get("weapon_pct", 0.0)), flat, ranged, outcome == "crit", school)
				dmg *= dmg_mult
				mob.take_damage(dmg, school, self, outcome == "crit", a["name"])
				if res_type == "rage" and a.has("weapon_pct"):
					gain_rage(Formulas.rage_from_damage_dealt(dmg, level) * 0.5)
		else:
			_spell_hit(mob, id, a, flat * dmg_mult, school)

	if a.has("dot") and mob.alive:
		var dot: Dictionary = a["dot"]
		var tick := float(dot["tick"]) + float(dot.get("per_level", 0)) * lvl_scale
		tick *= dmg_mult
		tick *= 1.0 + Game.talent_mod("school_damage_pct", { "school": school }) + _spell_wide_mult()
		if school == "physical":
			tick *= 1.0 + Game.talent_mod("bleed_damage_pct")
		mob.apply_buff({ "id": id, "name": a["name"], "kind": "debuff",
			"duration": float(dot["duration"]),
			"dot": { "tick": tick, "interval": float(dot["interval"]), "school": school, "source": self } })
	if a.has("slow") and mob.alive:
		var pct := float(a["slow"]["pct"]) * (1.0 + Game.talent_mod("slow_bonus_pct", { "school": school }))
		mob.apply_buff({ "id": id + "_slow", "name": a["name"], "kind": "debuff",
			"duration": float(a["slow"]["duration"]), "slow_pct": pct })
	if a.has("root") and mob.alive:
		mob.apply_buff({ "id": id + "_root", "name": a["name"], "kind": "debuff",
			"duration": float(a["root"]["duration"]), "root": true })
	if a.has("stun") and mob.alive:
		mob.apply_buff({ "id": id + "_stun", "name": a["name"], "kind": "debuff",
			"duration": float(a["stun"]["duration"]), "stun": true })
	if a.has("debuff") and mob.alive:
		var d: Dictionary = a["debuff"]
		mob.apply_buff({ "id": id, "name": a["name"], "kind": "debuff",
			"duration": float(d["duration"]), "stat": d["stat"], "amount": float(d["amount"]),
			"max_stacks": int(d.get("max_stacks", 1)) })
	if mob.alive:
		mob.add_threat(self, 1.0)


func _spell_wide_mult() -> float:
	var m := Game.talent_mod("spell_damage_pct")
	if Game.talent_mod("arcane_power") > 0.0:
		m += 0.2
	return m


func _spell_hit(mob: Mob, _id: String, a: Dictionary, flat: float, school: String) -> void:
	var hit_bonus := Game.talent_mod("spell_hit_pct")
	if randf() * 100.0 < Formulas.spell_resist_chance(level, mob.level, hit_bonus):
		Events.combat_text.emit(mob.global_position + Vector3(0, 2.2, 0), "Resist", "miss")
		return
	var s := Game.stats()
	var dmg := flat + Formulas.spell_bonus(s["int"], level)
	dmg *= 1.0 + Game.talent_mod("school_damage_pct", { "school": school }) + _spell_wide_mult()
	dmg *= _global_damage_mult(mob)
	var crit := Game.crit_pct("spell") + Game.talent_mod("school_crit_pct", { "school": school })
	if mob.is_rooted():
		crit += Game.talent_mod("shatter_crit_pct")
	var is_crit := randf() * 100.0 < crit + Formulas.crit_bonus_vs(level, mob.level)
	if is_crit:
		dmg *= 1.5 + Game.talent_mod("school_crit_bonus_pct", { "school": school })
	mob.take_damage(dmg, school, self, is_crit, a["name"])
	# Clearcasting proc.
	if randf() * 100.0 < Game.talent_mod("clearcast_pct"):
		apply_buff({ "id": "clearcast", "name": "Clearcasting", "kind": "buff", "duration": 15.0 })


func _apply_self_buff(id: String, a: Dictionary) -> void:
	var b: Dictionary = a["buff"]
	var amount := float(b.get("amount", 0)) + float(b.get("per_level", 0)) * maxf(level - int(a["level"]), 0)
	amount *= 1.0 + Game.talent_mod("ability_power_pct", { "ability": id })
	# Only one aspect at a time.
	if b.get("aspect", false):
		for other in buffs.duplicate():
			if other.get("aspect", false):
				_drop_buff(other)
	apply_buff({ "id": id, "name": a["name"], "kind": "buff", "duration": float(b["duration"]),
		"stat": b["stat"], "amount": amount, "aspect": b.get("aspect", false),
		"breaks_on_hit": b.get("breaks_on_hit", false) })
	Events.player_stats_changed.emit()


func _channel_tick(id: String, a: Dictionary) -> void:
	match str(a.get("special", "")):
		"evocation":
			resource = minf(resource + resource_max * 0.075, resource_max)
			return
		"mend_pet":
			if pet != null and is_instance_valid(pet) and pet.alive:
				pet.heal(float(a.get("heal_tick", 8)) + float(a.get("heal_per_level", 0)) * maxf(level - int(a["level"]), 0))
			return
		_:
			pass
	var mob: Mob = target as Mob if target is Mob else null
	if mob == null or not is_instance_valid(mob) or not mob.alive:
		_cancel_cast()
		return
	var lvl_scale := maxf(level - int(a["level"]), 0)
	var flat := randf_range(float(a["flat"][0]), float(a["flat"][1])) + float(a.get("flat_per_level", 0)) * lvl_scale
	flat *= 1.0 + Game.talent_mod("ability_damage_pct", { "ability": id })
	_spell_hit(mob, id, a, flat, a.get("school", "arcane"))


func _do_charge(mob: Mob, a: Dictionary) -> void:
	if mob == null:
		return
	var dir := (mob.global_position - global_position).normalized()
	var dest := mob.global_position - dir * 1.5
	var tw := create_tween()
	tw.tween_property(self, "global_position", dest, distance_to(mob) / 35.0)
	gain_rage(float(a["generates_rage"]) + Game.talent_mod("charge_rage"))
	mob.apply_buff({ "id": "charge_stun", "name": "Charge", "kind": "debuff",
		"duration": float(a["stun"]["duration"]), "stun": true })
	mob.add_threat(self, 5.0)
	start_attack()


func _do_blink() -> void:
	remove_buff("frost_nova_root")
	for b in buffs.duplicate():
		if b.get("root", false) or b.get("stun", false):
			_drop_buff(b)
	var fwd := -global_transform.basis.z
	var from := global_position + Vector3(0, 1, 0)
	var to := from + fwd * 15.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var dest := to
	if not hit.is_empty():
		dest = (hit["position"] as Vector3) - fwd * 1.0
	if Game.zone_node != null:
		dest.y = Game.zone_node.ground_height(dest.x, dest.z) + 0.4
	global_position = dest


func _do_polymorph(mob: Mob, a: Dictionary) -> void:
	if mob == null:
		return
	if not (mob.def.get("family", "") in ["beast", "humanoid"]):
		Events.error_message.emit("That target cannot be polymorphed.")
		return
	if poly_target != null and is_instance_valid(poly_target):
		poly_target.remove_buff("polymorph")
	poly_target = mob
	mob.apply_buff({ "id": "polymorph", "name": "Polymorph", "kind": "debuff",
		"duration": float(a.get("polymorph_duration", 20)) })


func _mobs_within(radius: float) -> Array:
	var out: Array = []
	if Game.zone_node == null:
		return out
	for m in Game.zone_node.mobs_root.get_children():
		if m is Mob and m.alive and distance_to(m) <= radius:
			out.append(m)
	return out


func _summon_pet() -> void:
	if pet != null and is_instance_valid(pet):
		pet.queue_free()
	pet = Pet.new()
	get_parent().add_child(pet)
	pet.setup(self)
	pet.global_position = global_position + global_transform.basis.x * -1.6
	Game.pc["has_pet"] = true
	Events.pet_changed.emit(pet)


# ================================================================= items

var _gathering_node: GatherNode = null


func _try_gather(gnode: GatherNode) -> void:
	if distance_to(gnode) > INTERACT_RANGE:
		Events.error_message.emit("You are too far away.")
		return
	if in_combat:
		Events.error_message.emit("You can't do that while in combat.")
		return
	if not gnode.can_gather():
		return
	_gathering_node = gnode
	Events.cast_started.emit(gnode.def["name"], float(gnode.def.get("gather_time", 3.0)))
	casting_id = "_gather"
	cast_total = float(gnode.def.get("gather_time", 3.0))
	cast_t = cast_total
	model.casting = true


func _try_loot(mob: Mob) -> void:
	if distance_to(mob) > INTERACT_RANGE:
		Events.error_message.emit("You are too far away.")
		return
	if mob.has_loot():
		Events.open_loot.emit(mob)
	elif mob.can_skin():
		mob.do_skin()
	else:
		Events.error_message.emit("Nothing to loot.")


func use_bag_item(i: int) -> void:
	var e = Game.pc["inventory"][i]
	if e == null:
		return
	var it := DB.item(str(e["id"]))
	if it.get("slot", "none") != "none":
		Game.equip_from_bag(i)
		return
	if not it.has("use"):
		return
	var use: Dictionary = it["use"]
	var amount_v = use.get("amount", 0)
	match str(use["type"]):
		"food", "drink":
			if in_combat:
				Events.error_message.emit("You can't eat while in combat.")
				return
			var amount := float(amount_v)
			if use.get("scale_level", false):
				amount *= 1.0 + 0.35 * (level - 1)
			set_sitting(true)
			var is_food: bool = str(use["type"]) == "food"
			apply_buff({ "id": "food" if is_food else "drink",
				"name": "Eating" if is_food else "Drinking", "kind": "buff",
				"duration": Formulas.EAT_DURATION,
				"hot": { "tick": amount / 9.0, "interval": 2.0, "mana": not is_food } })
			Game.remove_slot(i, 1)
		"potion_hp", "potion_mana":
			if potion_cd > 0.0:
				Events.error_message.emit("Potion is not ready yet.")
				return
			potion_cd = float(use.get("cooldown", 120))
			var lo := float(amount_v[0])
			var hi := float(amount_v[1])
			var roll := randf_range(lo, hi)
			if str(use["type"]) == "potion_hp":
				heal(roll)
			else:
				resource = minf(resource + roll, resource_max)
			Game.remove_slot(i, 1)


# Drinking restores mana; Unit.tick_buffs handles hp "hot", so intercept mana here.
func heal(amount: float, show_text: bool = true) -> void:
	super.heal(amount, show_text)


func tick_buffs(delta: float) -> void:
	# Mana drinks: reroute their hot ticks to mana.
	for b in buffs:
		if b.has("hot") and b["hot"].get("mana", false):
			var hot: Dictionary = b["hot"]
			hot["next"] = float(hot.get("next", 2.0)) - delta
			if float(hot["next"]) <= 0.0:
				hot["next"] = float(hot["next"]) + float(hot.get("interval", 2.0))
				resource = minf(resource + float(hot["tick"]), resource_max)
			b["t"] = float(b["t"]) - delta
			if float(b["t"]) <= 0.0:
				_drop_buff(b)
	# Strip mana hots before the generic pass would heal hp with them.
	var saved: Array = []
	for b in buffs.duplicate():
		if b.has("hot") and b["hot"].get("mana", false):
			buffs.erase(b)
			saved.append(b)
	super.tick_buffs(delta)
	for b in saved:
		buffs.append(b)


# ================================================================= death

func die(killer: Node) -> void:
	super.die(killer)
	auto_attack_on = false
	_cancel_cast()
	set_target(null)
	resource = 0.0
	if pet != null and is_instance_valid(pet):
		pet.command_follow()
	Events.player_died.emit()


func respawn_at_graveyard() -> void:
	if Game.zone_node == null:
		return
	global_position = Game.zone_node.graveyard_position()
	alive = true
	model.revive_pose()
	hp = int(hp_max * 0.5)
	if res_type == "mana":
		resource = resource_max * 0.5
	Events.player_respawned.emit()


func _on_level_up(_new_level: int) -> void:
	recompute_vitals(true)
	if pet != null and is_instance_valid(pet):
		pet._recalc_stats()
		pet.hp = pet.hp_max
	Events.combat_text.emit(global_position + Vector3(0, 2.5, 0), "Level Up!", "levelup")
