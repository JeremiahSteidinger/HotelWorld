extends RefCounted
## The owner or a staff member.
## role: "owner", "clerk", "housekeeper".
## job:  {} idle, {"type": "desk", "station": i}, {"type": "clean", "room": i}

var id := 0
var role := "owner"
var name := ""
var wage := 0.0
var pos := Vector2.ZERO
var path: Array = []
var target := Vector2i(-1, -1)
var job := {}
var orders: Array = []   # owner only: queued player orders
var serving := -1        # guest id being served at the desk
var progress := 0.0      # minutes into the current task
var days_employed := 0


func cell() -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


func arrived() -> bool:
	return path.is_empty()
