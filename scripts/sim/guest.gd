extends RefCounted
## A guest party. States:
##   queue -> to_desk -> at_desk -> (discount) -> waiting_room / to_room -> staying
##   staying -> queue (checkout) -> to_desk -> at_desk -> (discount) -> leaving -> gone

var id := 0
var archetype := "budget"
var name := ""
var room_type := "single"
var wtp := 60.0           # willingness to pay per night
var patience := 60.0      # minutes they will wait before giving up
var nights := 1
var mood := 70.0
var state := "queue"
var purpose := "checkin"  # or "checkout"
var wait := 0.0           # minutes waited in the current line/lobby
var room := -1
var paid := 0.0
var arrival_day := 1
var checkout_day := 2
var checkout_minute := 480.0
var discount_pct := 0
var discount_stage := ""  # "checkin" / "checkout" while a request is pending
var discount_timer := 0.0
var asked_discount := false
var early_state := ""     # "" (not asked yet), "asking", "haggling", "done"
var early_fee := 0.0      # fee paid for early check-in
var quirk := ""
var notes := {}           # cause -> mood impact (for review text)
var pos := Vector2.ZERO   # grid position (float)
var path: Array = []      # remaining Vector2i cells
var target := Vector2i(-1, -1)


func note(cause: String, amount: float) -> void:
	notes[cause] = notes.get(cause, 0.0) + amount
	mood = clampf(mood + amount, 0.0, 100.0)


func cell() -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


func arrived() -> bool:
	return path.is_empty()
