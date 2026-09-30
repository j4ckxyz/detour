extends Node
## Screenshot tour of laying planks across the first washed-out gap, from the player's own
## view: the pile of planks before it, carrying one, the preview lying across the trench (from a
## few steps back and up close), two planks laid, and the RV crossing.
##
##   godot --path game res://src/debug/plank_tour.tscn -- --shots=/tmp/planks

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")

var _pg: Playground
var _w: Walker
var _dir := "user://plank_tour"
var _shot := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_dir)
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	_tour()


func _tour() -> void:
	while not _pg.is_spawned or is_instance_valid(_pg.loading):
		await get_tree().process_frame
	_w = Walker.new(get_tree(), _pg.player, _pg.rv)
	var gap := _first(Trip.GAP)
	var dir: Vector3 = gap["dir"]
	var centre: Vector3 = gap["pos"]
	var half := float(gap["length"]) * 0.5
	await _teleport(float(gap["s"]) - half - 14.0)
	# The pile of planks for it, from the road.
	var pile: Dictionary = {}
	for supply: Dictionary in _pg.trip.data["supplies"]:
		if int(supply["kind"]) == 0 and absf(float(supply["s"]) - (float(gap["s"]) - half - 8.0)) < 20.0:
			pile = supply
			break
	if not pile.is_empty():
		var at: Vector3 = pile["pos"]
		_stand(at - dir * 9.0 + Vector3(-dir.z, 0.0, dir.x) * -(at - centre).dot(Vector3(-dir.z, 0.0, dir.x)) * 0.0)
		_w.face(at + Vector3.UP * 0.4)
		await _seconds(0.6)
		await _snap("pile_from_the_road")
	# Carrying one, at the edge, looking into the trench.
	_stand(centre - dir * (half + 2.0))
	var plank := ItemLibrary.create(&"plank")
	_pg.items.add_child(plank)
	plank.global_position = _pg.player.global_position + Vector3.UP
	await _seconds(0.3)
	_pg.player.pick_up(plank)
	_w.face(centre + Vector3.DOWN * 1.5)
	await _seconds(0.6)
	await _snap("preview_looking_into_the_trench")
	_w.face(centre + dir * 6.0)
	await _seconds(0.6)
	await _snap("preview_looking_across")
	_stand(centre - dir * (half + 4.0))
	_w.face(centre + Vector3.DOWN * 1.0)
	await _seconds(0.6)
	await _snap("preview_from_further_back")
	_w.face(centre + Vector3.UP * 0.3 + (Vector3(-dir.z, 0.0, dir.x)) * 3.0)
	await _seconds(0.6)
	await _snap("preview_aimed_off_to_the_side")
	# Lay it, then a second.
	_w.face(centre + Vector3(-dir.z, 0.0, dir.x) * -0.7 + Vector3.DOWN * 1.2)
	await _seconds(0.4)
	await _w.press(&"use_item")
	var second := ItemLibrary.create(&"plank")
	_pg.items.add_child(second)
	second.global_position = _pg.player.global_position + Vector3.UP
	await _seconds(0.3)
	_pg.player.pick_up(second)
	_w.face(centre + Vector3(-dir.z, 0.0, dir.x) * 0.7 + Vector3.DOWN * 1.2)
	await _seconds(0.5)
	await _snap("second_preview_on_the_other_track")
	await _w.press(&"use_item")
	await _seconds(0.5)
	await _snap("two_planks_laid")
	# From the RV's seat.
	_pg.player.take_wheel()
	await _seconds(1.0)
	await _snap("from_the_drivers_seat")
	get_tree().quit()


func _stand(at: Vector3) -> void:
	at.y = _ground(at).y + 0.1
	_pg.player.global_position = at
	_pg.player.velocity = Vector3.ZERO
	await _seconds(0.1)


func _first(kind: int) -> Dictionary:
	for o: Dictionary in _pg.trip.data["obstacles"]:
		if int(o["kind"]) == kind:
			return o
	return {}


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, TerrainStreamer.WORLD_LAYER)
	var hit := _pg.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


func _teleport(s: float) -> void:
	_pg._place_rv(_pg.trip.road_transform(s))
	while _pg.is_rv_waiting():
		await get_tree().physics_frame
	await _seconds(1.0)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := _dir.path_join("%02d_%s.png" % [_shot, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)
