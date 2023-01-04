#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D rendered_image;

layout(set = 0, binding = 1, std430) restrict buffer Camera {
	mat4 world_matrix;
	mat4 projection;
}
camera;

layout(set = 0, binding = 2, std430) restrict buffer DirectionalLight {
	vec4 data;
}
directional_light;

// Structs for RayTracing
struct Sphere {
	vec3 center;
	float radius;
	vec3 albedo;
};

struct Ray {
	vec3 origin;
	vec3 direction;
	vec3 inverse_direction;
};

struct RayHit
{
    vec3 position;
    float distance;
    vec3 normal;
	vec3 color;
};

// Global Constants
const vec3 SKY_COLOR = vec3(0.247, 0.435, 0.866);
const float INF = 99999999.0;
const float CONTACT_SHADOW_SPACE = 0.00001;
const float PI = 3.14159265;

uint voxels[230] = uint[230](66046u,196352u,719365u,1111306u,1504267u,1798287u,2010960u,2383776u,2760672u,3081212u,3244159u,3317855u,3448927u,3604224u,4127237u,4521728u,4997311u,5075087u,5308160u,5821483u,6094592u,6583690u,6924885u,7205389u,7533324u,7879365u,8190469u,8581900u,8917486u,9045243u,9153109u,9436928u,9961216u,10485504u,10945277u,11012853u,11206400u,11685298u,11992832u,12474280u,12782835u,12914672u,13238016u,13729664u,14169036u,14418430u,14484221u,14565312u,14946798u,33023u,57599u,12543u,52479u,41727u,51455u,52479u,8447u,65535u,52479u,52479u,65535u,65535u,57599u,61695u,35071u,65535u,43775u,65535u,61695u,65535u,62207u,65535u,65535u,65535u,65535u,65535u,49407u,61695u,20735u,12543u,52479u,50431u,65535u,65535u,52479u,52479u,65535u,65535u,20735u,50431u,65535u,54783u,65535u,65535u,65535u,65535u,65535u,65535u,65535u,65535u,62975u,28927u,65535u,12543u,65535u,33023u,61695u,56831u,14335u,12543u,60159u,65535u,47871u,65535u,61695u,61695u,65535u,65535u,29695u,12543u,65535u,511u,8447u,47103u,49407u,63743u,65535u,19711u,8959u,1535u,61695u,61695u,65535u,65535u,13311u,12799u,4351u,30719u,5631u,35071u,35071u,35071u,767u,52479u,52479u,65535u,65535u,52479u,52479u,8191u,49151u,35583u,65535u,44031u,65535u,2303u,36863u,2815u,45055u,65535u,65535u,65535u,65535u,53247u,61439u,65535u,65535u,3327u,2815u,767u,52479u,52479u,65535u,65535u,52479u,52479u,65535u,65535u,52479u,65535u,56831u,19967u,65535u,65535u,65535u,65535u,65535u,65535u,65535u,65535u,65535u,13311u,65535u,24575u,24575u,3327u,1279u,4095u,3583u,4095u,511u,61183u,65535u,65535u,65535u,61183u,57343u,49151u,32767u,65535u,65535u,22527u,1023u,4095u,4095u,511u,13311u,13311u,767u,1023u,4607u,1279u,65535u,65535u,13311u,13311u,16383u,8191u,30719u,511u);

const vec3 PPP = vec3(1, 1, 1);
const vec3 PNP = vec3(1, -1, 1);
const vec3 PNN = vec3(1, -1, -1);
const vec3 NPN = vec3(-1, 1, -1);
const vec3 NNN = vec3(-1, -1, -1);
const vec3 NNP = vec3(-1, -1, 1);
const vec3 NPP = vec3(-1, 1, 1);
const vec3 PPN = vec3(1, 1, -1);
const vec3 POS[8] = vec3[8](PNN, PNP, PPN, PPP, NNN, NNP, NPN, NPP);

vec3 sky_color_gradient(Ray ray)
{
	float t = 0.6 * (ray.direction.y + 1.0);
	return (1.0-t) * vec3(1.0, 1.0, 1.0) + t * SKY_COLOR;
}

Ray create_ray(vec3 origin, vec3 direction)
{
    Ray ray;
    ray.origin = origin;
    ray.direction = direction;
	ray.inverse_direction = 1.0f/direction;
    return ray;
}

Ray create_camera_ray(vec2 uv)
{
	vec3 origin = camera.world_matrix[3].xyz;
    vec3 direction = (inverse(camera.projection) * vec4(uv.x, -uv.y, 0.0, 1.0)).xyz;
    direction = (camera.world_matrix * vec4(direction, 0.0)).xyz;
    direction = normalize(direction);
    return create_ray(origin, direction);
}

RayHit create_ray_hit()
{
    RayHit hit;
    hit.position = vec3(0.0);
    hit.distance = INF;
    hit.normal = vec3(0.0);
	hit.color = vec3(0.0);
    return hit;
}

void intersect_ground_plane(Ray ray, inout RayHit best_hit)
{
    // Calculate distance along the ray where the ground plane is intersected
    float t = -ray.origin.y / ray.direction.y;
    if (t > 0 && t < best_hit.distance)
    {
        best_hit.distance = t;
        best_hit.position = ray.origin + t * ray.direction;
        best_hit.normal = vec3(0.0, 1.0, 0.0);
		best_hit.color = vec3(0.8);
    }
}

void intersect_sphere(Ray ray, inout RayHit best_hit, Sphere sphere)
{
	// Avoid self-shadowing
	if (distance(sphere.center, ray.origin) < sphere.radius + CONTACT_SHADOW_SPACE)
	{
		return;
	}

    // Calculate distance along the ray where the sphere is intersected
    vec3 d = ray.origin - sphere.center;
    float p1 = -dot(ray.direction, d);
    float p2sqr = p1 * p1 - dot(d, d) + sphere.radius * sphere.radius;
    if (p2sqr < 0.0)
        return;
    float p2 = sqrt(p2sqr);
    float t = p1 - p2 > 0.0 ? p1 - p2 : p1 + p2;

	// Successful Hit
    if (t > 0.0 && t < best_hit.distance)
    {
        best_hit.distance = t;
        best_hit.position = ray.origin + t * ray.direction;
        best_hit.normal = normalize(best_hit.position - sphere.center);
		best_hit.color = sphere.albedo;
    }
}

bool bounding_box_intersect(const vec3 box_min, const vec3 box_max, const Ray ray, out RayHit hit) {
	vec3 tbot = ray.inverse_direction * (box_min - ray.origin);
	vec3 ttop = ray.inverse_direction * (box_max - ray.origin);
	vec3 tmin = min(ttop, tbot);
	vec3 tmax = max(ttop, tbot);
	vec2 traverse = max(tmin.xx, tmin.yz);
	float traverselow = max(traverse.x, traverse.y);
	traverse = min(tmax.xx, tmax.yz);
	float traversehi = min(traverse.x, traverse.y);

	bool is_intersected = traversehi > max(traverselow, 0.0);
	if(!is_intersected) return is_intersected;

	vec3 box_center = (box_min + box_max) / 2.0;
	vec3 box_hit = ray.origin + (traverselow * ray.direction);
    vec3 normal = (box_hit - box_center);
    normal = sign(normal) * (abs(normal.x) > abs(normal.y) ? // Not y
        (abs(normal.x) > abs(normal.z) ? vec3(1., 0., 0.) : vec3(0., 0., 1.)) :
    	(abs(normal.y) > abs(normal.z) ? vec3(0., 1., 0.) : vec3(0., 0., 1.)));	

	hit.distance = traverselow;
	hit.position = ray.origin + traverselow * ray.direction;
	hit.normal = normal;
	hit.color = vec3(1.0, 0.0, 0.0);

	return is_intersected;
}
void intersect_svo(Ray ray, inout RayHit best_hit) {
	RayHit hit = create_ray_hit();

	vec3 center = vec3(0.0f, 2.0f, 0.0f); // Should later be an input parameter
    float scale = 1.0f;
	vec3 box_min = center - scale;
	vec3 box_max = center + scale;
	vec4 f = vec4(0.1f);
    struct Stack {
		uint index;
		vec3 center;
		float scale;
	};
    Stack stack[10];
    int stack_position = 1;
    if (!bounding_box_intersect(box_min, box_max, ray, hit)) return;
    uint index = 0u;
    scale *= 0.5f;
    stack[0] = Stack( 0u, center, scale);
    while(stack_position-- > 0) {
        f = vec4(0.1f);
        center = stack[stack_position].center;
		index = stack[stack_position].index;
		scale = stack[stack_position].scale;
        uint voxel_node = voxels[index];
        uint voxel_group_offset = voxel_node >> 16;
        uint voxel_child_mask = (voxel_node & 0x0000FF00u) >> 8u;
        uint voxel_leaf_mask = voxel_node & 0x000000FFu;
        uint accumulated_offset = 0u;
        for (uint i = 0u; i < 8u; ++i) {
            bool empty = (voxel_child_mask & (1u << i)) == 0u;
            bool is_leaf = (voxel_leaf_mask & (1u << i)) != 0u;
            if (empty){ //empty
                continue;
            }
            
            vec3 new_center = center + scale * POS[i];
            vec3 box_min = new_center - scale;
            vec3 box_max = new_center + scale;
            

            if (!bounding_box_intersect(box_min, box_max, ray, hit)){
                if(!is_leaf){
                   accumulated_offset +=1u;
                }
                continue;
            }
            if (is_leaf){ //not empty, but a leaf
				if (hit.distance > 0.0 && hit.distance < best_hit.distance)
				{
					best_hit.distance = hit.distance;
					best_hit.position = hit.position;
					best_hit.normal = hit.normal;
					best_hit.color = hit.color;
				}
            } else { //not empty and not a leaf
            	stack[stack_position++] = Stack(voxel_group_offset+accumulated_offset, new_center, scale*0.5f   );
            	f.z += 0.4f;
                accumulated_offset+=1u;
            }
        }
    }
}

Sphere[4] instance_spheres() // shows the axes
{
	Sphere[4] objects;

	Sphere sphere;
	sphere.center = vec3(0.0, 0.0, 0.0);
	sphere.radius = 0.2;
	sphere.albedo = vec3(1.0, 1.0, 1.0);
	objects[0] = sphere;

	Sphere sphere_x;
	sphere_x.center = vec3(1.0, 0.0, 0.0);
	sphere_x.radius = 0.2;
	sphere_x.albedo = vec3(1.0, 0.0, 0.0);
	objects[1] = sphere_x;

	Sphere sphere_y;
	sphere_y.center = vec3(0.0, 1.0, 0.0);
	sphere_y.radius = 0.2;
	sphere_y.albedo = vec3(0.0, 1.0, 0.0);
	objects[2] = sphere_y;

	Sphere sphere_z;
	sphere_z.center = vec3(0.0, 0.0, 1.0);
	sphere_z.radius = 0.2;
	sphere_z.albedo = vec3(0.0, 0.0, 1.0);
	objects[3] = sphere_z;

	return objects;
}

RayHit trace(Ray ray, Sphere[4] objects)
{
    RayHit best_hit = create_ray_hit();
    intersect_ground_plane(ray, best_hit);

	for (int i = 0; i < 4; i++)
	{
		Sphere sphere = objects[i];
		intersect_sphere(ray, best_hit, sphere);
	}

	intersect_svo(ray, best_hit);

    return best_hit;
}

vec3 shade(inout Ray ray, RayHit hit, Sphere[4] objects)
{
    if (hit.distance < INF)
    {
        vec3 light_direction = directional_light.data.xyz;
		
		// Shadow test ray
		bool shadow = false;
		Ray shadowRay = create_ray(hit.position + hit.normal * CONTACT_SHADOW_SPACE, -light_direction);
		RayHit shadowHit = trace(shadowRay, objects);
		if (shadowHit.distance != INF)
		{
			return vec3(0.0);
		}

        // Return a diffuse-shaded color
		// Basically a mini fragment shader calculation goes on here
		float NdotL = dot(hit.normal, light_direction);
		vec3 diffuse = hit.color * clamp(-NdotL, 0.0, 1.0);
		diffuse *= directional_light.data.w; // Multiply by light intensity
		
		return diffuse;
    }
    else
    {
        return sky_color_gradient(ray);
    }
}

void main()
{
	// base pixel colour for image
	vec4 pixel = vec4(0.0, 0.0, 0.0, 1.0);
	
	ivec2 image_size = imageSize(rendered_image);
	// Coords in the range [-1,1]
	vec2 uv = vec2((gl_GlobalInvocationID.xy) / vec2(image_size) * 2.0 - 1.0);
	float aspect_ratio = float(image_size.x) / float(image_size.y);
	uv.x *= aspect_ratio;

	Sphere[4] objects = instance_spheres();

	// Raytracing!
	Ray ray = create_camera_ray(uv);
	vec3 result = vec3(0.0, 0.0, 0.0);

	RayHit hit = trace(ray, objects);
	result += shade(ray, hit, objects);
	pixel.xyz = result;

	//pixel.xyz = hit.normal; // Uncomment this line if you want to see the normals

	// output to a specific pixel in the image buffer
	// Writes to texture
	imageStore(rendered_image, ivec2(gl_GlobalInvocationID.xy), pixel);
}
