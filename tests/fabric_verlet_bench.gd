extends SceneTree
## Fabric planning bench (dev-only, plan/fabric-physics — the Elements).
## Prices option 3, bone-spring secondary motion, as plain GDScript:
## verlet point-chains (cloak spine, hood, straps, the hound's tail)
## plus the Skeleton3D pose-write cost that would apply them.
## Everything is frame-rate work in _process (presentation tier), so
## the number that matters is us/frame at a plausible creature count.
## Run: godot --headless -s tests/fabric_verlet_bench.gd
func _init() -> void:
	# A "dressed character" budget guess: 6 chains x 5 points
	# (cloak spine x2, hood, 2 straps, tail/sash). Bench 1 / 10 / 30.
	for chars: int in [1, 10, 30]:
		var chains: int = chars * 6
		var pts := 5
		var pos: Array[Vector3] = []
		var prev: Array[Vector3] = []
		var anchors: Array[Vector3] = []
		for c in chains:
			anchors.append(Vector3(c * 0.5, 2.0, 0.0))
			for p in pts:
				pos.append(Vector3(c * 0.5, 2.0 - p * 0.15, 0.0))
				prev.append(pos[-1])
		var wind := Vector3(0.4, 0.0, 0.2)
		var t0 := Time.get_ticks_usec()
		var frames := 1000
		for f in frames:
			var dt := 1.0 / 60.0
			for c in chains:
				var base: int = c * pts
				pos[base] = anchors[c] + Vector3(sin(f * 0.1 + c) * 0.05, 0, 0)
				for p in range(1, pts):
					var i: int = base + p
					var cur := pos[i]
					pos[i] += (cur - prev[i]) * 0.96 \
						+ (Vector3.DOWN * 9.0 + wind * (1.0 + sin(f * 0.13 + i))) * dt * dt
					prev[i] = cur
				for iter in 2:  # distance constraints, 2 iterations
					for p in range(1, pts):
						var i: int = base + p
						var d := pos[i] - pos[i - 1]
						var l := d.length()
						if l > 0.0001:
							pos[i] = pos[i - 1] + d * (0.15 / l)
		var us := Time.get_ticks_usec() - t0
		print("VERLET %d chars (%d chains x %d pts): %.1f us/frame"
			% [chars, chains, pts, float(us) / float(frames)])

	# Skeleton3D pose-write cost: what applying those chains costs.
	var sk := Skeleton3D.new()
	get_root().add_child(sk)
	for b in 60:
		sk.add_bone("b%d" % b)
		if b > 0:
			sk.set_bone_parent(b, b - 1)
	var t0 := Time.get_ticks_usec()
	var frames := 1000
	for f in frames:
		for b in 60:
			sk.set_bone_pose_rotation(b, Quaternion(Vector3.RIGHT, sin(f * 0.01 + b) * 0.1))
	var us := Time.get_ticks_usec() - t0
	print("SKELETON 60 bone pose writes: %.1f us/frame" % (float(us) / float(frames)))
	quit()
