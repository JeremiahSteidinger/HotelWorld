extends RefCounted
## The owner or a staff member.
## role: "owner", "clerk", "housekeeper", "maintenance".
## job:  {} idle, {"type": "desk", "station": i}, {"type": "clean", "room": i},
##       {"type": "fix", "room": i}, {"type": "travel", "to": property index} (owner only),
##       {"type": "commute", "to": property index} (shared staff walking to their car)

var id := 0
var role := "owner"
var name := ""
var wage := 0.0
var home := -1           # staff only: index of the property that employs them and pays their wage
var shared := false      # staff only: may drive to other properties to help (roles with "can_share")
var shift := "day"       # staff only: "day", "evening" or "night" (see balance.json "shifts")
var present := true      # false while off shift (at home)
var pos := Vector2.ZERO
var path: Array = []
var target := Vector2i(-1, -1)
var job := {}
var orders: Array = []   # owner only: queued player orders {type, prop, room?}
var serving := -1        # guest id being served at the desk
var progress := 0.0      # minutes into the current task
var days_employed := 0


func cell() -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


func arrived() -> bool:
	return path.is_empty()
