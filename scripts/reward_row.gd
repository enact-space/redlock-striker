class_name RewardRow
extends Node3D
## A straight row of reward tiles along one edge of the bridge. Kick balls up the row's lane: the
## number over the front tile counts down, at zero that tile bursts, its reward flies to the squad
## and the whole row slides one tile forward.
## The recruits row hands out clones (+1 ... +99); the kit row hands out boot upgrades.

signal claimed(item: Dictionary)

const RECRUITS := [2, 3, 5, 5, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 75, 99]
const KIT := ["boots", "boots", "boots", "boots", "boots", "rate", "rate", "rate"]
const SLOTS := 20
const STEP := 1.1
const WIDTH := 1.1

var kind := "recruits"
var side := 1.0
var front := Vector3.ZERO   # centre of the front tile, on the deck
var made := 0
var items: Array[Dictionary] = []
var _num: Label3D
var _font: Font
var _shake := 0.0


func setup(k: String, s: float, at: Vector3, font: Font) -> void:
	kind = k
	side = s
	front = at
	_font = font
	_build()
	for i in SLOTS:
		_push_item()
	_layout(false)
	_refresh()


## Tile i sits i steps up the row from the front.
func _slot(i: int) -> Vector3:
	return front + Vector3(0, 0.06, -i * STEP)


func _std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _build() -> void:
	var length := SLOTS * STEP + 0.6
	# a slim dark track under the tiles with a cyan light line, like the Project R arena border
	var bed := MeshInstance3D.new()
	bed.mesh = Meshes.box(WIDTH + 0.14, 0.06, length)
	bed.position = front + Vector3(0, 0.03, STEP * 0.5 - length * 0.5)
	bed.material_override = _std(Color(0.2, 0.24, 0.31))
	add_child(bed)
	var led := MeshInstance3D.new()
	led.mesh = Meshes.box(0.05, 0.03, length)
	led.position = front + Vector3(-side * (WIDTH * 0.5 + 0.04), 0.07, STEP * 0.5 - length * 0.5)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.45, 0.95, 1.0)
	led.material_override = lm
	add_child(led)
	_num = Label3D.new()
	_num.font = _font
	_num.font_size = 110
	_num.outline_size = 24
	_num.pixel_size = 0.008
	_num.modulate = Color(1.0, 0.95, 0.6)
	_num.position = front + Vector3(0, 0.9, 0.5)
	_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_num.no_depth_test = true
	_num.render_priority = 2
	add_child(_num)


func _next_reward() -> Dictionary:
	var k := made
	made += 1
	if kind == "recruits":
		var v: int = RECRUITS[mini(k, RECRUITS.size() - 1)]
		var hits := int(round(4.0 * pow(1.38, k)))
		return {"reward": "recruits", "value": v, "hits": hits, "text": "+%d" % v}
	var r: String = KIT[mini(k, KIT.size() - 1)]
	var hits := int(round(12.0 * pow(2.6, k)))
	if r == "boots":
		return {"reward": "boots", "value": 1, "hits": hits, "text": "BOOTS"}
	return {"reward": "rate", "value": 1, "hits": hits, "text": "RAPID"}


func _push_item() -> void:
	var d := _next_reward()
	var n := Node3D.new()
	add_child(n)
	var tile := MeshInstance3D.new()
	tile.mesh = Meshes.box(WIDTH - 0.12, 0.2, STEP - 0.14)
	var m := StandardMaterial3D.new()
	var gold := kind == "recruits"
	m.albedo_color = Color(0.98, 0.76, 0.26) if gold else Color(0.36, 0.62, 0.98)
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 0.2
	tile.material_override = m
	tile.position.y = 0.1
	n.add_child(tile)
	var lab := Label3D.new()
	lab.font = _font
	lab.text = d.text
	lab.font_size = 80 if d.text.length() <= 3 else 52
	lab.outline_size = 18
	lab.pixel_size = 0.0068
	lab.rotation_degrees.x = -42   # leans back on the tile, square to the camera
	lab.position = Vector3(0, 0.3, 0.1)
	lab.modulate = Color(1, 1, 1)
	lab.render_priority = 1
	n.add_child(lab)
	d["node"] = n
	items.append(d)


func _layout(animate: bool) -> void:
	for i in items.size():
		var n: Node3D = items[i].node
		# the front tile shows its countdown instead; far tiles stay quiet so the row reads cleanly
		for c in n.get_children():
			if c is Label3D:
				c.visible = i > 0 and i < 12
		var goal := _slot(i)
		if animate:
			var tw := create_tween()
			tw.tween_property(n, "position", goal, 0.22).set_trans(Tween.TRANS_QUAD)
		else:
			n.position = goal


func _refresh() -> void:
	_num.text = "" if items.is_empty() else str(items[0].hits)


## World position of the gate, where the balls land.
func target() -> Vector3:
	return global_position + front + Vector3(0, 0.3, 0)


## A ball hit the gate. Returns the reward when the first tile bursts, else an empty dictionary.
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
	(it.node as Node3D).queue_free()
	_push_item()
	(items[items.size() - 1].node as Node3D).position = _slot(SLOTS) + Vector3(0, 0, -0.6)
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
		n.scale = Vector3(1.1, 1.4, 1.1)
	else:
		n.scale = Vector3.ONE
