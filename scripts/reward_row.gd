class_name RewardRow
extends Node3D
## A straight row of low walls across one edge lane of the bridge. Kick balls up the row's lane:
## the number over the front wall counts down, at zero the wall smashes, its upgrade flies to the
## squad and the walls behind slide one step forward.
## The recruits row hands out clones (+1 early, up to +99 far up); the kit row hands out boot
## upgrades. Like the video's barrel towers, plain walls sit between the prize walls: they cost hits
## and give nothing, so you don't get a power-up every time.

signal claimed(item: Dictionary)

# 0 / "" = a plain tile
const RECRUITS := [1, 1, 0, 1, 2, 0, 2, 0, 2, 0, 0, 3, 0, 3, 5, 0, 0, 5, 8, 0, 10, 0, 0, 15, 0, 20, 0, 25, 30, 0, 40, 0, 50, 75, 99]
const KIT := ["", "", "boots", "", "", "", "rate", "", "", "boots", "", "", "", "", "boots", "", "rate", "", "", "", "boots", "", "", "", "rate", "", "", "boots", "", "", "", "", "rate"]
const SLOTS := 12
const STEP := 1.9
const WIDTH := 1.15
const HEIGHT := 1.0
const THICK := 0.34

var kind := "recruits"
var side := 1.0
var front := Vector3.ZERO   # foot of the front wall, centre of the lane
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


## Wall i stands i steps up the row from the front.
func _slot(i: int) -> Vector3:
	return front + Vector3(0, 0, -i * STEP)


func _std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _build() -> void:
	var length := SLOTS * STEP + 0.6
	# a slim dark track under the walls with a cyan light line, like the Project R arena border
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
	_num.position = front + Vector3(0, HEIGHT + 0.55, 0.2)
	_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_num.no_depth_test = true
	_num.render_priority = 2
	add_child(_num)


func _next_reward() -> Dictionary:
	var k := made
	made += 1
	if kind == "recruits":
		var hits := int(round(3.0 * pow(1.24, k))) + k
		var v: int = RECRUITS[k] if k < RECRUITS.size() else (99 if k % 2 == 0 else 0)
		if v == 0:
			return {"reward": "none", "value": 0, "hits": hits, "text": ""}
		return {"reward": "recruits", "value": v, "hits": hits, "text": "+%d" % v}
	var r: String = KIT[k] if k < KIT.size() else ("rate" if k % 4 == 0 else "")
	var hits := int(round(8.0 * pow(1.35, k))) + 3 * k
	if r == "":
		return {"reward": "none", "value": 0, "hits": hits, "text": ""}
	if r == "boots":
		return {"reward": "boots", "value": 1, "hits": hits, "text": "BOOTS"}
	return {"reward": "rate", "value": 1, "hits": hits, "text": "RAPID"}


func _push_item() -> void:
	var d := _next_reward()
	var n := Node3D.new()
	add_child(n)
	var plain: bool = d.reward == "none"
	# the wall: a slate block with a lighter cap; prize walls carry a glowing coloured face
	var body := MeshInstance3D.new()
	body.mesh = Meshes.box(WIDTH, HEIGHT, THICK)
	body.position.y = HEIGHT * 0.5
	body.material_override = _wall_mat(Color(0.34, 0.37, 0.45) if plain else Color(0.2, 0.23, 0.3))
	n.add_child(body)
	var cap := MeshInstance3D.new()
	cap.mesh = Meshes.box(WIDTH + 0.06, 0.08, THICK + 0.06)
	cap.position.y = HEIGHT + 0.03
	cap.material_override = _wall_mat(Color(0.5, 0.53, 0.6))
	n.add_child(cap)
	if plain:
		# brick seams so it reads as a wall
		for row in 2:
			var seam := MeshInstance3D.new()
			seam.mesh = Meshes.box(WIDTH + 0.01, 0.025, THICK + 0.01)
			seam.position.y = HEIGHT * (0.33 + row * 0.33)
			seam.material_override = _wall_mat(Color(0.24, 0.26, 0.32))
			n.add_child(seam)
	else:
		var big := kind == "kit" or int(d.value) >= 10
		var face := MeshInstance3D.new()
		face.mesh = Meshes.box(WIDTH - 0.16, HEIGHT - 0.16, 0.04)
		face.position = Vector3(0, HEIGHT * 0.5, THICK * 0.5 + 0.01)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.62, 0.08) if big else Color(0.12, 0.42, 0.95)
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.35
		face.material_override = m
		n.add_child(face)
		var lab := Label3D.new()
		lab.font = _font
		lab.text = d.text
		lab.font_size = 72 if d.text.length() <= 3 else 44
		lab.outline_size = 16
		lab.pixel_size = 0.0085
		lab.rotation_degrees.x = -28   # leans back a little, square to the camera
		lab.position = Vector3(0, HEIGHT * 0.5, THICK * 0.5 + 0.05)
		lab.render_priority = 1
		n.add_child(lab)
	d["node"] = n
	d["color"] = Color(0.6, 0.62, 0.68) if plain else (Color(0.95, 0.62, 0.08) if kind == "kit" or int(d.value) >= 10 else Color(0.12, 0.42, 0.95))
	items.append(d)


static var _mats := {}


static func _wall_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		_mats[key] = m
	return _mats[key]


func _layout(animate: bool) -> void:
	for i in items.size():
		var n: Node3D = items[i].node
		# the front tile shows its countdown instead; far tiles stay quiet so the row reads cleanly
		for c in n.get_children():
			if c is Label3D:
				c.visible = i < 9
		var goal := _slot(i)
		if animate:
			var tw := create_tween()
			tw.tween_property(n, "position", goal, 0.3).set_trans(Tween.TRANS_QUAD)
		else:
			n.position = goal


func _refresh() -> void:
	_num.text = "" if items.is_empty() else str(items[0].hits)


## World position of the gate, where the balls land.
func target() -> Vector3:
	return global_position + front + Vector3(0, HEIGHT * 0.5, 0)


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
		n.scale = Vector3(1.06, 1.1, 1.06)
	else:
		n.scale = Vector3.ONE
