extends TextureRect

@export var halfsize_render = false

var image_size : Vector2i
var rd = RenderingServer.create_local_rendering_device()
var uniform_set
var pipeline
var image_buffer_out
var bindings : Array
var shader
var output_tex : RID
var camera : Camera3D
var directional_light : DirectionalLight3D

func _ready():
	get_tree().get_root().size_changed.connect(_on_resize)
	
	camera = get_viewport().get_camera_3d()
	directional_light = get_tree().current_scene.find_child("DirectionalLight3d")
	
	texture_init()
	
	setup_compute()
	render()


func _process(_delta):
	update_compute()
	render()


func _on_resize():
	texture_init()
	fill_output_tex_uniform()


func setup_compute():
	var shader_file = load("res://voxel_ray_tracer/voxel_ray_tracer.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)	
	
	bindings = [null, null, null]
	fill_output_tex_uniform()
	fill_camera_buffer()
	fill_light_buffer()
	uniform_set = rd.uniform_set_create(bindings, shader, 0)


func update_compute():
	#fill_output_tex_uniform()
	fill_camera_buffer()
	fill_light_buffer()
	uniform_set = rd.uniform_set_create(bindings, shader, 0)


func render():
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, image_size.x / 8.0, image_size.y / 8.0, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	var byte_data : PackedByteArray = rd.texture_get_data(output_tex, 0)
	set_texture_data(byte_data)


func fill_output_tex_uniform():
	var fmt := RDTextureFormat.new()
	fmt.width = image_size.x
	fmt.height = image_size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view := RDTextureView.new()
	var output_image := Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBAF)
	output_tex = rd.texture_create(fmt, view, [output_image.get_data()])
	var output_tex_uniform := RDUniform.new()
	output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_uniform.binding = 0
	output_tex_uniform.add_id(output_tex)
	
	bindings[output_tex_uniform.binding] = output_tex_uniform


func fill_camera_buffer():
	var cam_to_world : Transform3D = camera.global_transform
	var projection = Projection.create_perspective(camera.fov, 1.0, camera.near, camera.far)
	
	var camera_matrices_bytes := PackedByteArray()
	camera_matrices_bytes.append_array(transform_3d_to_bytes(cam_to_world))
	camera_matrices_bytes.append_array(projection_to_bytes(projection))
	var camera_matrices_buffer = rd.storage_buffer_create(camera_matrices_bytes.size(), camera_matrices_bytes)
	var camera_matrices_uniform := RDUniform.new()
	camera_matrices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_matrices_uniform.binding = 1
	camera_matrices_uniform.add_id(camera_matrices_buffer)
	
	bindings[camera_matrices_uniform.binding] = camera_matrices_uniform


func fill_light_buffer():
	var light_direction : Vector3 = -directional_light.global_transform.basis.z
	light_direction = light_direction.normalized()
	var light_data_bytes := PackedFloat32Array([
		light_direction.x, light_direction.y, light_direction.z,
		directional_light.light_energy
	]).to_byte_array()
	var light_data_buffer = rd.storage_buffer_create(light_data_bytes.size(), light_data_bytes)
	var light_data_uniform := RDUniform.new()
	light_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	light_data_uniform.binding = 2
	light_data_uniform.add_id(light_data_buffer)
	
	bindings[light_data_uniform.binding] = light_data_uniform


func transform_3d_to_bytes(t : Transform3D):
	var bytes : PackedByteArray = PackedFloat32Array([
		t.basis.x.x, t.basis.x.y, t.basis.x.z, 1.0,
		t.basis.y.x, t.basis.y.y, t.basis.y.z, 1.0,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, 1.0,
		t.origin.x, t.origin.y, t.origin.z, 1.0
	]).to_byte_array()
	return bytes


func projection_to_bytes(p : Projection):
	var bytes : PackedByteArray = PackedFloat32Array([
		p.x.x, p.x.y, p.x.z, p.x.w,
		p.y.x, p.y.y, p.y.z, p.y.w,
		p.z.x, p.z.y, p.z.z, p.z.w,
		p.w.x, p.w.y, p.w.z, p.x.w
	]).to_byte_array()
	return bytes


func texture_init():
	var image_factor = 1;
	if halfsize_render: image_factor = 2
	
	var window:Window = get_viewport() as Window
	image_size.x = window.size.x/image_factor;
	image_size.y = window.size.y/image_factor;
	
	var image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBAF)
	var image_texture = ImageTexture.create_from_image(image)
	texture = image_texture


func set_texture_data(data : PackedByteArray):
	var image := Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBAF, data)
	texture.update(image)
