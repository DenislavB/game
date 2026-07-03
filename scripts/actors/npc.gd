class_name Npc
extends StaticBody3D
## Friendly NPC: quest giver, vendor and/or class trainer.
## Shows the classic "!" / "?" markers above quest NPCs.

var npc_id := ""
var npc_name := ""
var title := ""
var roles: Array = []
var trainer_class := ""
var stock: Array = []
var model: ActorModel
var _marker: Label3D


func setup(ndef: Dictionary) -> void:
	npc_id = ndef["id"]
	npc_name = ndef["name"]
	title = ndef.get("title", "")
	roles = ndef.get("roles", [])
	trainer_class = ndef.get("trainer", "")
	stock = ndef.get("stock", [])

	collision_layer = 8
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 2.0
	cs.shape = cap
	cs.position.y = 1.0
	add_child(cs)

	var race: Dictionary = DB.races.get(ndef.get("race", "human"), DB.races["human"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(npc_id)
	var skins: Array = race["skin_colors"]
	var shirt := Color.from_hsv(rng.randf(), 0.35, 0.55)
	if trainer_class != "":
		shirt = Color(DB.classes[trainer_class]["color"]).darkened(0.2)
	# Hand-tuned looks from the Character Editor override the generated ones.
	var app: Dictionary = ndef.get("appearance", {})
	var skin_c := Color(str(app["skin"])) if app.has("skin") else Color(skins[rng.randi_range(0, skins.size() - 1)])
	if app.has("shirt"):
		shirt = Color(str(app["shirt"]))
	var pants_c := Color(str(app["pants"])) if app.has("pants") else shirt.darkened(0.5)
	var hair_c := Color(str(app["hair"])) if app.has("hair") else \
		Color.from_hsv(rng.randf() * 0.15, 0.5, rng.randf_range(0.1, 0.5))
	model = ActorModel.new()
	add_child(model)
	model.build_humanoid({
		"skin": skin_c,
		"shirt": shirt,
		"pants": pants_c,
		"features": race.get("model", {}),
		"hair": hair_c
	})

	var label := Label3D.new()
	label.text = npc_name + ("\n<%s>" % title if title != "" else "")
	label.font_size = 30
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("a0e8a0")
	label.outline_size = 6
	label.position.y = 2.5
	label.visibility_range_end = 40.0
	add_child(label)

	_marker = Label3D.new()
	_marker.font_size = 120
	_marker.pixel_size = 0.01
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.outline_size = 12
	_marker.position.y = 3.4
	_marker.visibility_range_end = 90.0
	add_child(_marker)
	Events.quest_log_changed.connect(_update_marker)
	Events.player_xp_changed.connect(_update_marker)
	_update_marker()


func _update_marker() -> void:
	if not ("quest" in roles):
		_marker.text = ""
		return
	match Game.npc_quest_marker(npc_id):
		"!":
			_marker.text = "!"
			_marker.modulate = Color("ffd100")
		"?":
			_marker.text = "?"
			_marker.modulate = Color("ffd100")
		"?gray":
			_marker.text = "?"
			_marker.modulate = Color("9d9d9d")
		_:
			_marker.text = ""


func interact() -> void:
	if "quest" in roles:
		Events.open_quest_giver.emit(self)
	elif "vendor" in roles:
		Events.open_vendor.emit(self)
	elif "trainer" in roles:
		Events.open_trainer.emit(self)
