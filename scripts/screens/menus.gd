class_name Menus
extends CanvasLayer
## Main menu and character creation.

signal start_game
signal open_editor

var menu_root: Control
var create_root: Control
var name_edit: LineEdit
var picked_race := "orc"
var picked_class := "warrior"
var race_buttons: Dictionary = {}
var class_buttons: Dictionary = {}
var info_label: RichTextLabel


func _ready() -> void:
	layer = 10
	_build_menu()
	_build_create()
	show_menu()


func show_menu() -> void:
	menu_root.visible = true
	create_root.visible = false


func _full_bg(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)


func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)
	_full_bg(menu_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var title := UI.label("EMBERFALL", 64, UI.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("A slow, grindy, old-school world.  Low poly. High stakes. No mercy.", 16, Color(0.75, 0.7, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())

	if Game.has_save():
		var cont := UI.button("Continue", func():
			if Game.load_game():
				start_game.emit())
		cont.custom_minimum_size = Vector2(280, 44)
		v.add_child(cont)
	var newb := UI.button("New Character", func():
		menu_root.visible = false
		create_root.visible = true)
	newb.custom_minimum_size = Vector2(280, 44)
	v.add_child(newb)
	if Game.has_save():
		var delb := UI.button("Delete Save", func():
			Game.delete_save()
			_rebuild())
		delb.custom_minimum_size = Vector2(280, 44)
		v.add_child(delb)
	var editor_b := UI.button("Character Editor", func(): open_editor.emit())
	editor_b.custom_minimum_size = Vector2(280, 44)
	v.add_child(editor_b)
	var quitb := UI.button("Quit", func(): get_tree().quit())
	quitb.custom_minimum_size = Vector2(280, 44)
	v.add_child(quitb)

	var help := UI.label("W/S move · A/D turn · Q/E strafe · Right-drag mouse-turn · Tab target · Right-click interact/attack\n1-0 abilities · B bags · C character · L quests · N talents · X sit", 13, Color(0.55, 0.52, 0.45))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(help)


func _rebuild() -> void:
	menu_root.queue_free()
	create_root.queue_free()
	_build_menu()
	_build_create()
	show_menu()


func _build_create() -> void:
	create_root = Control.new()
	create_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	create_root.visible = false
	add_child(create_root)
	_full_bg(create_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	create_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(620, 0)
	center.add_child(v)

	v.add_child(UI.header("Create Your Character"))
	v.add_child(HSeparator.new())

	var nh := HBoxContainer.new()
	nh.add_child(UI.label("Name: ", 15))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(240, 34)
	name_edit.max_length = 16
	name_edit.text = "Adventurer"
	nh.add_child(name_edit)
	v.add_child(nh)

	v.add_child(UI.label("Race", 15, UI.COL_GOLD))
	var rh := GridContainer.new()
	rh.columns = 3
	rh.add_theme_constant_override("h_separation", 8)
	rh.add_theme_constant_override("v_separation", 8)
	for rid in DB.races:
		var b := UI.button(DB.races[rid]["name"])
		b.custom_minimum_size = Vector2(190, 40)
		var rid2 := str(rid)
		b.pressed.connect(func():
			picked_race = rid2
			_update_selection())
		rh.add_child(b)
		race_buttons[rid] = b
	v.add_child(rh)

	v.add_child(UI.label("Class", 15, UI.COL_GOLD))
	var ch := GridContainer.new()
	ch.columns = 3
	ch.add_theme_constant_override("h_separation", 8)
	ch.add_theme_constant_override("v_separation", 8)
	for cid in DB.classes:
		var b2 := UI.button(DB.classes[cid]["name"])
		b2.custom_minimum_size = Vector2(190, 40)
		var cid2 := str(cid)
		b2.pressed.connect(func():
			picked_class = cid2
			_update_selection())
		ch.add_child(b2)
		class_buttons[cid] = b2
	v.add_child(ch)

	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(620, 150)
	info_label.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(info_label)

	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	var create := UI.button("Enter the World", func():
		var pname := name_edit.text.strip_edges()
		if pname.length() < 2:
			pname = "Adventurer"
		Game.new_character(pname, picked_race, picked_class)
		start_game.emit())
	create.custom_minimum_size = Vector2(220, 44)
	bh.add_child(create)
	var back := UI.button("Back", func(): show_menu())
	back.custom_minimum_size = Vector2(120, 44)
	bh.add_child(back)
	v.add_child(bh)
	_update_selection()


func _update_selection() -> void:
	for rid in race_buttons:
		var b: Button = race_buttons[rid]
		b.text = ("> " if rid == picked_race else "") + DB.races[rid]["name"]
	for cid in class_buttons:
		var b2: Button = class_buttons[cid]
		b2.text = ("> " if cid == picked_class else "") + DB.classes[cid]["name"]
	var race: Dictionary = DB.races[picked_race]
	var cls: Dictionary = DB.classes[picked_class]
	info_label.text = "[color=#ffd100][b]%s[/b][/color] — %s\n[color=#c8c8c8]Racial: %s — %s[/color]\n\n[color=#%s][b]%s[/b][/color] — %s\n[color=#c8c8c8]Resource: %s.  Starts in %s.[/color]" % [
		race["name"], race["description"],
		race["racial"]["name"], race["racial"]["desc"],
		Color(cls["color"]).to_html(false), cls["name"], cls["description"],
		str(cls["resource"]).capitalize(), DB.zones[race["start_zone"]]["name"]
	]
