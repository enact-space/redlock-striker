extends SceneTree
## Bakes light, unskinned "clone" meshes of a character for the crowd: poses the real model, applies
## the skinning on the CPU, simplifies each surface with Godot's LOD generator plus vertex
## clustering and saves ArrayMeshes (1 m tall, facing -Z, feet at 0) that keep the original
## materials. With a clip and times it bakes one mesh per time (a flipbook the crowd cycles through),
## all sharing the first pose's scale and centre so the feet stay put.
## Needs a real renderer (mesh arrays are empty under --headless):
##   DISPLAY=:99 godot --rendering-driver opengl3 -s res://tools/models/bake_clone.gd -- hiyori 3000
##   DISPLAY=:99 godot --rendering-driver opengl3 -s res://tools/models/bake_clone.gd -- hiyori 1500 kick 0.15,0.3,0.4,0.48,0.6,0.75
## Writes res://assets/characters/<who>_clone.res, or <who>_<clip>_<n>.res for each time.

var who := "hiyori"
var budget := 3000
var clip := ""
var times: Array = []


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		who = a[0]
	if a.size() > 1:
		budget = int(a[1])
	if a.size() > 3:
		clip = a[2]
		for x in a[3].split(","):
			times.append(float(x))
	call_deferred("_run")


func _run() -> void:
	var root: Node3D = load("res://assets/characters/%s.glb" % who).instantiate()
	get_root().add_child(root)
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var anim_name := ""
	if clip == "":
		times = [0.4]
		for n in ap.get_animation_list():
			if n.ends_with("idle_f_loop") or n == "idle_f":
				anim_name = n
				break
	else:
		ap.add_animation_library("fb", load("res://assets/characters/football_clips.res"))
		anim_name = "fb/" + clip
	var fix := Transform3D()
	for ti in times.size():
		if anim_name != "":
			ap.play(anim_name)
			ap.seek(times[ti], true)
			ap.pause()
		await process_frame
		await process_frame
		var got := _pose(root)
		if ti == 0:
			fix = _normaliser(got[0])
		var path := "res://assets/characters/%s_clone.res" % who
		if clip != "":
			path = "res://assets/characters/%s_%s_%d.res" % [who, clip, ti]
		_build(got[0], got[1], fix, path)
	quit()


## Skins every surface of the posed model into root space. Returns [parts, total triangles].
func _pose(root: Node3D) -> Array:
	var parts := []   # [arrays, material]
	var total := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var skel := m.get_node_or_null(m.skeleton) as Skeleton3D
		var skin := m.skin
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var out_v := PackedVector3Array()
			var out_n := PackedVector3Array()
			out_v.resize(v.size())
			out_n.resize(v.size())
			if skel and skin and arr[Mesh.ARRAY_BONES] != null:
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				var per := bones.size() / v.size()
				var mats: Array[Transform3D] = []
				var to_root := root.global_transform.affine_inverse() * skel.global_transform
				for i in skin.get_bind_count():
					var b := skin.get_bind_bone(i)
					if b < 0:
						b = skel.find_bone(skin.get_bind_name(i))
					mats.append(to_root * skel.get_bone_global_pose(b) * skin.get_bind_pose(i))
				for k in v.size():
					var p := Vector3.ZERO
					var q := Vector3.ZERO
					var wsum := 0.0
					for j in per:
						var w := weights[k * per + j]
						if w <= 0.0:
							continue
						var t: Transform3D = mats[bones[k * per + j]]
						p += (t * v[k]) * w
						q += (t.basis * nrm[k]) * w
						wsum += w
					out_v[k] = p / maxf(wsum, 0.0001)
					out_n[k] = q.normalized()
			else:
				var t := root.global_transform.affine_inverse() * m.global_transform
				for k in v.size():
					out_v[k] = t * v[k]
					out_n[k] = (t.basis * nrm[k]).normalized()
			var keep := []
			keep.resize(Mesh.ARRAY_MAX)
			keep[Mesh.ARRAY_VERTEX] = out_v
			keep[Mesh.ARRAY_NORMAL] = out_n
			keep[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
			keep[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
			var mat := m.get_active_material(s)
			parts.append([keep, mat])
			total += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return [parts, total]


## 1 m tall, feet on 0, centred, facing -Z (the models face +Z).
func _normaliser(parts: Array) -> Transform3D:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in parts:
		for x in p[0][Mesh.ARRAY_VERTEX]:
			lo = lo.min(x)
			hi = hi.max(x)
	var s := 1.0 / (hi.y - lo.y)
	return Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis(), -Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5))


func _build(parts: Array, total: int, fix: Transform3D, path: String) -> void:
	var out := ArrayMesh.new()
	var kept := 0
	for p in parts:
		var arrs: Array = p[0]
		var vv: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
		for k in vv.size():
			vv[k] = fix * vv[k]
			nn[k] = (fix.basis * nn[k]).normalized()
		arrs[Mesh.ARRAY_VERTEX] = vv
		arrs[Mesh.ARRAY_NORMAL] = nn
		var tris := (arrs[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var want := maxi(60, int(budget * float(tris) / total))
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrs)
		im.generate_lods(25.0, 60.0, [])
		var best: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
		for l in im.get_surface_lod_count(0):
			var ix := im.get_surface_lod_indices(0, l)
			if ix.size() / 3 >= want or ix.size() < best.size() and best.size() / 3 > want * 2:
				if ix.size() < best.size():
					best = ix
		arrs[Mesh.ARRAY_INDEX] = best
		# the LOD generator stops early on these (UV seams), so finish with vertex clustering
		var cell := 0.012
		while (arrs[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 > want * 1.3 and cell < 0.2:
			arrs = _cluster(p[0], best, cell)
			cell *= 1.35
		kept += (arrs[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		out.surface_set_material(out.get_surface_count() - 1, p[1])
	ResourceSaver.save(out, path)
	print("CLONE %s: %d -> %d triangles, saved %s" % [who, total, kept, path])


## Merge every vertex inside the same cube of side `cell` into one, drop collapsed triangles.
func _cluster(arrs: Array, idx: PackedInt32Array, cell: float) -> Array:
	var v: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var map := {}
	var remap := PackedInt32Array()
	remap.resize(v.size())
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var cnt := PackedFloat32Array()
	for k in v.size():
		var key := Vector3i((v[k] / cell).floor())
		if map.has(key):
			var j: int = map[key]
			remap[k] = j
			nv[j] += v[k]
			nn[j] += n[k]
			cnt[j] += 1.0
		else:
			map[key] = nv.size()
			remap[k] = nv.size()
			nv.append(v[k])
			nn.append(n[k])
			nuv.append(uv[k] if uv.size() > k else Vector2.ZERO)
			cnt.append(1.0)
	for j in nv.size():
		nv[j] /= cnt[j]
		nn[j] = nn[j].normalized()
	var ni := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var a := remap[idx[t]]
		var b := remap[idx[t + 1]]
		var c := remap[idx[t + 2]]
		if a != b and b != c and a != c:
			ni.append(a)
			ni.append(b)
			ni.append(c)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TEX_UV] = nuv
	out[Mesh.ARRAY_INDEX] = ni
	return out
