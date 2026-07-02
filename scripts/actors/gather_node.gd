class_name GatherNode
extends StaticBody3D
## Mining vein or herb node. Right-click to gather (with a short cast),
## then it despawns and respawns later elsewhere in its timer window.

var node_type := ""
var def: Dictionary = {}
var respawn_time := 180.0
var depleted := false
var _respawn_t := 0.0
var _label: Label3D


func setup(type: String, type_def: Dictionary, respawn: float) -> void:
	node_type = type
	def = type_def
	respawn_time = respawn

	collision_layer = 8
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	cs.shape = sph
	cs.position.y = 0.5
	add_child(cs)

	add_child(Props.build_gather_node(def.get("shape", "vein"), Color(def.get("color", "#ffffff"))))

	_label = Label3D.new()
	_label.text = def["name"]
	_label.font_size = 26
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color("d8d0a0")
	_label.outline_size = 5
	_label.position.y = 1.6
	_label.visibility_range_end = 25.0
	add_child(_label)


func can_gather() -> bool:
	if depleted:
		return false
	var prof: String = def["prof"]
	var skill := int(Game.pc["profs"].get(prof, 1))
	if skill < int(def.get("skill_req", 1)):
		Events.error_message.emit("Requires %s skill %d." % [DB.professions["professions"][prof]["name"], int(def["skill_req"])])
		return false
	return true


func complete_gather() -> void:
	if depleted:
		return
	var count := randi_range(int(def["count"][0]), int(def["count"][1]))
	if Game.add_item(def["item"], count) > 0:
		return
	Events.game_message.emit("You receive %s x%d." % [DB.item(def["item"])["name"], count])
	Game.gain_prof_skill(def["prof"], def)
	depleted = true
	visible = false
	collision_layer = 0
	_respawn_t = respawn_time


func _process(delta: float) -> void:
	if depleted:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			depleted = false
			visible = true
			collision_layer = 8
