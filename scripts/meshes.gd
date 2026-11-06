class_name Meshes
extends RefCounted
## Builds single merged meshes (one draw call each) out of simple shapes, with a vertex colour per
## part. The crowd and the holo keeper stream are drawn as MultiMeshes of these.

## parts: Array of [PrimitiveMesh, Transform3D, Color]
static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var m: PrimitiveMesh = p[0]
		var xf: Transform3D = p[1]
		var c: Color = p[2]
		var arr := m.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		for k in v.size():
			verts.append(xf * v[k])
			norms.append((xf.basis * n[k]).normalized())
			cols.append(c)
		for k in ii.size():
			idx.append(base + ii[k])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func sphere(r: float, seg := 10) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c


static func at(pos: Vector3, rot_deg := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * PI / 180.0), pos)


## A Redlock trainee seen from behind: suit, trim, head, hair, legs, boots. suit/trim change with
## the squad's boot tier.
static func trainee(suit: Color, trim: Color, hair := Color(0.16, 0.12, 0.1)) -> ArrayMesh:
	var skin := Color(1.0, 0.86, 0.76)
	var boot := Color(0.06, 0.06, 0.07)
	return merge([
		[box(0.3, 0.38, 0.19), at(Vector3(0, 0.74, 0)), suit],
		[box(0.32, 0.06, 0.21), at(Vector3(0, 0.92, 0)), trim],
		[sphere(0.16), at(Vector3(0, 1.13, 0)), skin],
		[sphere(0.175), at(Vector3(0, 1.16, 0.035)), hair],
		[box(0.11, 0.46, 0.12), at(Vector3(-0.08, 0.32, 0)), suit],
		[box(0.11, 0.46, 0.12), at(Vector3(0.08, 0.32, 0)), suit],
		[box(0.12, 0.08, 0.19), at(Vector3(-0.08, 0.05, -0.03)), boot],
		[box(0.12, 0.08, 0.19), at(Vector3(0.08, 0.05, -0.03)), boot],
		[box(0.08, 0.36, 0.09), at(Vector3(-0.2, 0.74, 0), Vector3(0, 0, -8)), suit],
		[box(0.08, 0.36, 0.09), at(Vector3(0.2, 0.74, 0), Vector3(0, 0, 8)), suit],
	])


## A holographic keeper: arms spread wide, big gloves. Coloured white; the shader tints it.
static func keeper() -> ArrayMesh:
	var w := Color(1, 1, 1)
	return merge([
		[capsule(0.2, 0.62), at(Vector3(0, 0.82, 0)), w],
		[sphere(0.16, 12), at(Vector3(0, 1.3, 0)), w],
		[capsule(0.07, 0.42), at(Vector3(-0.37, 1.14, 0), Vector3(0, 0, 55)), w],
		[capsule(0.07, 0.42), at(Vector3(0.37, 1.14, 0), Vector3(0, 0, -55)), w],
		[box(0.17, 0.2, 0.09), at(Vector3(-0.56, 1.28, 0)), w],
		[box(0.17, 0.2, 0.09), at(Vector3(0.56, 1.28, 0)), w],
		[capsule(0.075, 0.44), at(Vector3(-0.1, 0.28, 0)), w],
		[capsule(0.075, 0.44), at(Vector3(0.1, 0.28, 0)), w],
	])
