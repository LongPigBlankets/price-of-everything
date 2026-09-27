shader_type canvas_item;
// A render's silhouette printed flat in one ink: the building's icon on the site board's blueprint tile.
uniform vec4 ink : source_color = vec4(0.89, 0.92, 0.96, 1.0);

void fragment() {
	COLOR = vec4(ink.rgb, texture(TEXTURE, UV).a * ink.a);
}
