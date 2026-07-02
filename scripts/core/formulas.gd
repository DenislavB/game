class_name Formulas
## Classic-style combat, XP and stat math. All tuning constants live here.

const MAX_LEVEL := 60
const GCD := 1.5
const MELEE_RANGE := 3.2
const HP_PER_STA := 10.0
const MANA_PER_INT := 15.0
const CRIT_PER_AGI := 0.05     # % crit per point of agility
const DODGE_PER_AGI := 0.04    # % dodge per point of agility
const ARMOR_PER_AGI := 2.0
const BASE_CRIT := 5.0
const BASE_MISS := 5.0
const RUN_SPEED := 7.0
const EAT_DURATION := 18.0
const FIVE_SECOND_RULE := 5.0


# ---------- Experience ----------

static func xp_to_level(level: int) -> int:
	# Slow, grindy curve. Level 1->2 = 400 xp, scaling to ~150k at 59->60.
	return 40 * level * level + 360 * level


static func gray_level(player_level: int) -> int:
	# Mobs at or below this level grant no XP.
	if player_level <= 5:
		return 0
	elif player_level <= 39:
		return player_level - 5 - int(floor(player_level / 10.0))
	else:
		return player_level - 1 - int(floor(player_level / 5.0))


static func mob_xp(mob_level: int, player_level: int, elite: bool) -> int:
	if mob_level <= gray_level(player_level):
		return 0
	var base := float(mob_level) * 5.0 + 45.0
	var diff := mob_level - player_level
	if diff > 0:
		base *= 1.0 + 0.05 * minf(diff, 4)
	else:
		# Linear falloff toward the gray threshold.
		var zd := player_level - gray_level(player_level)
		base *= 1.0 - float(-diff) / float(maxi(zd, 1))
	if elite:
		base *= 2.0
	return maxi(int(base), 1)


# ---------- Mob scaling ----------

static func mob_health(level: int, elite: bool) -> int:
	var hp := 30.0 + level * 16.0 + level * level * 1.15
	return int(hp * (2.6 if elite else 1.0))


static func mob_damage(level: int, elite: bool) -> Vector2:
	var avg := 3.0 + level * 2.0 + level * level * 0.04
	if elite:
		avg *= 1.7
	return Vector2(avg * 0.8, avg * 1.2)


static func mob_armor(level: int) -> float:
	return level * 45.0


static func mob_attack_speed() -> float:
	return 2.0


# ---------- Mitigation & hit tables ----------

static func armor_reduction(armor: float, attacker_level: int) -> float:
	var dr := armor / (armor + 400.0 + 85.0 * attacker_level)
	return clampf(dr, 0.0, 0.75)


static func miss_chance(attacker_level: int, defender_level: int) -> float:
	return clampf(BASE_MISS + 1.5 * float(defender_level - attacker_level), 0.0, 40.0)


static func dodge_chance_mob(attacker_level: int, defender_level: int) -> float:
	return clampf(5.0 + 1.0 * float(defender_level - attacker_level), 0.0, 20.0)


static func spell_resist_chance(attacker_level: int, defender_level: int, hit_bonus: float) -> float:
	var c := 4.0 + 2.0 * float(defender_level - attacker_level) - hit_bonus
	return clampf(c, 1.0, 40.0)


static func crit_bonus_vs(attacker_level: int, defender_level: int) -> float:
	# Higher-level targets are harder to crit.
	return -0.4 * float(defender_level - attacker_level)


static func attack_roll(attacker_level: int, defender_level: int, defender_dodge: float, crit: float) -> String:
	## One roll on a classic-style attack table: miss -> dodge -> crit -> hit.
	var r := randf() * 100.0
	var miss := miss_chance(attacker_level, defender_level)
	if r < miss:
		return "miss"
	r -= miss
	if r < defender_dodge:
		return "dodge"
	r -= defender_dodge
	if r < crit + crit_bonus_vs(attacker_level, defender_level):
		return "crit"
	return "hit"


# ---------- Resources ----------

static func rage_from_damage_dealt(dmg: float, level: int) -> float:
	return 3.0 + dmg * 8.0 / (2.0 * level + 20.0)


static func rage_from_damage_taken(dmg: float, level: int) -> float:
	return dmg * 5.0 / (2.0 * level + 20.0)


static func mana_regen_per_tick(spirit: float) -> float:
	# Per 2-second tick, outside the five-second rule.
	return 6.0 + spirit / 3.5


static func health_regen_per_tick(spirit: float, level: int) -> float:
	# Out of combat only.
	return 2.0 + spirit / 4.0 + level * 0.2


# ---------- Attack power ----------

static func melee_attack_power(strength: float, level: int) -> float:
	return strength * 2.0 + level * 2.0


static func ranged_attack_power(agility: float, level: int) -> float:
	return agility * 2.0 + level * 2.0


static func weapon_damage_bonus(attack_power: float, weapon_speed: float) -> float:
	return attack_power / 14.0 * weapon_speed


static func spell_bonus(intellect: float, level: int) -> float:
	# Flat bonus added to damaging spells.
	return intellect * 0.12 + level * 0.3


# ---------- Economy ----------

static func ability_train_cost(ability_level: int) -> int:
	# In copper. Trainers get expensive, classic style.
	return maxi(10, 35 * ability_level * ability_level)


static func money_string(copper: int) -> String:
	var g := copper / 10000
	var s := (copper % 10000) / 100
	var c := copper % 100
	var parts: PackedStringArray = []
	if g > 0:
		parts.append("%dg" % g)
	if s > 0 or g > 0:
		parts.append("%ds" % s)
	parts.append("%dc" % c)
	return " ".join(parts)
