class_name RewardRow
extends Node3D
## A straight row of reward tiles along one edge of the bridge, behind a stone gate on the lane
## edge. Kick balls up the row's lane: the gate's number counts down, at zero the first tile bursts,
## its reward flies to the squad and the whole row slides one tile forward.
## The recruits row hands out clones (+1 ... +99); the kit row hands out boot upgrades.

signal claimed(item: Dictionary)

const RECRUITS := [1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 75, 99]
const KIT := ["boots", "boots", "boots", "boots", "boots", "rate", "rate", "rate"]
const SLOTS := 20
const STEP := 1.1
const WIDTH := 1.1

var kind := "recruits"
var side := 1.0
var front := Vector3.ZERO   # centre of the gate, on the deck
var made := 0
var items: Array[Dictionary] = []
var _num: Label3D
var _gate: MeshInstance3D
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


## Tile i sits i steps up the row behind the gate.
func _slot(i: int) -> Vector3:
	return front + Vector3(0, 0.12, -1.0 - i * STEP)


func _std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _build() -> void:
	var stone := _std(Color(0.8, 0.78, 0.73))
	var dark := _std(Color(0.62, 0.6, 0.56))
	var length := SLOTS * STEP + 1.4
	# the raised stone bed the tiles slide along
	var bed := MeshInstance3D.new()
	bed.mesh = Meshes.box(WIDTH + 0.2, 0.12, length)
	bed.position = front + Vector3(0, 0.06, -0.4 - length * 0.5)
	bed.material_override = dark
	add_child(bed)
	# a low kerb between the row and the keepers' lane
	var kerb := MeshInstance3D.new()
	kerb.mesh = Meshes.box(0.16, 0.36, length)
	kerb.position = front + Vector3(-side * (WIDTH * 0.5 + 0.18), 0.18, -0.4 - length * 0.5)
	kerb.material_override = stone
	add_child(kerb)
	# the gate on the lane edge, its number facing the squad
	_gate = MeshInstance3D.new()
	_gate.mesh = Meshes.box(WIDTH + 0.3, 0.95, 0.6)
	_gate.position = front + Vector3(0, 0.47, 0)
	_gate.material_override = _std(Color(0.55, 0.42, 0.32))
	add_child(_gate)
	for dx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = Meshes.box(0.22, 1.25, 0.7)
		post.position = front + Vector3(dx * (WIDTH * 0.5 + 0.22), 0.62, 0)
		post.material_override = stone
		add_child(post)
	_num = Label3D.new()
	_num.font = _font
	_num.font_size = 110
	_num.outline_size = 22
	_num.pixel_size = 0.009
	_num.position = front + Vector3(0, 1.0, 0.35)
	_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_num.no_depth_test = true
	_num.render_priority = 2
	add_child(_num)


func _next_reward() -> Dictionary:
	var k := made
	made += 1
	if kind == "recruits":
		var v: int = RECRUITS[mini(k, RECRUITS.size() - 1)]
		var hits := int(round(8.0 * pow(1.6, k)))
		return {"reward": "recruits", "value": v, "hits": hits, "text": "+%d" % v}
	var r: String = KIT[mini(k, KIT.size() - 1)]
	var hits := int(round(30.0 * pow(4.0, k)))
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
	return global_position + front + Vector3(0, 0.45, 0)


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
	if _shake > 0.0:
		_shake -= delta
		_gate.scale = Vector3(1.06, 1.06, 1.06)
	else:
		_gate.scale = Vector3.ONE
