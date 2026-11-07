class_name HoloKeeper
extends Node3D
## A holographic goalkeeper marching down the lane: see-through glowing figure with scanlines,
## arms spread in a keeper's stance, a projector disc under its feet. Same look as Redlock's
## entrance-trial holo keepers (scripts/holo.gd there), rebuilt as a light standalone figure.

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.42, 0.9, 1.0, 1.0);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scan = 0.6 + 0.4 * step(0.45, fract(world.y * 14.0 - TIME * 1.6));
	float flick = 0.9 + 0.1 * sin(TIME * 23.0 + world.x * 3.0);
	// solid and bright so it reads on the daylight bridge
	vec3 c = mix(tint.rgb, vec3(1.0), clamp(rim * 0.8, 0.0, 0.8)) * (0.85 + 0.15 * scan) * flick;
	ALBEDO = c * strength;
	ALPHA = 0.92;
}
"""

const KINDS := {
	"grunt": {"hp": 1, "scale": 1.15, "speed": 3.2, "tint": Color(0.42, 0.9, 1.0), "coins": 1},
	"brute": {"hp": 4, "scale": 1.35, "speed": 2.6, "tint": Color(1.0, 0.45, 0.3), "coins": 3},
	"boss": {"hp": 120, "scale": 3.2, "speed": 1.1, "tint": Color(0.85, 0.1, 0.35), "coins": 40},
}

static var _shader: Shader
static var _mats := {}
static var _flash: ShaderMaterial

var kind := "grunt"
var hp := 1
var max_hp := 1
var speed := 3.0
var radius := 0.35
var coins := 1
var dead := false
var _parts: Array[MeshInstance3D] = []
var _mat: ShaderMaterial
var _flash_t := -1.0
var _t := 0.0
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _body: Node3D


static func mat_for(c: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var key := c.to_html()
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("tint", c)
		_mats[key] = m
	return _mats[key]


static func flash_mat() -> ShaderMaterial:
	if _flash == null:
		_flash = mat_for(Color(1, 1, 1)).duplicate()
		_flash.set_shader_parameter("strength", 2.4)
	return _flash


func setup(k: String, hp_scale := 1.0) -> void:
	kind = k
	var d: Dictionary = KINDS[k]
	max_hp = maxi(1, int(round(d.hp * hp_scale)))
	hp = max_hp
	speed = d.speed
	coins = d.coins
	var s: float = d.scale
	radius = 0.35 * s
	_mat = mat_for(d.tint)
	_build(s)
	_t = randf() * 10.0


func _part(mesh: Mesh, parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_parts.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build(s: float) -> void:
	_body = Node3D.new()
	_body.scale = Vector3.ONE * s
	add_child(_body)
	var torso := CapsuleMesh.new()
	torso.radius = 0.2
	torso.height = 0.62
	torso.radial_segments = 10
	torso.rings = 3
	_part(torso, _body, Vector3(0, 0.82, 0))
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	head.radial_segments = 12
	head.rings = 6
	_part(head, _body, Vector3(0, 1.3, 0))
	var limb := CapsuleMesh.new()
	limb.radius = 0.07
	limb.height = 0.42
	limb.radial_segments = 8
	limb.rings = 2
	var glove := BoxMesh.new()
	glove.size = Vector3(0.17, 0.2, 0.09)
	# arms spread up and out: a keeper ready to save
	_arm_l = _pivot(_body, Vector3(-0.2, 1.02, 0))
	_part(limb, _arm_l, Vector3(-0.17, 0.12, 0), Vector3(0, 0, 55))
	_part(glove, _arm_l, Vector3(-0.36, 0.26, 0))
	_arm_r = _pivot(_body, Vector3(0.2, 1.02, 0))
	_part(limb, _arm_r, Vector3(0.17, 0.12, 0), Vector3(0, 0, -55))
	_part(glove, _arm_r, Vector3(0.36, 0.26, 0))
	_leg_l = _pivot(_body, Vector3(-0.1, 0.52, 0))
	_part(limb, _leg_l, Vector3(0, -0.24, 0))
	_leg_r = _pivot(_body, Vector3(0.1, 0.52, 0))
	_part(limb, _leg_r, Vector3(0, -0.24, 0))
	var disc := CylinderMesh.new()
	disc.top_radius = 0.32
	disc.bottom_radius = 0.32
	disc.height = 0.01
	disc.radial_segments = 16
	_part(disc, _body, Vector3(0, 0.02, 0))


## Take a hit. Returns true when this one goes down.
func hit(dmg: int) -> bool:
	if dead:
		return false
	hp -= dmg
	if _flash_t < -0.12:   # flash on a hit, but not every hit, so the colour still reads
		_flash_t = 0.05
		for p in _parts:
			p.material_override = flash_mat()
	if hp <= 0:
		dead = true
		return true
	return false


func _process(delta: float) -> void:
	_t += delta
	var was := _flash_t
	_flash_t -= delta
	if was > 0.0 and _flash_t <= 0.0:
		for p in _parts:
			p.material_override = _mat
	var w := sin(_t * speed * 3.2)
	_leg_l.rotation.x = w * 0.6
	_leg_r.rotation.x = -w * 0.6
	_arm_l.rotation.z = 0.15 * sin(_t * 2.1)
	_arm_r.rotation.z = -0.15 * sin(_t * 2.1 + 0.6)
	_body.position.y = absf(w) * 0.04
