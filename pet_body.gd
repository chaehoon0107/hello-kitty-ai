extends CharacterBody2D

const WALK_SPEED := 36.0
const GRAVITY := 1600.0
var direction := 1.0
var grounded := false
var held := false
var walking_enabled := true

func _physics_process(delta: float) -> void:
	if held:
		grounded = false
		return
	if grounded and velocity.y <= 0.0:
		velocity.y = 0.0
	# Resolve a small downward step against one continuous flat plane.
	velocity.y = minf(velocity.y + GRAVITY * delta, 2000.0)
	if grounded:
		velocity.x = move_toward(velocity.x, direction * WALK_SPEED if walking_enabled else 0.0, 520.0 * delta)
	move_and_slide()
	grounded = is_on_floor()
