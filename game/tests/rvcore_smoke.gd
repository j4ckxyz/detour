extends SceneTree
## Headless smoke test for the rvcore GDExtension.
##   godot --headless --path game --script res://tests/rvcore_smoke.gd

## Must match native/rvgen/tests/golden.rs.
const GOLDEN_CODE := "DT6-00000-0000M"
const GOLDEN_HASH_0_0 := "d12d9c3612f09f86"

var _failures: PackedStringArray = []


func _initialize() -> void:
	var gen := WorldGen.new()
	_check(WorldGen.gen_version() >= 1, "gen_version")
	_check(gen.load(GOLDEN_CODE), "load golden code")
	_check(gen.get_code() == GOLDEN_CODE, "code round-trips")
	_check(gen.chunk_hash(0, 0) == GOLDEN_HASH_0_0, "golden hash via GDExtension: %s" % gen.chunk_hash(0, 0))
	_check(WorldGen.code_error("DT6-00000-0000N") != "", "typo detected")
	_check(WorldGen.code_error(WorldGen.random_code(1)) == "", "random code valid")
	_check(gen.chunk_heights(0, 0).size() == 129 * 129, "heights size")
	var arrays := gen.chunk_mesh(0, 0, 4)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(verts.size() == 33 * 33 + 4 * 33, "mesh vertex count %d" % verts.size())
	_check(absf(gen.height_at(10.0, 20.0) - gen.chunk_heights(0, 0)[20 * 129 + 10]) < 0.001, "height_at matches grid")

	var builder := ChunkBuilder.new()
	_check(builder.start(GOLDEN_CODE, 2), "builder start")
	for i: int in 8:
		var flags := ChunkBuilder.DECOR | (ChunkBuilder.HEIGHTS if i == 0 else 0)
		builder.request(i, 0, 2, flags)
	builder.request(0, 1, 0, ChunkBuilder.HEIGHTS) # Collision only: no mesh.
	var got: Dictionary[int, Dictionary] = {}
	var deadline := Time.get_ticks_msec() + 5000
	var heights_only: Dictionary = {}
	while (got.size() < 8 or heights_only.is_empty()) and Time.get_ticks_msec() < deadline:
		for r: Dictionary in builder.poll(8):
			if int(r["cz"]) == 1:
				heights_only = r
			else:
				got[int(r["cx"])] = r
		OS.delay_msec(5)
	_check(got.size() == 8, "builder produced %d/8 chunks" % got.size())
	_check(not heights_only.is_empty() and heights_only["arrays"] == null, "step 0 builds no mesh")
	_check(not heights_only.is_empty() and heights_only["tree_buffers"] == null, "no decor unless asked")
	_check(not heights_only.is_empty() and (heights_only["heights"] as PackedFloat32Array).size() == 129 * 129, "heights-only job")
	_check(builder.pending() == 0, "nothing pending")
	if got.has(0):
		_check(got[0]["hash"] == GOLDEN_HASH_0_0, "threaded hash matches")
		_check((got[0]["heights"] as PackedFloat32Array).size() == 129 * 129, "threaded heights")
		var count: int = got[0]["tree_count"]
		var instances := 0
		for buffer: PackedFloat32Array in got[0]["tree_buffers"]:
			instances += buffer.size() / 12
		_check(instances == count, "tree multimesh buffers cover every tree")
		var props: PackedFloat32Array = got[0]["props"]
		_check(props.size() == int(got[0]["prop_count"]) * 14, "prop layout")
		_check(props == gen.chunk_props(0, 0), "threaded props match WorldGen")
	var prop_count := 0
	for r: Dictionary in got.values():
		prop_count += int(r["prop_count"])
	_check(prop_count > 0, "8 chunks have props")
	builder.stop()

	# Any text is a seed; a typed code is itself; blank is a new trip.
	var hello: Dictionary = WorldGen.code_from_text("hello world", 0)
	_check(String(hello["code"]).begins_with("DT%d-" % WorldGen.gen_version()) and hello["error"] == "", "text seeds: %s" % hello)
	_check(WorldGen.code_from_text("  hello world ", 0)["code"] == hello["code"], "text seeds ignore spaces at the ends")
	_check(WorldGen.code_from_text(GOLDEN_CODE, 2)["code"] == GOLDEN_CODE, "a code is itself")
	_check(WorldGen.code_from_text("", 0)["code"] == "", "blank is a new trip")
	_check(WorldGen.code_from_text("DT6-00000-0000N", 0)["error"] != "", "a code with a typo is an error")
	_check(WorldGen.text_seed_max() == 20, "text seeds up to 20 characters")

	# Loading in the background, with progress; the world is shared once built.
	var fresh: String = WorldGen.code_from_text("background load", 1)["code"]
	_check(not WorldGen.is_cached(fresh), "not built yet")
	var bg := WorldGen.new()
	bg.begin_load(fresh)
	var stages: Dictionary = {}
	deadline = Time.get_ticks_msec() + 20000
	var state := 0
	while state == 0 and Time.get_ticks_msec() < deadline:
		state = bg.poll_load()
		stages[bg.load_stage()] = bg.load_progress()
		OS.delay_msec(1)
	_check(state == 1 and bg.get_code() == fresh, "background load finished (%d)" % state)
	_check(WorldGen.is_cached(fresh), "and is kept for the chunk builder")
	var trip := bg.trip()
	_check((trip["obstacles"] as Array).size() > 5 and trip.has("pois") and trip.has("spurs"), "the trip has obstacles, places and side tracks")
	var p0: Vector3 = (trip["points"] as PackedVector3Array)[10]
	_check(bg.outside_valley(p0.x, p0.z) < 0.0 and bg.outside_valley(p0.x, p0.z + 600.0) > 0.0, "the road's on the valley floor, far off it isn't")
	var bad := WorldGen.new()
	bad.begin_load("DT6-00000-0000N")
	_check(bad.poll_load() == -1 and bad.load_error() != "", "a bad code fails to load: %s" % bad.load_error())

	if _failures.is_empty():
		print("rvcore smoke: all checks passed")
		quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
