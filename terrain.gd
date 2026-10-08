extends Node3D

@export var terrain_size: float = 60.0
@export var resolution: int = 129
@export var brush_radius: float = 3.0
@export var brush_strength: float = 0.75

var array_mesh: ArrayMesh
var normals: PackedVector3Array
var uvs: PackedVector2Array
var indices: PackedInt32Array

var vertices: PackedVector3Array
var mesh_instance: MeshInstance3D
var terrain_material: StandardMaterial3D

var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

enum SurfaceType {
	ROUGH,
	FAIRWAY,
	GREEN
}

var surface_types: PackedFloat32Array
var colors: PackedColorArray


func _ready() -> void:
	generate_terrain()


func generate_terrain() -> void:
	vertices = PackedVector3Array()
	surface_types = PackedFloat32Array()
	colors = PackedColorArray()

	normals = PackedVector3Array()
	uvs = PackedVector2Array()
	indices = PackedInt32Array()

	var spacing := terrain_size / float(resolution - 1)
	var half_size := terrain_size / 2.0

	# Create vertices.
	for z in range(resolution):
		for x in range(resolution):
			var x_pos := -half_size + x * spacing
			var z_pos := -half_size + z * spacing

			vertices.append(Vector3(x_pos, 0.0, z_pos))
			normals.append(Vector3.UP)
			uvs.append(Vector2(
				float(x) / float(resolution - 1),
				float(z) / float(resolution - 1)
			))
			surface_types.append(float(SurfaceType.ROUGH))
			colors.append(get_surface_color(SurfaceType.ROUGH))

	# Create two triangles for every grid square.
	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var top_left := z * resolution + x
			var top_right := top_left + 1
			var bottom_left := (z + 1) * resolution + x
			var bottom_right := bottom_left + 1

			indices.append(top_left)
			indices.append(top_right)
			indices.append(bottom_left)

			indices.append(top_right)
			indices.append(bottom_right)
			indices.append(bottom_left)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors

	array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	
	terrain_material = StandardMaterial3D.new()

	terrain_material.albedo_color = Color.WHITE
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.95

	array_mesh.surface_set_material(
		0,
		terrain_material
	)
	
	add_child(mesh_instance)
	
	collision_body = StaticBody3D.new()
	collision_shape = CollisionShape3D.new()

	collision_body.add_child(collision_shape)
	add_child(collision_body)

	update_collision()
	
func get_surface_color(surface: SurfaceType) -> Color:
	match surface:
		SurfaceType.ROUGH:
			return Color(0.18, 0.32, 0.12)

		SurfaceType.FAIRWAY:
			return Color(0.28, 0.48, 0.18)

		SurfaceType.GREEN:
			return Color(0.38, 0.58, 0.24)

	return Color.WHITE
	
func paint_surface(
	world_position: Vector3,
	radius: float,
	surface: SurfaceType
) -> void:

	var local_position := to_local(world_position)

	for i in range(vertices.size()):
		var vertex := vertices[i]

		var distance := Vector2(
			vertex.x - local_position.x,
			vertex.z - local_position.z
		).length()

		if distance <= radius:
			surface_types[i] = float(surface)
			colors[i] = get_surface_color(surface)

	update_mesh()
	
func sculpt(
	world_position: Vector3,
	radius: float,
	strength: float,
	delta: float
) -> void:

	var local_position := to_local(world_position)

	for i in range(vertices.size()):
		var vertex := vertices[i]

		var distance := Vector2(
			vertex.x - local_position.x,
			vertex.z - local_position.z
		).length()

		if distance <= radius:
			var normalized_distance := distance / radius

			# Soft falloff toward the edge of the brush.
			var inner_radius := 0.35

			var falloff: float

			if normalized_distance <= inner_radius:
				falloff = 1.0
			else:
				var edge_distance := (
					normalized_distance - inner_radius
				) / (1.0 - inner_radius)

				falloff = smoothstep(
					1.0,
					0.0,
					edge_distance
				)

			vertex.y += strength * falloff * delta
			vertices[i] = vertex

	update_mesh()
	
func smooth_terrain(
	world_position: Vector3,
	radius: float,
	strength: float,
	delta: float
) -> void:

	var local_position := to_local(world_position)

	# Copy the current heights so changing one vertex doesn't
	# influence its neighbors during this same pass.
	var old_vertices := vertices.duplicate()

	for z in range(1, resolution - 1):
		for x in range(1, resolution - 1):
			var index := z * resolution + x
			var vertex := old_vertices[index]

			var distance := Vector2(
				vertex.x - local_position.x,
				vertex.z - local_position.z
			).length()

			if distance <= radius:
				var normalized_distance := distance / radius

				var falloff := smoothstep(
					1.0,
					0.0,
					normalized_distance
				)

				# Average the surrounding 3x3 area.
				var average_height := 0.0

				for neighbor_z in range(-1, 2):
					for neighbor_x in range(-1, 2):
						var neighbor_index := (
							(z + neighbor_z) * resolution
							+ (x + neighbor_x)
						)

						average_height += old_vertices[neighbor_index].y

				average_height /= 9.0

				vertices[index].y = lerp(
					vertex.y,
					average_height,
					strength * falloff * delta
				)

	update_mesh()
	
func flatten_terrain(
	world_position: Vector3,
	target_height: float,
	radius: float,
	strength: float,
	delta: float
) -> void:

	var local_position := to_local(world_position)

	for i in range(vertices.size()):
		var vertex := vertices[i]

		var distance := Vector2(
			vertex.x - local_position.x,
			vertex.z - local_position.z
		).length()

		if distance <= radius:
			var normalized_distance := distance / radius

			var inner_radius := 0.35
			var falloff: float

			if normalized_distance <= inner_radius:
				falloff = 1.0
			else:
				var edge_distance := (
					normalized_distance - inner_radius
				) / (1.0 - inner_radius)

				falloff = smoothstep(
					1.0,
					0.0,
					edge_distance
				)

			vertex.y = move_toward(
				vertex.y,
				target_height,
				strength * falloff * delta
			)

			vertices[i] = vertex

	update_mesh()
	
func slope_terrain(
	world_position: Vector3,
	point_a_world: Vector3,
	point_b_world: Vector3,
	radius: float,
	strength: float,
	delta: float
) -> void:

	var brush_position := to_local(world_position)
	var point_a := to_local(point_a_world)
	var point_b := to_local(point_b_world)

	var a_2d := Vector2(point_a.x, point_a.z)
	var b_2d := Vector2(point_b.x, point_b.z)

	var slope_vector := b_2d - a_2d
	var slope_length_squared := slope_vector.length_squared()

	if slope_length_squared < 0.001:
		return

	for i in range(vertices.size()):
		var vertex := vertices[i]

		var distance := Vector2(
			vertex.x - brush_position.x,
			vertex.z - brush_position.z
		).length()

		if distance <= radius:
			var vertex_2d := Vector2(vertex.x, vertex.z)

			# Find where this vertex lies along the A -> B direction.
			var t := (
				(vertex_2d - a_2d).dot(slope_vector)
				/ slope_length_squared
			)

			# For now, don't extend beyond A or B.
			t = clamp(t, 0.0, 1.0)

			var target_height: float = lerpf(
				point_a.y,
				point_b.y,
				t
			)

			var normalized_distance := distance / radius

			var falloff := smoothstep(
				1.0,
				0.0,
				normalized_distance
			)

			vertex.y = move_toward(
				vertex.y,
				target_height,
				strength * falloff * delta
			)

			vertices[i] = vertex

	update_mesh()
	
func update_mesh() -> void:
	recalculate_normals()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors

	array_mesh.clear_surfaces()

	array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	array_mesh.surface_set_material(0, terrain_material)
	
	update_collision()
	
func recalculate_normals() -> void:
	normals = PackedVector3Array()
	normals.resize(vertices.size())

	# Start every normal at zero.
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO

	# Calculate each triangle's normal and add it to its vertices.
	for i in range(0, indices.size(), 3):
		var i0 := indices[i]
		var i1 := indices[i + 1]
		var i2 := indices[i + 2]

		var v0 := vertices[i0]
		var v1 := vertices[i1]
		var v2 := vertices[i2]

		var edge1 := v1 - v0
		var edge2 := v2 - v0

		var face_normal := edge2.cross(edge1).normalized()

		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal

	# Average the surrounding triangle normals.
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()

func update_collision() -> void:
	var faces := PackedVector3Array()

	for i in range(0, indices.size(), 3):
		faces.append(vertices[indices[i]])
		faces.append(vertices[indices[i + 1]])
		faces.append(vertices[indices[i + 2]])

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	collision_shape.shape = shape
