extends Node3D

@export var distance: float = 55.0
@export var min_distance: float = 15.0
@export var max_distance: float = 100.0

@export var orbit_speed: float = 0.005
@export var pan_speed: float = 0.010
@export var zoom_speed: float = 5.0

@export var min_pitch: float = -80.0
@export var max_pitch: float = -15.0

var yaw: float = 0.0
var pitch: float = -45.0

# The point on the terrain that we're looking at/orbiting around.
var target: Vector3 = Vector3.ZERO

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:

		# Middle mouse = orbit
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			yaw -= event.relative.x * orbit_speed
			pitch -= event.relative.y * orbit_speed

			pitch = clamp(
				pitch,
				deg_to_rad(min_pitch),
				deg_to_rad(max_pitch)
			)

			update_camera()

		# Right mouse = pan
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			pan_camera(event.relative)

	elif event is InputEventMouseButton:

		# Mouse wheel = zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance -= zoom_speed
			distance = clamp(distance, min_distance, max_distance)
			update_camera()

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance += zoom_speed
			distance = clamp(distance, min_distance, max_distance)
			update_camera()


func pan_camera(mouse_delta: Vector2) -> void:
	# Camera's local right direction projected onto the ground.
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	# Ground-plane forward direction.
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var speed := pan_speed * distance

	target += right * -mouse_delta.x * speed
	target += forward * mouse_delta.y * speed

	update_camera()


func update_camera() -> void:
	var direction := Vector3(
		cos(pitch) * sin(yaw),
		-sin(pitch),
		cos(pitch) * cos(yaw)
	)

	camera.position = target + direction * distance
	camera.look_at(target, Vector3.UP)
