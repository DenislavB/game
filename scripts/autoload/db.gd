extends Node
## DB — loads all game data from res://data/*.json at startup.
## Content lives in JSON so it stays engine-agnostic and easy to edit.

var races: Dictionary = {}
var classes: Dictionary = {}
var abilities: Dictionary = {}
var talents: Dictionary = {}
var items: Dictionary = {}
var mobs: Dictionary = {}
var loot_tables: Dictionary = {}
var professions: Dictionary = {}
var zones: Dictionary = {}
var quests: Dictionary = {}
var quests_by_giver: Dictionary = {}
var quests_by_turnin: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	## Re-read all data files (used by the Character Editor after saving).
	quests_by_giver.clear()
	quests_by_turnin.clear()
	zones.clear()
	quests.clear()
	races = _load_json("res://data/races.json")
	classes = _load_json("res://data/classes.json")
	abilities = _load_json("res://data/abilities.json")
	talents = _load_json("res://data/talents.json")
	items = _load_json("res://data/items.json")
	mobs = _load_json("res://data/mobs.json")
	loot_tables = _load_json("res://data/loot_tables.json")
	professions = _load_json("res://data/professions.json")
	_load_dir("res://data/zones", zones)
	_load_dir("res://data/quests", quests, true)
	_index_quests()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DB: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		push_error("DB: bad JSON in %s" % path)
		return {}
	return parsed


func _load_dir(dir_path: String, target: Dictionary, merge: bool = false) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("DB: cannot open dir %s" % dir_path)
		return
	for file in dir.get_files():
		# Exported builds keep .json files with a .remap suffix sometimes; strip safely.
		var fname := file.trim_suffix(".remap")
		if not fname.ends_with(".json"):
			continue
		var data := _load_json(dir_path + "/" + fname)
		if merge:
			target.merge(data)
		else:
			target[data.get("id", fname.get_basename())] = data


func _index_quests() -> void:
	for qid in quests:
		var q: Dictionary = quests[qid]
		var giver: String = q.get("giver", "")
		var turnin: String = q.get("turnin", giver)
		if not quests_by_giver.has(giver):
			quests_by_giver[giver] = []
		quests_by_giver[giver].append(qid)
		if not quests_by_turnin.has(turnin):
			quests_by_turnin[turnin] = []
		quests_by_turnin[turnin].append(qid)


func ability(id: String) -> Dictionary:
	return abilities.get(id, {})


func item(id: String) -> Dictionary:
	return items.get(id, {})


func quest(id: String) -> Dictionary:
	return quests.get(id, {})


func mob(id: String) -> Dictionary:
	return mobs.get(id, {})


func class_abilities(class_id: String) -> Array:
	## All trainable abilities for a class, sorted by learn level.
	var out: Array = []
	for id in abilities:
		var a: Dictionary = abilities[id]
		if a.get("class", "") == class_id and not a.get("from_talent", false):
			out.append(id)
	out.sort_custom(func(x, y): return abilities[x]["level"] < abilities[y]["level"])
	return out


func quality_color(quality: String) -> Color:
	match quality:
		"poor": return Color("9d9d9d")
		"common": return Color("ffffff")
		"uncommon": return Color("1eff00")
		"rare": return Color("0070dd")
		"epic": return Color("a335ee")
		"quest": return Color("ffd100")
		_: return Color("ffffff")
