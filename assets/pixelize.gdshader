shader_type canvas_item;

uniform float pixel_size : hint_range(1.0, 256.0, 1.0) = 4.0;
uniform sampler2D screen_texture : hint_screen_texture;

void fragment() {
	vec2 pixel_uv = SCREEN_PIXEL_SIZE * pixel_size;
	vec2 uv = floor(SCREEN_UV / pixel_uv) * pixel_uv;
	COLOR = texture(screen_texture, uv);
}
