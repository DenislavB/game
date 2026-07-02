extends Node
## Events — global signal bus. Systems emit, UI listens.

# Player vitals / progression
signal player_stats_changed
signal player_xp_changed
signal player_level_up(new_level: int)
signal player_died
signal player_respawned
signal money_changed
signal inventory_changed
signal equipment_changed
signal abilities_changed
signal talents_changed
signal action_bar_changed
signal buffs_changed(unit: Node)
signal pet_changed(pet: Node)

# Combat / casting
signal target_changed(unit: Node)
signal cast_started(label: String, duration: float)
signal cast_progress(t: float)
signal cast_stopped
signal gcd_started(duration: float)
signal cooldown_started(ability_id: String, duration: float)
signal combat_text(world_pos: Vector3, text: String, kind: String)
signal combat_log(text: String)
signal error_message(text: String)
signal game_message(text: String)
signal mob_killed(mob: Node)

# Quests
signal quest_accepted(quest_id: String)
signal quest_progress(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_log_changed

# Interaction windows
signal open_loot(corpse: Node)
signal close_loot
signal open_vendor(npc: Node)
signal open_trainer(npc: Node)
signal open_quest_giver(npc: Node)
signal close_windows

# World
signal zone_changed(zone_id: String)
signal request_zone_travel(zone_id: String, spawn: String)
