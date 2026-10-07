shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_albedo_texture = true;
uniform vec4 albedo_tint : source_color = vec4(1.0);

void fragment() {
	vec3 texture_color = has_albedo_texture ? texture(albedo_texture, UV).rgb : vec3(1.0);
	ALBEDO = texture_color * albedo_tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float facing = clamp((dot(NORMAL, LIGHT) + 0.3) / 1.3, 0.0, 1.0);
	float softness = smoothstep(0.0, 1.0, facing);
	vec3 shade = mix(vec3(0.72, 0.68, 0.86), vec3(1.0), softness);
	DIFFUSE_LIGHT += shade * (0.38 + 0.62 * softness) * ATTENUATION * LIGHT_COLOR / PI;
}
