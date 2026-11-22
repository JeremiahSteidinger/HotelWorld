extends SceneTree
## Unit tests for the simulation (no rendering).
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.

const Sim := preload("res://scripts/sim/sim.gd")
const Layout := preload("res://scripts/sim/layout.gd")
const Reviews := preload("res://scripts/sim/reviews.gd")

var bal: Dictionary
var failures := 0
var checks := 0
var current := ""


func _init() -> void:
	bal = Sim.load_balance()
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
			current = n
			call(n)
	print("\n%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL [%s] %s" % [current, msg])


func fresh(mode := "sandbox"):
	var s = Sim.new()
	s.new_game(bal, mode, 42)
	s.arrivals = []  # tests add guests by hand
	return s


func add_guest(s, archetype := "budget"):
	# Force an arrival of a given archetype.
	var saved: Dictionary = s.bal["archetypes"].duplicate(true)
	for k in s.bal["archetypes"]:
		s.bal["archetypes"][k]["weight"] = 1.0 if k == archetype else 0.0
	s._arrive()
	s.bal["archetypes"] = saved
	return s.guests[s.next_id - 1] if s.guests.has(s.next_id - 1) else null


func run_until(s, cond: Callable, max_minutes := 600.0) -> bool:
	var t := 0.0
	while t < max_minutes:
		if cond.call():
			return true
		s.tick(1.0)
		t += 1.0
	return cond.call()


# --------------------------------------------------------------------------- layout

func test_paths_use_doors() -> void:
	var p := Layout.find_path(Layout.GUEST_SPAWN, Layout.room_bed(3))
	check(not p.is_empty(), "path from road to a room exists")
	check(p.has(Layout.room_door(3)), "path into a room goes through its door")
	var q := Layout.find_path(Layout.room_bed(0), Layout.room_bed(1))
	check(q.has(Layout.room_door(0)) and q.has(Layout.room_door(1)), "rooms are not connected through walls")
	check(not Layout.walkable(Layout.DESK_CELLS[0]), "desk blocks movement")
	for c in [Vector2i(0, 0), Vector2i(5, 1), Vector2i(17, 8)]:
		check(Layout.to_grid(Layout.to_screen(Vector2(c))) == c, "screen/grid round trip for %s" % c)


# --------------------------------------------------------------------------- reviews

func test_review_math() -> void:
	check(Reviews.stars_for_mood(0) == 1, "mood 0 -> 1 star")
	check(Reviews.stars_for_mood(100) == 5, "mood 100 -> 5 stars")
	check(Reviews.stars_for_mood(70) == 4, "mood 70 -> 4 stars")
	check(is_equal_approx(Reviews.rating([], 3.0, 20, 5), 3.0), "no reviews -> starting rating")
	var fives := []
	for i in 20:
		fives.append({"stars": 5})
	check(is_equal_approx(Reviews.rating(fives, 3.0, 20, 5), 5.0), "many 5-star reviews -> 5.0")
	check(Reviews.pick_cause({"long_wait": -30.0, "fast_service": 8.0}, 2) == "long_wait", "bad review blames the wait")


# --------------------------------------------------------------------------- guest flow

func test_checkin_charges_and_assigns_room() -> void:
	var s = fresh()
	var cash_before: float = s.cash
	var g = add_guest(s, "budget")
	check(g != null, "guest arrived")
	check(run_until(s, func(): return g.state == "staying"), "guest checked in and reached the room")
	check(g.room >= 0 and s.rooms[g.room].type == "single", "budget guest got a single room")
	check(is_equal_approx(s.cash - cash_before, s.rates["single"] * g.nights * (1.0 - g.discount_pct / 100.0)), "paid rate x nights")
	check(s.rooms[g.room].state == "occupied", "room is occupied")


func test_walkout_when_desk_empty() -> void:
	var s = fresh()
	s.owner().orders.clear()
	s.owner().job = {}
	s.stations = [-1, -1]
	var g = add_guest(s, "business")
	var gid: int = g.id
	check(run_until(s, func(): return not s.guests.has(gid) or s.guests[gid].state == "leaving"), "guest gave up")
	check(s.stats["walkouts"] == 1, "walkout counted")
	check(s.reviews.size() == 1 and s.reviews[0]["stars"] == 1, "walkout leaves a 1-star review")


func test_dirty_room_makes_guest_wait_then_cleaning_fixes_it() -> void:
	var s = fresh()
	for r in s.rooms:
		r.state = "dirty"
	var g = add_guest(s, "family")
	g.patience = 10000.0
	check(run_until(s, func(): return g.state == "waiting_room"), "guest waits in the lobby for a dirty room")
	var mood_before: float = g.mood
	s.tick(30.0)
	check(g.mood < mood_before, "waiting for a room lowers mood")
	check(s.order_clean(g.room), "owner can be ordered to clean the room")
	check(run_until(s, func(): return g.state in ["to_room", "staying"]), "guest goes to the room once it is clean")


func test_checkout_makes_room_dirty_and_reviews() -> void:
	var s = fresh()
	var g = add_guest(s, "business")
	check(run_until(s, func(): return g.state == "staying"), "checked in")
	var room: int = g.room
	check(run_until(s, func(): return s.rooms[room].state == "dirty", 1440.0 * 2), "room becomes dirty at checkout")
	check(run_until(s, func(): return not s.reviews.is_empty()), "guest leaves a review at checkout")


func test_discount_accept_and_refuse() -> void:
	var s = fresh()
	var g = add_guest(s, "budget")
	g.mood = 10.0
	s.bal["discount"]["chance"] = 1.0
	check(run_until(s, func(): return g.state == "discount"), "unhappy guest asks for a discount")
	var cash_before: float = s.cash
	var expected: float = s.rates["single"] * g.nights * (1.0 - g.discount_pct / 100.0)
	s.resolve_discount(g.id, true)
	check(is_equal_approx(s.cash - cash_before, expected), "accepted discount lowers the price")
	check(g.notes.has("got_discount"), "guest remembers the discount")
	var g2 = add_guest(s, "budget")
	g2.mood = 10.0
	check(run_until(s, func(): return g2.state == "discount"), "second guest asks")
	s.resolve_discount(g2.id, false)
	check(g2.discount_pct == 0 and g2.notes.has("refused_discount"), "refusal keeps full price and upsets guest")


func test_price_too_high_drives_guests_away() -> void:
	var s = fresh()
	s.set_rate("single", 400)
	var g = add_guest(s, "budget")
	check(g == null and s.stats["lost_price"] == 1, "overpriced guests drive past")


# --------------------------------------------------------------------------- staff and money

func test_housekeeper_cleans_automatically() -> void:
	var s = fresh()
	s.candidates = [{"role": "housekeeper", "name": "Test Sweeper", "wage": 45.0}]
	check(s.hire(0), "hired")
	s.rooms[2].state = "dirty"
	check(run_until(s, func(): return s.rooms[2].state == "clean"), "housekeeper cleaned the room")


func test_end_of_day_pays_wages_and_upkeep() -> void:
	var s = fresh()
	s.candidates = [{"role": "clerk", "name": "Test Clerk", "wage": 55.0}]
	s.hire(0)
	var cash_before: float = s.cash
	s.time = 1440.0 - 1.0
	s.tick(2.0)
	var r: Dictionary = s.reports[-1]
	check(is_equal_approx(r["wages"], 55.0), "wages recorded")
	check(is_equal_approx(r["upkeep"], s.daily_upkeep()), "upkeep recorded")
	check(is_equal_approx(s.cash, cash_before - 55.0 - s.daily_upkeep()), "cash reduced by wages + upkeep")


func test_underpaid_staff_quit() -> void:
	var s = fresh()
	s.candidates = [{"role": "housekeeper", "name": "Grumpy", "wage": 45.0}]
	s.hire(0)
	s.set_wage(s.workers[-1].id, 0.0)
	for d in 15:
		s.time = d * 1440.0 + 1439.0
		s.tick(2.0)
	check(s.staff_count("housekeeper") == 0, "unpaid housekeeper quit")


func test_bankruptcy_in_campaign() -> void:
	var s = fresh("campaign")
	s.cash = -5000.0
	for d in 3:
		s.time = (s.day() - 1) * 1440.0 + 1439.0
		s.tick(2.0)
	check(s.game_over == "bankrupt", "three broke nights in a row ends the campaign")


func test_campaign_win() -> void:
	var s = fresh("campaign")
	s.cash = 20000.0
	s.time = 1439.0
	s.tick(2.0)
	check(s.game_over == "won", "reaching the cash goal wins")


func test_save_load_round_trip() -> void:
	var s = fresh()
	add_guest(s, "family")
	add_guest(s, "budget")
	s.tick(30.0)
	var path := "user://test_save.txt"
	check(s.save_to(path), "saved")
	var t = Sim.new()
	check(t.load_from(bal, path), "loaded")
	check(is_equal_approx(t.time, s.time) and is_equal_approx(t.cash, s.cash), "time and cash restored")
	check(t.guests.size() == s.guests.size() and t.queue == s.queue, "guests and line restored")
	s.tick(120.0)
	t.tick(120.0)
	check(is_equal_approx(t.cash, s.cash) and t.guests.size() == s.guests.size(), "loaded game continues identically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
