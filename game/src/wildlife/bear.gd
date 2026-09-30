class_name Bear
extends Animal
## A bear: wanders near its den; spots players out in the open (crouching halves how far it
## sees), rears up and roars as a warning, then charges. Up close it swipes. It gives up if
## you get in the RV, go down, get far away, or lead it too far from home. Bear spray or the
## RV driving at it sends it running.

enum State { WANDER, ALERT, CHASE, ATTACK, FLEE, RETURN }

const SENSE := 24.0
const CROUCH_SENSE := 0.5
const GIVE_UP := 45.0
const LEASH := 80.0
const WALK := 1.3
## A little slower than a sprinting player (7 m/s): outrun it, or reach the RV.
const RUN := 6.3
const FLEE_SPEED := 8.5
const SWIPE_RANGE := 1.9
const SWIPE_DAMAGE := 30.0
const SWIPE_EVERY := 1.5
const ALERT_TIME := 1.4
const FLEE_TIME := 9.0
## After being scared off it leaves people alone for a while.
const CALM_TIME := 15.0

var calm := 0.0
var _wander_to := Vector3.ZERO
var _flee_from := Vector3.ZERO
var _swiped := false
var _swipe_heard := false
var _body: Node3D
var _legs: Array[Node3D] = []


func _build() -> void:
	var brown := Color(0.36, 0.22, 0.12)
	var dark := Color(0.22, 0.13, 0.07)
	_body = Node3D.new()
	add_child(_body)
	part(_body, Vector3(1.0, 0.95, 1.9), Vector3(0.0, 1.05, 0.0), brown)
	part(_body, Vector3(0.95, 0.35, 0.8), Vector3(0.0, 1.55, -0.3), brown) # Hump.
	part(_body, Vector3(0.62, 0.6, 0.6), Vector3(0.0, 1.25, -1.15), brown) # Head.
	part(_body, Vector3(0.32, 0.28, 0.35), Vector3(0.0, 1.12, -1.55), Color(0.5, 0.36, 0.24)) # Snout.
	part(_body, Vector3(0.12, 0.08, 0.06), Vector3(0.0, 1.2, -1.74), Color(0.05, 0.05, 0.05)) # Nose.
	for x: float in [-0.22, 0.22]:
		part(_body, Vector3(0.16, 0.16, 0.1), Vector3(x, 1.6, -1.1), dark) # Ears.
	for spec: Vector3 in [Vector3(-0.32, 0, -0.65), Vector3(0.32, 0, -0.65), Vector3(-0.32, 0, 0.65), Vector3(0.32, 0, 0.65)]:
		_legs.append(limb(_body, Vector3(spec.x, 0.75, spec.z), Vector3(0.3, 0.78, 0.34), Vector3(0.0, -0.38, 0.0), dark))
	_wander_to = home


func sprayed(from: Vector3) -> void:
	_flee_from = from
	set_state(State.FLEE)


func _on_state(s: int) -> void:
	_swipe_heard = false
	if s == State.ALERT:
		Sfx.cue(self, "wildlife/bear_roar", global_position + Vector3.UP * 1.4, 2.0, 14.0, 150.0)


func think(dt: float) -> void:
	state_time += dt
	calm = maxf(0.0, calm - dt)
	if state != State.FLEE and rv_scare():
		_flee_from = rv.global_position
		set_state(State.FLEE)
	match state:
		State.WANDER:
			if go_to(_wander_to, WALK, dt, 1.0) and state_time > 6.0:
				_wander_to = random_point(home, 20.0)
				state_time = 0.0
			if calm <= 0.0:
				target = nearest_player(SENSE, CROUCH_SENSE)
				if target:
					set_state(State.ALERT)
		State.ALERT:
			speed = 0.0
			if not is_exposed(target) or flat_distance(target.global_position) > SENSE * 1.6:
				set_state(State.WANDER)
			else:
				turn_towards(target.global_position, dt, 6.0)
				if state_time > ALERT_TIME:
					set_state(State.CHASE)
		State.CHASE:
			if not is_exposed(target) or flat_distance(target.global_position) > GIVE_UP or flat_distance(home) > LEASH:
				set_state(State.RETURN)
			elif go_to(target.global_position, RUN, dt, SWIPE_RANGE * 0.8):
				_swiped = false
				set_state(State.ATTACK)
		State.ATTACK:
			speed = 0.0
			if not is_exposed(target):
				calm = CALM_TIME * 0.5
				set_state(State.RETURN) # Lost interest (in the RV, or down).
				return
			turn_towards(target.global_position, dt, 8.0)
			var d := flat_distance(target.global_position)
			if state_time > 0.45 and not _swiped:
				_swiped = true
				if d < SWIPE_RANGE + 0.5:
					var push := (target.global_position - global_position).normalized()
					target.knock(Vector3(push.x, 0.0, push.z) * 4.0 + Vector3.UP * 2.0)
					target.hurt(SWIPE_DAMAGE, "mauled by a bear")
			if state_time > SWIPE_EVERY:
				_swiped = false
				state_time = 0.0
				if d > SWIPE_RANGE + 0.6:
					set_state(State.CHASE)
		State.FLEE:
			go_to(away_from(_flee_from, 10.0), FLEE_SPEED, dt, 0.1)
			if state_time > FLEE_TIME:
				calm = CALM_TIME
				set_state(State.RETURN)
		State.RETURN:
			if go_to(home, WALK * 2.0, dt, 4.0):
				set_state(State.WANDER)


func _process(dt: float) -> void:
	if state == State.ATTACK and state_time > 0.42 and not _swipe_heard:
		_swipe_heard = true
		Sfx.cue(self, "wildlife/bear_swipe", global_position + Vector3.UP * 1.2, 0.0, 8.0, 80.0)
	var phase := stride(dt, 2.2)
	for i: int in _legs.size():
		var swing := sin(phase + (PI if i % 3 == 0 else 0.0)) * clampf(speed / 3.0, 0.0, 0.8)
		_legs[i].rotation.x = swing
	# Rear up on the hind legs to warn, lean in to swipe.
	var rear := 0.0
	if state == State.ALERT:
		rear = 0.7 * sin(clampf(state_time / ALERT_TIME, 0.0, 1.0) * PI)
	elif state == State.ATTACK:
		rear = 0.35 * sin(clampf(state_time / 0.6, 0.0, 1.0) * PI)
	_body.rotation.x = lerpf(_body.rotation.x, rear, minf(1.0, dt * 10.0))
	_body.position.z = rear * 0.6
