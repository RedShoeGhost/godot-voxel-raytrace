extends Camera3D

@export var mouse_sensitivity : float = 1.0
@export var move_speed : float = 0.1


func _input(event):
	if event is InputEventMouseMotion:
		if _is_mouse_captured():
			rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
			rotate_object_local(Vector3(1.0, 0.0, 0.0), deg_to_rad(-event.relative.y * mouse_sensitivity))


func _process(_delta):
	_toggle_mouse_capture()
	_move()


func _move():
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	
	var displacement := Vector3.ZERO
	displacement = global_transform.basis.z * move_speed * input_vector.y
	global_transform.origin += displacement
	
	displacement = global_transform.basis.x * move_speed * input_vector.x
	global_transform.origin += displacement


func _is_mouse_captured() -> bool:
	return DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED


func _toggle_mouse_capture():
	if Input.is_action_just_pressed("ui_cancel"):
		if _is_mouse_captured():
			DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
		else:
			DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_CAPTURED)
