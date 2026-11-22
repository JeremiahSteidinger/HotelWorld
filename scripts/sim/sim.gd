extends RefCounted
## Core motel simulation: clock, guests, rooms, staff, desk line, money, reviews.
## Pure logic (no nodes) so it can be unit-tested and fast-forwarded headless.
## Time unit: game minutes. `time` counts minutes since day 1, 00:00.

const Layout := preload("res://scripts/sim/layout.gd")
const Reviews := preload("res://scripts/sim/reviews.gd")
const Guest := preload("res://scripts/sim/guest.gd")
const Room := preload("res://scripts/sim/room.gd")
const Worker := preload("res://scripts/sim/worker.gd")

const MIN_PER_DAY := 1440.0
const SAVE_VERSION := 1

const FIRST_NAMES := ["Pat", "Sam", "Alex", "Jo", "Robin", "Casey", "Morgan", "Jamie", "Riley", "Taylor",
	"Jordan", "Avery", "Quinn", "Drew", "Sky", "Kai", "Rene", "Lou", "Max", "Ari", "Dale", "Frankie",
	"Bo", "Charlie", "Toni", "Mel", "Rory", "Jules", "Sasha", "Remy"]
const LAST_NAMES := ["Wheeler", "Roadman", "Milestone", "Highway", "Dusty", "Pickett", "Gravel",
	"Overnight", "Snooze", "Pillow", "Turnpike", "Motor", "Lugg", "Napper", "Keyes", "Bellhop"]
const QUIRKS := ["collects motel soaps", "is on a cross-country donut tour", "brought a pet iguana",
	"is writing a travel blog", "snores like a truck", "is avoiding a family reunion",
	"is chasing a solar eclipse", "only drinks tap water", "is very into ice machines",
	"has a suspicious amount of luggage", "is a retired rodeo clown", "is visiting the world's largest ball of twine"]

var bal: Dictionary = {}
var rng := RandomNumberGenerator.new()
var mode := "campaign"  # or "sandbox"

var time := 0.0
var cash := 0.0
var rates := {}
var rooms: Array = []
var guests := {}        # id -> Guest
var workers: Array = []
var queue: Array = []   # guest ids in the desk line, front first
var stations := [-1, -1]
var reviews: Array = []
var arrivals: Array = []      # absolute minute times of today's remaining arrivals
var candidates: Array = []    # [{role, name, wage}]
var ledger := {}
var reports: Array = []
var stats := {}
var next_id := 1
var neg_days := 0
var game_over := ""     # "", "won", "bankrupt", "out_of_time"
var events: Array = []
var _full_logged := false  # only announce "NO VACANCY" once each time the motel fills up  # notifications for the UI: {type, text, ...}


# --------------------------------------------------------------------------- setup

static func load_balance(path := "res://data/balance.json") -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open balance file %s" % path)
		return {}
	return JSON.parse_string(f.get_as_text())


func new_game(balance: Dictionary, game_mode := "campaign", seed_value := -1) -> void:
	bal = balance
	mode = game_mode
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	time = bal["start_hour"] * 60.0
	cash = bal["start_cash"]
	rates = {}
	for t in bal["room_types"]:
		rates[t] = float(bal["room_types"][t]["default_rate"])
	rooms = []
	var types: Array = bal["rooms"]
	for i in types.size():
		var r = Room.new()
		r.index = i
		r.type = types[i]
		rooms.append(r)
	guests = {}
	workers = []
	queue = []
	stations = [-1, -1]
	reviews = []
	reports = []
	next_id = 1
	neg_days = 0
	game_over = ""
	events = []
	stats = {"served": 0, "walkouts": 0, "lost_price": 0, "lost_vacancy": 0, "lost_line": 0}
	_reset_ledger()
	var owner = _new_worker("owner", "You", 0.0)
	owner.pos = Vector2(Layout.STATIONS[0])
	owner.orders.append({"type": "desk"})
	_schedule_arrivals()
	_refresh_candidates()


func _new_worker(role: String, worker_name: String, wage: float):
	var w = Worker.new()
	w.id = _take_id()
	w.role = role
	w.name = worker_name
	w.wage = wage
	w.pos = Vector2(Layout.STAFF_SPAWN)
	workers.append(w)
	return w


func _take_id() -> int:
	next_id += 1
	return next_id - 1


func _reset_ledger() -> void:
	ledger = {"revenue": 0.0, "refunds": 0.0, "wages": 0.0, "upkeep": 0.0,
		"checkins": 0, "checkouts": 0, "walkouts": 0, "turned_away": 0, "stars": []}


# --------------------------------------------------------------------------- queries

func day() -> int:
	return int(time / MIN_PER_DAY) + 1


func minute_of_day() -> float:
	return fmod(time, MIN_PER_DAY)


func clock_text() -> String:
	var m := int(minute_of_day())
	var h := m / 60
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m % 60, suffix]


func rating() -> float:
	var r: Dictionary = bal["rating"]
	return Reviews.rating(reviews, r["start"], int(r["window"]), int(r["prior_weight"]))


func owner():
	for w in workers:
		if w.role == "owner":
			return w
	return null


func get_worker(id: int):
	for w in workers:
		if w.id == id:
			return w
	return null


func staff() -> Array:
	return workers.filter(func(w): return w.role != "owner")


func staff_count(role: String) -> int:
	return workers.filter(func(w): return w.role == role).size()


func daily_wages() -> float:
	var total := 0.0
	for w in staff():
		total += w.wage
	return total


func daily_upkeep() -> float:
	var total: float = bal["base_upkeep"]
	for r in rooms:
		total += bal["room_types"][r.type]["upkeep"]
	return total


func willingness(arch_key: String) -> float:
	var d: Dictionary = bal["demand"]
	return bal["archetypes"][arch_key]["budget"] * (d["wtp_base"] + d["wtp_per_star"] * rating())


func expected_arrivals() -> float:
	var d: Dictionary = bal["demand"]
	return d["base_arrivals"] * (d["rating_base"] + d["rating_weight"] * rating())


## Check-in opens at checkin_hour (3 PM). Late-night arrivals (after midnight) can still check in.
func check_in_open() -> bool:
	var m := minute_of_day()
	return m >= bal["checkin_hour"] * 60.0 or m < bal["checkout_start_hour"] * 60.0


func is_early(g) -> bool:
	return g.purpose == "checkin" and not check_in_open()


## True while at least one room is neither occupied nor reserved. Drives the roadside sign.
func has_vacancy() -> bool:
	for r in rooms:
		if r.guest_id == -1:
			return true
	return false


func free_rooms_for(room_type: String) -> int:
	var n := 0
	for r in rooms:
		if r.type == room_type and r.guest_id == -1:
			n += 1
	for gid in guests:
		var g = guests[gid]
		if g.purpose == "checkin" and g.room == -1 and g.room_type == room_type and g.state in ["queue", "to_desk", "at_desk", "discount"]:
			n -= 1
	return n


func pending_discounts() -> Array:
	var out := []
	for gid in guests:
		if guests[gid].state == "discount":
			out.append(guests[gid])
	return out


func waiting_guests_for_room(i: int) -> bool:
	var gid: int = rooms[i].guest_id
	return gid != -1 and guests.has(gid) and guests[gid].state == "waiting_room"


func _event(type: String, text: String, extra := {}) -> void:
	var e := {"type": type, "text": text, "day": day(), "time": clock_text()}
	e.merge(extra)
	events.append(e)


func pop_events() -> Array:
	var e := events
	events = []
	return e


# --------------------------------------------------------------------------- player actions

func order_desk() -> void:
	var o = owner()
	if o.job.get("type", "") == "desk" and o.orders.is_empty():
		return
	o.orders.append({"type": "desk"})


func order_clean(room_index: int) -> bool:
	var r = rooms[room_index]
	if r.state != "dirty":
		_event("info", "Room %d doesn't need cleaning." % (room_index + 1))
		return false
	if r.cleaner_id != -1 and r.cleaner_id != owner().id:
		_event("info", "Someone is already cleaning room %d." % (room_index + 1))
		return false
	var o = owner()
	for ord in o.orders:
		if ord["type"] == "clean" and ord["room"] == room_index:
			return false
	if o.job.get("type", "") == "clean" and o.job["room"] == room_index:
		return false
	o.orders.append({"type": "clean", "room": room_index})
	return true


func clear_orders() -> void:
	owner().orders.clear()


func set_rate(room_type: String, value: float) -> void:
	rates[room_type] = clampf(roundf(value), 10.0, 500.0)


func hire(candidate_index: int) -> bool:
	if candidate_index < 0 or candidate_index >= candidates.size():
		return false
	var c: Dictionary = candidates[candidate_index]
	if staff_count(c["role"]) >= int(bal["staff"][c["role"]]["max"]):
		_event("info", "You can't have more than %d of that role yet." % int(bal["staff"][c["role"]]["max"]))
		return false
	_new_worker(c["role"], c["name"], c["wage"])
	candidates.remove_at(candidate_index)
	_event("staff", "%s joined as %s ($%d/day)." % [c["name"], bal["staff"][c["role"]]["name"], int(c["wage"])])
	return true


func fire(worker_id: int, quit := false) -> void:
	var w = get_worker(worker_id)
	if w == null or w.role == "owner":
		return
	_release_worker(w)
	workers.erase(w)
	if quit:
		_event("staff", "%s quit. They felt underpaid." % w.name)
	else:
		_event("staff", "%s was let go." % w.name)


func set_wage(worker_id: int, wage: float) -> void:
	var w = get_worker(worker_id)
	if w != null and w.role != "owner":
		w.wage = clampf(roundf(wage), 0.0, 1000.0)


func resolve_discount(guest_id: int, accept: bool) -> void:
	if not guests.has(guest_id):
		return
	var g = guests[guest_id]
	if g.state != "discount":
		return
	var d: Dictionary = bal["discount"]
	var stage: String = g.discount_stage
	g.discount_stage = ""
	if accept:
		g.note("got_discount", d["accept_mood"])
	else:
		g.note("refused_discount", d["refuse_mood"])
		g.discount_pct = 0
	if stage == "checkin":
		_finish_checkin(g)
	else:
		_finish_checkout(g)


# --------------------------------------------------------------------------- main loop

func tick(minutes: float) -> void:
	while minutes > 0.0 and game_over == "":
		var to_midnight := MIN_PER_DAY - minute_of_day()
		var step := minf(minf(minutes, 0.5), to_midnight)
		_step(step)
		minutes -= step
		if minute_of_day() < 0.0001 or MIN_PER_DAY - minute_of_day() < 0.0001:
			time = roundf(time / MIN_PER_DAY) * MIN_PER_DAY
			_end_of_day()


func _step(dt: float) -> void:
	time += dt
	if _full_logged and has_vacancy():
		_full_logged = false
	while not arrivals.is_empty() and arrivals[0] <= time:
		arrivals.pop_front()
		_arrive()
	for gid in guests.keys():
		if guests.has(gid):
			_update_guest(guests[gid], dt)
	for w in workers.duplicate():
		_update_worker(w, dt)
	_cleanup_guests()


# --------------------------------------------------------------------------- movement

func _move(entity, dt: float) -> void:
	var budget: float = bal["walk_cells_per_minute"] * dt
	while budget > 0.0 and not entity.path.is_empty():
		var nxt := Vector2(entity.path[0])
		var dist: float = entity.pos.distance_to(nxt)
		if dist <= budget:
			entity.pos = nxt
			entity.path.pop_front()
			budget -= dist
		else:
			entity.pos += (nxt - entity.pos) / dist * budget
			budget = 0.0


func _go(entity, goal: Vector2i) -> void:
	if entity.target == goal and (not entity.path.is_empty() or entity.cell() == goal):
		return
	entity.target = goal
	var start: Vector2i = entity.cell()
	if not entity.path.is_empty():
		start = entity.path[0]
		entity.path = [start]
		entity.path.append_array(Layout.find_path(start, goal))
	else:
		entity.path = Layout.find_path(start, goal)
		if entity.path.is_empty() and Vector2(goal) != entity.pos:
			entity.path = [goal]


func _at(entity, goal: Vector2i) -> bool:
	return entity.path.is_empty() and entity.pos.distance_to(Vector2(goal)) < 0.01


# --------------------------------------------------------------------------- guests

func _schedule_arrivals() -> void:
	arrivals = []
	var d: Dictionary = bal["demand"]
	var count := int(round(expected_arrivals() * rng.randf_range(0.8, 1.2)))
	var day_start := (day() - 1) * MIN_PER_DAY
	for i in count:
		var t := day_start + rng.randf_range(d["arrival_start_hour"] * 60.0, d["arrival_end_hour"] * 60.0)
		if t > time:
			arrivals.append(t)
	arrivals.sort()


func _pick_archetype() -> String:
	var total := 0.0
	for k in bal["archetypes"]:
		total += bal["archetypes"][k]["weight"]
	var roll := rng.randf() * total
	for k in bal["archetypes"]:
		roll -= bal["archetypes"][k]["weight"]
		if roll <= 0.0:
			return k
	return bal["archetypes"].keys()[0]


func _arrive() -> void:
	var key := _pick_archetype()
	var a: Dictionary = bal["archetypes"][key]
	var room_type: String = a["room"]
	var wtp := willingness(key) * rng.randf_range(0.85, 1.15)
	var guest_name := "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	if key == "family":
		guest_name = "The %s family" % LAST_NAMES[rng.randi() % LAST_NAMES.size()]
	if rates[room_type] > wtp * bal["demand"]["walkaway_price_ratio"]:
		stats["lost_price"] += 1
		ledger["turned_away"] += 1
		_event("lost", "%s saw your $%d %s rate and kept driving." % [guest_name, int(rates[room_type]), bal["room_types"][room_type]["name"]])
		return
	if free_rooms_for(room_type) <= 0:
		stats["lost_vacancy"] += 1
		ledger["turned_away"] += 1
		if has_vacancy():
			_event("lost", "No %s room free for %s." % [bal["room_types"][room_type]["name"].to_lower(), guest_name])
		elif not _full_logged:
			_full_logged = true
			_event("lost", "Every room is taken. The sign now says NO VACANCY and guests drive past.")
		return
	if queue.size() >= int(bal["max_line"]):
		stats["lost_line"] += 1
		ledger["turned_away"] += 1
		_event("lost", "%s saw the line out the door and left." % guest_name)
		return
	var g = Guest.new()
	g.id = _take_id()
	g.archetype = key
	g.name = guest_name
	g.room_type = room_type
	g.wtp = wtp
	g.patience = a["patience"] * rng.randf_range(0.8, 1.2)
	g.nights = rng.randi_range(int(a["nights_min"]), int(a["nights_max"]))
	g.mood = bal["mood"]["start"] + rng.randf_range(-8.0, 8.0)
	g.arrival_day = day()
	g.checkout_day = day() + g.nights
	g.checkout_minute = rng.randf_range(bal["checkout_start_hour"] * 60.0, (bal["checkout_end_hour"] - 0.5) * 60.0)
	g.quirk = QUIRKS[rng.randi() % QUIRKS.size()]
	g.pos = Vector2(Layout.GUEST_SPAWN)
	g.state = "queue"
	g.purpose = "checkin"
	guests[g.id] = g
	queue.append(g.id)
	_event("arrive", "%s arrived (%s, %d night%s)%s." % [g.name, a["name"], g.nights, "" if g.nights == 1 else "s",
		"" if check_in_open() else " and will wait for 3 PM check-in"], {"guest": g.id})


func _update_guest(g, dt: float) -> void:
	_move(g, dt)
	var m: Dictionary = bal["mood"]
	match g.state:
		"queue":
			var idx := queue.find(g.id)
			_go(g, Layout.queue_slot(idx))
			if is_early(g):
				# Guests who arrive before check-in time wait patiently: they expected to.
				return
			g.wait += dt
			if g.wait > m["wait_grace"]:
				g.note("long_wait", -m["wait_per_minute"] * dt)
			if g.wait > g.patience:
				if g.purpose == "checkin":
					_walkout(g)
				else:
					_leave_without_checkout(g)
		"to_desk":
			g.wait += dt
			for i in stations.size():
				var w = get_worker(stations[i])
				if w != null and w.serving == g.id and _at(g, Layout.SERVICE_SPOTS[i]):
					g.state = "at_desk"
		"waiting_room":
			g.wait += dt
			if g.wait > m["wait_grace"]:
				g.note("room_not_ready", -m["wait_per_minute"] * dt)
			var r = rooms[g.room]
			if r.state == "clean":
				g.state = "to_room"
				_go(g, Layout.room_bed(g.room))
			elif g.wait > g.patience * 1.5:
				_refund_and_leave(g)
		"to_room":
			if _at(g, Layout.room_bed(g.room)):
				g.state = "staying"
				rooms[g.room].state = "occupied"
		"staying":
			if day() > g.checkout_day or (day() == g.checkout_day and minute_of_day() >= g.checkout_minute):
				_start_checkout(g)
		"discount":
			g.discount_timer += dt
			if g.discount_timer > bal["discount"]["timeout"]:
				_event("info", "%s gave up waiting for an answer about their discount." % g.name)
				resolve_discount(g.id, false)
		"leaving":
			if _at(g, Layout.EXIT_CELL):
				g.state = "gone"


func _start_checkout(g) -> void:
	var r = rooms[g.room]
	r.state = "dirty"
	r.guest_id = -1
	r.clean_progress = 0.0
	g.pos = Vector2(Layout.room_door(g.room))
	g.path = []
	g.target = Vector2i(-1, -1)
	g.state = "queue"
	g.purpose = "checkout"
	g.wait = 0.0
	queue.append(g.id)
	_event("checkout", "%s is heading to the desk to check out. Room %d needs cleaning." % [g.name, g.room + 1], {"guest": g.id, "room": g.room})


func _walkout(g) -> void:
	queue.erase(g.id)
	stats["walkouts"] += 1
	ledger["walkouts"] += 1
	_add_review(Reviews.make(g, day(), rng, "walked_out"))
	_event("angry", "%s got tired of waiting and left. (1 star)" % g.name, {"guest": g.id})
	_send_away(g)


func _leave_without_checkout(g) -> void:
	queue.erase(g.id)
	g.note("left_checkout", -15.0)
	_add_review(Reviews.make(g, day(), rng))
	_event("angry", "%s gave up on checking out and just left." % g.name, {"guest": g.id})
	_send_away(g)


func _refund_and_leave(g) -> void:
	var r = rooms[g.room]
	r.guest_id = -1
	cash -= g.paid
	ledger["refunds"] += g.paid
	g.note("room_not_ready", -100.0)
	_add_review(Reviews.make(g, day(), rng))
	_event("angry", "%s demanded a refund ($%d): their room was never ready." % [g.name, int(g.paid)], {"guest": g.id})
	g.paid = 0.0
	_send_away(g)


func _send_away(g) -> void:
	g.state = "leaving"
	g.target = Vector2i(-1, -1)
	_go(g, Layout.EXIT_CELL)


func _cleanup_guests() -> void:
	for gid in guests.keys():
		if guests[gid].state == "gone":
			guests.erase(gid)


func _add_review(r: Dictionary) -> void:
	reviews.append(r)
	ledger["stars"].append(r["stars"])
	_event("review", "%s %s: \"%s\"" % ["★".repeat(r["stars"]), r["author"], r["text"]], {"stars": r["stars"]})


# --------------------------------------------------------------------------- desk service

func _best_room_for(room_type: String) -> int:
	var best := -1
	var best_score := -1.0
	for r in rooms:
		if r.type != room_type or r.guest_id != -1:
			continue
		var score := 0.0
		if r.state == "clean":
			score = 10.0
		elif r.cleaner_id != -1:
			score = 1.0 + r.clean_progress
		if score > best_score:
			best_score = score
			best = r.index
	return best


func _complete_service(w, g) -> void:
	if g.purpose == "checkin":
		_process_checkin(g)
	else:
		_process_checkout(g)


func _maybe_ask_discount(g, stage: String) -> bool:
	var d: Dictionary = bal["discount"]
	if g.asked_discount or g.mood >= d["threshold"] or rng.randf() > d["chance"]:
		return false
	g.asked_discount = true
	g.discount_pct = rng.randi_range(int(d["pct_min"]) / 5, int(d["pct_max"]) / 5) * 5
	g.discount_stage = stage
	g.discount_timer = 0.0
	g.state = "discount"
	var why := "the long wait" if g.notes.get("long_wait", 0.0) <= g.notes.get("room_not_ready", 0.0) else "their room not being ready"
	if g.notes.get("overpriced", 0.0) < minf(g.notes.get("long_wait", 0.0), g.notes.get("room_not_ready", 0.0)):
		why = "the price"
	_event("discount", "%s is unhappy about %s and asks for %d%% off." % [g.name, why, g.discount_pct], {"guest": g.id})
	return true


func _process_checkin(g) -> void:
	var m: Dictionary = bal["mood"]
	g.room = _best_room_for(g.room_type)
	if g.room == -1:
		g.note("room_not_ready", -40.0)
		stats["walkouts"] += 1
		ledger["walkouts"] += 1
		_add_review(Reviews.make(g, day(), rng))
		_event("angry", "Overbooked! %s had no room and left." % g.name, {"guest": g.id})
		_release_desk_for(g)
		_send_away(g)
		return
	rooms[g.room].guest_id = g.id
	if g.wait <= m["wait_grace"]:
		g.note("fast_service", m["fast_service_bonus"])
	var ratio: float = rates[g.room_type] / g.wtp
	if ratio > 1.0:
		g.note("overpriced", -(ratio - 1.0) * m["price_penalty"])
	elif ratio < m["value_ratio"]:
		g.note("great_value", m["value_bonus"])
	g.paid = rates[g.room_type] * g.nights
	if _maybe_ask_discount(g, "checkin"):
		return
	_finish_checkin(g)


func _finish_checkin(g) -> void:
	var price: float = g.paid * (1.0 - g.discount_pct / 100.0)
	g.paid = price
	cash += price
	ledger["revenue"] += price
	ledger["checkins"] += 1
	stats["served"] += 1
	g.wait = 0.0
	_release_desk_for(g)
	var r = rooms[g.room]
	if r.state == "clean":
		g.state = "to_room"
		_go(g, Layout.room_bed(g.room))
		_event("checkin", "%s checked in to room %d for $%d." % [g.name, g.room + 1, int(price)], {"guest": g.id})
	else:
		g.state = "waiting_room"
		_go(g, Layout.WAIT_SPOTS[g.id % Layout.WAIT_SPOTS.size()])
		_event("warn", "%s checked in, but room %d isn't clean yet! They're waiting in the lobby." % [g.name, g.room + 1], {"guest": g.id, "room": g.room})


func _process_checkout(g) -> void:
	if _maybe_ask_discount(g, "checkout"):
		return
	_finish_checkout(g)


func _finish_checkout(g) -> void:
	if g.discount_pct > 0:
		var refund: float = g.paid * g.discount_pct / 100.0
		cash -= refund
		ledger["refunds"] += refund
	ledger["checkouts"] += 1
	_add_review(Reviews.make(g, day(), rng))
	_release_desk_for(g)
	_send_away(g)


func _release_desk_for(g) -> void:
	for w in workers:
		if w.serving == g.id:
			w.serving = -1
			w.progress = 0.0


# --------------------------------------------------------------------------- workers

func _update_worker(w, dt: float) -> void:
	_move(w, dt)
	if w.job.is_empty():
		_choose_job(w)
	match w.job.get("type", ""):
		"desk":
			_do_desk(w, dt)
		"clean":
			_do_clean(w, dt)
		"":
			if w.role != "owner" and w.arrived():
				_go(w, Layout.IDLE_SPOT)


func _choose_job(w) -> void:
	match w.role:
		"owner":
			while not w.orders.is_empty() and w.job.is_empty():
				var o: Dictionary = w.orders.pop_front()
				if o["type"] == "desk":
					w.job = {"type": "desk", "station": -1}
				elif o["type"] == "clean":
					var r = rooms[o["room"]]
					if r.state == "dirty" and (r.cleaner_id == -1 or r.cleaner_id == w.id):
						r.cleaner_id = w.id
						w.job = {"type": "clean", "room": o["room"]}
		"clerk":
			w.job = {"type": "desk", "station": -1}
		"housekeeper":
			var best := -1
			var best_score := -INF
			for r in rooms:
				if r.state != "dirty" or r.cleaner_id != -1:
					continue
				var score: float = -w.pos.distance_to(Vector2(Layout.room_work_spot(r.index)))
				if r.guest_id != -1:
					score += 100.0  # someone is waiting for this room
				if score > best_score:
					best_score = score
					best = r.index
			if best != -1:
				rooms[best].cleaner_id = w.id
				w.job = {"type": "clean", "room": best}


func _do_desk(w, dt: float) -> void:
	var s: int = w.job["station"]
	if s == -1:
		for i in stations.size():
			if stations[i] == -1 or stations[i] == w.id:
				s = i
				break
		if s == -1:
			# Desk is full: an owner with other orders moves on, others wait.
			if w.role == "owner" and not w.orders.is_empty():
				w.job = {}
			elif w.arrived():
				_go(w, Layout.IDLE_SPOT)
			return
		stations[s] = w.id
		w.job["station"] = s
	_go(w, Layout.STATIONS[s])
	if not _at(w, Layout.STATIONS[s]):
		return
	if w.serving == -1:
		if w.role == "owner" and not w.orders.is_empty():
			stations[s] = -1
			w.job = {}
			return
		var next := -1
		for i in queue.size():
			if not is_early(guests[queue[i]]):
				next = i
				break
		if next != -1:
			var g = guests[queue[next]]
			queue.remove_at(next)
			g.state = "to_desk"
			_go(g, Layout.SERVICE_SPOTS[s])
			w.serving = g.id
			w.progress = 0.0
		return
	if not guests.has(w.serving):
		w.serving = -1
		return
	var g = guests[w.serving]
	if g.state != "at_desk":
		return
	w.progress += dt
	var need: float = bal["task_minutes"]["check_in" if g.purpose == "checkin" else "check_out"]
	if w.progress >= need:
		_complete_service(w, g)


func _do_clean(w, dt: float) -> void:
	var r = rooms[w.job["room"]]
	if r.state != "dirty" or r.cleaner_id != w.id:
		w.job = {}
		return
	var spot := Layout.room_work_spot(r.index)
	_go(w, spot)
	if not _at(w, spot):
		return
	r.clean_progress += dt / float(bal["task_minutes"]["clean"])
	if r.clean_progress >= 1.0:
		r.clean_progress = 0.0
		r.state = "clean"
		r.cleaner_id = -1
		w.job = {}
		if waiting_guests_for_room(r.index):
			_event("clean", "Room %d is clean. %s can finally go in." % [r.index + 1, guests[r.guest_id].name])


func _release_worker(w) -> void:
	for i in stations.size():
		if stations[i] == w.id:
			stations[i] = -1
	for r in rooms:
		if r.cleaner_id == w.id:
			r.cleaner_id = -1
	if w.serving != -1 and guests.has(w.serving):
		var g = guests[w.serving]
		if g.state in ["to_desk", "at_desk"]:
			g.state = "queue"
			queue.push_front(g.id)
	w.serving = -1
	w.job = {}


# --------------------------------------------------------------------------- day cycle

func _end_of_day() -> void:
	var ended_day := day() - 1
	var wages := daily_wages()
	var upkeep := daily_upkeep()
	cash -= wages + upkeep
	ledger["wages"] = wages
	ledger["upkeep"] = upkeep
	var stars: Array = ledger["stars"]
	var avg := 0.0
	for s in stars:
		avg += s
	avg = avg / stars.size() if not stars.is_empty() else 0.0
	var report := {
		"day": ended_day,
		"revenue": ledger["revenue"],
		"refunds": ledger["refunds"],
		"wages": wages,
		"upkeep": upkeep,
		"net": ledger["revenue"] - ledger["refunds"] - wages - upkeep,
		"cash": cash,
		"checkins": ledger["checkins"],
		"checkouts": ledger["checkouts"],
		"walkouts": ledger["walkouts"],
		"turned_away": ledger["turned_away"],
		"reviews": stars.size(),
		"avg_stars": avg,
		"rating": rating(),
		"quits": [],
	}
	for w in staff():
		w.days_employed += 1
		var market: float = bal["staff"][w.role]["market_wage"]
		if w.wage < market:
			var p: float = (market - w.wage) / market * bal["staff"]["quit_factor"]
			if rng.randf() < p:
				report["quits"].append(w.name)
				fire(w.id, true)
	reports.append(report)
	_reset_ledger()
	_check_game_over(ended_day)
	_event("day_end", "Day %d is over. Net: $%d." % [ended_day, int(report["net"])], {"report": report})
	_schedule_arrivals()
	_refresh_candidates()


func _check_game_over(ended_day: int) -> void:
	if mode != "campaign":
		return
	var g: Dictionary = bal["goal"]
	if cash >= g["cash"]:
		game_over = "won"
		_event("game_over", "You reached $%d! Time to buy a bigger property." % int(g["cash"]))
		return
	neg_days = neg_days + 1 if cash < 0.0 else 0
	if neg_days >= int(g["bankrupt_days"]):
		game_over = "bankrupt"
		_event("game_over", "Bankrupt! The bank took the keys.")
	elif ended_day >= int(g["days"]):
		game_over = "out_of_time"
		_event("game_over", "Day %d came and went without reaching $%d." % [ended_day, int(g["cash"])])


func _refresh_candidates() -> void:
	candidates = []
	for role in ["clerk", "housekeeper"]:
		var market: float = bal["staff"][role]["market_wage"]
		for i in 2:
			candidates.append({
				"role": role,
				"name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]],
				"wage": roundf(market * rng.randf_range(0.85, 1.15)),
			})


# --------------------------------------------------------------------------- save / load

func to_save() -> Dictionary:
	var data := {
		"version": SAVE_VERSION, "mode": mode, "time": time, "cash": cash, "rates": rates,
		"queue": queue, "stations": stations, "reviews": reviews, "arrivals": arrivals,
		"candidates": candidates, "ledger": ledger, "reports": reports, "stats": stats,
		"next_id": next_id, "neg_days": neg_days, "game_over": game_over, "rng_state": rng.state,
		"rooms": rooms.map(func(r): return inst_to_dict(r)),
		"workers": workers.map(func(w): return inst_to_dict(w)),
		"guests": guests.values().map(func(g): return inst_to_dict(g)),
	}
	return data


func from_save(balance: Dictionary, data: Dictionary) -> void:
	bal = balance
	for k in ["mode", "time", "cash", "rates", "queue", "stations", "reviews", "arrivals",
			"candidates", "ledger", "reports", "stats", "next_id", "neg_days", "game_over"]:
		set(k, data[k])
	rng.state = data["rng_state"]
	rooms = data["rooms"].map(func(d): return dict_to_inst(d))
	workers = data["workers"].map(func(d): return dict_to_inst(d))
	guests = {}
	for d in data["guests"]:
		var g = dict_to_inst(d)
		guests[g.id] = g
	events = []


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(var_to_str(to_save()))
	return true


func load_from(balance: Dictionary, path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var data = str_to_var(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != SAVE_VERSION:
		return false
	from_save(balance, data)
	return true
