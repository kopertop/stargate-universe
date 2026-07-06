extends SceneTree

func _initialize() -> void:
	var passes := 0
	var injury_sys := InjurySystem.new()

	# Test 1: Register recoverable injury
	var tag := injury_sys.register_injury("scott", InjurySystem.InjuryCause.FALL, 0.3)
	assert(tag == InjurySystem.InjuryTag.RECOVERABLE, "Expected RECOVERABLE")
	passes += 1

	# Test 2: Register fatal injury
	tag = injury_sys.register_injury("greer", InjurySystem.InjuryCause.HOSTILE, 0.9)
	assert(tag == InjurySystem.InjuryTag.FATAL, "Expected FATAL")
	passes += 1

	# Test 3: Recover from recoverable
	var ok := injury_sys.attempt_recovery("scott")
	assert(ok == true, "Recovery should succeed")
	passes += 1

	# Test 4: Cannot recover from fatal
	ok = injury_sys.attempt_recovery("greer")
	assert(ok == false, "Fatal recovery should fail")
	passes += 1

	# Test 5: No injury returns false
	ok = injury_sys.attempt_recovery("unknown")
	assert(ok == false, "Unknown character should fail")
	passes += 1

	print("injury_system smoke: %d passes" % passes)
	quit(0)