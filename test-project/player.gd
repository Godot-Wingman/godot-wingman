extends CharacterBody2D
## Simple player used by the tests.

const SPEED := 200.0


func _physics_process(_delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	velocity.x = direction * SPEED
	move_and_slide()
