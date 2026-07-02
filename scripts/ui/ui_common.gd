class_name UI
## Shared helpers for the code-built interface. Dark panels with gold
## trim, quality-colored item text — the classic look.

const COL_BG := Color(0.09, 0.075, 0.06, 0.94)
const COL_BORDER := Color(0.62, 0.5, 0.28)
const COL_TEXT := Color(0.92, 0.88, 0.8)
const COL_GOLD := Color(1.0, 0.82, 0.0)
const COL_HP := Color(0.13, 0.7, 0.13)
const COL_MANA := Color(0.18, 0.35, 0.9)
const COL_RAGE := Color(0.78, 0.12, 0.12)
const COL_XP := Color(0.45, 0.2, 0.65)


static func panel_style(border: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	if border:
		sb.border_color = COL_BORDER
		sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	return sb


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p


static func label(text: String, size: int = 14, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func header(text: String) -> Label:
	return label(text, 18, COL_GOLD)


static func button(text: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.15, 0.1)
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.3, 0.25, 0.15)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(0.4, 0.32, 0.18)
	b.add_theme_stylebox_override("pressed", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.12, 0.11, 0.1)
	b.add_theme_stylebox_override("disabled", sbd)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func bar(fill_color: Color, height: float = 18.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size.y = height
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(2)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p


static func school_color(school: String) -> Color:
	match school:
		"fire": return Color("ff8030")
		"frost": return Color("60b0ff")
		"arcane": return Color("d070ff")
		"nature": return Color("70d060")
		_: return Color("d8c8a0")


static func ability_glyph(id: String) -> String:
	var a := DB.ability(id)
	var words: PackedStringArray = str(a.get("name", "??")).split(" ")
	if words.size() >= 2:
		return words[0].substr(0, 1) + words[1].substr(0, 1)
	return words[0].substr(0, 2)


static func item_glyph(id: String) -> String:
	var it := DB.item(id)
	var slot: String = it.get("slot", "none")
	match slot:
		"mainhand": return "/"
		"ranged": return ")"
		"chest": return "T"
		"legs": return "L"
		"feet": return "B"
		"head": return "H"
		"shoulder": return "S"
		"hands": return "G"
		"waist": return "W"
		_:
			if it.has("use"):
				return "o"
			return "."


static func ability_tooltip(id: String) -> String:
	var a := DB.ability(id)
	if a.is_empty():
		return id
	var lines: Array = []
	lines.append("[b][color=#ffd100]%s[/color][/b]" % a["name"])
	var cost: Dictionary = a.get("cost", {})
	var costs: Array = []
	if cost.has("rage"):
		costs.append("%d Rage" % int(cost["rage"]))
	if cost.has("mana"):
		costs.append("%d Mana" % int(cost["mana"]))
	if cost.has("health_pct"):
		costs.append("%d%% Health" % int(float(cost["health_pct"]) * 100))
	var meta: Array = []
	if not costs.is_empty():
		meta.append(", ".join(costs))
	if float(a.get("range", 0)) > 0:
		meta.append("%dm range" % int(a["range"]))
	if float(a.get("cast", 0)) > 0:
		meta.append("%.1f sec cast" % float(a["cast"]))
	elif a.has("channel"):
		meta.append("Channeled")
	else:
		meta.append("Instant")
	if float(a.get("cooldown", 0)) > 0:
		meta.append("%s cooldown" % _time_str(float(a["cooldown"])))
	lines.append("[color=#c8c8c8]%s[/color]" % " — ".join(meta))
	lines.append("[color=#ffe8c0]%s[/color]" % a.get("desc", ""))
	lines.append("[color=#808080]Level %d %s[/color]" % [int(a["level"]), str(a.get("class", a.get("race", ""))).capitalize()])
	return "\n".join(lines)


static func item_tooltip(id: String) -> String:
	var it := DB.item(id)
	if it.is_empty():
		return id
	var c := DB.quality_color(it.get("quality", "common"))
	var lines: Array = []
	lines.append("[b][color=#%s]%s[/color][/b]" % [c.to_html(false), it["name"]])
	var slot: String = it.get("slot", "none")
	if slot != "none":
		lines.append("[color=#c8c8c8]%s[/color]" % slot.capitalize())
	if it.has("dmg"):
		var dps := (float(it["dmg"][0]) + float(it["dmg"][1])) * 0.5 / float(it["speed"])
		lines.append("%d - %d Damage, Speed %.1f  [color=#c8c8c8](%.1f dps)[/color]" % [int(it["dmg"][0]), int(it["dmg"][1]), float(it["speed"]), dps])
	if it.has("armor"):
		lines.append("%d Armor" % int(it["armor"]))
	for k in it.get("stats", {}):
		var names := { "str": "Strength", "agi": "Agility", "sta": "Stamina", "int": "Intellect", "spi": "Spirit" }
		lines.append("[color=#40c040]+%d %s[/color]" % [int(it["stats"][k]), names.get(k, k)])
	if int(it.get("req_level", 1)) > 1:
		var ok: bool = int(Game.pc.get("level", 60)) >= int(it["req_level"])
		lines.append("[color=#%s]Requires Level %d[/color]" % ["c8c8c8" if ok else "ff4040", int(it["req_level"])])
	if it.has("desc"):
		lines.append("[color=#ffd100]%s[/color]" % it["desc"])
	if int(it.get("value", 0)) > 0:
		lines.append("[color=#c8c8c8]Sells for %s[/color]" % Formulas.money_string(int(it["value"])))
	return "\n".join(lines)


static func _time_str(sec: float) -> String:
	if sec >= 60.0:
		return "%d min" % int(sec / 60.0)
	return "%d sec" % int(sec)
