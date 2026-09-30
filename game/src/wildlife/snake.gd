class_name Snake
extends Animal
## A rattlesnake lying by the road: rattles when someone comes near (a warning: go round it),
## and bites anyone who gets too close. The bite's venom keeps hurting until an antidote.
## Bear spray, or the RV rolling up, sends it slithering off.

enum State { COILED, RATTLE, STRIKE, FLEE }

const SENSE := 6.0
const CROUCH_SENSE := 0.6
const BITE_RANGE := 1.6
const BITE_DAMAGE := 8.0
const BITE_COOLDOWN := 4.0
const SLITHER := 2.4

var _cooldown := 0.0
var _flee_to := Vector3.ZERO
var _segments: Array[Node3D] = []
var _head: Node3D


func _build() -> void:
	var skin := Color(0.55, 0.47, 0.28)
	var band := Color(0.3, 0.22, 0.12)
	for i: int in 9:
		var s := Node3D.new()
		add_child(s)
		var w := 0.11 - 0.006 * i
		part(s, Vector3(w, w * 0.8, 0.16), Vector3.ZERO, band if i % 2 else skin)
		_segments.append(s)
	_head = Node3D.new()
	add_child(_head)
	part(_head, Vector3(0.13, 0.08, 0.16), Vector3.ZERO, skin)
	part(_head, Vector3(0.02, 0.02, 0.02), Vector3(-0.045, 0.035, -0.05), Color.BLACK)
	part(_head, Vector3(0.02, 0.02, 0.02), Vector3(0.045, 0.035, -0.05), Color.BLACK)


func sprayed(from: Vector3) -> void:
	_flee_to = away_from(from, 12.0)
	set_state(State.FLEE)


func think(dt: float) -> void:
	state_time += dt
	_cooldown = maxf(0.0, _cooldown - dt)
	if state != State.FLEE and rv_scare() and rv.global_position.distance_to(global_position) < 6.0:
		_flee_to = away_from(rv.global_position, 10.0)
		set_state(State.FLEE)
	match state:
		State.COILED, State.RATTLE:
			speed = 0.0
			target = nearest_player(SENSE, CROUCH_SENSE)
			if target == null:
				if state == State.RATTLE:
					set_state(State.COILED)
				return
			if state == State.COILED:
				set_state(State.RATTLE)
			turn_towards(target.global_position, dt, 3.0)
			if flat_distance(target.global_position) < BITE_RANGE and _cooldown <= 0.0 and Animal.is_exposed(target):
				set_state(State.STRIKE)
				target.hurt(BITE_DAMAGE, "bitten by a rattlesnake")
				target.poison()
				_cooldown = BITE_COOLDOWN
		State.STRIKE:
			if state_time > 0.5:
				set_state(State.RATTLE)
		State.FLEE:
			if go_to(_flee_to, SLITHER, dt, 0.3):
				home = global_position # Settles down wherever it ended up.
				set_state(State.COILED)


## True while it's warning someone off.
func is_rattling() -> bool:
	return state == State.RATTLE


func _process(dt: float) -> void:
	var phase := stride(dt, 6.0) if speed > 0.0 else fmod(Time.get_ticks_msec() * 0.001, TAU)
	var slithering := speed > 0.0
	var coil := 0.0 if slithering else 1.0
	# Body: a sine along the length when moving; a loose coil at rest.
	for i: int in _segments.size():
		var t := float(i) / _segments.size()
		var along := Vector3(sin(phase * 2.0 - i * 0.9) * 0.08, 0.05, 0.12 * i)
		var coiled := Vector3(cos(i * 0.75) * (0.14 + 0.012 * i), 0.05 + 0.01 * (i % 3), sin(i * 0.75) * (0.14 + 0.012 * i))
		_segments[i].position = along.lerp(coiled, coil)
		_segments[i].rotation.y = lerpf(sin(phase * 2.0 - i * 0.9) * 0.4, -i * 0.75, coil)
		if i == _segments.size() - 1 and state == State.RATTLE:
			_segments[i].position.y += 0.1 + absf(sin(phase * 40.0)) * 0.02 # The rattle.
		_segments[i].scale = Vector3.ONE * (1.0 - t * 0.3)
	var raise := 0.0 if slithering else (0.28 if state == State.RATTLE else 0.12)
	var lunge := 0.35 * sin(clampf(state_time / 0.3, 0.0, 1.0) * PI) if state == State.STRIKE else 0.0
	_head.position = Vector3(0.0, 0.05 + raise, -0.1 - lunge)
