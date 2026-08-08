extends Node2D
## Draw slot for the farm layer, sitting UNDER the forest canopy.
##
## Farms are the one built thing that shares ground with trees: a field runs up to
## (and under) the edge of a wood rather than stopping short of it. Everything in
## the world tree draws at z=0, so layering is pure sibling order — this node is
## created by BuildingVisuals and moved to just before ForestVisuals, which is the
## only slot that is above the terrain but below the canopy.
##
## It owns no geometry. BuildingVisuals still computes and caches every farm shape;
## this node just gives it a canvas that the trees paint over.

var source: Node2D = null   # the BuildingVisuals that owns the farm geometry


func _draw() -> void:
	if source != null and is_instance_valid(source):
		source.draw_farm_layer(self)
