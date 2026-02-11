shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D cover_tex : source_color, filter_linear_mipmap;
uniform vec2 texel_size = vec2(1.0 / 512.0, 1.0 / 512.0);
uniform float blur_px : hint_range(0.0, 32.0) = 8.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float r = max(blur_px, 0.0);
	vec2 o = texel_size * r;

	// Simple 9-tap blur (box-ish). Cheap and good enough for "motion blur" feel.
	vec4 c = vec4(0.0);
	c += texture(cover_tex, uv + vec2(-o.x, -o.y));
	c += texture(cover_tex, uv + vec2( 0.0, -o.y));
	c += texture(cover_tex, uv + vec2( o.x, -o.y));
	c += texture(cover_tex, uv + vec2(-o.x,  0.0));
	c += texture(cover_tex, uv);
	c += texture(cover_tex, uv + vec2( o.x,  0.0));
	c += texture(cover_tex, uv + vec2(-o.x,  o.y));
	c += texture(cover_tex, uv + vec2( 0.0,  o.y));
	c += texture(cover_tex, uv + vec2( o.x,  o.y));
	c *= (1.0 / 9.0);

	ALBEDO = c.rgb;
	// Don't rely on texture alpha (some PNGs import with unexpected alpha).
	ALPHA = opacity;
}

