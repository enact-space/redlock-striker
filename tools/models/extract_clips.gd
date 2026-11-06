extends SceneTree
## Copies football clips from the rigged Medium Body (same skeleton as Hiyori and Kasumi) into an
## AnimationLibrary the game adds to the characters' AnimationPlayer. Root travel is removed so the
## kick plays on the spot. Run (body GLB copied into the project first, e.g. res://_tmp/body.glb):
##   godot --headless -s res://tools/models/extract_clips.gd -- res://_tmp/body.glb kick kick_running pass

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var root: Node = load(a[0]).instantiate()
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := AnimationLibrary.new()
	for clip in a.slice(1):
		var anim: Animation = ap.get_animation(clip).duplicate(true)
		for tr in anim.get_track_count():
			if anim.track_get_type(tr) != Animation.TYPE_POSITION_3D:
				continue
			if not str(anim.track_get_path(tr)).ends_with(":root"):
				continue
			var first: Vector3 = anim.track_get_key_value(tr, 0)
			for k in anim.track_get_key_count(tr):
				var v: Vector3 = anim.track_get_key_value(tr, k)
				anim.track_set_key_value(tr, k, Vector3(first.x, v.y, first.z))
		anim.loop_mode = Animation.LOOP_NONE
		lib.add_animation(clip, anim)
		print("CLIP %s %.2f s, %d tracks" % [clip, anim.length, anim.get_track_count()])
	ResourceSaver.save(lib, "res://assets/characters/football_clips.res")
	quit()
