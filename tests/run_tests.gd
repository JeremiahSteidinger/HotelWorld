extends SceneTree
## Unit tests for the simulation (no rendering).
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.

const Game := preload("res://scripts/sim/game.gd")
const Bot := preload("res://tools/bot.gd")
const Layout := preload("res://scripts/sim/layout.gd")
const Reviews := preload("res://scripts/sim/reviews.gd")

var bal: Dictionary
var failures := 0
var checks := 0
var current := ""


func _init() -> void:
	bal = Game.load_balance()
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


## A new game; returns its first property (the motel). The game is `s.game`.
func fresh(mode := "sandbox"):
	var g = Game.new()
	g.new_game(bal.duplicate(true), mode, 42)
	var s = g.properties[0]
	s.arrivals = []  # tests add guests by hand
	return s


func add_guest(s, archetype := "budget"):
	# Force an arrival of a given archetype.
	var arch: Dictionary = s.cfg["archetypes"]
	var saved: Dictionary = arch.duplicate(true)
	for k in arch:
		arch[k]["weight"] = 1.0 if k == archetype else 0.0
	s._arrive()
	s.cfg["archetypes"] = saved
	return s.guests[s.game.next_id - 1] if s.guests.has(s.game.next_id - 1) else null


func run_until(s, cond: Callable, max_minutes := 600.0) -> bool:
	var t := 0.0
	while t < max_minutes:
		if cond.call():
			return true
		s.game.tick(1.0)
		t += 1.0
	return cond.call()


# --------------------------------------------------------------------------- layout

func test_paths_use_doors() -> void:
	for L in [Layout.motel(), Layout.hotel()]:
		var p: Array[Vector2i] = L.find_path(L.guest_spawn, L.room_bed(3))
		check(not p.is_empty(), "%s: path from road to a room exists" % L.kind)
		check(p.has(L.room_door(3)), "%s: path into a room goes through its door" % L.kind)
		var q: Array[Vector2i] = L.find_path(L.room_bed(0), L.room_bed(1))
		check(q.has(L.room_door(0)) and q.has(L.room_door(1)), "%s: rooms are not connected through walls" % L.kind)
		check(not L.walkable(L.desk_cells[0]), "%s: desk blocks movement" % L.kind)
		for i in L.room_count():
			check(not L.find_path(L.service_spots[0], L.room_bed(i)).is_empty(), "%s: room %d reachable from the desk" % [L.kind, i])
			check(not L.find_path(L.staff_spawn, L.room_work_spot(i)).is_empty(), "%s: staff can reach room %d" % [L.kind, i])
		for i in L.line.size():
			check(not L.find_path(L.guest_spawn, L.queue_slot(i)).is_empty(), "%s: line slot %d reachable" % [L.kind, i])
		check(not L.find_path(L.service_spots[0], L.exit_cell).is_empty(), "%s: guests can leave" % L.kind)
	var h = Layout.hotel()
	check(h.room_count() == 14, "hotel has 14 rooms")
	var back_to_front: Array[Vector2i] = h.find_path(h.room_bed(0), h.room_bed(7))
	check(back_to_front.has(Vector2i(7, 2)), "hotel rooms connect through the hall")
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
	s.game.tick(30.0)
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


func test_guest_goes_to_bed_and_gets_up() -> void:
	var s = fresh()
	var g = add_guest(s, "business")
	check(run_until(s, func(): return g.state == "staying"), "checked in")
	check(not g.asleep, "guest is awake after checking in")
	check(run_until(s, func(): return g.asleep, 1440.0), "guest goes to bed at night")
	check(g.cell() == s.layout.room_bed(g.room), "sleeping guest is in the bed")
	var m: float = s.minute_of_day()
	check(m >= 21.5 * 60.0 or m < 7.0 * 60.0, "bedtime is in the evening")
	check(run_until(s, func(): return not g.asleep, 1440.0), "guest wakes up")
	check(g.state == "staying" and s.minute_of_day() < g.checkout_minute, "guest wakes up before check-out")
	check(run_until(s, func(): return g.state != "staying", 600.0), "guest still checks out after sleeping")


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
	s.game.time = 1440.0 - 1.0
	s.game.tick(2.0)
	var r: Dictionary = s.game.reports[-1]["props"][0]
	check(is_equal_approx(r["wages"], 55.0), "wages recorded")
	check(is_equal_approx(r["upkeep"], s.daily_upkeep()), "upkeep recorded")
	check(is_equal_approx(s.cash, cash_before - 55.0 - s.daily_upkeep()), "cash reduced by wages + upkeep")


func test_underpaid_staff_quit() -> void:
	var s = fresh()
	s.candidates = [{"role": "housekeeper", "name": "Grumpy", "wage": 45.0}]
	s.hire(0)
	s.set_wage(s.workers[-1].id, 0.0)
	for d in 15:
		s.game.time = d * 1440.0 + 1439.0
		s.game.tick(2.0)
	check(s.staff_count("housekeeper") == 0, "unpaid housekeeper quit")


func test_bankruptcy_in_campaign() -> void:
	var s = fresh("campaign")
	s.cash = -5000.0
	for d in 3:
		s.game.time = (s.day() - 1) * 1440.0 + 1439.0
		s.game.tick(2.0)
	check(s.game.game_over == "bankrupt", "three broke nights in a row ends the campaign")


func test_campaign_chapters() -> void:
	var s = fresh("campaign")
	var g = s.game
	check(g.listings()[0]["can_buy"] == false, "hotel is not for sale in chapter 1")
	g.cash = 8000.0
	g.borrow(5000.0)
	g.time = 1439.0
	g.tick(2.0)
	check(g.chapter == 1, "borrowed money doesn't count toward the savings goal")
	g.repay(g.loans[0]["id"], g.loans[0]["balance"])
	g.cash = 9500.0
	g.time = 2 * 1440.0 - 1.0
	g.tick(2.0)
	check(g.chapter == 2 and g.game_over == "", "saving $9,000 completes chapter 1, the game goes on")
	check(g.listings()[0]["can_buy"], "the hotel can be bought in chapter 2")
	g.cash = 200000.0
	g.time = 3 * 1440.0 - 1.0
	g.tick(2.0)
	check(g.game_over == "", "chapter 2 needs the hotel, not just money")
	check(g.buy_property("hotel"), "bought the hotel")
	g.time = 4 * 1440.0 - 1.0
	g.tick(2.0)
	check(g.game_over == "won", "owning the hotel with enough net worth wins the campaign")


func test_save_load_round_trip() -> void:
	var s = fresh()
	add_guest(s, "family")
	add_guest(s, "budget")
	s.game.tick(30.0)
	var path := "user://test_save.txt"
	check(s.game.save_to(path), "saved")
	var t = Game.new()
	check(t.load_from(s.bal, path), "loaded")
	t = t.properties[0]
	check(is_equal_approx(t.game.time, s.game.time) and is_equal_approx(t.cash, s.cash), "time and cash restored")
	check(t.guests.size() == s.guests.size() and t.queue == s.queue, "guests and line restored")
	s.game.tick(120.0)
	t.game.tick(120.0)
	check(is_equal_approx(t.cash, s.cash) and t.guests.size() == s.guests.size(), "loaded game continues identically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_check_in_waits_for_3pm_and_checkouts_spread_7_to_11() -> void:
	var s = fresh()
	s.game.time = 13 * 60.0
	var g = add_guest(s, "budget")
	g.early_state = "done"  # already told to wait for 3 PM
	var mood: float = g.mood
	s.game.tick(60.0)
	check(g.state == "queue" and s.minute_of_day() < 15 * 60.0, "no check-in before 3 PM")
	check(is_equal_approx(g.mood, mood) and g.wait == 0.0, "early guests don't lose patience before 3 PM")
	check(run_until(s, func(): return g.state == "staying"), "checked in after 3 PM")
	var mins := []
	for i in 40:
		var h = add_guest(s, "budget")
		if h != null:
			mins.append(h.checkout_minute)
			s.guests.erase(h.id)
			s.queue.erase(h.id)
	mins.sort()
	check(mins[0] >= 7 * 60.0 and mins[-1] <= 11 * 60.0, "checkout times fall between 7 and 11 AM")
	check(mins[-1] - mins[0] > 120.0, "checkout times are spread out, not all at once")


func test_no_vacancy_sign_state() -> void:
	var s = fresh()
	check(s.has_vacancy(), "empty motel has vacancy")
	for r in s.rooms:
		r.guest_id = 999
	check(not s.has_vacancy(), "all rooms taken -> no vacancy")
	s.rooms[4].guest_id = -1
	check(s.has_vacancy(), "one free room -> vacancy again")


func _early_guest(s, archetype := "budget"):
	s.game.time = 13 * 60.0
	var g = add_guest(s, archetype)
	check(run_until(s, func(): return g.state == "early_request", 60.0), "early guest asks to check in early")
	return g


func test_early_checkin_free() -> void:
	var s = fresh()
	var g = _early_guest(s)
	var mood: float = g.mood
	s.resolve_early(g.id, "free")
	check(g.mood > mood, "free early check-in makes the guest happier")
	check(run_until(s, func(): return g.state == "staying", 60.0) and s.minute_of_day() < 15 * 60.0, "checked in before 3 PM")


func test_early_checkin_refused() -> void:
	var s = fresh()
	var g = _early_guest(s)
	s.resolve_early(g.id, "no")
	check(g.state == "queue" and g.early_state == "done", "refused guest goes back to the line")
	s.game.tick(60.0)
	check(g.state == "queue", "and is not asked again or checked in before 3 PM")
	check(run_until(s, func(): return g.state == "staying", 200.0), "checks in after 3 PM")


func test_early_checkin_fee_and_haggle() -> void:
	var s = fresh()
	s.bal["early_checkin"]["haggle_chance"]["business"] = 0.0
	var g = _early_guest(s, "business")
	var cash: float = s.cash
	s.resolve_early(g.id, "fee")
	check(is_equal_approx(s.cash - cash, s.early_fee) and g.early_fee == s.early_fee, "fee charged")
	var t = fresh()
	t.bal["early_checkin"]["haggle_chance"]["budget"] = 1.0
	t.bal["early_checkin"]["pay_after_insist_chance"]["budget"] = 0.0
	var h = _early_guest(t, "budget")
	t.resolve_early(h.id, "fee")
	check(h.state == "early_request" and h.early_state == "haggling", "guest haggles over the fee")
	t.resolve_early(h.id, "fee")
	check(h.state == "queue" and h.notes.has("early_fee"), "insisting can make them refuse and wait, unhappy")
	var u = fresh()
	u.bal["early_checkin"]["haggle_chance"]["budget"] = 1.0
	var k = _early_guest(u, "budget")
	u.resolve_early(k.id, "fee")
	var c2: float = u.cash
	u.resolve_early(k.id, "free")
	check(is_equal_approx(u.cash, c2) and k.notes.has("early_checkin"), "waiving the fee after haggling is free")


func test_no_early_offer_without_clean_room() -> void:
	var s = fresh()
	for r in s.rooms:
		r.state = "dirty"
	s.game.time = 13 * 60.0
	var g = add_guest(s, "budget")
	s.game.tick(60.0)
	check(g.state == "queue" and g.early_state == "", "no early offer when no clean room is free")


# --------------------------------------------------------------------------- phase 2: hotel, bank, shifts, repairs

func hotel_game():
	var s = fresh()
	var g = s.game
	g.cash = 20000.0
	check(g.buy_property("hotel"), "sandbox can buy the hotel")
	var h = g.prop("hotel")
	h.arrivals = []
	return h


func test_buy_hotel_with_mortgage() -> void:
	var s = fresh()
	var g = s.game
	g.cash = 5000.0
	check(not g.buy_property("hotel"), "can't buy without the down payment")
	g.cash = 10000.0
	var worth: float = g.net_worth()
	check(g.buy_property("hotel"), "bought with 20% down")
	var price: float = g.bal["properties"]["hotel"]["price"]
	check(is_equal_approx(g.cash, 10000.0 - price * 0.2), "paid the down payment")
	check(g.loans.size() == 1 and g.loans[0]["kind"] == "mortgage" and is_equal_approx(g.debt(), price * 0.8), "mortgage for the rest")
	check(is_equal_approx(g.net_worth(), worth), "buying doesn't change net worth on day one")
	var h = g.prop("hotel")
	check(h.rooms.size() == 14 and h.layout.kind == "hotel", "hotel has its own layout")
	check(h.broken_rooms().size() == int(g.bal["properties"]["hotel"]["start_broken"]), "hotel starts with broken rooms")
	check(h.rating() < s.rating(), "hotel starts with a worse rating")
	check(g.listings().is_empty(), "nothing else for sale")


func test_loans_amortize() -> void:
	var s = fresh()
	var g = s.game
	check(g.credit_limit() == 10000.0, "credit limit is half the motel's value")
	check(not g.borrow(20000.0), "can't borrow over the limit")
	var cash: float = g.cash
	check(g.borrow(3000.0), "borrowed")
	check(is_equal_approx(g.cash, cash + 3000.0) and is_equal_approx(g.debt(), 3000.0), "cash and debt go up")
	var days := int(g.bal["bank"]["loan_days"])
	var expect: float = Game.payment_for(3000.0, g.bal["bank"]["loan_rate"], days)
	check(is_equal_approx(g.loans[0]["payment"], expect), "daily payment is amortized")
	g.cash = 100000.0
	for d in days:
		g._pay_loans()
	check(g.loans.is_empty(), "loan is paid off after its term")
	check(is_equal_approx(100000.0 - g.cash, expect * days), "total paid = payment x days")
	check(expect * days > 3000.0, "interest costs something")
	g.borrow(1000.0)
	check(g.repay(g.loans[0]["id"], 400.0) and is_equal_approx(g.debt(), 600.0), "partial repayment")
	check(g.repay(g.loans[0]["id"], 10000.0) and g.loans.is_empty(), "full repayment closes the loan")


func test_shifts_send_staff_home() -> void:
	var s = fresh()
	s.candidates = [{"role": "clerk", "name": "Eve Ning", "wage": 55.0}]
	s.hire(0)
	var w = s.workers[-1]
	check(w.shift == "evening", "clerks start on the evening shift")
	s.game.time = 10 * 60.0
	s.game.tick(1.0)
	check(not w.present, "off shift in the morning")
	s.game.time = 15 * 60.0 - 1.0
	s.game.tick(2.0)
	check(w.present, "shows up at 3 PM")
	s.game.time = 23 * 60.0 - 1.0
	s.game.tick(30.0)
	check(not w.present and not s.stations.has(w.id), "goes home after 11 PM and frees the desk")
	s.set_shift(w.id, "night")
	s.game.tick(1.0)
	check(w.present, "night shift works after 11 PM")
	var cov: Dictionary = s.coverage("clerk")
	check(cov["night"] == 1 and cov["evening"] == 0, "coverage counts staff per shift")


func test_clerk_finishes_guest_before_leaving() -> void:
	var s = fresh()
	s.owner().orders.clear()
	s.owner().job = {}
	s.stations = [-1, -1]
	s.candidates = [{"role": "clerk", "name": "Last Call", "wage": 55.0}]
	s.hire(0)
	s.game.time = 22 * 60.0 + 50.0
	var g = add_guest(s, "budget")
	g.patience = 1000.0
	check(run_until(s, func(): return g.state == "at_desk", 30.0), "clerk starts serving")
	check(run_until(s, func(): return g.state in ["to_room", "staying"], 30.0), "clerk finishes the check-in after 11 PM")


func test_breakage_and_repairs() -> void:
	var s = fresh()
	s.cfg["break_chance"] = 1.0
	var g = add_guest(s, "business")
	check(run_until(s, func(): return g.state == "staying"), "checked in")
	var room: int = g.room
	check(run_until(s, func(): return s.rooms[room].broken != "", 2880.0), "something broke at checkout")
	s.cfg["break_chance"] = 0.0
	s.rooms[room].state = "clean"
	for r in s.rooms:
		if r.index != room and r.type == s.rooms[room].type:
			r.guest_id = 999
	check(s.free_rooms_for(s.rooms[room].type) == 0, "a broken room can't be rented")
	add_guest(s, "business")
	check(s.stats["lost_vacancy"] == 1, "guests are turned away if only broken rooms are free")
	s.owner().orders.clear()
	check(s.order_fix(room), "owner can fix it")
	var cash: float = s.cash
	check(run_until(s, func(): return s.rooms[room].broken == "", 200.0), "owner fixed the room")
	check(is_equal_approx(cash - s.cash, s.bal["repair_parts_cost"]), "repairs cost parts")


func test_maintenance_fixes_hotel_rooms() -> void:
	var h = hotel_game()
	var broken: int = h.broken_rooms().size()
	check(broken > 0, "hotel has broken rooms")
	h.candidates = [{"role": "maintenance", "name": "Fix-It Felix", "wage": 60.0}]
	h.hire(0)
	h.game.time = 7 * 60.0
	var mins: float = h.bal["task_minutes"]["repair"] * broken + 120.0
	check(run_until(h, func(): return h.broken_rooms().is_empty(), mins), "maintenance tech fixed every room")


func test_owner_drives_between_properties() -> void:
	var h = hotel_game()
	var g = h.game
	var motel = g.properties[0]
	g.owner_w.orders.clear()
	h.order_desk()
	check(g.owner_prop() == 0, "owner still at the motel")
	check(run_until(h, func(): return g.owner_prop() == -1, 60.0), "owner drives off")
	var t0: float = g.time
	check(run_until(h, func(): return g.owner_prop() == 1, 200.0), "owner arrives at the hotel")
	check(g.time - t0 >= g.bal["travel_minutes"] - 1.0, "driving takes time")
	check(run_until(h, func(): return h.stations.has(g.owner_w.id), 60.0), "owner works the hotel desk")
	check(not motel.workers.has(g.owner_w), "owner is not at the motel any more")
	var guest = add_guest(h, "couple")
	check(guest != null and h.rooms[0].type == "queen", "hotel guests")
	check(run_until(h, func(): return guest.state == "staying"), "couple checked in at the hotel")
	check(h.rooms[guest.room].type == "suite", "couples get a suite")


func test_hotel_day_report_and_bank() -> void:
	var h = hotel_game()
	var g = h.game
	var debt: float = g.debt()
	g.time = 1439.0
	g.tick(2.0)
	var r: Dictionary = g.reports[-1]
	check(r["props"].size() == 2, "report covers both properties")
	check(r["interest"] > 0.0 and g.debt() < debt, "mortgage payment made at midnight")
	check(is_equal_approx(r["net_worth"], g.net_worth()), "net worth reported")


func test_save_load_two_properties() -> void:
	var h = hotel_game()
	var g = h.game
	h.order_desk()
	add_guest(h, "family")
	g.tick(30.0)
	var path := "user://test_save2.txt"
	check(g.save_to(path), "saved")
	var t = Game.new()
	check(t.load_from(g.bal, path), "loaded")
	check(t.properties.size() == 2 and t.loans.size() == 1, "properties and loans restored")
	check(t.owner_prop() == g.owner_prop() and t.travel.size() == g.travel.size(), "owner location restored")
	g.tick(300.0)
	t.tick(300.0)
	check(is_equal_approx(t.cash, g.cash) and t.prop("hotel").guests.size() == h.guests.size(), "loaded game continues identically")
	check(t.owner_prop() == 1, "owner made it to the hotel in the loaded game")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_load_milestone1_save() -> void:
	# A minimal save in the old (version 1) format.
	var s = fresh()
	var old := {
		"version": 1, "mode": "campaign", "time": 2000.0, "cash": 4321.0, "rates": {"single": 66.0, "double": 95.0},
		"early_fee": 15.0, "queue": [], "stations": [5, -1], "reviews": [{"stars": 4, "cause": "general_good", "text": "ok", "author": "A", "archetype": "budget", "day": 1}],
		"arrivals": [], "candidates": [], "ledger": {"revenue": 0.0, "refunds": 0.0, "wages": 0.0, "upkeep": 0.0, "checkins": 0, "checkouts": 0, "walkouts": 0, "turned_away": 0, "stars": []},
		"reports": [{"day": 1, "revenue": 300.0, "net": 200.0, "cash": 1700.0}], "stats": {"served": 3, "walkouts": 0, "lost_price": 0, "lost_vacancy": 0, "lost_line": 0},
		"next_id": 10, "neg_days": 0, "game_over": "", "rng_state": 1,
		"rooms": s.rooms.map(func(r): return inst_to_dict(r)),
		"workers": [
			{"@path": "res://scripts/sim/worker.gd", "@subpath": "", "id": 5, "role": "owner", "name": "You", "wage": 0.0, "pos": Vector2(1, 0), "path": [], "target": Vector2i(-1, -1), "job": {"type": "desk", "station": 0}, "orders": [], "serving": -1, "progress": 0.0, "days_employed": 0},
			{"@path": "res://scripts/sim/worker.gd", "@subpath": "", "id": 6, "role": "housekeeper", "name": "Hk", "wage": 45.0, "pos": Vector2(3, 1), "path": [], "target": Vector2i(-1, -1), "job": {}, "orders": [], "serving": -1, "progress": 0.0, "days_employed": 2},
		],
		"guests": [],
	}
	var g = Game.new()
	g.from_save(s.bal, old)
	check(g.properties.size() == 1 and g.properties[0].key == "motel", "old save becomes the motel")
	check(is_equal_approx(g.cash, 4321.0) and g.properties[0].rates["single"] == 66.0, "cash and rates kept")
	check(g.owner_prop() == 0 and g.properties[0].staff_count("housekeeper") == 1, "owner and staff kept")
	check(g.reports[0]["props"][0]["revenue"] == 300.0, "old reports converted")
	g.tick(1440.0)
	check(g.reports.size() == 2, "old game keeps running")


func test_bots_play_full_days() -> void:
	# Smoke test: the pro bot runs a sandbox game through buying and staffing the hotel.
	var s = fresh()
	var g = s.game
	g.cash = 15000.0
	for i in 288 * 3:
		Bot.play(g, "pro")
		g.tick(5.0)
	check(g.owns("hotel"), "bot bought the hotel")
	check(g.prop("hotel").staff().size() >= 4, "bot staffed the hotel")
	check(g.prop("hotel").stats["served"] > 10, "hotel served guests")
