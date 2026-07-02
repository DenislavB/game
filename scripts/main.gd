class_name Main
extends Node
## Root node: screen flow (menu -> character creation -> world),
## zone loading and travel, save on quit.

var menus: Menus
var hud: Hud = null
var windows: GameWindows = null
var zone: Zone = null
var loading_layer: CanvasLayer
var loading_label: Label


func _ready() -> void:
	_build_loading_overlay()
	menus = Menus.new()
	add_child(menus)
	menus.start_game.connect(_on_start_game)
	Events.request_zone_travel.connect(_on_zone_travel)


func _build_loading_overlay() -> void:
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 20
	loading_layer.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_layer.add_child(bg)
	loading_label = UI.label("Loading...", 32, UI.COL_GOLD)
	loading_label.set_anchors_preset(Control.PRESET_CENTER)
	loading_label.offset_left = -120
	loading_label.offset_top = -20
	loading_layer.add_child(loading_label)
	add_child(loading_layer)


func _on_start_game() -> void:
	menus.visible = false
	hud = Hud.new()
	add_child(hud)
	windows = GameWindows.new()
	add_child(windows)
	var use_saved_pos: bool = Game.pc.get("pos") != null
	await _load_zone(Game.current_zone_id, "", use_saved_pos)


func _on_zone_travel(zone_id: String, spawn: String) -> void:
	Game.save_game()
	await _load_zone(zone_id, spawn, false)


func _load_zone(zone_id: String, entrance: String, use_saved_pos: bool) -> void:
	loading_label.text = "Loading %s..." % DB.zones.get(zone_id, {}).get("name", zone_id)
	loading_layer.visible = true
	# Let the overlay actually draw before the synchronous build.
	await get_tree().process_frame
	await get_tree().process_frame

	if zone != null and is_instance_valid(zone):
		Game.player = null
		zone.queue_free()
		await get_tree().process_frame
	zone = Zone.new()
	add_child(zone)
	zone.build(zone_id)

	var player := Player.new()
	zone.add_child(player)
	Game.player = player
	if entrance != "":
		player.global_transform = zone.entrance_position(entrance)
	elif use_saved_pos and Game.pc.get("pos") != null:
		var p: Array = Game.pc["pos"]
		player.global_position = Vector3(float(p[0]), float(p[1]) + 0.5, float(p[2]))
	else:
		player.global_transform = zone.start_position()

	loading_layer.visible = false
	Events.zone_changed.emit(zone_id)
	Game.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()
		get_tree().quit()
