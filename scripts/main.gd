extends Node3D
## Redlock Striker (working title). Portrait lane shooter on a floating Redlock bridge, seen from a
## fixed steep camera. Your squad stands near the bottom and kicks footballs nonstop; drag left and
## right to aim it. Holographic keepers pour down the bridge from the far end; touching the squad
## costs strikers. Two spiral racks flank the far end: shoot the bottom crate's number down to zero
## for its reward. The recruits rack gives strikers (+1 ... +99), the kit rack gives boot upgrades.
## Every so often a giant holo keeper walks down with a big health number.
## The squad and the keepers are MultiMeshes (one draw call each) so the crowd can reach hundreds.

const HALF := 3.4            # bridge half width
const SQUAD_Z := 1.0
const GATE_Z := -17.0        # where keepers come out
const TOWER_Z := -8.0       # bottom crates of the racks
const TOWER_X := 2.45
const BALL_SPEED := 26.0
const MAX_BALLS := 900
const MAX_BALLS_PER_SEC := 140.0
const MAX_KEEPERS := 420
const MAX_CROWD := 300
const SPACING := 0.32
const BOOTS := [
	{"name": "Training boots", "dmg": 1, "rate": 1.0, "suit": Color(0.14, 0.24, 0.5), "trim": Color(0.95, 0.93, 0.85), "ball": Color(1, 1, 1)},
	{"name": "Studded boots", "dmg": 2, "rate": 1.1, "suit": Color(0.12, 0.36, 0.6), "trim": Color(0.55, 0.95, 0.85), "ball": Color(0.8, 1.0, 0.95)},
	{"name": "Pro boots", "dmg": 4, "rate": 1.2, "suit": Color(0.1, 0.45, 0.72), "trim": Color(1.0, 1.0, 1.0), "ball": Color(0.7, 0.9, 1.0)},
	{"name": "Golden boots", "dmg": 7, "rate": 1.3, "suit": Color(0.9, 0.9, 0.95), "trim": Color(1.0, 0.8, 0.3), "ball": Color(1.0, 0.85, 0.4)},
	{"name": "Spirit boots", "dmg": 12, "rate": 1.4, "suit": Color(1.0, 0.8, 0.88), "trim": Color(1.0, 0.45, 0.65), "ball": Color(1.0, 0.6, 0.8)},
	{"name": "Redlock elite", "dmg": 20, "rate": 1.5, "suit": Color(0.95, 0.25, 0.3), "trim": Color(1.0, 0.85, 0.4), "ball": Color(1.0, 0.5, 0.4)},
]
const KEEPER_TINT := Color(0.42, 0.9, 1.0)
const BRUTE_TINT := Color(1.0, 0.45, 0.3)

var state := "title"
var hero_pick := "hiyori"
var heroes: Array[Striker] = []
var crowd := 1            # trainees, not counting the heroes
var tier := 0
var rate_mul := 1.0
var squad_x := 0.0
var target_x := 0.0
var t := 0.0
var kills := 0
var boss: HoloKeeper
var boss_label: Label3D
var next_boss := 40.0
var bosses_beaten := 0
var spawn_acc := 0.0
var shot_acc := 0.0
var shake := 0.0
var hero_models := {}
var font: Font

# keepers: flat arrays, drawn by one MultiMesh
var k_pos := PackedVector3Array()
var k_hp := PackedFloat32Array()
var k_big := PackedByteArray()
var k_flash := PackedFloat32Array()
var k_mm: MultiMesh
# balls
var b_pos := PackedVector3Array()
var b_vel := PackedVector3Array()
var b_dmg := PackedFloat32Array()
var b_mm: MultiMesh
var b_mat: StandardMaterial3D
# crowd
var c_mm: MultiMesh
var c_pos := PackedVector3Array()

var towers: Array[Tower] = []
var cam: Camera3D
var count_label: Label3D
var hud_score: Label
var hud_kit: Label
var overlay: Control
var banner: Label
var _banner_t := 0.0


func _ready() -> void:
	randomize()
	font = load("res://assets/fonts/Nunito.ttf")
	for who in ["hiyori", "kasumi"]:
		var path := "res://assets/characters/%s.glb" % who
		if ResourceLoader.exists(path):
			hero_models[who] = load(path)
	_build_world()
	_build_ui()
	_show_title()
	_debug_args()
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()


# ---------------------------------------------------------------- world

func _std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.09, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.0
	add_child(sun)

	cam = Camera3D.new()
	cam.far = 150
	add_child(cam)
	cam.position = Vector3(0, 14.5, 8.8)
	cam.look_at(Vector3(0, 0, -4.8))

	# the bridge: a long ivory pitch slab with low navy walls, floating in the night
	var deck := MeshInstance3D.new()
	deck.mesh = Meshes.box(HALF * 2.0, 1.0, 30)
	deck.position = Vector3(0, -0.5, -5)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float stripe = step(0.5, fract(wp.z / 4.0));
	vec3 g = mix(vec3(0.17, 0.44, 0.26), vec3(0.2, 0.5, 0.3), stripe);
	float edge = 1.0 - smoothstep(0.05, 0.09, abs(abs(wp.x) - 3.05));
	float mid = 1.0 - smoothstep(0.04, 0.08, abs(wp.x));
	float top = step(-0.01, wp.y);
	vec3 c = mix(g, vec3(0.95, 0.95, 0.9), max(edge, mid * 0.5));
	ALBEDO = mix(vec3(0.86, 0.84, 0.79), c, top);
	ROUGHNESS = 0.9;
}
"""
	var dm := ShaderMaterial.new()
	dm.shader = sh
	deck.material_override = dm
	add_child(deck)
	for side in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		wall.mesh = Meshes.box(0.3, 0.5, 30)
		wall.position = Vector3(side * (HALF + 0.15), 0.25, -5)
		wall.material_override = _std(Color(0.13, 0.19, 0.36))
		add_child(wall)
		var strip := MeshInstance3D.new()
		strip.mesh = Meshes.box(0.32, 0.05, 30)
		strip.position = Vector3(side * (HALF + 0.15), 0.52, -5)
		var m := _std(Color(0.55, 0.95, 0.85))
		m.emission_enabled = true
		m.emission = Color(0.55, 0.95, 0.85)
		m.emission_energy_multiplier = 0.4
		strip.material_override = m
		add_child(strip)
		# the racks stand on round plinths off the bridge edge
		var plinth := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 2.1
		pc.bottom_radius = 1.7
		pc.height = 1.0
		plinth.mesh = pc
		plinth.position = Vector3(side * (TOWER_X + 1.45), -0.5, TOWER_Z - 2.5)
		plinth.material_override = _std(Color(0.86, 0.84, 0.79))
		add_child(plinth)
	# the keepers' gate at the far end: a holo projector arch
	var arch := MeshInstance3D.new()
	arch.mesh = Meshes.box(4.6, 0.4, 0.5)
	arch.position = Vector3(0, 3.2, GATE_Z + 0.5)
	var am := _std(Color(0.1, 0.15, 0.3))
	am.emission_enabled = true
	am.emission = KEEPER_TINT
	am.emission_energy_multiplier = 0.6
	arch.material_override = am
	add_child(arch)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = Meshes.box(0.4, 3.2, 0.5)
		post.position = Vector3(side * 2.1, 1.6, GATE_Z + 0.5)
		post.material_override = am
		add_child(post)
	var sign := Label3D.new()
	sign.text = "REDLOCK"
	sign.font = font
	sign.font_size = 120
	sign.pixel_size = 0.012
	sign.modulate = Color(1.0, 0.4, 0.45)
	sign.position = Vector3(0, 3.9, GATE_Z + 0.5)
	add_child(sign)
	# stars
	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(0.7, 0.85, 1.0)
	q.material = qm
	mm.mesh = q
	mm.instance_count = 220
	for i in mm.instance_count:
		var x := randf_range(6, 30) * (-1.0 if randf() < 0.5 else 1.0)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, randf_range(-25, 5), randf_range(-60, 15))))
	stars.multimesh = mm
	add_child(stars)

	# racks
	for side in [-1.0, 1.0]:
		var tw := Tower.new()
		add_child(tw)
		# recruits on the right, kit on the left (as you look up the bridge)
		tw.setup("recruits" if side > 0 else "kit", side, Vector3(side * TOWER_X, 0, TOWER_Z), font)
		towers.append(tw)

	# keepers
	k_mm = MultiMesh.new()
	k_mm.transform_format = MultiMesh.TRANSFORM_3D
	k_mm.use_custom_data = true
	k_mm.mesh = Meshes.keeper()
	k_mm.instance_count = MAX_KEEPERS
	k_mm.visible_instance_count = 0
	var ksh := Shader.new()
	ksh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
varying vec4 tint;
void vertex() {
	tint = INSTANCE_CUSTOM;
	float ph = float(INSTANCE_ID) * 1.7;
	VERTEX.y += abs(sin(TIME * 7.0 + ph)) * 0.05;
	VERTEX.x += sin(TIME * 3.5 + ph) * 0.02 * VERTEX.y;
}
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scan = 0.6 + 0.4 * step(0.45, fract(world.y * 14.0 - TIME * 1.6));
	float k = (0.32 + rim * 1.3) * scan;
	vec3 c = mix(tint.rgb, vec3(1.0), tint.a);
	ALBEDO = c * k * (1.0 + tint.a * 1.5);
	ALPHA = clamp(k, 0.0, 1.0);
}
"""
	var kmat := ShaderMaterial.new()
	kmat.shader = ksh
	var kmi := MultiMeshInstance3D.new()
	kmi.multimesh = k_mm
	kmi.material_override = kmat
	kmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kmi.custom_aabb = AABB(Vector3(-10, -2, -40), Vector3(20, 10, 50))
	add_child(kmi)

	# crowd
	c_mm = MultiMesh.new()
	c_mm.transform_format = MultiMesh.TRANSFORM_3D
	c_mm.instance_count = MAX_CROWD
	c_mm.visible_instance_count = 0
	var csh := Shader.new()
	csh.code = """
shader_type spatial;
varying vec3 col;
void vertex() {
	col = COLOR.rgb;
	float ph = float(INSTANCE_ID) * 2.3;
	VERTEX.y += abs(sin(TIME * 9.0 + ph)) * 0.035;
}
void fragment() { ALBEDO = col; ROUGHNESS = 0.75; }
"""
	var cmat := ShaderMaterial.new()
	cmat.shader = csh
	var cmi := MultiMeshInstance3D.new()
	cmi.multimesh = c_mm
	cmi.material_override = cmat
	cmi.custom_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 6, 20))
	add_child(cmi)
	_restyle_crowd()

	# balls
	b_mm = MultiMesh.new()
	b_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bs := Meshes.sphere(0.12, 10)
	b_mat = _std(Color(1, 1, 1))
	b_mat.emission_enabled = true
	b_mat.emission = Color(1, 1, 1)
	b_mat.emission_energy_multiplier = 0.5
	bs.material = b_mat
	b_mm.mesh = bs
	b_mm.instance_count = MAX_BALLS
	b_mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = b_mm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.custom_aabb = AABB(Vector3(-10, -2, -40), Vector3(20, 10, 50))
	add_child(bmi)

	count_label = _label3d(84, Color.WHITE)
	add_child(count_label)


func _label3d(size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = size
	l.outline_size = size / 5
	l.pixel_size = 0.01
	l.modulate = c
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	return l


func _restyle_crowd() -> void:
	var b: Dictionary = BOOTS[tier]
	c_mm.mesh = Meshes.trainee(b.suit, b.trim)
	if b_mat:
		b_mat.albedo_color = b.ball
		b_mat.emission = b.ball


## Portrait phones keep the bridge's width on screen; a wide window keeps the vertical view.
func _fit_camera() -> void:
	var sz := get_viewport().get_visible_rect().size
	if sz.y > 0 and sz.x / sz.y > 0.62:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 64.0
	else:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = 42.0


# ---------------------------------------------------------------- ui

func _label(txt: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.12))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	return l


func _style(c: Color, r := 22) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _button(txt: String, col: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 30)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color(0.05, 0.08, 0.16))
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _style(col.lightened(0.12 if st == "hover" else 0.0)))
	b.custom_minimum_size = Vector2(200, 64)
	return b


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -18
	top.offset_top = 14
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	hud_kit = _label("", 26, Color(1.0, 0.82, 0.45))
	hud_kit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(hud_kit)
	hud_score = _label("", 26, Color(0.85, 0.92, 1.0))
	top.add_child(hud_score)
	banner = _label("", 40, Color(1.0, 0.85, 0.5))
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.offset_left = -270
	banner.offset_right = 270
	banner.offset_top = -200
	banner.offset_bottom = -120
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(banner)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)


func _say(text: String, secs := 1.6) -> void:
	banner.text = text
	banner.visible = true
	_banner_t = secs


func _overlay_box(title: String, sub: String) -> VBoxContainer:
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.12, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.custom_minimum_size = Vector2(440, 0)
	center.add_child(v)
	var t1 := _label(title, 56, Color(1.0, 0.5, 0.58))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t1)
	var t2 := _label(sub, 24, Color(0.9, 0.93, 1.0))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t2)
	return v


func _show_title() -> void:
	state = "title"
	_reset()
	var v := _overlay_box("REDLOCK\nSTRIKER", "Working title. Drag to aim your squad. Shoot the right rack for recruits and the left rack for better boots. Hold the bridge against the holo keepers.\n\nWho leads the squad?")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var bh := _button("Hiyori", Color(1.0, 0.66, 0.72))
	bh.pressed.connect(func(): _start("hiyori"))
	row.add_child(bh)
	var bk := _button("Kasumi", Color(0.55, 0.95, 0.85))
	bk.pressed.connect(func(): _start("kasumi"))
	row.add_child(bk)


# ---------------------------------------------------------------- run

func _reset() -> void:
	for h in heroes:
		h.queue_free()
	heroes.clear()
	crowd = 0
	tier = 0
	rate_mul = 1.0
	squad_x = 0.0
	target_x = 0.0
	t = 0.0
	kills = 0
	next_boss = 40.0
	bosses_beaten = 0
	k_pos.clear()
	k_hp.clear()
	k_big.clear()
	k_flash.clear()
	b_pos.clear()
	b_vel.clear()
	b_dmg.clear()
	if boss:
		boss.queue_free()
		boss = null
	if boss_label:
		boss_label.queue_free()
		boss_label = null
	_restyle_crowd()


func _start(pick: String) -> void:
	hero_pick = pick
	_reset()
	for tw in towers:
		tw.hero_name = "Kasumi" if pick == "hiyori" else "Hiyori"
	_add_hero(pick)
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = false
	state = "play"
	_say("Hold the bridge!", 1.4)


func _add_hero(look: String) -> void:
	var s := Striker.new()
	add_child(s)
	s.setup(look)
	if hero_models.has(look):
		s.use_model(hero_models[look], 1.9)   # captains stand a head taller than the trainees
	s.position = Vector3(squad_x, 0, SQUAD_Z)
	heroes.append(s)


func _units() -> int:
	return crowd + heroes.size()


func _radius() -> float:
	return SPACING * 0.55 * sqrt(float(maxi(1, _units()))) + 0.25


## Sunflower packing: slot 0 at the front middle, the rest spiral out behind and around it.
func _slot(i: int) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	var a := i * 2.399963
	var r := SPACING * 0.55 * sqrt(float(i)) * 1.0
	return Vector3(cos(a) * r, 0, sin(a) * r * 0.9)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if state != "play":
		return
	var w := get_viewport().get_visible_rect().size.x
	if event is InputEventScreenDrag:
		target_x += event.relative.x / w * HALF * 2.4
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DisplayServer.is_touchscreen_available():
		target_x += event.relative.x / w * HALF * 2.4


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_debug_tick(delta)
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.visible = _banner_t > 0.0
	hud_kit.text = BOOTS[tier].name.to_upper()
	hud_score.text = "%d KO" % kills
	if state != "play":
		_draw_crowd(delta)
		return
	t += delta
	target_x += Input.get_axis("ui_left", "ui_right") * 7.0 * delta
	var lim := maxf(0.0, HALF - 0.3 - _radius())
	target_x = clampf(target_x, -lim, lim)
	squad_x = lerpf(squad_x, target_x, 1.0 - exp(-12.0 * delta))
	_spawn_keepers(delta)
	_fire(delta)
	_move_balls(delta)
	_move_keepers(delta)
	_move_boss(delta)
	_draw_crowd(delta)
	if _units() <= 0:
		_game_over()
	if shake > 0.0:
		shake -= delta
		cam.h_offset = randf_range(-0.12, 0.12)
		cam.v_offset = randf_range(-0.08, 0.08)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func _spawn_keepers(delta: float) -> void:
	# a steady stream that thickens over time; bosses on a timer
	var rate := minf(0.7 + t * 0.05, 11.0)
	spawn_acc += rate * delta
	var hp := 1.0 + t / 35.0 + pow(t / 50.0, 2.6) * 5.0
	while spawn_acc >= 1.0 and k_pos.size() < MAX_KEEPERS:
		spawn_acc -= 1.0
		var big := t > 20.0 and randf() < 0.1
		k_pos.append(Vector3(randf_range(-1.5, 1.5), 0, GATE_Z + randf_range(-0.5, 0.5)))
		k_hp.append(hp * (8.0 if big else 1.0))
		k_big.append(1 if big else 0)
		k_flash.append(0.0)
	if boss == null and t >= next_boss:
		_spawn_boss()


func _spawn_boss() -> void:
	boss = HoloKeeper.new()
	add_child(boss)
	var hp := 800.0 * pow(4.0, bosses_beaten)
	boss.setup("boss", hp / 120.0)
	boss.position = Vector3(0, 0, GATE_Z)
	boss_label = _label3d(90, Color(1, 0.45, 0.5))
	add_child(boss_label)
	shake = 0.4
	_say("GIANT HOLO KEEPER", 1.8)


func _targets() -> Array:
	# what the squad shoots at: the closest keepers in front, the boss, and a rack crate if lined up
	var out := []
	var front := SQUAD_Z - 1.0
	var best := []
	for i in k_pos.size():
		var p := k_pos[i]
		if p.z < front and absf(p.x - squad_x) < 2.6 and p.z > GATE_Z - 1.0:
			best.append([front - p.z + absf(p.x - squad_x) * 1.5, p])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(5, best.size()):
		out.append(best[k][1] + Vector3(0, 0.8, 0))
	if boss:
		out.append(boss.position + Vector3(0, 2.5, 0))
	for tw in towers:
		var tp := tw.target()
		if absf(tp.x - squad_x) < 1.3 + _radius() * 0.5:
			out.append(tp)
			out.append(tp)
	return out


func _fire(delta: float) -> void:
	var b: Dictionary = BOOTS[tier]
	var per_sec: float = (crowd + heroes.size() * 3.0) * 1.4 * b.rate * rate_mul   # heroes kick three times as hard
	var balls_per_sec := minf(per_sec, MAX_BALLS_PER_SEC)
	var dmg: float = b.dmg * per_sec / maxf(balls_per_sec, 0.001)
	shot_acc += balls_per_sec * delta
	if shot_acc < 1.0:
		return
	var targets := _targets()
	var n := _units()
	while shot_acc >= 1.0:
		shot_acc -= 1.0
		if b_pos.size() >= MAX_BALLS:
			continue
		var from := Vector3(squad_x, 0.3, SQUAD_Z) + _slot(randi() % n)
		var aim: Vector3 = from + Vector3(0, 0, -30) if targets.is_empty() else targets[randi() % targets.size()]
		aim += Vector3(randf_range(-0.25, 0.25), 0, 0)
		var dir := (aim - from)
		dir.y = 0.0
		b_pos.append(from)
		b_vel.append(dir.normalized() * BALL_SPEED)
		b_dmg.append(dmg)
	for h in heroes:
		if randf() < delta * 3.0:
			h.kick()


func _move_balls(delta: float) -> void:
	var buckets := {}
	for i in k_pos.size():
		var key := int(floor(k_pos[i].z))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var dead_k := {}
	var i := 0
	while i < b_pos.size():
		var p := b_pos[i] + b_vel[i] * delta
		var gone := p.z < GATE_Z - 3.0 or absf(p.x) > HALF + 1.5
		if not gone:
			var key := int(floor(p.z))
			for kk in [key - 1, key, key + 1]:
				if gone or not buckets.has(kk):
					continue
				for ki in buckets[kk]:
					if dead_k.has(ki):
						continue
					var r := 0.5 if k_big[ki] == 1 else 0.36
					if absf(k_pos[ki].x - p.x) < r and absf(k_pos[ki].z - p.z) < r:
						k_hp[ki] -= b_dmg[i]
						k_flash[ki] = 0.06
						if k_hp[ki] <= 0.0:
							dead_k[ki] = true
						gone = true
						break
		if not gone and boss and absf(boss.position.x - p.x) < 1.3 and absf(boss.position.z - p.z) < 0.8:
			gone = true
			if boss.hit(int(ceil(b_dmg[i]))):
				_boss_down()
		if not gone:
			for tw in towers:
				var tp := tw.target()
				if absf(tp.x - p.x) < 0.5 and absf(tp.z - p.z) < 0.45:
					gone = true
					var got := tw.hit(maxi(1, int(round(b_dmg[i]))))
					if not got.is_empty():
						_claim(got, tp)
					break
		if gone:
			var last := b_pos.size() - 1
			b_pos[i] = b_pos[last]
			b_vel[i] = b_vel[last]
			b_dmg[i] = b_dmg[last]
			b_pos.resize(last)
			b_vel.resize(last)
			b_dmg.resize(last)
		else:
			b_pos[i] = p
			i += 1
	if not dead_k.is_empty():
		var idx := dead_k.keys()
		idx.sort()
		idx.reverse()
		for ki in idx:
			kills += 1
			if randf() < 0.35:
				_burst(k_pos[ki], BRUTE_TINT if k_big[ki] == 1 else KEEPER_TINT, 6)
			_remove_keeper(ki)
	b_mm.visible_instance_count = b_pos.size()
	for j in b_pos.size():
		b_mm.set_instance_transform(j, Transform3D(Basis(), b_pos[j]))


func _remove_keeper(i: int) -> void:
	var last := k_pos.size() - 1
	k_pos[i] = k_pos[last]
	k_hp[i] = k_hp[last]
	k_big[i] = k_big[last]
	k_flash[i] = k_flash[last]
	k_pos.resize(last)
	k_hp.resize(last)
	k_big.resize(last)
	k_flash.resize(last)


func _move_keepers(delta: float) -> void:
	var rad := _radius()
	var centre := Vector3(squad_x, 0, SQUAD_Z)
	var i := 0
	while i < k_pos.size():
		var p := k_pos[i]
		var spd := 1.5 if k_big[i] == 1 else 2.1
		p.z += spd * delta
		# past the racks the bridge opens up and they head for the squad
		if p.z > TOWER_Z + 1.0:
			p.x = move_toward(p.x, squad_x + clampf(p.x - squad_x, -rad, rad), 0.9 * delta)
		k_pos[i] = p
		k_flash[i] = maxf(0.0, k_flash[i] - delta)
		var d := Vector2(p.x - centre.x, (p.z - centre.z) * 1.1).length()
		if d < rad + 0.2 or p.z > SQUAD_Z + 3.0:
			if p.z <= SQUAD_Z + 3.0:
				_lose(3 if k_big[i] == 1 else 1)
			_remove_keeper(i)
			continue
		i += 1
	k_mm.visible_instance_count = k_pos.size()
	for j in k_pos.size():
		var big := k_big[j] == 1
		var s := 1.5 if big else 1.0
		k_mm.set_instance_transform(j, Transform3D(Basis().scaled(Vector3.ONE * s), k_pos[j]))
		var c := BRUTE_TINT if big else KEEPER_TINT
		k_mm.set_instance_custom_data(j, Color(c.r, c.g, c.b, 1.0 if k_flash[j] > 0.0 else 0.0))


func _move_boss(delta: float) -> void:
	if boss == null:
		return
	var front := SQUAD_Z - _radius() - 1.0
	if boss.position.z < front:
		boss.position.z += 0.9 * delta
		boss.position.x = move_toward(boss.position.x, clampf(squad_x, -1.5, 1.5), 0.4 * delta)
	else:
		# it reached the squad: it flattens strikers until it falls
		if randf() < delta * 3.0:
			_lose(maxi(1, int(_units() * 0.04)))
			shake = 0.15
	boss_label.text = str(maxi(0, boss.hp))
	boss_label.position = boss.position + Vector3(0, 5.2, 0)


func _boss_down() -> void:
	_burst(boss.position + Vector3(0, 1.5, 0), Color(1, 0.4, 0.8), 50)
	kills += 1
	boss.queue_free()
	boss = null
	boss_label.queue_free()
	boss_label = null
	bosses_beaten += 1
	next_boss = t + 45.0
	shake = 0.5
	_say("GIANT KEEPER DOWN!", 1.8)


func _lose(n: int) -> void:
	for k in n:
		if crowd > 0:
			crowd -= 1
		elif not heroes.is_empty():
			var h: Striker = heroes.pop_back()
			_burst(h.position, Color(1, 0.6, 0.7), 10)
			h.queue_free()


func _claim(it: Dictionary, at: Vector3) -> void:
	_burst(at, Color(1, 0.85, 0.4) if it.reward in ["boots", "rate"] else Color(0.5, 0.75, 1.0), 20)
	var pop := _label3d(110, Color.WHITE)
	pop.text = it.text
	pop.position = at + Vector3(0, 1.0, 0)
	add_child(pop)
	var tw := create_tween()
	tw.tween_property(pop, "position", Vector3(squad_x, 2.2, SQUAD_Z), 0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		_apply(it)
		pop.queue_free())


func _apply(it: Dictionary) -> void:
	match it.reward:
		"recruits":
			crowd = mini(MAX_CROWD - heroes.size(), crowd + int(it.value))
		"hero":
			var other := "kasumi" if hero_pick == "hiyori" else "hiyori"
			_add_hero(other)
			_say("%s JOINS!" % Striker.LOOKS[other].name.to_upper())
		"boots":
			if tier < BOOTS.size() - 1:
				tier += 1
				_restyle_crowd()
				_say(BOOTS[tier].name.to_upper() + "!")
			else:
				rate_mul *= 1.25
		"rate":
			rate_mul *= 1.25
			_say("RAPID KICKS!")


func _draw_crowd(delta: float) -> void:
	var n := crowd
	c_mm.visible_instance_count = n
	var base := Vector3(squad_x, 0, SQUAD_Z)
	var unit := Basis().scaled(Vector3.ONE * 0.78)
	for i in n:
		c_mm.set_instance_transform(i, Transform3D(unit, base + _slot(i)))
	# the named strikers lead from the front of the crowd
	var front := -_radius() * 0.85 if n > 0 else 0.0
	for i in heroes.size():
		var h := heroes[i]
		var off := Vector3((i - (heroes.size() - 1) * 0.5) * 0.75, 0, front - 0.3)
		var goal := base + off
		h.set_moving(absf(goal.x - h.position.x) > 0.05)
		h.position = h.position.lerp(goal, 1.0 - exp(-12.0 * delta))
	count_label.visible = state == "play"
	count_label.text = str(_units())
	count_label.position = base + Vector3(0, 2.4, 0)


func _game_over() -> void:
	state = "over"
	var v := _overlay_box("SQUAD DOWN", "%d holo keepers kicked out, %d giant keepers beaten." % [kills, bosses_beaten])
	var b := _button("Try again", Color(1.0, 0.66, 0.72))
	b.pressed.connect(func(): _start(hero_pick))
	v.add_child(b)
	var m := _button("Change leader", Color(0.85, 0.88, 0.95))
	m.pressed.connect(_show_title)
	v.add_child(m)


# ---------------------------------------------------------------- effects

func _burst(pos: Vector3, c: Color, n: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = n
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 80
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9, 0)
	var q := Meshes.box(0.09, 0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	q.material = m
	p.mesh = q
	p.position = pos + Vector3(0, 0.6, 0)
	add_child(p)
	get_tree().create_timer(0.8, false).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- debug

## --auto (play by itself), --t=secs (start later in the run), --crowd=N, --tier=N,
## --shot=path.png --at=secs (screenshot then quit), --quit=secs (print a summary).
var _auto := false
var _shot_path := ""
var _shot_at := -1.0
var _quit_at := -1.0
var _clock := 0.0


func _debug_args() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--auto":
			_auto = true
		elif a.begins_with("--shot="):
			_shot_path = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			_shot_at = float(a.get_slice("=", 1))
		elif a.begins_with("--quit="):
			_quit_at = float(a.get_slice("=", 1))
	if not _auto:
		return
	_start("hiyori")
	for a in args:
		if a.begins_with("--t="):
			t = float(a.get_slice("=", 1))
		elif a.begins_with("--crowd="):
			crowd = int(a.get_slice("=", 1))
		elif a == "--closeup":
			cam.position = Vector3(0, 3.0, SQUAD_Z + 4.5)
			cam.look_at(Vector3(0, 0.9, SQUAD_Z - 1.0))
			_add_hero("kasumi")
		elif a.begins_with("--tier="):
			tier = int(a.get_slice("=", 1))
			_restyle_crowd()


func _debug_tick(delta: float) -> void:
	_clock += delta
	if _auto and state == "play":
		# alternate between the racks and the middle every few seconds
		# like a player: deal with keepers that get close, otherwise work the racks in turn
		var near := 0.0
		var cnt := 0
		for p in k_pos:
			if p.z > SQUAD_Z - 7.0:
				near += p.x
				cnt += 1
		if cnt > 2:
			target_x = near / cnt
		else:
			target_x = TOWER_X if int(_clock / 5.0) % 2 == 0 else -TOWER_X
	if _auto and state == "over" and _quit_at < 0.0:
		get_tree().quit()
	if _shot_path != "" and _shot_at >= 0.0 and _clock >= _shot_at:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		_shot_path = ""
		if _quit_at < 0.0:
			get_tree().quit()
	if _quit_at >= 0.0 and _clock >= _quit_at:
		print("QUIT t=%d state=%s units=%d tier=%d kills=%d bosses=%d keepers=%d" % [t, state, _units(), tier, kills, bosses_beaten, k_pos.size()])
		get_tree().quit()
