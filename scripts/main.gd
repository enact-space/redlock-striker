extends Node3D
## Redlock Striker (working title): a portrait lane shooter. Your squad runs up a floating
## Redlock training pitch kicking footballs automatically; drag left/right to aim the squad.
## Holographic keepers march down at you, crate stacks at the edges give rewards when you
## kick them down, and each stage ends with a giant holo keeper. Everything is built in code.

const LANE_HALF := 3.2
const SPAWN_Z := -50.0
const BALL_SPEED := 24.0
const BALL_END_Z := -52.0
const MAX_BALLS := 600
const MAX_SQUAD := 32
const RUN := 4.0
const HERO_RATE := 2.4
const TRAINEE_RATE := 1.2

const DIRECTOR_START := [
	"Holo keepers don't get tired. Neither should you. Kick through them.",
	"Every stack you break makes your squad stronger. Choose fast.",
	"Strikers who hesitate stay at the bottom. Show me your ego.",
]
const DIRECTOR_BOSS := [
	"Here comes the wall. Break it, or go home.",
	"A keeper this size has never conceded. Change that.",
]

var state := "title"
var stage := 1
var hero_pick := "hiyori"
var squad: Array[Striker] = []
var leader_x := 0.0
var target_x := 0.0
var shots := 1
var power := 1
var rate_mul := 1.0
var curve := false
var run_speed := RUN
var t := 0.0
var stage_len := 40.0
var timeline: Array = []
var enemies: Array[HoloKeeper] = []
var gates: Array[RewardGate] = []
var boss: HoloKeeper
var spirit := 0.0
var coins := 0
var kills := 0
var scroll := 0.0
var shake := 0.0
var spirit_ball: Node3D
var hero_model: PackedScene

# balls live in flat arrays and draw through one MultiMesh
var b_pos := PackedVector3Array()
var b_vel := PackedVector3Array()
var b_dmg := PackedInt32Array()
var balls_mm: MultiMesh

var cam: Camera3D
var lane_mat: ShaderMaterial
var posts: Array[Node3D] = []
var count_label: Label3D
var ui: CanvasLayer
var hud_stage: Label
var hud_coins: Label
var bar: ProgressBar
var bar_label: Label
var director_box: PanelContainer
var director_text: Label
var spirit_btn: Button
var spirit_fill: ColorRect
var overlay: Control
var cutin: Control
var cutin_label: Label
var hint: Label
var font: Font
var _director_t := 0.0
var _cutin_t := 0.0
var _drag := false


func _ready() -> void:
	randomize()
	font = load("res://assets/fonts/Nunito.ttf")
	_build_world()
	_build_ui()
	if ResourceLoader.exists("res://assets/characters/hiyori.glb"):
		hero_model = load("res://assets/characters/hiyori.glb")
	_show_title()
	_debug_args()
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()


## Portrait phones keep the lane's width on screen; a wide window (desktop browser) keeps the
## same vertical view instead, so the lane doesn't get cropped top and bottom.
func _fit_camera() -> void:
	var sz := get_viewport().get_visible_rect().size
	if sz.y > 0 and sz.x / sz.y > 0.62:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 71.0
	else:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = 44.0


## Debug: --auto (start as Hiyori, steer by itself), --stage=N, --spirit,
## --shot=path.png --at=secs (save a screenshot then quit), --quit=secs.
var _auto := false
var _shot_path := ""
var _shot_at := -1.0
var _quit_at := -1.0
var _clock := 0.0
var _jump_boss := false


func _debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--auto":
			_auto = true
		elif a.begins_with("--stage="):
			stage = int(a.get_slice("=", 1))
		elif a == "--boss":
			_jump_boss = true
		elif a.begins_with("--shot="):
			_shot_path = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			_shot_at = float(a.get_slice("=", 1))
		elif a.begins_with("--quit="):
			_quit_at = float(a.get_slice("=", 1))
	if _auto:
		var st := stage
		_start_game("hiyori")
		if st > 1:
			stage = st
			_start_stage()
		for a in OS.get_cmdline_user_args():
			if a == "--spirit":
				spirit = 1.0
		if _jump_boss:
			for i in 12:
				_add_member("trainee")
			power = 3
			timeline.clear()
			t = stage_len


func _debug_tick(delta: float) -> void:
	_clock += delta
	gates = gates.filter(func(g): return is_instance_valid(g) and not g.done)
	enemies = enemies.filter(func(e): return is_instance_valid(e) and not e.dead)
	if _auto and (state == "play" or state == "boss"):
		# aim at the nearest open crate stack, else the nearest crowd
		var aim := 0.0
		var best := 1e9
		for g in gates:
			if not g.done and g.position.z > -30.0 and -g.position.z < best:
				best = -g.position.z
				aim = g.position.x
		if best > 1e8:
			for e in enemies:
				if e.position.z > -30.0 and -e.position.z < best:
					best = -e.position.z
					aim = e.position.x
		target_x = aim
		if spirit >= 1.0 and boss:
			_use_spirit()
	if _auto and state == "clear":
		stage += 1
		_start_stage()
	if _shot_path != "" and _shot_at >= 0.0 and _clock >= _shot_at:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		_shot_path = ""
		if _quit_at < 0.0:
			get_tree().quit()
	if _quit_at >= 0.0 and _clock >= _quit_at:
		print("QUIT stage=%d state=%s squad=%d kills=%d shots=%d power=%d" % [stage, state, squad.size(), kills, shots, power])
		get_tree().quit()


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.07, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.95)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.1, 0.2)
	env.fog_density = 0.018
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.1
	add_child(sun)

	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 44
	cam.far = 140
	add_child(cam)
	cam.position = Vector3(0, 12.5, 8.0)
	cam.look_at(Vector3(0, 0, -7.5))

	# the pitch: one long strip, stripes scroll to show we're running forward
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float scroll = 0.0;
uniform float half_w = 3.2;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float z = wp.z - scroll;
	float stripe = step(0.5, fract(z / 6.0));
	vec3 g = mix(vec3(0.16, 0.42, 0.24), vec3(0.2, 0.5, 0.29), stripe);
	float edge = 1.0 - smoothstep(0.06, 0.1, abs(abs(wp.x) - (half_w - 0.35)));
	float mid = (1.0 - smoothstep(0.04, 0.07, abs(wp.x))) * step(0.5, fract(z / 3.0));
	vec3 c = mix(g, vec3(0.95, 0.95, 0.9), max(edge, mid * 0.6));
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""
	lane_mat = ShaderMaterial.new()
	lane_mat.shader = sh
	lane_mat.set_shader_parameter("half_w", LANE_HALF)
	var lane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LANE_HALF * 2.0, 90)
	lane.mesh = pm
	lane.position = Vector3(0, 0, -36)
	lane.material_override = lane_mat
	add_child(lane)
	# slab under the pitch: ivory edge, navy underside
	var slab := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(LANE_HALF * 2.0 + 0.6, 1.4, 90)
	slab.mesh = sb
	slab.position = Vector3(0, -0.72, -36)
	slab.material_override = _std(Color(0.88, 0.86, 0.8))
	add_child(slab)
	# barriers with a mint light strip
	for side in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(0.3, 0.45, 90)
		wall.mesh = wb
		wall.position = Vector3(side * (LANE_HALF + 0.15), 0.22, -36)
		wall.material_override = _std(Color(0.12, 0.17, 0.32))
		add_child(wall)
		var strip := MeshInstance3D.new()
		var stb := BoxMesh.new()
		stb.size = Vector3(0.32, 0.05, 90)
		strip.mesh = stb
		strip.position = Vector3(side * (LANE_HALF + 0.15), 0.47, -36)
		var m := _std(Color(0.55, 0.95, 0.85))
		m.emission_enabled = true
		m.emission = Color(0.55, 0.95, 0.85)
		m.emission_energy_multiplier = 0.5
		strip.material_override = m
		add_child(strip)
		# floodlight posts that slide past to sell the speed
		for i in 12:
			var p := Node3D.new()
			var pole := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.12, 2.4, 0.12)
			pole.mesh = pb
			pole.position.y = 1.2
			pole.material_override = _std(Color(0.85, 0.85, 0.82))
			p.add_child(pole)
			var lamp := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.5, 0.18, 0.22)
			lamp.mesh = lb
			lamp.position = Vector3(-side * 0.18, 2.45, 0)
			var lm := _std(Color(1, 0.97, 0.85))
			lm.emission_enabled = true
			lm.emission = Color(1, 0.95, 0.8)
			lm.emission_energy_multiplier = 2.0
			lamp.material_override = lm
			p.add_child(lamp)
			p.position = Vector3(side * (LANE_HALF + 0.55), 0, -i * 7.0)
			add_child(p)
			posts.append(p)
	# the big screen far up the lane where the Director watches
	var screen := MeshInstance3D.new()
	var scb := BoxMesh.new()
	scb.size = Vector3(14, 6, 0.3)
	screen.mesh = scb
	screen.position = Vector3(0, 5, -66)
	var sm := _std(Color(0.05, 0.08, 0.15))
	sm.emission_enabled = true
	sm.emission = Color(0.1, 0.18, 0.35)
	screen.material_override = sm
	add_child(screen)
	var title := Label3D.new()
	title.text = "REDLOCK"
	title.font = font
	title.font_size = 260
	title.pixel_size = 0.012
	title.modulate = Color(1.0, 0.35, 0.4)
	title.position = Vector3(0, 5.4, -65.8)
	add_child(title)
	# stars in the void around the pitch
	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(0.7, 0.85, 1.0)
	q.material = qm
	mm.mesh = q
	mm.instance_count = 260
	for i in mm.instance_count:
		var x := randf_range(8, 40) * (-1.0 if randf() < 0.5 else 1.0)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, randf_range(-20, 18), randf_range(-90, 10))))
	stars.multimesh = mm
	add_child(stars)

	# balls
	balls_mm = MultiMesh.new()
	balls_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bs := SphereMesh.new()
	bs.radius = 0.13
	bs.height = 0.26
	bs.radial_segments = 10
	bs.rings = 5
	var bm := _std(Color(1, 1, 1))
	bm.emission_enabled = true
	bm.emission = Color(0.9, 0.95, 1.0)
	bm.emission_energy_multiplier = 0.4
	bs.material = bm
	balls_mm.mesh = bs
	balls_mm.instance_count = MAX_BALLS
	balls_mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = balls_mm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)

	count_label = Label3D.new()
	count_label.font = font
	count_label.font_size = 80
	count_label.outline_size = 16
	count_label.pixel_size = 0.006
	count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	count_label.no_depth_test = true
	add_child(count_label)


func _std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


# ---------------------------------------------------------------- ui

func _label(txt: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.12))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	return l


func _panel_style(c: Color, r := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _button(txt: String, col: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.05, 0.08, 0.16))
	b.add_theme_color_override("font_hover_color", Color(0.05, 0.08, 0.16))
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.08, 0.16))
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _panel_style(col.lightened(0.15 if st == "hover" else 0.0), 22))
	b.custom_minimum_size = Vector2(240, 64)
	return b


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for s in ["left", "right"]:
		top.add_theme_constant_override("margin_" + s, 16)
	top.add_theme_constant_override("margin_top", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	hud_stage = _label("STAGE 1", 30)
	hud_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hud_stage)
	hud_coins = _label("0", 30, Color(1.0, 0.85, 0.4))
	row.add_child(hud_coins)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.add_theme_stylebox_override("background", _panel_style(Color(0.05, 0.08, 0.16, 0.8), 8))
	bar.add_theme_stylebox_override("fill", _panel_style(Color(0.55, 0.95, 0.85), 8))
	col.add_child(bar)
	bar_label = _label("", 20, Color(0.85, 0.9, 1.0))
	col.add_child(bar_label)

	director_box = PanelContainer.new()
	director_box.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.08, 0.16, 0.88)))
	director_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	director_box.offset_top = 120
	director_box.offset_left = 16
	director_box.offset_right = -16
	director_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(director_box)
	var dv := VBoxContainer.new()
	director_box.add_child(dv)
	dv.add_child(_label("DIRECTOR · BIG SCREEN", 18, Color(1.0, 0.4, 0.45)))
	director_text = _label("", 24)
	director_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(director_text)
	director_box.visible = false

	hint = _label("Drag to move · your squad kicks by itself", 22, Color(0.85, 0.9, 1.0))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_top = -60
	hint.offset_left = -260
	hint.offset_right = 260
	root.add_child(hint)

	spirit_btn = Button.new()
	spirit_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	spirit_btn.offset_left = -136
	spirit_btn.offset_top = -176
	spirit_btn.offset_right = -20
	spirit_btn.offset_bottom = -60
	spirit_btn.add_theme_stylebox_override("normal", _panel_style(Color(0.05, 0.08, 0.16, 0.85), 58))
	spirit_btn.add_theme_stylebox_override("hover", _panel_style(Color(0.05, 0.08, 0.16, 0.85), 58))
	spirit_btn.add_theme_stylebox_override("pressed", _panel_style(Color(0.2, 0.1, 0.2, 0.9), 58))
	spirit_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	spirit_btn.clip_contents = true
	root.add_child(spirit_btn)
	spirit_fill = ColorRect.new()
	spirit_fill.color = Color(1.0, 0.55, 0.72, 0.85)
	spirit_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spirit_btn.add_child(spirit_fill)
	var sl := _label("SPIRIT\nSHOT", 22)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.set_anchors_preset(Control.PRESET_FULL_RECT)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spirit_btn.add_child(sl)
	spirit_btn.pressed.connect(_use_spirit)

	cutin = Control.new()
	cutin.set_anchors_preset(Control.PRESET_FULL_RECT)
	cutin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cutin)
	var band := ColorRect.new()
	band.color = Color(1.0, 0.5, 0.68, 0.92)
	band.set_anchors_preset(Control.PRESET_CENTER)
	band.offset_left = -400
	band.offset_right = 400
	band.offset_top = -80
	band.offset_bottom = 80
	band.rotation_degrees = -8
	band.pivot_offset = Vector2(400, 80)
	cutin.add_child(band)
	cutin_label = _label("", 44)
	cutin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cutin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cutin_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.add_child(cutin_label)
	cutin.visible = false

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)


func _clear_overlay() -> void:
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = false


func _overlay_box(title: String, sub: String) -> VBoxContainer:
	_clear_overlay()
	overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.12, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.custom_minimum_size = Vector2(440, 0)
	center.add_child(v)
	var t1 := _label(title, 54, Color(1.0, 0.45, 0.5))
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
	_reset_run()
	var v := _overlay_box("REDLOCK\nSTRIKER", "Working title. Kick your way through the holo keepers.\nPick who leads the squad:")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var bh := _button("Hiyori", Color(1.0, 0.65, 0.72))
	bh.custom_minimum_size = Vector2(200, 64)
	bh.pressed.connect(func(): _start_game("hiyori"))
	row.add_child(bh)
	var bk := _button("Kasumi", Color(0.55, 0.95, 0.85))
	bk.custom_minimum_size = Vector2(200, 64)
	bk.pressed.connect(func(): _start_game("kasumi"))
	row.add_child(bk)
	if OS.has_feature("web"):
		var fs := _button("Full screen", Color(0.85, 0.88, 0.95))
		fs.pressed.connect(func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN))
		v.add_child(fs)


func _director(lines: Array) -> void:
	director_text.text = lines[randi() % lines.size()]
	director_box.visible = true
	_director_t = 3.6


# ---------------------------------------------------------------- run flow

func _reset_run() -> void:
	for s in squad:
		s.queue_free()
	squad.clear()
	shots = 1
	power = 1
	rate_mul = 1.0
	curve = false
	coins = 0
	kills = 0
	spirit = 0.0
	stage = 1
	leader_x = 0.0
	target_x = 0.0
	_clear_field()


func _clear_field() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for g in gates:
		if is_instance_valid(g):
			g.queue_free()
	gates.clear()
	boss = null
	b_pos.clear()
	b_vel.clear()
	b_dmg.clear()
	if spirit_ball:
		spirit_ball.queue_free()
		spirit_ball = null


func _start_game(pick: String) -> void:
	hero_pick = pick
	_reset_run()
	_add_member(pick)
	for i in 3:
		_add_member("trainee")
	_start_stage()


func _other_hero() -> String:
	return "kasumi" if hero_pick == "hiyori" else "hiyori"


func _start_stage() -> void:
	_clear_overlay()
	_clear_field()
	state = "play"
	t = 0.0
	run_speed = RUN
	stage_len = 38.0 + stage * 4.0
	timeline = _make_timeline()
	hud_stage.text = "STAGE %d" % stage
	hint.visible = stage == 1
	get_tree().create_timer(6.0, false).timeout.connect(func(): hint.visible = false)
	_director(DIRECTOR_START)


func _make_timeline() -> Array:
	var tl: Array = []
	var hp_scale := pow(1.7, stage - 1)
	var at := 2.0
	var n := 0
	while at < stage_len:
		n += 1
		var big := n > 3 and randf() < 0.1 + (stage - 1) * 0.1
		var rows := 2 + mini(stage - 1, 4) + (n % 2)
		var cols := 3 + mini(stage - 1, 3)
		tl.append({"t": at, "type": "group", "rows": rows, "cols": cols, "x": randf_range(-1.6, 1.6),
			"kind": "brute" if big else "grunt", "hp": hp_scale})
		if n % 2 == 0:
			tl.append({"t": at + 1.5, "type": "gates"})
		at += maxf(2.2, 3.6 - stage * 0.25)
	if stage == 1:
		tl.append({"t": 12.5, "type": "hero_gate"})
	tl.sort_custom(func(a, b): return a.t < b.t)
	return tl


func _add_member(look: String) -> void:
	if squad.size() >= MAX_SQUAD:
		return
	var s := Striker.new()
	add_child(s)
	s.setup(look)
	if look == "hiyori" and hero_model:
		s.use_model(hero_model, 1.55)
	s.fire_cd = randf() * 0.5
	s.position = Vector3(leader_x, 0, 0)
	if look != "trainee":
		var idx := 0 if look == hero_pick else 1
		squad.insert(mini(idx, squad.size()), s)
	else:
		squad.append(s)


func _slot(i: int) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	var a := i * 2.399963
	var r := 0.5 * sqrt(float(i))
	return Vector3(cos(a) * r, 0, sin(a) * r * 0.85 + 0.2)


func _squad_radius() -> float:
	return 0.5 * sqrt(float(maxi(1, squad.size() - 1))) + 0.3


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if state != "play" and state != "boss":
		return
	var w := get_viewport().get_visible_rect().size.x
	if event is InputEventScreenTouch:
		_drag = event.pressed
	elif event is InputEventScreenDrag:
		target_x += event.relative.x / w * LANE_HALF * 2.6
		hint.visible = false
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DisplayServer.is_touchscreen_available():
		target_x += event.relative.x / w * LANE_HALF * 2.6


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_debug_tick(delta)
	if _director_t > 0.0:
		_director_t -= delta
		if _director_t <= 0.0:
			director_box.visible = false
	if _cutin_t > 0.0:
		_cutin_t -= delta / maxf(Engine.time_scale, 0.01)
		if _cutin_t <= 0.0:
			cutin.visible = false
			Engine.time_scale = 1.0
			_launch_spirit_ball()
	spirit_fill.size = Vector2(spirit_btn.size.x, spirit_btn.size.y * spirit)
	spirit_fill.position = Vector2(0, spirit_btn.size.y * (1.0 - spirit))
	spirit_btn.disabled = spirit < 1.0 or not (state == "play" or state == "boss")
	spirit_btn.modulate = Color(1, 1, 1, 1.0 if spirit >= 1.0 else 0.75)
	hud_coins.text = "%d KO" % kills

	if state != "play" and state != "boss":
		_update_squad(delta)
		return
	t += delta
	var k := Input.get_axis("ui_left", "ui_right")
	target_x += k * 7.0 * delta
	var lim := maxf(0.2, LANE_HALF - 0.35 - minf(_squad_radius(), 2.0))
	target_x = clampf(target_x, -lim, lim)
	leader_x = lerpf(leader_x, target_x, 1.0 - exp(-14.0 * delta))

	scroll += run_speed * delta
	lane_mat.set_shader_parameter("scroll", scroll)
	for p in posts:
		p.position.z += run_speed * delta
		if p.position.z > 10.0:
			p.position.z -= 84.0

	while not timeline.is_empty() and timeline[0].t <= t:
		_spawn(timeline.pop_front())
	if state == "play":
		bar.value = clampf(t / stage_len, 0, 1) * 100.0
		bar_label.text = ""
		if t >= stage_len and timeline.is_empty() and enemies.is_empty():
			_spawn_boss()
	elif boss:
		bar.value = float(boss.hp) / boss.max_hp * 100.0
		bar_label.text = "GIANT HOLO KEEPER  %d" % maxi(0, boss.hp)

	enemies = enemies.filter(func(e): return is_instance_valid(e) and not e.dead)
	_update_squad(delta)
	_fire(delta)
	_move_balls(delta)
	_move_enemies(delta)
	_move_gates(delta)
	_move_spirit(delta)

	cam.position.x = lerpf(cam.position.x, leader_x * 0.35, 1.0 - exp(-4.0 * delta))
	if shake > 0.0:
		shake -= delta
		cam.h_offset = randf_range(-0.12, 0.12)
		cam.v_offset = randf_range(-0.08, 0.08)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func _update_squad(delta: float) -> void:
	for i in squad.size():
		var s := squad[i]
		var goal := Vector3(leader_x, 0, 0) + _slot(i)
		s.position = s.position.lerp(goal, 1.0 - exp(-10.0 * delta))
	count_label.visible = not squad.is_empty() and state != "title"
	count_label.text = str(squad.size())
	count_label.position = Vector3(leader_x, 2.3, 0.2)


func _fire(delta: float) -> void:
	for s in squad:
		s.fire_cd -= delta
		if s.fire_cd > 0.0:
			continue
		var r := (HERO_RATE if s.hero else TRAINEE_RATE) * rate_mul
		s.fire_cd = 1.0 / r
		s.kick()
		var dmg := power * (2 if s.hero else 1)
		var n := shots
		for j in n:
			if b_pos.size() >= MAX_BALLS:
				return
			var ang := 0.0 if n == 1 else lerpf(-0.09, 0.09, float(j) / (n - 1)) * (1.0 + n * 0.15)
			b_pos.append(s.position + Vector3(0.1, 0.25, -0.35))
			b_vel.append(Vector3(sin(ang) * BALL_SPEED, 0, -cos(ang) * BALL_SPEED))
			b_dmg.append(dmg)


func _move_balls(delta: float) -> void:
	# bucket enemies by metre of depth so each ball only checks its neighbours
	var buckets := {}
	for e in enemies:
		var key := int(floor(e.position.z))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(e)
	var i := 0
	while i < b_pos.size():
		var p := b_pos[i]
		var v := b_vel[i]
		if curve and not enemies.is_empty():
			var best: HoloKeeper = null
			var bd := 6.0
			for key in [int(floor(p.z)) - 3, int(floor(p.z)) - 4, int(floor(p.z)) - 5]:
				if buckets.has(key):
					for e in buckets[key]:
						var d := absf(e.position.x - p.x)
						if d < bd:
							bd = d
							best = e
			if best:
				v.x = move_toward(v.x, clampf((best.position.x - p.x) * 6.0, -9.0, 9.0), 40.0 * delta)
		p += v * delta
		var gone := p.z < BALL_END_Z or absf(p.x) > LANE_HALF + 0.4
		if not gone:
			var key := int(floor(p.z))
			for kk in [key - 1, key, key + 1]:
				if gone or not buckets.has(kk):
					continue
				for e in buckets[kk]:
					if e.dead:
						continue
					var rr: float = e.radius + 0.13
					if absf(e.position.x - p.x) < rr and absf(e.position.z - p.z) < rr:
						if e.hit(b_dmg[i]):
							_kill(e)
						elif e == boss:
							_pop_text("%d" % b_dmg[i], p + Vector3(0, 1.5, 0), Color(1, 0.9, 0.5), 0.5)
						gone = true
						break
		if not gone:
			for g in gates:
				if g.done:
					continue
				if absf(g.position.x - p.x) < g.half.x and absf(g.position.z - p.z) < g.half.y:
					if g.hit(b_dmg[i]):
						_claim(g)
					gone = true
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
			b_vel[i] = v
			i += 1
	balls_mm.visible_instance_count = b_pos.size()
	for j in b_pos.size():
		balls_mm.set_instance_transform(j, Transform3D(Basis(), b_pos[j]))


func _move_enemies(delta: float) -> void:
	var i := 0
	while i < enemies.size():
		var e := enemies[i]
		if e.dead:
			enemies.remove_at(i)
			continue
		var step := e.speed * (0.55 if e == boss else 1.0) + (run_speed * 0.5)
		e.position.z += step * delta
		# steer slightly toward the squad so you can't just sidestep a whole wave
		if e != boss and e.position.z > -12.0:
			e.position.x = move_toward(e.position.x, leader_x, 0.5 * delta)
		if e.position.z > -2.2:
			for s in squad:
				var d := Vector2(s.position.x - e.position.x, s.position.z - e.position.z).length()
				if d < e.radius + 0.25:
					_lose_member(s)
					if e != boss:
						e.dead = true
						_burst(e.position, HoloKeeper.KINDS[e.kind].tint, 10)
						e.queue_free()
					break
			if squad.is_empty():
				_game_over()
				return
		if e.position.z > 4.0:
			e.queue_free()
			enemies.remove_at(i)
			continue
		i += 1


func _move_gates(delta: float) -> void:
	var i := 0
	while i < gates.size():
		var g := gates[i]
		g.position.z += run_speed * delta
		if g.done or g.position.z > 3.0:
			if not g.done:
				g.queue_free()
			gates.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- spawning

func _spawn(ev: Dictionary) -> void:
	match ev.type:
		"group":
			var sp := 0.72 if ev.kind == "grunt" else 1.0
			for r in ev.rows:
				for c in ev.cols:
					var x: float = ev.x + (c - (ev.cols - 1) * 0.5) * sp + randf_range(-0.1, 0.1)
					if absf(x) > LANE_HALF - 0.4:
						continue
					var kind: String = ev.kind
					if kind == "brute" and (r + c) % 3 != 0:
						kind = "grunt"
					_spawn_enemy(kind, Vector3(x, 0, SPAWN_Z - r * sp), ev.hp)
		"gates":
			var opts := ["squad", "squad", "shots", "power", "rate", "curve", "spirit"]
			if shots >= 4:
				opts.erase("shots")
			if curve:
				opts.erase("curve")
			opts.shuffle()
			var a: String = opts[0]
			var b: String = opts[1]
			if a == b:
				b = "power"
			_spawn_gate(a, -1.0)
			_spawn_gate(b, 1.0)
		"hero_gate":
			var g := RewardGate.new()
			add_child(g)
			g.setup("hero", 30, 1, Striker.LOOKS[_other_hero()].name)
			g.position = Vector3(-(LANE_HALF - 0.95) if randf() < 0.5 else (LANE_HALF - 0.95), 0, SPAWN_Z)
			gates.append(g)


func _spawn_enemy(kind: String, pos: Vector3, hp_scale: float) -> HoloKeeper:
	var e := HoloKeeper.new()
	add_child(e)
	e.setup(kind, hp_scale)
	e.position = pos
	enemies.append(e)
	return e


func _spawn_gate(kind: String, side: float) -> void:
	var g := RewardGate.new()
	add_child(g)
	var need := int((10 + stage * 8) * (1.0 + squad.size() * 0.08) * sqrt(float(power * shots)) * (1.5 if kind in ["shots", "curve"] else 1.0))
	var amt := 2 + stage + randi() % 3
	g.setup(kind, need, amt)
	g.position = Vector3(side * (LANE_HALF - 0.95), 0, SPAWN_Z)
	gates.append(g)


func _spawn_boss() -> void:
	state = "boss"
	run_speed = 0.6
	boss = _spawn_enemy("boss", Vector3(0, 0, -38), pow(1.8, stage - 1) * (1.0 + squad.size() * 0.1) * (0.6 + power * 0.4))
	_director(DIRECTOR_BOSS)
	shake = 0.4
	# a few escorts so it isn't a free hit
	for i in 6:
		_spawn_enemy("grunt", Vector3(randf_range(-2.5, 2.5), 0, -42 - i), 1.0 + stage * 0.5)


# ---------------------------------------------------------------- events

func _kill(e: HoloKeeper) -> void:
	kills += 1
	coins += e.coins
	spirit = minf(1.0, spirit + (0.012 if e.kind == "grunt" else 0.04))
	_burst(e.position, HoloKeeper.KINDS[e.kind].tint, 8 if e.kind == "grunt" else 16)
	e.queue_free()
	if e == boss:
		boss = null
		shake = 0.5
		_burst(e.position, HoloKeeper.KINDS.boss.tint, 60)
		for x in enemies:
			if is_instance_valid(x) and not x.dead:
				x.dead = true
				x.queue_free()
		enemies.clear()
		_stage_clear()


func _claim(g: RewardGate) -> void:
	var c: Color = RewardGate.REWARDS[g.reward].color
	_burst(g.position + Vector3(0, 0.8, 0), c, 24)
	match g.reward:
		"squad":
			for i in g.amount:
				_add_member("trainee")
		"shots":
			shots = mini(5, shots + 1)
		"power":
			power += 1
		"rate":
			rate_mul *= 1.25
		"curve":
			curve = true
		"spirit":
			spirit = minf(1.0, spirit + 0.5)
		"hero":
			_add_member(_other_hero())
			_cut_in("%s JOINS THE SQUAD" % Striker.LOOKS[_other_hero()].name.to_upper(), 0.9, false)
	var txt: String = "+%d" % g.amount if g.reward == "squad" else RewardGate.REWARDS[g.reward].text.split(" ")[0]
	if g.reward != "hero":
		_pop_text(txt, Vector3(leader_x, 2.6, -0.5), c, 0.9)
	g.queue_free()


func _lose_member(s: Striker) -> void:
	_burst(s.position + Vector3(0, 0.6, 0), Color(1, 0.4, 0.4), 6)
	squad.erase(s)
	s.queue_free()
	shake = 0.15


func _game_over() -> void:
	state = "over"
	var v := _overlay_box("SQUAD DOWN", "Stage %d · %d holo keepers kicked out" % [stage, kills])
	var b := _button("Try again", Color(1.0, 0.65, 0.72))
	b.pressed.connect(func(): _start_game(hero_pick))
	v.add_child(b)
	var m := _button("Change striker", Color(0.85, 0.88, 0.95))
	m.pressed.connect(_show_title)
	v.add_child(m)


func _stage_clear() -> void:
	state = "clear"
	var v := _overlay_box("STAGE %d CLEAR" % stage, "The giant keeper is down. Your squad of %d moves deeper into Redlock." % squad.size())
	var b := _button("Next stage", Color(0.55, 0.95, 0.85))
	b.pressed.connect(func():
		stage += 1
		_start_stage())
	v.add_child(b)


func _use_spirit() -> void:
	if spirit < 1.0 or squad.is_empty():
		return
	spirit = 0.0
	var lead := squad[0]
	var who: String = Striker.LOOKS[lead.look].name
	var move := "PEACH COMET" if lead.look == "hiyori" else ("TIDE BREAKER" if lead.look == "kasumi" else "SPIRIT SHOT")
	_cut_in("%s\n%s" % [who.to_upper(), move], 0.9, true)


func _cut_in(text: String, secs: float, launch: bool) -> void:
	cutin_label.text = text
	cutin.visible = true
	_cutin_t = secs if launch else 0.0
	if launch:
		Engine.time_scale = 0.2
	else:
		var tw := create_tween()
		tw.tween_interval(secs)
		tw.tween_callback(func(): cutin.visible = false)


func _launch_spirit_ball() -> void:
	if spirit_ball:
		spirit_ball.queue_free()
	spirit_ball = Node3D.new()
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.7
	s.height = 1.4
	m.mesh = s
	var mat := _std(Color(1.0, 0.7, 0.8))
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.65)
	mat.emission_energy_multiplier = 2.5
	m.material_override = mat
	spirit_ball.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.7)
	l.light_energy = 3.0
	l.omni_range = 6.0
	spirit_ball.add_child(l)
	spirit_ball.position = Vector3(leader_x, 0.75, -0.8)
	add_child(spirit_ball)
	shake = 0.3


func _move_spirit(delta: float) -> void:
	if spirit_ball == null:
		return
	spirit_ball.position.z -= 20.0 * delta
	spirit_ball.rotate_x(-12.0 * delta)
	if randf() < 0.6:
		_burst(spirit_ball.position, Color(1.0, 0.55, 0.72), 2)
	for e in enemies.duplicate():
		if e.dead:
			continue
		if absf(e.position.x - spirit_ball.position.x) < 1.6 + e.radius and absf(e.position.z - spirit_ball.position.z) < 1.0 + e.radius:
			if e == boss:
				var dmg := int(ceil(boss.max_hp * 0.3))
				_pop_text("%d" % dmg, boss.position + Vector3(0, 4, 0), Color(1, 0.6, 0.8), 1.2)
				shake = 0.4
				if boss.hit(dmg):
					_kill(boss)
				else:
					spirit_ball.queue_free()
					spirit_ball = null
					return
			elif e.hit(9999):
				_kill(e)
	for g in gates:
		if not g.done and absf(g.position.x - spirit_ball.position.x) < 1.6 and absf(g.position.z - spirit_ball.position.z) < 1.0:
			if g.hit(9999):
				_claim(g)
	if spirit_ball and spirit_ball.position.z < BALL_END_Z:
		spirit_ball.queue_free()
		spirit_ball = null


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
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := BoxMesh.new()
	q.size = Vector3(0.09, 0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	q.material = m
	p.mesh = q
	p.position = pos + Vector3(0, 0.6, 0)
	add_child(p)
	get_tree().create_timer(0.8, false).timeout.connect(p.queue_free)


func _pop_text(txt: String, pos: Vector3, c: Color, secs: float) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font = font
	l.font_size = 72
	l.outline_size = 14
	l.pixel_size = 0.006
	l.modulate = c
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	add_child(l)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(l, "position:y", pos.y + 1.0, secs)
	tw.tween_property(l, "modulate:a", 0.0, secs).set_delay(secs * 0.4)
	tw.chain().tween_callback(l.queue_free)
