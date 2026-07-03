class_name Pet
extends Unit
## Companion pet: the hunter's wolf, the warlock's imp (ranged caster)
## or voidwalker (tanky, high threat). Follows the owner, attacks their
## target on command, and generates extra threat.

var kind := "wolf"
var owner_unit: Unit = null
var attack_target: Mob = null
var _swing_t := 0.0
var _regen_t := 0.0


func threat_mult() -> float:
	match kind:
		"voidwalker": return 3.5
		"imp": return 1.2
		_: return 2.5


func setup(p_owner: Unit, p_kind: String = "wolf") -> void:
	owner_unit = p_owner
	kind = p_kind
	is_player_unit = true
	level = int(Game.pc["level"])
	_recalc_stats()
	hp = hp_max

	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.4
	cs.shape = cap
	cs.position.y = 0.7
	add_child(cs)

	model = ActorModel.new()
	add_child(model)
	match kind:
		"imp":
			unit_name = "Imp"
			model.build_creature("spirit", Color("c05838"), 0.55)
		"voidwalker":
			unit_name = "Voidwalker"
			model.build_creature("spirit", Color("4a5ad8"), 1.15)
		_:
			unit_name = "Wolf"
			var def := DB.mob("hunter_wolf_pet")
			model.build_creature("wolf", Color(def["color"]), float(def["scale"]))

	var label := Label3D.new()
	label.text = unit_name
	label.font_size = 28
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("60d060")
	label.outline_size = 5
	label.position.y = 1.8
	add_child(label)


func _recalc_stats() -> void:
	level = int(Game.pc["level"])
	var hp_f := 1.0 + Game.talent_mod("pet_health_pct")
	var base := 45.0 + level * 13.0 + level * level * 0.6
	match kind:
		"voidwalker": base *= 1.7
		"imp": base *= 0.65
	hp_max = int(base * hp_f)


func pet_damage() -> float:
	var avg := 2.5 + level * 1.3
	match kind:
		"voidwalker": avg = 2.0 + level * 1.0
		"imp": avg = 3.0 + level * 1.4
	avg *= 1.0 + Game.talent_mod("pet_damage_pct")
	if has_buff("bestial_wrath"):
		avg *= 1.5
	return randf_range(avg * 0.8, avg * 1.2)


func command_attack(target: Mob) -> void:
	if target != null and is_instance_valid(target) and target.alive:
		attack_target = target


func command_follow() -> void:
	attack_target = null


func _physics_process(delta: float) -> void:
	if owner_unit == null or not is_instance_valid(owner_unit):
		return
	tick_buffs(delta)
	if not alive:
		return
	_regen_t -= delta
	if _regen_t <= 0.0:
		_regen_t = 2.0
		if attack_target == null and hp < hp_max:
			heal(hp_max * 0.04, false)

	if attack_target != null and (not is_instance_valid(attack_target) or not attack_target.alive):
		attack_target = null

	var goal: Vector3
	var goal_range: float
	if attack_target != null:
		goal = attack_target.global_position
		# The imp fights at range like its master taught it.
		goal_range = 14.0 if kind == "imp" else attack_target.melee_range
	else:
		# Heel at the owner's left side.
		goal = owner_unit.global_position + owner_unit.global_transform.basis.x * -1.6
		goal_range = 1.2

	var to_goal := goal - global_position
	var dist := Vector2(to_goal.x, to_goal.z).length()
	if dist > goal_range:
		var dir := to_goal.normalized()
		var spd := 8.5 * slow_factor()
		# Teleport to the owner if left far behind (classic pet catch-up).
		if attack_target == null and dist > 40.0:
			global_position = owner_unit.global_position
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		face_direction(to_goal, delta)
	else:
		velocity.x = 0
		velocity.z = 0
		if attack_target != null:
			face_direction(to_goal, delta)
			_swing_t -= delta
			if _swing_t <= 0.0:
				var speed := 2.4 if kind == "imp" else 1.6
				_swing_t = speed / (1.0 + Game.talent_mod("pet_attack_speed_pct"))
				_swing()
	model.moving = Vector2(velocity.x, velocity.z).length() > 0.5
	apply_gravity(delta)
	move_and_slide()


func _swing() -> void:
	if kind == "imp":
		# Firebolt: a small ranged spell, no armor mitigation.
		model.play_attack("bolt")
		FX.bolt(get_parent(), global_position + Vector3(0, 1.0, 0),
			attack_target.global_position + Vector3(0, 1.0, 0), Color("ff7030"))
		SFX.play_at("spell_fire", global_position + Vector3(0, 1.0, 0), get_parent())
		if randf() * 100.0 < Formulas.spell_resist_chance(level, attack_target.level, 0.0):
			Events.combat_text.emit(attack_target.global_position + Vector3(0, 2, 0), "Resist", "mob_miss")
			return
		attack_target.take_damage(pet_damage(), "fire", self)
		if is_instance_valid(attack_target) and attack_target.alive:
			attack_target.add_threat(self, pet_damage() * threat_mult())
		return
	model.play_attack("claw")
	var outcome := Formulas.attack_roll(level, attack_target.level, 5.0, 5.0)
	if outcome == "miss" or outcome == "dodge":
		Events.combat_text.emit(attack_target.global_position + Vector3(0, 2, 0), outcome.capitalize(), "mob_miss")
		return
	var dmg := pet_damage()
	if outcome == "crit":
		dmg *= 2.0
	dmg *= 1.0 - Formulas.armor_reduction(Formulas.mob_armor(attack_target.level), level)
	attack_target.take_damage(dmg, "physical", self, outcome == "crit")
	if is_instance_valid(attack_target) and attack_target.alive:
		attack_target.add_threat(self, dmg * threat_mult())


func die(killer: Node) -> void:
	super.die(killer)
	Events.game_message.emit("Your %s has died." % unit_name.to_lower())
	Events.pet_changed.emit(null)
	await get_tree().create_timer(4.0).timeout
	queue_free()
