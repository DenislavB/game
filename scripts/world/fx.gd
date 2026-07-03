class_name FX
## Tiny visual-effects helpers. Damage is already resolved by the caller —
## these are purely cosmetic projectiles/flashes so ranged attacks and
## spells visibly travel to their target.


static func bolt(parent: Node, from: Vector3, to: Vector3, color: Color, arrow: bool = false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var p := Node3D.new()
	var mi := MeshInstance3D.new()
	if arrow:
		mi.mesh = Props._box(0.04, 0.04, 0.55)
		mi.material_override = Props.mat(Color("9a7a4a"))
		mi.position.z = -0.2
	else:
		mi.mesh = Props._sphere(0.15, 6)
		mi.material_override = Props.mat(color, true)
		var l := OmniLight3D.new()
		l.light_color = color
		l.omni_range = 3.0
		p.add_child(l)
	p.add_child(mi)
	parent.add_child(p)
	p.global_position = from
	var d := from.distance_to(to)
	if d > 0.6:
		p.look_at(to)
	var tw := p.create_tween()
	tw.tween_property(p, "global_position", to, clampf(d / 35.0, 0.08, 0.6))
	tw.tween_callback(p.queue_free)


static func impact(parent: Node, at: Vector3, color: Color = Color(1, 0.9, 0.6)) -> void:
	## Quick flash where a hit lands.
	if parent == null or not is_instance_valid(parent):
		return
	var p := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Props._sphere(0.12, 5)
	mi.material_override = Props.mat(color, true)
	p.add_child(mi)
	parent.add_child(p)
	p.global_position = at
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector3(2.2, 2.2, 2.2), 0.12)
	tw.tween_callback(p.queue_free)


static func burst(parent: Node, at: Vector3, color: Color, radius: float = 1.0) -> void:
	## Expanding flash ring for AoE impacts.
	if parent == null or not is_instance_valid(parent):
		return
	var p := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Props._cyl(radius, radius, 0.06, 12)
	mi.material_override = Props.mat(color, true)
	p.add_child(mi)
	parent.add_child(p)
	p.global_position = at
	p.scale = Vector3(0.2, 1, 0.2)
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector3(1.6, 1, 1.6), 0.35)
	tw.tween_callback(p.queue_free)
