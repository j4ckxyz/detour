extends SceneTree
## Headless smoke test for the rvcore GDExtension.
##   godot --headless --path game --script res://tests/rvcore_smoke.gd

## Must match native/rvgen/tests/golden.rs.
const GOLDEN_CODE := "DT1-00000-0000N"
const GOLDEN_HASH_0_0 := "7585ca9ee9cd7632"

var _failures: PackedStringArray = []


func _initialize() -> void:
	var gen := WorldGen.new()
	_check(WorldGen.gen_version() >= 1, "gen_version")
	_check(gen.load(GOLDEN_CODE), "load golden code")
	_check(gen.get_code() == GOLDEN_CODE, "code round-trips")
	_check(gen.chunk_hash(0, 0) == GOLDEN_HASH_0_0, "golden hash via GDExtension: %s" % gen.chunk_hash(0, 0))
	_check(WorldGen.code_error("DT1-00000-0000M") != "", "typo detected")
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
