extends Node3D
## Redlock Striker (working title). Portrait lane shooter on a long floating Redlock bridge, seen
## from a fixed camera behind the squad. Your squad stands at the near end and kicks footballs
## straight up the bridge nonstop; drag left and right to pick a lane. Holographic keepers pour down
## the middle lane from the far end; touching the squad costs clones. Two straight rows of reward
## tiles line the edges behind stone gates: kick a gate's number down to zero for its first tile.
## The right row gives clones (+1 ... +99), the left row gives boot upgrades.
## Levels: each level is a fresh run that ends with a giant holo keeper with a big health number.
## Beat it to clear the level and unlock the next one, which is tougher. Progress is saved.
## Every squad member is a clone of the girl you pick: the leader is the full animated model, the
## rest are baked low-poly kick poses drawn as MultiMeshes (a six-frame flipbook) so the squad can
## reach hundreds.

const HALF := 3.4            # bridge half width
const SQUAD_Z := 5.0
const GATE_Z := -30.0        # where keepers come out
const ROW_Z := -4.0          # the reward rows' gates
const ROW_X := 2.65          # centre of each reward row
const LANE := 1.75           # the middle lane between the reward rows
const MARCH := 0.8           # keepers march down in a column, |x| < MARCH, straight at the near end
const CLONE_H := 1.1        # clone height in metres
const LEADER_H := 1.3
const POSES := 8             # clone frames: 0 = standing, 1..7 = the kick
const POSE_FPS := 16.0
const KICK_EVERY := 0.9
const WAVE_EVERY := 18.0     # a rush of keepers this often
const SAVE_PATH := "user://striker_save.json"      # each clone kicks once per this many seconds
const BALL_SPEED := 26.0
const MAX_BALLS := 900
const MAX_BALLS_PER_SEC := 140.0
const MAX_KEEPERS := 420
const MAX_CROWD := 300
const SPACING := 0.36
const BOOTS := [
	{"name": "Training boots", "dmg": 1, "rate": 1.0, "suit": Color(0.14, 0.24, 0.5), "trim": Color(0.95, 0.93, 0.85), "ball": Color(1, 1, 1)},
	{"name": "Studded boots", "dmg": 2, "rate": 1.1, "suit": Color(0.12, 0.36, 0.6), "trim": Color(0.55, 0.95, 0.85), "ball": Color(0.8, 1.0, 0.95)},
	{"name": "Pro boots", "dmg": 4, "rate": 1.2, "suit": Color(0.1, 0.45, 0.72), "trim": Color(1.0, 1.0, 1.0), "ball": Color(0.7, 0.9, 1.0)},
	{"name": "Golden boots", "dmg": 7, "rate": 1.3, "suit": Color(0.9, 0.9, 0.95), "trim": Color(1.0, 0.8, 0.3), "ball": Color(1.0, 0.85, 0.4)},
	{"name": "Spirit boots", "dmg": 12, "rate": 1.4, "suit": Color(1.0, 0.8, 0.88), "trim": Color(1.0, 0.45, 0.65), "ball": Color(1.0, 0.6, 0.8)},
	{"name": "Redlock elite", "dmg": 20, "rate": 1.5, "suit": Color(0.95, 0.25, 0.3), "trim": Color(1.0, 0.85, 0.4), "ball": Color(1.0, 0.5, 0.4)},
]
const KEEPER_TINT := Color(1.0, 0.16, 0.38)    # hot red-pink holograms: pop against the green turf
const BRUTE_TINT := Color(1.0, 0.55, 0.05)

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
var next_boss := 55.0
var bosses_beaten := 0
var level := 1
var unlocked := 1
var boss_hp := 0
var hud_level: Label
var hud_bar: ProgressBar
var spawn_acc := 0.0
var next_wave := 20.0
var wave_left := 0
var shot_acc := 0.0
var shake := 0.0
var hero_models := {}
var clone_poses := {}     # who -> Array of POSES meshes
var clips: AnimationLibrary
var font: Font

# keepers: flat arrays, drawn by one MultiMesh
var k_pos := PackedVector3Array()
var k_hp := PackedFloat32Array()
var k_big := PackedByteArray()
var k_flash := PackedFloat32Array()
var k_mm: MultiMesh
# balls
var b_pos := PackedVector3Array()
var b_vel := PackedVector3Array()   # x = the column the ball lines up on
var b_dmg := PackedFloat32Array()
var b_mm: MultiMesh
var b_mat: StandardMaterial3D
# crowd: one MultiMesh per kick pose, plus a tier-coloured disc under each clone
var c_mms: Array[MultiMesh] = []
var d_mm: MultiMesh
var d_mat: StandardMaterial3D

var rows: Array[RewardRow] = []
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
		var poses := []
		for i in POSES:
			var pp := "res://assets/characters/%s_kick_%d.res" % [who, i]
			if ResourceLoader.exists(pp):
				poses.append(load(pp))
		if poses.size() == POSES:
			clone_poses[who] = poses
	if ResourceLoader.exists("res://assets/characters/football_clips.res"):
		clips = load("res://assets/characters/football_clips.res")
	_load_save()
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
	# bright and clean like the Project R arena: pale sky, soft daylight, slate and cyan trim
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.5, 0.66, 0.86)
	sky_mat.sky_horizon_color = Color(0.86, 0.9, 0.95)
	sky_mat.ground_bottom_color = Color(0.6, 0.7, 0.85)
	sky_mat.ground_horizon_color = Color(0.86, 0.9, 0.95)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.9, 1.0)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -25, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 26.0
	add_child(sun)

	cam = Camera3D.new()
	cam.far = 150
	add_child(cam)
	cam.position = Vector3(0, 11.5, SQUAD_Z + 9.0)
	cam.look_at(Vector3(0, 0, SQUAD_Z - 12.5))

	# the bridge deck: Project R floor slabs, with the arena's striped turf down the middle lane
	var deck_len := SQUAD_Z + 6.0 - (GATE_Z - 4.0)
	var deck_mid := (SQUAD_Z + 6.0 + GATE_Z - 4.0) * 0.5
	var deck := MeshInstance3D.new()
	deck.mesh = Meshes.box(HALF * 2.0, 1.0, deck_len)
	deck.position = Vector3(0, -0.5, deck_mid)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float row_z;
uniform float lane;
uniform sampler2D slab : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D slab_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D turf_d : filter_linear_mipmap, repeat_enable;
uniform sampler2D turf_n : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// light grey floor panels with thin dark seams every 2 m
	vec2 pf = fract(wp.xz / 2.0);
	float seam = 1.0 - step(0.012, pf.x) * step(0.012, pf.y);
	vec3 floor_c = texture(slab, wp.xz / 4.0).rgb * vec3(0.8, 0.82, 0.88);
	floor_c = mix(floor_c, pow(vec3(0.42, 0.45, 0.52), vec3(2.2)), seam * 0.8);
	// turf: the arena's mowing stripes (2.5 m bands) plus fine grain
	float stripe = step(0.5, fract(wp.z / 5.0));
	vec3 turf_c = pow(mix(vec3(0.17, 0.42, 0.08), vec3(0.23, 0.5, 0.1), stripe), vec3(2.2));
	turf_c *= 0.82 + 0.36 * texture(turf_d, wp.xz / 3.0).r;
	float in_lane = step(wp.z, row_z) * step(abs(wp.x), lane + 0.25);
	// white touchlines down both sides of the lane and across its mouth
	float line = in_lane * (step(lane + 0.13, abs(wp.x)) + step(row_z - 0.12, wp.z));
	vec3 c = mix(floor_c, turf_c, in_lane);
	c = mix(c, vec3(0.85), clamp(line, 0.0, 1.0));
	float top = step(-0.01, wp.y);
	ALBEDO = mix(pow(vec3(0.3, 0.34, 0.42), vec3(2.2)), c, top);
	NORMAL_MAP = mix(texture(slab_n, wp.xz / 4.0).rgb, texture(turf_n, wp.xz / 2.0).rgb, in_lane);
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = mix(0.55, 0.95, in_lane);
}
"""
	var dm := ShaderMaterial.new()
	dm.shader = sh
	dm.set_shader_parameter("row_z", ROW_Z + 0.6)
	dm.set_shader_parameter("lane", LANE)
	dm.set_shader_parameter("slab", load("res://assets/textures/slab_albedo.jpg"))
	dm.set_shader_parameter("slab_n", load("res://assets/textures/slab_normal.png"))
	dm.set_shader_parameter("turf_d", load("res://assets/textures/turf_detail.png"))
	dm.set_shader_parameter("turf_n", load("res://assets/textures/turf_normal.png"))
	deck.material_override = dm
	add_child(deck)
	# low slate border along both edges with the arena's cyan light strip (no tall walls)
	var slate := _std(Color(0.27, 0.31, 0.39))
	slate.roughness = 0.5
	var cyan := StandardMaterial3D.new()
	cyan.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyan.albedo_color = Color(0.45, 0.95, 1.0)
	for side in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		rim.mesh = Meshes.box(0.26, 0.18, deck_len)
		rim.position = Vector3(side * (HALF + 0.13), 0.09, deck_mid)
		rim.material_override = slate
		add_child(rim)
		var strip := MeshInstance3D.new()
		strip.mesh = Meshes.box(0.03, 0.04, deck_len)
		strip.position = Vector3(side * HALF, 0.1, deck_mid)
		strip.material_override = cyan
		add_child(strip)
	# the keepers' gate at the far end: a slate frame with a cyan holo projector bar
	var frame := _std(Color(0.22, 0.26, 0.34))
	var bar := MeshInstance3D.new()
	bar.mesh = Meshes.box(4.4, 0.45, 0.5)
	bar.position = Vector3(0, 3.0, GATE_Z - 0.6)
	bar.material_override = frame
	add_child(bar)
	var glow := MeshInstance3D.new()
	glow.mesh = Meshes.box(3.6, 0.08, 0.06)
	glow.position = Vector3(0, 2.8, GATE_Z - 0.33)
	glow.material_override = cyan
	add_child(glow)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = Meshes.box(0.4, 3.0, 0.5)
		post.position = Vector3(side * 2.0, 1.5, GATE_Z - 0.6)
		post.material_override = frame
		add_child(post)
	var sign := Label3D.new()
	sign.text = "REDLOCK"
	sign.font = font
	sign.font_size = 120
	sign.outline_size = 18
	sign.pixel_size = 0.011
	sign.modulate = Color(0.95, 0.25, 0.3)
	sign.outline_modulate = Color(1, 1, 1)
	sign.position = Vector3(0, 3.0, GATE_Z - 0.3)
	add_child(sign)

	# reward rows: clones on the right, kit on the left (as you look up the bridge)
	for side in [-1.0, 1.0]:
		var row := RewardRow.new()
		add_child(row)
		row.setup("recruits" if side > 0 else "kit", side, Vector3(side * ROW_X, 0, ROW_Z), font)
		rows.append(row)

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
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;
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
	// a solid, bright hologram: strong colour core, white-hot rim, faint scanlines
	float scan = 0.88 + 0.12 * step(0.5, fract(world.y * 12.0 - TIME * 1.6));
	vec3 c = mix(tint.rgb * 0.95, vec3(1.0), clamp(rim * 0.8, 0.0, 0.8)) * scan;
	c = mix(c, vec3(1.0), tint.a);
	ALBEDO = c;
	ALPHA = 0.9;
}
"""
	var kmat := ShaderMaterial.new()
	kmat.shader = ksh
	var kmi := MultiMeshInstance3D.new()
	kmi.multimesh = k_mm
	kmi.material_override = kmat
	kmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kmi.custom_aabb = AABB(Vector3(-10, -2, -45), Vector3(20, 12, 60))
	add_child(kmi)

	# crowd: the clones, one MultiMesh per kick pose; the meshes keep the model's own materials
	for f in POSES:
		var cm := MultiMesh.new()
		cm.transform_format = MultiMesh.TRANSFORM_3D
		cm.instance_count = MAX_CROWD
		cm.visible_instance_count = 0
		var cmi := MultiMeshInstance3D.new()
		cmi.multimesh = cm
		cmi.custom_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 6, 25))
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cmi)
		c_mms.append(cm)
	# a soft blob shadow under every clone keeps them on the ground
	d_mm = MultiMesh.new()
	d_mm.transform_format = MultiMesh.TRANSFORM_3D
	d_mm.instance_count = MAX_CROWD + 1
	d_mm.visible_instance_count = 0
	var disc := PlaneMesh.new()
	disc.size = Vector2(0.55, 0.55)
	d_mat = StandardMaterial3D.new()
	d_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	d_mat.albedo_color = Color(0.05, 0.07, 0.12, 0.45)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.gradient = gr
	d_mat.albedo_texture = g
	disc.material = d_mat
	d_mm.mesh = disc
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = d_mm
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.custom_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 6, 25))
	add_child(dmi)
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
	bmi.custom_aabb = AABB(Vector3(-10, -2, -45), Vector3(20, 12, 60))
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
	# level name and a bar that fills until the level's giant keeper arrives
	var mid := VBoxContainer.new()
	mid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mid.offset_left = -110
	mid.offset_right = 110
	mid.offset_top = 52
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	hud_level = _label("", 30, Color(1, 1, 1))
	hud_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(hud_level)
	hud_bar = ProgressBar.new()
	hud_bar.show_percentage = false
	hud_bar.custom_minimum_size = Vector2(220, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.14, 0.25, 0.6)
	bg.set_corner_radius_all(7)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1.0, 0.3, 0.45)
	fg.set_corner_radius_all(7)
	hud_bar.add_theme_stylebox_override("background", bg)
	hud_bar.add_theme_stylebox_override("fill", fg)
	hud_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(hud_bar)
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
	var v := _overlay_box("REDLOCK\nSTRIKER", "Working title. Drag to pick your lane: your kicks fly straight ahead. Right row: more clones. Left row: better boots. Grey walls hold nothing. Middle: stop the holo keepers. Beat the giant keeper at the end of each level to unlock the next.\n\nWho do you play? Every new squad member is her clone.")
	# level picker: any level you've unlocked
	var pick := HBoxContainer.new()
	pick.alignment = BoxContainer.ALIGNMENT_CENTER
	pick.add_theme_constant_override("separation", 14)
	v.add_child(pick)
	var lv := _label("", 34, Color(1, 0.85, 0.5))
	lv.custom_minimum_size = Vector2(170, 0)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var prev := _button("<", Color(0.85, 0.88, 0.95))
	prev.custom_minimum_size = Vector2(64, 64)
	var next := _button(">", Color(0.85, 0.88, 0.95))
	next.custom_minimum_size = Vector2(64, 64)
	var show := func():
		lv.text = "LEVEL %d" % level
		prev.disabled = level <= 1
		next.disabled = level >= unlocked
	prev.pressed.connect(func():
		level = maxi(1, level - 1)
		show.call())
	next.pressed.connect(func():
		level = mini(unlocked, level + 1)
		show.call())
	pick.add_child(prev)
	pick.add_child(lv)
	pick.add_child(next)
	show.call()
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


# ---------------------------------------------------------------- levels

## How tough level L is compared with level 1 (keeper health and numbers).
func _tough() -> float:
	return pow(1.18, level - 1)


## Seconds until the level's giant keeper walks out: later levels give a little longer to grow.
func _boss_time() -> float:
	return 55.0 + 6.0 * minf(level - 1, 10)


## Clones you start a level with: two, plus one more for every two levels behind you, so later levels open with
## a squad ready for their tougher keepers.
func _head_start() -> int:
	return 2 + mini(10, (level - 1) / 2)


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		unlocked = maxi(1, int(d.get("unlocked", 1)))
		level = clampi(int(d.get("level", unlocked)), 1, unlocked)
		hero_pick = str(d.get("pick", hero_pick))


func _save() -> void:
	if _auto:
		return   # bot runs never touch the player's progress
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked": unlocked, "level": level, "pick": hero_pick}))


func _level_cleared() -> void:
	state = "cleared"
	# the rest of the keepers burst
	for p in k_pos:
		_burst(p, KEEPER_TINT, 6)
	k_pos.clear()
	k_hp.clear()
	k_big.clear()
	k_flash.clear()
	k_mm.visible_instance_count = 0
	unlocked = maxi(unlocked, level + 1)
	_save()
	var v := _overlay_box("LEVEL %d\nCLEARED!" % level, "%d clones, %d holo keepers kicked out." % [_units(), kills])
	var b := _button("Next: level %d" % (level + 1), Color(1.0, 0.66, 0.72))
	b.pressed.connect(func():
		level += 1
		_start(hero_pick))
	v.add_child(b)
	var m := _button("Menu", Color(0.85, 0.88, 0.95))
	m.pressed.connect(_show_title)
	v.add_child(m)


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
	next_boss = _boss_time()
	next_wave = 20.0
	wave_left = 0
	spawn_acc = 0.0
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
	_save()
	if clone_poses.has(pick):
		for f in POSES:
			c_mms[f].mesh = clone_poses[pick][f]
	_add_hero(pick)
	crowd = _head_start()
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = false
	state = "play"
	_say("LEVEL %d" % level, 1.4)


func _add_hero(look: String) -> void:
	var s := Striker.new()
	add_child(s)
	s.setup(look)
	if hero_models.has(look):
		s.use_model(hero_models[look], LEADER_H)
		s.add_clips(clips)
		s.set_kicking(true)
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
	hud_level.text = "LEVEL %d" % level
	hud_level.visible = state != "title"
	hud_bar.visible = state == "play"
	if boss:
		hud_bar.value = 100.0 * float(boss.hp) / maxf(1.0, float(boss_hp))
	else:
		hud_bar.value = 100.0 * clampf(t / maxf(1.0, next_boss), 0.0, 1.0)
	if state != "play":
		_draw_crowd(delta)
		return
	t += delta
	target_x += Input.get_axis("ui_left", "ui_right") * 7.0 * delta
	target_x = clampf(target_x, -ROW_X, ROW_X)   # far enough out to stand right in front of a row
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
	# a steady trickle plus a rush every WAVE_EVERY seconds, both thickening over time
	var rate := minf((0.25 + t * 0.02) * (1.0 + 0.05 * (level - 1)), 9.0)
	spawn_acc += rate * delta
	if t >= next_wave:
		next_wave = t + WAVE_EVERY
		wave_left += 2 + int(t / 10.0)
	if wave_left > 0:
		var n := mini(wave_left, int(ceil(14.0 * delta * 6.0)))
		wave_left -= n
		spawn_acc += n
	var hp := (1.0 + t / 40.0 + pow(t / 70.0, 3.3) * 3.0) * _tough()
	while spawn_acc >= 1.0 and k_pos.size() < MAX_KEEPERS:
		spawn_acc -= 1.0
		var big := t > 25.0 and randf() < 0.1
		k_pos.append(Vector3(randf_range(-MARCH, MARCH), 0, GATE_Z + randf_range(-1.0, 0.5)))
		k_hp.append(hp * (8.0 if big else 1.0))
		k_big.append(1 if big else 0)
		k_flash.append(0.0)
	if boss == null and t >= next_boss:
		_spawn_boss()


func _spawn_boss() -> void:
	boss = HoloKeeper.new()
	add_child(boss)
	var hp := 250.0 * pow(1.55, level - 1)
	boss.setup("boss", hp / 120.0)
	boss_hp = boss.max_hp
	boss.position = Vector3(0, 0, GATE_Z)
	boss_label = _label3d(150, Color(1, 0.9, 0.3))
	add_child(boss_label)
	shake = 0.4
	_say("LEVEL BOSS!", 1.8)


## Every kick lines up on the squad's own column: the balls fan in from the clones and fly straight
## up the bridge, so standing on the right hits only the right row, the left only the left row, and
## the middle only the keepers in front of you.
func _fire(delta: float) -> void:
	var b: Dictionary = BOOTS[tier]
	var per_sec: float = (crowd + heroes.size() * 3.0) * 1.0 * b.rate * rate_mul   # the leader kicks three times as hard
	var balls_per_sec := minf(per_sec, MAX_BALLS_PER_SEC)
	var dmg: float = b.dmg * per_sec / maxf(balls_per_sec, 0.001)
	shot_acc += balls_per_sec * delta
	if shot_acc < 1.0:
		return
	var n := _units()
	var w := minf(0.7, 0.3 + 0.05 * sqrt(float(n)))
	while shot_acc >= 1.0:
		shot_acc -= 1.0
		if b_pos.size() >= MAX_BALLS:
			continue
		var from := _clone_pos(randi() % n) + Vector3(0, 0.3, 0)
		b_pos.append(from)
		b_vel.append(Vector3(squad_x + randf_range(-w, w), 0, 0))
		b_dmg.append(dmg)


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
		var p := b_pos[i]
		p.x = move_toward(p.x, b_vel[i].x, 10.0 * delta)
		p.z -= BALL_SPEED * delta
		var gone := p.z < GATE_Z - 3.0 or absf(p.x) > HALF + 1.5
		if not gone:
			var key := int(floor(p.z))
			for kk in [key - 1, key, key + 1]:
				if gone or not buckets.has(kk):
					continue
				for ki in buckets[kk]:
					if dead_k.has(ki):
						continue
					var r := 0.62 if k_big[ki] == 1 else 0.46
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
		if not gone and p.z < ROW_Z + 0.4 and absf(p.x) > LANE + 0.1:
			# up a reward row's lane: the front tile takes it
			for row in rows:
				var tp := row.target()
				if absf(tp.x - p.x) < 0.6:
					gone = true
					var got := row.hit(maxi(1, int(round(b_dmg[i]))))
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
			if idx.size() < 8 or randf() < 0.4:
				_burst(k_pos[ki], BRUTE_TINT if k_big[ki] == 1 else KEEPER_TINT, 8)
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
		var spd := 1.9 if k_big[i] == 1 else 2.6
		p.z += spd * delta
		# they march straight down their own line; they never turn towards you
		k_pos[i] = p
		k_flash[i] = maxf(0.0, k_flash[i] - delta)
		var d := Vector2(p.x - centre.x, (p.z - centre.z) * 1.1).length()
		if d < rad + 0.2 or p.z > SQUAD_Z + 1.0:
			# walking into the squad, or slipping past it off the end of the bridge, costs clones
			if d >= rad + 0.2:
				# slipped past: costs clones, never the leader herself
				crowd = maxi(0, crowd - (3 if k_big[i] == 1 else 1))
				_leak_flash()
			else:
				_lose(3 if k_big[i] == 1 else 1)
			_remove_keeper(i)
			continue
		i += 1
	k_mm.visible_instance_count = k_pos.size()
	for j in k_pos.size():
		var big := k_big[j] == 1
		var s := 1.9 if big else 1.3
		k_mm.set_instance_transform(j, Transform3D(Basis().scaled(Vector3.ONE * s), k_pos[j]))
		var c := BRUTE_TINT if big else KEEPER_TINT
		k_mm.set_instance_custom_data(j, Color(c.r, c.g, c.b, 1.0 if k_flash[j] > 0.0 else 0.0))


func _move_boss(delta: float) -> void:
	if boss == null:
		return
	var front := SQUAD_Z - _radius() - 1.0
	if boss.position.z < front:
		boss.position.z += 0.9 * delta
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
	next_boss = INF
	shake = 0.5
	state = "cleared"
	call_deferred("_level_cleared")   # not mid-way through the ball loop


## A keeper got past: a red flash along the near end of the bridge.
func _leak_flash() -> void:
	shake = maxf(shake, 0.12)
	_burst(Vector3(squad_x, 0, SQUAD_Z + 1.0), Color(1, 0.25, 0.3), 6)


func _lose(n: int) -> void:
	for k in n:
		if crowd > 0:
			crowd -= 1
		elif not heroes.is_empty():
			var h: Striker = heroes.pop_back()
			_burst(h.position, Color(1, 0.6, 0.7), 10)
			h.queue_free()


func _claim(it: Dictionary, at: Vector3) -> void:
	# the wall smashes into chunks; a plain wall gives nothing
	_burst(at - Vector3(0, 0.5, 0), it.get("color", Color(0.6, 0.62, 0.68)), 18, 0.2)
	_burst(at - Vector3(0, 0.5, 0), Color(0.78, 0.8, 0.85), 8, 0.14)
	shake = maxf(shake, 0.08)
	if it.reward == "none":
		return
	var pop := _label3d(70, Color.WHITE)
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
	var base := Vector3(squad_x, 0, SQUAD_Z)
	var counts := PackedInt32Array()
	counts.resize(POSES)
	counts.fill(0)
	var unit := Basis().scaled(Vector3.ONE * CLONE_H)
	var flat := Basis()
	# every clone stands, then kicks once per KICK_EVERY seconds; four groups take turns so the
	# squad ripples instead of twitching
	var kick_len := float(POSES - 1) / POSE_FPS
	for i in n:
		var p := _clone_pos(i)
		var ph := fposmod(_clock + float(i % 4) * KICK_EVERY * 0.25, KICK_EVERY)
		var f := 0
		if ph < kick_len:
			f = 1 + mini(POSES - 2, int(ph * POSE_FPS))
		c_mms[f].set_instance_transform(counts[f], Transform3D(unit, p))
		counts[f] += 1
		d_mm.set_instance_transform(i, Transform3D(flat, p + Vector3(0, 0.012, 0)))
	for f in POSES:
		c_mms[f].visible_instance_count = counts[f]
	d_mm.visible_instance_count = n + heroes.size()
	for i in heroes.size():
		var h := heroes[i]
		var goal := base + Vector3(0, 0, -_radius() * 0.8 - 0.15 if n > 0 else 0.0)   # the leader at the front
		h.set_moving(absf(goal.x - h.position.x) > 0.05)
		h.position = h.position.lerp(goal, 1.0 - exp(-12.0 * delta))
		d_mm.set_instance_transform(n + i, Transform3D(Basis().scaled(Vector3(1.3, 1, 1.3)), h.position + Vector3(0, 0.012, 0)))
	count_label.visible = state == "play"
	count_label.text = str(_units())
	count_label.position = base + Vector3(0, 2.0, 0)


## Where clone i stands: packed round the squad's centre, squeezed in at the bridge edges.
func _clone_pos(i: int) -> Vector3:
	var p := Vector3(squad_x, 0, SQUAD_Z) + _slot(i)
	p.x = clampf(p.x, -HALF + 0.25, HALF - 0.25)
	return p


func _game_over() -> void:
	state = "over"
	var v := _overlay_box("SQUAD DOWN", "Level %d. %d holo keepers kicked out." % [level, kills])
	var b := _button("Try again", Color(1.0, 0.66, 0.72))
	b.pressed.connect(func(): _start(hero_pick))
	v.add_child(b)
	var m := _button("Change leader", Color(0.85, 0.88, 0.95))
	m.pressed.connect(_show_title)
	v.add_child(m)


# ---------------------------------------------------------------- effects

func _burst(pos: Vector3, c: Color, n: int, chunk := 0.09) -> void:
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
	var q := Meshes.box(chunk, chunk, chunk)
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
	for a in args:
		if a.begins_with("--level="):
			level = int(a.get_slice("=", 1))
			unlocked = maxi(unlocked, level)
	_start("hiyori")
	for a in args:
		if a.begins_with("--t="):
			t = float(a.get_slice("=", 1))
		elif a.begins_with("--crowd="):
			crowd = int(a.get_slice("=", 1))
		elif a == "--closeup":
			cam.position = Vector3(1.2, 2.2, SQUAD_Z + 3.2)
			cam.look_at(Vector3(0, 0.6, SQUAD_Z - 0.8))
			_auto = false
		elif a == "--cleared":
			call_deferred("_level_cleared")
		elif a.begins_with("--tier="):
			tier = int(a.get_slice("=", 1))
			_restyle_crowd()


func _debug_tick(delta: float) -> void:
	_clock += delta
	if _auto and state == "play":
		# like a player: deal with keepers once they're past the rows, otherwise work the rows in turn
		var near := 0.0
		var cnt := 0
		for p in k_pos:
			if p.z > ROW_Z + 1.0:
				near += p.x
				cnt += 1
		if boss and boss.position.z > ROW_Z - 8.0:
			target_x = boss.position.x
		elif cnt > 1:
			target_x = near / cnt
		else:
			target_x = ROW_X if int(_clock / 6.0) % 2 == 0 else -ROW_X
	if _auto and state == "cleared" and _quit_at < 0.0:
		print("CLEAR level=%d t=%d units=%d tier=%d kills=%d" % [level, t, _units(), tier, kills])
		get_tree().quit()
	if _auto and state == "over" and _quit_at < 0.0:
		print("OVER level=%d t=%d units=%d tier=%d kills=%d boss_hp=%d" % [level, t, _units(), tier, kills, boss.hp if boss else -1])
		get_tree().quit()
	if _shot_path != "" and _shot_at >= 0.0 and _clock >= _shot_at:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		_shot_path = ""
		if _quit_at < 0.0:
			get_tree().quit()
	if _quit_at >= 0.0 and _clock >= _quit_at:
		print("QUIT t=%d state=%s units=%d tier=%d kills=%d bosses=%d keepers=%d" % [t, state, _units(), tier, kills, bosses_beaten, k_pos.size()])
		get_tree().quit()
