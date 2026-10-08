extends Node

@onready var camera: Camera3D = $"../CameraRig/Camera3D"
@onready var brush_cursor: MeshInstance3D = $"../BrushCursor"
@onready var terrain = $"../Terrain"
@onready var slope_marker_a: MeshInstance3D = $"../SlopeMarkerA"
@onready var slope_marker_b: MeshInstance3D = $"../SlopeMarkerB"

enum Tool {
	RAISE,
	LOWER,
	SMOOTH,
	FLATTEN,
	SLOPE
}

enum EditMode {
	SCULPT,
	PAINT
}

var edit_mode: EditMode = EditMode.SCULPT
var paint_surface_type: int = 0

@export var current_tool: Tool = Tool.RAISE

@export_group("Raise")
@export var raise_radius: float = 3.0
@export var raise_strength: float = 0.75

@export_group("Lower")
@export var lower_radius: float = 3.0
@export var lower_strength: float = 0.75

@export_group("Smooth")
@export var smooth_radius: float = 3.0
@export var smooth_strength: float = 4.0

@export_group("Flatten")
@export var flatten_radius: float = 3.0
@export var flatten_strength: float = 1.5

@export_group("Slope")
@export var slope_radius: float = 4.0
@export var slope_strength: float = 1.5

var slope_point_a: Vector3
var slope_point_b: Vector3

var slope_has_a: bool = false
var slope_has_b: bool = false

var slope_can_paint: bool = false

var brush_position: Vector3
var flatten_target_height: float = 0.0
var was_left_pressed: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_G:
			edit_mode = EditMode.PAINT
			paint_surface_type = terrain.SurfaceType.GREEN

		elif event.keycode == KEY_F:
			edit_mode = EditMode.PAINT
			paint_surface_type = terrain.SurfaceType.FAIRWAY

		elif event.keycode == KEY_T:
			edit_mode = EditMode.PAINT
			paint_surface_type = terrain.SurfaceType.ROUGH
			
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if current_tool == Tool.SLOPE:

				if not slope_has_a:
					slope_point_a = brush_position
					slope_has_a = true

					slope_marker_a.global_position = (
						slope_point_a + Vector3(0, 0.3, 0)
					)
					slope_marker_a.visible = true

					get_viewport().set_input_as_handled()
					return

				elif not slope_has_b:
					slope_point_b = brush_position
					slope_has_b = true
					slope_can_paint = false

					slope_marker_b.global_position = (
						slope_point_b + Vector3(0, 0.3, 0)
					)
					slope_marker_b.visible = true

					get_viewport().set_input_as_handled()
					return
				
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				edit_mode = EditMode.SCULPT
				current_tool = Tool.RAISE
			KEY_2:
				edit_mode = EditMode.SCULPT
				current_tool = Tool.LOWER
			KEY_3:
				edit_mode = EditMode.SCULPT
				current_tool = Tool.SMOOTH
			KEY_4:
				edit_mode = EditMode.SCULPT
				current_tool = Tool.FLATTEN
			KEY_5:
				edit_mode = EditMode.SCULPT
				current_tool = Tool.SLOPE
				reset_slope_points()
			KEY_R:
				if current_tool == Tool.SLOPE:
					reset_slope_points()

func get_brush_radius() -> float:
	match current_tool:
		Tool.RAISE:
			return raise_radius
		Tool.LOWER:
			return lower_radius
		Tool.SMOOTH:
			return smooth_radius
		Tool.FLATTEN:
			return flatten_radius
		Tool.SLOPE:
			return slope_radius

	return 3.0

func get_brush_strength() -> float:
	match current_tool:
		Tool.RAISE:
			return raise_strength
		Tool.LOWER:
			return lower_strength
		Tool.SMOOTH:
			return smooth_strength
		Tool.FLATTEN:
			return flatten_strength
		Tool.SLOPE:
			return slope_strength

	return 1.0
	
func use_current_tool(delta: float) -> void:
	var radius := get_brush_radius()
	var strength := get_brush_strength()

	match current_tool:
		Tool.RAISE:
			terrain.sculpt(
				brush_position,
				radius,
				strength,
				delta
			)

		Tool.LOWER:
			terrain.sculpt(
				brush_position,
				radius,
				strength,
				delta
			)

		Tool.SMOOTH:
			terrain.smooth_terrain(
				brush_position,
				radius,
				strength,
				delta
			)

		Tool.FLATTEN:
			if not was_left_pressed:
				flatten_target_height = brush_position.y

			terrain.flatten_terrain(
				brush_position,
				flatten_target_height,
				radius,
				strength,
				delta
			)
			
		Tool.SLOPE:
			if slope_has_a and slope_has_b and slope_can_paint:
				terrain.slope_terrain(
					brush_position,
					slope_point_a,
					slope_point_b,
					radius,
					strength,
					delta
				)
	
func _process(delta: float) -> void:
	update_brush_position()
	update_brush_size()

	var left_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if not left_pressed and slope_has_a and slope_has_b:
		slope_can_paint = true
		
	if brush_cursor.visible and left_pressed:
		use_current_tool(delta)
		
	if brush_cursor.visible and left_pressed:
		if edit_mode == EditMode.PAINT:
			terrain.paint_surface(
				brush_position,
				get_brush_radius(),
				paint_surface_type
			)
		else:
			use_current_tool(delta)

	was_left_pressed = left_pressed

func update_brush_position() -> void:
	var mouse_position := get_viewport().get_mouse_position()

	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)

	var ray_length := 1000.0
	var ray_end := ray_origin + ray_direction * ray_length

	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end
	)

	var space_state := camera.get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	if result:
		brush_position = result.position

		# Slightly above the terrain to avoid flickering.
		brush_cursor.global_position = brush_position + Vector3(0, 0.05, 0)

		brush_cursor.visible = true
	else:
		brush_cursor.visible = false
		
func update_brush_size() -> void:
	var radius := get_brush_radius()
	var scale_factor := radius / 3.0

	brush_cursor.scale = Vector3(
		scale_factor,
		scale_factor,
		scale_factor
	)
	
func reset_slope_points() -> void:
	slope_has_a = false
	slope_has_b = false
	slope_can_paint = false

	slope_marker_a.visible = false
	slope_marker_b.visible = false
