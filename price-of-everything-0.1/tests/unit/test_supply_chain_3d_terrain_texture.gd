extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Encoding := preload("res://scripts/supply_chain_3d/terrain_texture.gd")
const Retention := preload("res://scripts/supply_chain_3d/tile_resource_cache.gd")

func _test_terrain_texture_protects_urban_neighbour_ring() -> void:
	var tiles := {"tile_4_9":{"type":"urban"},"tile_5_9":{"type":"rural"},"tile_6_9":{"type":"rural"},"tile_7_9":{"type":"hill"},"tile_8_9":{"type":"mountain"},"tile_9_9":{"type":"sea"}}
	var allowed := Encoding.eligible_tiles(tiles)
	_check(not allowed.tile_4_9 and not allowed.tile_5_9,"Terrain texture: urban and adjacent rural keep resolution")
	_check(allowed.tile_6_9 and allowed.tile_7_9 and allowed.tile_8_9,"Terrain texture: distant rural, hill and mountain are candidates")
	_check(not allowed.tile_9_9,"Terrain texture: other tile types are not silently reduced")
	# The opposite column parity must protect its diagonals too.
	tiles={"tile_5_9":{"type":"urban"},"tile_6_8":{"type":"hill"},"tile_4_8":{"type":"mountain"}}
	allowed=Encoding.eligible_tiles(tiles)
	_check(not allowed.tile_6_8 and not allowed.tile_4_8,"Terrain texture: odd-q adjacency protects both diagonal neighbours")

func _test_terrain_texture_quality_rejects_localised_detail_loss() -> void:
	_check(Encoding.target_size(Vector2i(6144,4922),1.0)==Vector2i(6144,4924),"Terrain texture: far atlas is explicitly resampled to BC7 block alignment")
	_check(Encoding.target_size(Vector2i(2048,1824),.75)==Vector2i(1536,1368),"Terrain texture: tile dimensions need no alignment padding")
	var image := Image.create(256,256,false,Image.FORMAT_RGB8)
	image.fill(Color(.5,.6,.4))
	var decoded := image.duplicate() as Image
	_check(Encoding.acceptable(Encoding.quality(image,decoded)),"Terrain texture: unchanged flat colour passes")
	decoded.fill_rect(Rect2i(0,0,8,8),Color.BLACK)
	_check(not Encoding.acceptable(Encoding.quality(image,decoded)),"Terrain texture: localised high contrast loss is rejected")
	_check(not Encoding.acceptable({"rmse":.5,"worst_patch_rmse":5.0}),"Terrain texture: global average cannot hide a damaged patch")

func _test_terrain_texture_codec_and_retained_memory() -> void:
	var image := Image.create(256,224,false,Image.FORMAT_RGB8)
	image.fill(Color(.5,.6,.4));image.generate_mipmaps()
	var encoded := Encoding.encode(ImageTexture.create_from_image(image),true)
	var info: Dictionary=encoded.terrain_texture
	_check(info.reduced and encoded.texture.get_width()==128 and encoded.texture.get_height()==112,"Terrain texture: simple art retains extent at half dimensions")
	_check(encoded.texture.get_format()==Image.FORMAT_BPTC_RGBA and encoded.texture.get_image().has_mipmaps(),"Terrain texture: BC7 and mipmaps survive native resource creation")
	var estimate := Retention.estimate({"textures":[null,encoded.texture]}, {})
	_check(estimate==info.bytes,"Terrain texture: retention counts compressed blocks including all mips")
	var saved := preload("res://scripts/supply_chain_3d/bake_data.gd").new()
	saved.data=encoded
	var path := "/private/tmp/terrain-texture-roundtrip-%d.res" % Time.get_ticks_usec()
	_check(ResourceSaver.save(saved,path,ResourceSaver.FLAG_COMPRESS)==OK,"Terrain texture: compressed native resource saves")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var pixels: Image=loaded.values().texture.get_image()
	_check(pixels.get_format()==Image.FORMAT_BPTC_RGBA and pixels.get_size()==Vector2i(128,112) and pixels.get_data_size()==info.bytes,"Terrain texture: disk reload retains compressed blocks and dimensions")
	DirAccess.remove_absolute(path)
