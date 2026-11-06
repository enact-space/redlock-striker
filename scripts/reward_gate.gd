class_name RewardGate
extends Node3D
## A stack of training crates at the edge of the lane with a number on it. Every ball that hits it
## counts the number down; at zero the stack bursts and the squad gets the reward printed on top.
## It scrolls down the lane with the pitch, so you have to slide over and hit it before it passes.

const REWARDS := {
	"squad": {"text": "+%d STRIKERS", "color": Color(0.55, 0.95, 0.85)},
	"shots": {"text": "+1 BALL", "color": Color(1.0, 0.82, 0.35)},
	"power": {"text": "POWER +1", "color": Color(1.0, 0.5, 0.4)},
	"rate": {"text": "RAPID KICKS", "color": Color(0.6, 0.8, 1.0)},
	"curve": {"text": "CURVE", "color": Color(0.85, 0.65, 1.0)},
	"spirit": {"text": "SPIRIT +50%", "color": Color(1.0, 0.62, 0.78)},
	"hero": {"text": "%s JOINS!", "color": Color(1.0, 0.62, 0.78)},
}

var reward := "squad"
var amount := 1
var hits := 10
var half := Vector2(0.75, 0.5)
var done := false
var _num: Label3D
var _stack: Node3D
var _shake := 0.0


func setup(kind: String, need: int, amt := 1, hero_name := "") -> void:
	reward = kind
	hits = need
	amount = amt
	var d: Dictionary = REWARDS[kind]
	var txt: String = d.text
	if kind == "squad":
		txt = txt % amt
	elif kind == "hero":
		txt = txt % hero_name.to_upper()
	_stack = Node3D.new()
	add_child(_stack)
	var navy := StandardMaterial3D.new()
	navy.albedo_color = Color(0.13, 0.19, 0.36)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = d.color
	trim.emission_enabled = true
	trim.emission = d.color
	trim.emission_energy_multiplier = 0.6
	for i in 3:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4 - i * 0.18, 0.5, 0.9 - i * 0.1)
		b.mesh = bm
		b.position.y = 0.25 + i * 0.5
		b.material_override = navy
		_stack.add_child(b)
		var t := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(bm.size.x + 0.02, 0.07, bm.size.z + 0.02)
		t.mesh = tm
		t.position.y = 0.47 + i * 0.5
		t.material_override = trim
		_stack.add_child(t)
	_num = Label3D.new()
	_num.text = str(hits)
	_num.font = load("res://assets/fonts/Nunito.ttf")
	_num.font_size = 110
	_num.outline_size = 22
	_num.pixel_size = 0.009
	_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_num.no_depth_test = true
	_num.position = Vector3(0, 0.75, 0.5)
	add_child(_num)
	var lab := Label3D.new()
	lab.text = txt
	lab.font = _num.font
	lab.font_size = 64
	lab.outline_size = 16
	lab.modulate = d.color
	lab.pixel_size = 0.011
	lab.width = 600
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = Vector3(0, 2.5, 0)
	add_child(lab)


## A ball hit it. Returns true when it bursts.
func hit(dmg: int) -> bool:
	if done:
		return false
	hits = maxi(0, hits - dmg)
	_num.text = str(hits)
	_shake = 0.08
	if hits <= 0:
		done = true
		return true
	return false


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake -= delta
		_stack.position.x = randf_range(-0.05, 0.05)
		_stack.scale = Vector3.ONE * 1.06
	else:
		_stack.position.x = 0.0
		_stack.scale = Vector3.ONE
