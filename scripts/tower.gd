class_name Tower
extends Node3D
## A spiral rack beside the top of the bridge, loaded with crates. Only the crate at the bottom
## (on the lane edge) can be hit; its number counts down with every ball, and at zero it bursts,
## its reward flies to the squad, and the next crate slides down the spiral into its place.
## The recruits tower hands out strikers (+1, +2 ... +99); the kit tower hands out boot upgrades.

signal claimed(item: Dictionary)

const RECRUITS := [1, 1, 2, 2, 3, "hero", 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 75, 99]
const KIT := ["boots", "boots", "boots", "boots", "boots", "rate", "rate", "rate"]
const SLOTS := 13

var kind := "recruits"
var side := 1.0
var base := Vector3.ZERO
var made := 0
var items: Array[Dictionary] = []
var _num: Label3D
var _font: Font
var _shake := 0.0
var hero_name := "Kasumi"


func setup(k: String, s: float, bottom: Vector3, font: Font) -> void:
	kind = k
	side = s
	base = bottom
	_font = font
	_build_rack()
	for i in SLOTS:
		_push_item()
	_layout(false)
	_num = Label3D.new()
	_num.font = font
	_num.font_size = 120
	_num.outline_size = 24
	_num.pixel_size = 0.01
	_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_num.no_depth_test = true
	_num.render_priority = 2
	add_child(_num)
	_num.position = _slot(0) + Vector3(0, -0.15, 0.85)
	_refresh()


## Where slot i sits: 0 is the bottom crate on the lane edge, then a short ramp up and round the spiral.
func _slot(i: int) -> Vector3:
	if i == 0:
		return base
	var centre := base + Vector3(side * 1.45, 0, -2.5)
	var a := PI * 0.75 + (i - 1) * 0.9   # starts on the lane side, facing the camera, winds round
	var r := 1.4
	return centre + Vector3(cos(a) * side * r, 0.3 + i * 0.44, sin(a) * r)


func _build_rack() -> void:
	var centre := base + Vector3(side * 1.45, 0, -2.5)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.82, 0.8, 0.76)
	var navy := StandardMaterial3D.new()
	navy.albedo_color = Color(0.13, 0.19, 0.36)
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.65
	cm.height = 6.4
	core.mesh = cm
	core.position = centre + Vector3(0, 3.2, 0)
	core.material_override = navy
	add_child(core)
	# a spiral ramp: one deck tile under every crate slot, winding up round the core
	for i in range(1, SLOTS + 1):
		var tile := MeshInstance3D.new()
		tile.mesh = Meshes.box(1.15, 0.12, 0.95)
		var p := _slot(i)
		tile.position = p + Vector3(0, -0.06, 0)
		var dir := (p - centre)
		dir.y = 0.0
		tile.rotation.y = atan2(dir.x, dir.z)
		tile.material_override = stone
		add_child(tile)
	# the chute down to the lane edge
	var chute := MeshInstance3D.new()
	chute.mesh = Meshes.box(1.0, 0.12, 2.2)
	chute.position = (base + _slot(1)) * 0.5 + Vector3(0, -0.2, 0)
	chute.material_override = stone
	add_child(chute)
	var pad := MeshInstance3D.new()
	pad.mesh = Meshes.box(1.2, 0.12, 1.1)
	pad.position = base + Vector3(0, -0.28, 0)
	pad.material_override = stone
	add_child(pad)


func _next_reward() -> Dictionary:
	var k := made
	made += 1
	if kind == "recruits":
		var v = RECRUITS[mini(k, RECRUITS.size() - 1)]
		var hits := int(round(7.0 * pow(1.5, k)))
		if v is String:
			return {"reward": "hero", "value": 1, "hits": hits, "text": hero_name.to_upper()}
		return {"reward": "recruits", "value": v, "hits": hits, "text": "+%d" % v}
	var r: String = KIT[mini(k, KIT.size() - 1)]
	var hits := int(round(20.0 * pow(3.2, k)))
	if r == "boots":
		return {"reward": "boots", "value": 1, "hits": hits, "text": "BOOTS"}
	return {"reward": "rate", "value": 1, "hits": hits, "text": "RAPID"}


func _push_item() -> void:
	var d := _next_reward()
	var n := Node3D.new()
	add_child(n)
	var crate := MeshInstance3D.new()
	crate.mesh = Meshes.box(0.95, 0.72, 0.72)
	var m := StandardMaterial3D.new()
	var gold := kind == "kit"
	m.albedo_color = Color(0.95, 0.72, 0.3) if gold else Color(0.38, 0.62, 0.95)
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 0.25
	crate.material_override = m
	crate.position.y = 0.36
	n.add_child(crate)
	var lab := Label3D.new()
	lab.font = _font
	lab.text = d.text
	lab.font_size = 80 if d.text.length() <= 3 else 46
	lab.outline_size = 16
	lab.pixel_size = 0.0085
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 0.45, 0.4)
	lab.modulate = Color(1, 1, 1)
	n.add_child(lab)
	d["node"] = n
	items.append(d)


func _layout(animate: bool) -> void:
	for i in items.size():
		var n: Node3D = items[i].node
		# only the next few crates show what they hold, so the rack stays readable
		for c in n.get_children():
			if c is Label3D:
				c.visible = i > 0 and i < 6   # the bottom crate shows its counter instead
		var goal := _slot(i)
		if animate:
			var tw := create_tween()
			tw.tween_property(n, "position", goal, 0.28).set_trans(Tween.TRANS_QUAD)
		else:
			n.position = goal


func _refresh() -> void:
	if items.is_empty():
		_num.text = ""
		return
	_num.text = str(items[0].hits)


## World position of the hittable bottom crate.
func target() -> Vector3:
	return global_position + base + Vector3(0, 0.3, 0)


## A ball hit the bottom crate. Returns the reward when it bursts, else an empty dictionary.
func hit(dmg: int) -> Dictionary:
	if items.is_empty():
		return {}
	var it := items[0]
	it.hits = maxi(0, int(it.hits) - dmg)
	_shake = 0.07
	if it.hits > 0:
		_refresh()
		return {}
	items.pop_front()
	_push_item()
	(items[items.size() - 1].node as Node3D).position = _slot(SLOTS) + Vector3(0, 0.6, 0)
	_layout(true)
	_refresh()
	claimed.emit(it)
	return it


func _process(delta: float) -> void:
	if items.is_empty():
		return
	var n: Node3D = items[0].node
	if _shake > 0.0:
		_shake -= delta
		n.scale = Vector3.ONE * 1.08
	else:
		n.scale = Vector3.ONE
