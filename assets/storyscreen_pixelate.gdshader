shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D story_tex : source_color, filter_nearest;
uniform vec2 tex_size = vec2(512.0, 512.0);
uniform float pixel_size : hint_range(1.0, 256.0) = 8.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float hover : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hover_tint : source_color = vec3(1.0, 0.97, 0.88);

void fragment() {
	vec2 uv = UV;
	vec2 ts = max(tex_size, vec2(1.0));
	float ps = max(pixel_size, 1.0);

	vec2 cell = ps / ts;                 // UV size of one pixel-block
	vec2 uvp = (floor(uv / cell) + 0.5) * cell; // sample block center

	vec4 c = texture(story_tex, uvp);
	vec3 col = c.rgb;
	// Cinematic hover: slightly brighten + warm tint.
	col = mix(col, hover_tint, hover * 0.22);
	col *= (1.0 + hover * 0.35);
	ALBEDO = col;
	ALPHA = opacity;
}

