shader_type canvas_item;

uniform float speed : hint_range(0.1, 5.0) = 1.4;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rain_color : source_color = vec4(0.70, 0.76, 0.88, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rain_layer(vec2 uv, float t, float scale, float tilt, float brightness) {
	vec2 ruv = uv;
	ruv.x += ruv.y * tilt;
	ruv *= vec2(scale, scale * 0.2);
	ruv.y -= t;

	vec2 id = floor(ruv);
	vec2 gv = fract(ruv);

	float h    = hash(id);
	float sx   = h;                                // streak x position in cell
	float slen = 0.35 + hash(id + 13.7) * 0.5;    // streak length
	float sa   = hash(id + 7.3);                   // per-streak opacity variation

	float dx   = abs(gv.x - sx);
	float ix   = smoothstep(0.04, 0.0, dx);
	float iy   = step(0.0, gv.y) * step(gv.y, slen);
	float fade = 1.0 - gv.y / max(slen, 0.001);   // brighter at head, fades to tail

	return ix * iy * fade * sa * brightness;
}

void fragment() {
	float t  = TIME * speed;
	vec2  uv = UV;

	float r = 0.0;
	// Three slightly offset layers for depth: far (dense, dim), mid, near (sparse, bright)
	r += rain_layer(uv, t,        14.0, -0.15, 0.55);
	r += rain_layer(uv, t * 1.3,  22.0, -0.12, 0.35);
	r += rain_layer(uv, t * 0.85,  9.0, -0.18, 0.75);

	r = clamp(r, 0.0, 1.0) * intensity;
	COLOR = vec4(rain_color.rgb, r);
}
