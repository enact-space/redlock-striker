class_name Striker
extends Node3D
## One of your squad. STAND-IN figure (body, head, hair, legs) until the real character
## models are in: Hiyori (pink bob, black suit), Kasumi, or a navy-kit Redlock trainee.
## The real model plugs in through use_model(); kick() and the run cycle still drive it.

const LOOKS := {
	"hiyori": {"hair": Color(1.0, 0.62, 0.66), "suit": Color(0.08, 0.08, 0.12), "trim": Color(1.0, 0.75, 0.82), "name": "Hiyori"},
	"kasumi": {"hair": Color(0.2, 0.22, 0.35), "suit": Color(0.1, 0.12, 0.2), "trim": Color(0.55, 0.95, 0.85), "name": "Kasumi"},
	"trainee": {"hair": Color(0.18, 0.13, 0.1), "suit": Color(0.12, 0.2, 0.42), "trim": Color(0.95, 0.93, 0.85), "name": "Trainee"},
}

static var _mats := {}

var look := "trainee"
var hero := false   # named character: bigger, stronger kick
var fire_cd := 0.0
var _t := 0.0
var _kick_t := 0.0
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _rig: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _moving := false
var _kicking := false
var _move_hold := 0.0
var _rest := 0.0


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		_mats[key] = m
	return _mats[key]


func setup(l: String) -> void:
	look = l
	hero = l != "trainee"
	_t = randf() * 3.0
	_build()


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(c)
	parent.add_child(mi)
	return mi


func _build() -> void:
	var d: Dictionary = LOOKS[look]
	_rig = Node3D.new()
	_rig.scale = Vector3.ONE * (1.15 if hero else 0.9)
	add_child(_rig)
	var skin := Color(1.0, 0.86, 0.76)
	_box(_rig, Vector3(0.32, 0.4, 0.2), Vector3(0, 0.78, 0), d.suit)
	_box(_rig, Vector3(0.34, 0.06, 0.22), Vector3(0, 0.98, 0), d.trim)
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	var h := MeshInstance3D.new()
	h.mesh = head
	h.position = Vector3(0, 1.22, 0)
	h.material_override = _mat(skin)
	_rig.add_child(h)
	# hair: a bob that sits over the back and top of the head (we see the back of the head)
	var hair := SphereMesh.new()
	hair.radius = 0.2
	hair.height = 0.36
	var hm := MeshInstance3D.new()
	hm.mesh = hair
	hm.position = Vector3(0, 1.25, 0.04)
	hm.scale = Vector3(1.05, 1.0, 0.95)
	hm.material_override = _mat(d.hair)
	_rig.add_child(hm)
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.08, 0.58, 0)
	_rig.add_child(_leg_l)
	_box(_leg_l, Vector3(0.12, 0.5, 0.13), Vector3(0, -0.25, 0), d.suit)
	_box(_leg_l, Vector3(0.13, 0.08, 0.2), Vector3(0, -0.52, -0.03), Color(0.05, 0.05, 0.06))
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.08, 0.58, 0)
	_rig.add_child(_leg_r)
	_box(_leg_r, Vector3(0.12, 0.5, 0.13), Vector3(0, -0.25, 0), d.suit)
	_box(_leg_r, Vector3(0.13, 0.08, 0.2), Vector3(0, -0.52, -0.03), Color(0.05, 0.05, 0.06))
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.2, 0.95, 0)
	_rig.add_child(_arm_l)
	_box(_arm_l, Vector3(0.09, 0.4, 0.1), Vector3(0, -0.2, 0), d.suit)
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.2, 0.95, 0)
	_rig.add_child(_arm_r)
	_box(_arm_r, Vector3(0.09, 0.4, 0.1), Vector3(0, -0.2, 0), d.suit)
	# soft blob shadow
	var sh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	sh.mesh = q
	sh.rotation_degrees.x = -90
	sh.position.y = 0.015
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0, 0, 0, 0.35)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.gradient = gr
	sm.albedo_texture = g
	sh.material_override = sm
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sh)


## Swap the stand-in for a real character scene (a GLB). Plays "run" style clips if it has them.
func use_model(scene: PackedScene, height := 1.6) -> void:
	_model = scene.instantiate()
	add_child(_model)
	_rig.visible = false
	var aabb := _aabb(_model)
	if aabb.size.y > 0.01:
		_model.scale = Vector3.ONE * (height / aabb.size.y)
	_model.rotation_degrees.y = 180   # face up the lane
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play(["idle_f_loop", "idle"])


## Adds the football clips (kick, kick_running, pass) to the model as "fb/...".
func add_clips(lib: AnimationLibrary) -> void:
	if _anim == null or lib == null:
		return
	if not _anim.has_animation_library("fb"):
		_anim.add_animation_library("fb", lib)
	if not _anim.animation_finished.is_connected(_on_anim_done):
		_anim.animation_finished.connect(_on_anim_done)


## Kick over and over on the spot (run while the squad slides), instead of idling.
func set_kicking(on: bool) -> void:
	_kicking = on
	_resume()


## Run while the squad slides, kick (or idle) while it holds still. Holds each state for a
## moment so small drags don't flick between run and kick.
func set_moving(on: bool) -> void:
	if on:
		_move_hold = 0.25
	if _anim == null or on == _moving:
		return
	if not on and _move_hold > 0.0:
		return
	_moving = on
	_resume()


func _resume() -> void:
	if _anim == null:
		return
	if _moving:
		_play(["run_f_loop", "run_f", "run"])
	elif _kicking and _anim.has_animation("fb/kick"):
		_anim.play("fb/kick", 0.2, 1.15)
		_anim.seek(0.15, false)
	else:
		_play(["idle_f_loop", "idle_f", "idle"])


func _on_anim_done(_name: StringName) -> void:
	if not _moving:
		_resume()


func _play(names: Array) -> void:
	if _anim == null:
		return
	for n in names:
		for a in _anim.get_animation_list():
			if a == n or a.ends_with("/" + n):
				_anim.play(a, 0.15)
				return


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = (n.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func kick() -> void:
	_kick_t = 0.22


func _process(delta: float) -> void:
	_t += delta
	_move_hold -= delta
	if _moving and _move_hold <= 0.0:
		_moving = false
		_resume()
	# kick, settle into the stance for a beat, kick again
	if _kicking and not _moving and _anim and _anim.current_animation == "fb/kick" and _anim.current_animation_position > 0.85:
		_play(["idle_f_loop", "idle_f", "idle"])
		_rest = 0.2
	if _rest > 0.0:
		_rest -= delta
		if _rest <= 0.0 and not _moving:
			_resume()
	if _rig == null or not _rig.visible:
		return
	var w := sin(_t * 13.0)
	_leg_l.rotation.x = w * 0.7
	_leg_r.rotation.x = -w * 0.7
	_arm_l.rotation.x = -w * 0.6
	_arm_r.rotation.x = w * 0.6
	_rig.position.y = absf(w) * 0.05
	if _kick_t > 0.0:
		_kick_t -= delta
		var k := sin((1.0 - _kick_t / 0.22) * PI)
		_leg_r.rotation.x = 1.5 * k   # right leg swings up the lane (-Z)
