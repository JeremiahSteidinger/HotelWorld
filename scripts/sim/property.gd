extends RefCounted
## One property (the motel, the hotel...): its map, rooms, guests, staff, desk line, rates and reviews.
## Pure logic (no nodes). Time, cash and the random generator belong to the Game that owns it.
## Time unit: game minutes.

const Layout := preload("res://scripts/sim/layout.gd")
const Reviews := preload("res://scripts/sim/reviews.gd")
const Guest := preload("res://scripts/sim/guest.gd")
const Room := preload("res://scripts/sim/room.gd")
const Worker := preload("res://scripts/sim/worker.gd")

const MIN_PER_DAY := 1440.0
const STAFF_ROLES := ["clerk", "housekeeper", "maintenance"]

const FIRST_NAMES := ["Pat", "Sam", "Alex", "Jo", "Robin", "Casey", "Morgan", "Jamie", "Riley", "Taylor",
	"Jordan", "Avery", "Quinn", "Drew", "Sky", "Kai", "Rene", "Lou", "Max", "Ari", "Dale", "Frankie",
	"Bo", "Charlie", "Toni", "Mel", "Rory", "Jules", "Sasha", "Remy"]
const LAST_NAMES := ["Wheeler", "Roadman", "Milestone", "Highway", "Dusty", "Pickett", "Gravel",
	"Overnight", "Snooze", "Pillow", "Turnpike", "Motor", "Lugg", "Napper", "Keyes", "Bellhop"]
const QUIRKS := ["collects motel soaps", "is on a cross-country donut tour", "brought a pet iguana",
	"is writing a travel blog", "snores like a truck", "is avoiding a family reunion",
	"is chasing a solar eclipse", "only drinks tap water", "is very into ice machines",
	"has a suspicious amount of luggage", "is a retired rodeo clown", "is visiting the world's largest ball of twine"]
## Things that break in rooms, and how the log describes it.
const BREAKABLES := [
	["AC", "The AC in room %s now only blows lukewarm disappointment."],
	["TV", "The TV in room %s is stuck on the shopping channel."],
	["shower", "The shower in room %s has gone from 'rain' to 'sad drizzle'."],
	["toilet", "The toilet in room %s won't stop running. It has places to be."],
	["lamp", "The lamp in room %s flickers like a haunted house."],
	["door lock", "The door lock in room %s jammed. Someone pried it open with a shoe."],
	["mini fridge", "The mini fridge in room %s is now a mini oven."],
]

var game                    # the Game this property belongs to
var key := "motel"          # which entry in balance.json "properties"
var index := 0              # position in game.properties
var layout                  # Layout instance

var rates := {}
var early_fee := 20.0       # player-set early check-in fee
var rooms: Array = []
var guests := {}            # id -> Guest
var workers: Array = []     # staff, plus the owner while they are here
var queue: Array = []       # guest ids in the desk line, front first
var stations: Array = []    # worker id per desk station, -1 if free
var reviews: Array = []
var arrivals: Array = []    # absolute minute times of today's remaining arrivals
var candidates: Array = []  # [{role, name, wage}]
var ledger := {}
var stats := {}
var _full_logged := false   # only announce "NO VACANCY" once each time the property fills up

# Shared with the game.
var bal: Dictionary:
	get: return game.bal
var rng: RandomNumberGenerator:
	get: return game.rng
var time: float:
	get: return game.time
var cash: float:
	get: return game.cash
	set(v): game.cash = v
var cfg: Dictionary:
	get: return game.bal["properties"][key]


# --------------------------------------------------------------------------- setup

func setup(owner_game, property_key: String, property_index: int) -> void:
	game = owner_game
	key = property_key
	index = property_index
	layout = Layout.for_kind(cfg["layout"])
	rates = {}
	for t in cfg["room_types"]:
		rates[t] = float(cfg["room_types"][t]["default_rate"])
	early_fee = float(bal["early_checkin"]["default_fee"])
	rooms = []
	var types: Array = cfg["rooms"]
	for i in types.size():
		var r = Room.new()
		r.index = i
		r.type = types[i]
		rooms.append(r)
	# A property bought second-hand comes with some problems.
	var broken := int(cfg.get("start_broken", 0))
	var order := range(rooms.size())
	_shuffle(order)
	for i in mini(broken, order.size()):
		rooms[order[i]].broken = BREAKABLES[rng.randi() % BREAKABLES.size()][0]
	guests = {}
	workers = []
	queue = []
	stations = []
	for s in layout.stations:
		stations.append(-1)
	reviews = []
	stats = {"served": 0, "walkouts": 0, "lost_price": 0, "lost_vacancy": 0, "lost_line": 0, "repairs": 0, "breakages": 0}
	_reset_ledger()
	_schedule_arrivals()
	_refresh_candidates()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _new_worker(role: String, worker_name: String, wage: float):
	var w = Worker.new()
	w.id = game.take_id()
	w.role = role
	w.name = worker_name
	w.wage = wage
	w.shift = default_shift(role)
	w.pos = Vector2(layout.staff_spawn)
	w.present = false
	workers.append(w)
	return w


func _reset_ledger() -> void:
	ledger = {"revenue": 0.0, "refunds": 0.0, "wages": 0.0, "upkeep": 0.0,
		"checkins": 0, "checkouts": 0, "walkouts": 0, "turned_away": 0, "stars": [], "repairs": 0, "breakages": 0}


# --------------------------------------------------------------------------- queries

func day() -> int:
	return game.day()


func minute_of_day() -> float:
	return game.minute_of_day()


func clock_text() -> String:
	return game.clock_text()


func display_name() -> String:
	return cfg["name"]


func room_label(i: int) -> String:
	return str(int(cfg.get("first_room_number", 1)) + i)


func room_type_name(t: String) -> String:
	return cfg["room_types"][t]["name"]


func rating() -> float:
	var r: Dictionary = bal["rating"]
	var start: float = cfg.get("start_rating", r["start"])
	return Reviews.rating(reviews, start, int(r["window"]), int(r["prior_weight"]))


## Archetype settings at this property: the global archetype merged with this property's overrides.
func archetype(arch_key: String) -> Dictionary:
	var a: Dictionary = bal["archetypes"][arch_key].duplicate()
	a.merge(cfg["archetypes"].get(arch_key, {}), true)
	return a


func archetype_keys() -> Array:
	return cfg["archetypes"].keys()


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


func staff_max(role: String) -> int:
	return int(cfg["staff_max"].get(role, 0))


func daily_wages() -> float:
	var total := 0.0
	for w in staff():
		total += w.wage
	return total


func daily_upkeep() -> float:
	var total: float = cfg["base_upkeep"]
	for r in rooms:
		total += cfg["room_types"][r.type]["upkeep"]
	return total


func willingness(arch_key: String) -> float:
	var d: Dictionary = bal["demand"]
	return archetype(arch_key)["budget"] * (d["wtp_base"] + d["wtp_per_star"] * rating())


func expected_arrivals() -> float:
	var d: Dictionary = bal["demand"]
	return cfg["base_arrivals"] * (d["rating_base"] + d["rating_weight"] * rating())


## Check-in opens at checkin_hour (3 PM). Late-night arrivals (after midnight) can still check in.
func check_in_open() -> bool:
	var m := minute_of_day()
	return m >= bal["checkin_hour"] * 60.0 or m < bal["checkout_start_hour"] * 60.0


func is_early(g) -> bool:
	return g.purpose == "checkin" and not check_in_open()


func rentable(r) -> bool:
	return r.guest_id == -1 and r.broken == ""


## True while at least one working room is neither occupied nor reserved. Drives the roadside sign.
func has_vacancy() -> bool:
	for r in rooms:
		if rentable(r):
			return true
	return false


func broken_rooms() -> Array:
	return rooms.filter(func(r): return r.broken != "")


func clean_room_free(room_type: String) -> bool:
	for r in rooms:
		if r.type == room_type and rentable(r) and r.state == "clean":
			return true
	return false


## An early guest the desk can talk to about early check-in (not asked yet, and a clean room is free).
func can_offer_early(g) -> bool:
	return is_early(g) and g.early_state == "" and clean_room_free(g.room_type)


func pending_early() -> Array:
	var out := []
	for gid in guests:
		if guests[gid].state == "early_request":
			out.append(guests[gid])
	return out


func set_early_fee(value: float) -> void:
	early_fee = clampf(roundf(value), 0.0, 200.0)


## Player's answer to an early check-in request. choice: "no", "fee" or "free".
func resolve_early(guest_id: int, choice: String) -> void:
	if not guests.has(guest_id):
		return
	var g = guests[guest_id]
	if g.state != "early_request":
		return
	var e: Dictionary = bal["early_checkin"]
	var haggling: bool = g.early_state == "haggling"
	match choice:
		"free":
			g.note("early_checkin", e["free_bonus"])
			_event("checkin", "%s gets an early check-in, free of charge." % g.name, {"guest": g.id})
			_start_early_checkin(g)
		"fee":
			if early_fee <= 0.0:
				resolve_early(guest_id, "free")
				return
			if not haggling and rng.randf() < e["haggle_chance"].get(g.archetype, 0.5):
				g.early_state = "haggling"
				g.discount_timer = 0.0
				_event("early", "%s asks if you could waive the $%d early check-in fee." % [g.name, int(early_fee)], {"guest": g.id})
				return
			if haggling and rng.randf() > e["pay_after_insist_chance"].get(g.archetype, 0.5):
				g.note("early_fee", e["declined_fee_mood"])
				_event("angry", "%s won't pay the early fee and will wait for 3 PM." % g.name, {"guest": g.id})
				_back_to_line(g)
				return
			g.note("early_checkin", e["paid_bonus"])
			g.note("early_fee", -early_fee * e["fee_mood_per_dollar"] + (e["insist_mood"] if haggling else 0.0))
			g.early_fee = early_fee
			cash += early_fee
			ledger["revenue"] += early_fee
			_event("checkin", "%s paid $%d to check in early." % [g.name, int(early_fee)], {"guest": g.id})
			_start_early_checkin(g)
		_:
			g.note("no_early", e["refuse_mood"])
			_event("info", "%s will wait for 3 PM check-in." % g.name)
			_back_to_line(g)


func _start_early_checkin(g) -> void:
	g.early_state = "done"
	g.state = "at_desk"
	for w in workers:
		if w.serving == g.id:
			w.progress = 0.0


func _back_to_line(g) -> void:
	g.early_state = "done"
	_release_desk_for(g)
	g.state = "queue"
	queue.push_front(g.id)


func free_rooms_for(room_type: String) -> int:
	var n := 0
	for r in rooms:
		if r.type == room_type and rentable(r):
			n += 1
	for gid in guests:
		var g = guests[gid]
		if g.purpose == "checkin" and g.room == -1 and g.room_type == room_type and g.state in ["queue", "to_desk", "at_desk", "discount", "early_request"]:
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


## Who works when. Shift hours come from balance.json; night shift wraps past midnight.
func shift_hours(shift: String) -> Array:
	return bal["shifts"][shift]["hours"]


func on_duty(w) -> bool:
	if w.role == "owner":
		return true
	var hrs: Array = shift_hours(w.shift)
	var hour := minute_of_day() / 60.0
	var a: float = hrs[0]
	var b: float = hrs[1]
	if a < b:
		return hour >= a and hour < b
	return hour >= a or hour < b


func default_shift(role: String) -> String:
	return bal["staff"][role].get("default_shift", "day")


## Staff of a role scheduled on each shift, e.g. {"day": 1, "evening": 1, "night": 0}.
func coverage(role: String) -> Dictionary:
	var out := {}
	for s in bal["shifts"]:
		out[s] = 0
	for w in workers:
		if w.role == role:
			out[w.shift] += 1
	return out


func _event(type: String, text: String, extra := {}) -> void:
	extra["prop"] = index
	game.add_event(type, text, extra)


# --------------------------------------------------------------------------- player actions

## Owner orders. They are queued on the owner even if the owner is at another property:
## they will drive over first.
func order_desk() -> void:
	var o = game.owner_w
	if o.orders.is_empty() and game.owner_prop() == index and o.job.get("type", "") == "desk":
		return
	if not o.orders.is_empty() and o.orders[-1]["type"] == "desk" and o.orders[-1]["prop"] == index:
		return
	o.orders.append({"type": "desk", "prop": index})


func order_clean(room_index: int) -> bool:
	var r = rooms[room_index]
	if r.state != "dirty":
		_event("info", "Room %s doesn't need cleaning." % room_label(room_index))
		return false
	var o = game.owner_w
	if r.cleaner_id != -1 and r.cleaner_id != o.id:
		_event("info", "Someone is already cleaning room %s." % room_label(room_index))
		return false
	if _has_order(o, "clean", room_index):
		return false
	o.orders.append({"type": "clean", "prop": index, "room": room_index})
	return true


func order_fix(room_index: int) -> bool:
	var r = rooms[room_index]
	if r.broken == "":
		_event("info", "Nothing is broken in room %s." % room_label(room_index))
		return false
	var o = game.owner_w
	if r.fixer_id != -1 and r.fixer_id != o.id:
		_event("info", "Someone is already fixing room %s." % room_label(room_index))
		return false
	if _has_order(o, "fix", room_index):
		return false
	o.orders.append({"type": "fix", "prop": index, "room": room_index})
	return true


## Click on a room: clean it and/or fix it, whatever it needs.
func order_room(room_index: int) -> Array:
	var r = rooms[room_index]
	var added := []
	if r.state == "dirty" and order_clean(room_index):
		added.append("clean")
	if r.broken != "" and order_fix(room_index):
		added.append("fix")
	if r.state != "dirty" and r.broken == "":
		_event("info", "Room %s doesn't need anything." % room_label(room_index))
	return added


func _has_order(o, type: String, room_index: int) -> bool:
	for ord in o.orders:
		if ord["type"] == type and ord.get("prop", -1) == index and ord.get("room", -1) == room_index:
			return true
	return o.job.get("type", "") == type and game.owner_prop() == index and o.job.get("room", -1) == room_index


func set_rate(room_type: String, value: float) -> void:
	rates[room_type] = clampf(roundf(value), 10.0, 800.0)


func hire(candidate_index: int) -> bool:
	if candidate_index < 0 or candidate_index >= candidates.size():
		return false
	var c: Dictionary = candidates[candidate_index]
	if staff_count(c["role"]) >= staff_max(c["role"]):
		_event("info", "%s can't use more than %d of that role." % [display_name(), staff_max(c["role"])])
		return false
	var w = _new_worker(c["role"], c["name"], c["wage"])
	candidates.remove_at(candidate_index)
	_event("staff", "%s joined %s as %s ($%d/day, %s shift)." % [c["name"], display_name(), bal["staff"][c["role"]]["name"],
		int(c["wage"]), bal["shifts"][w.shift]["name"].to_lower()])
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


func set_shift(worker_id: int, shift: String) -> void:
	var w = get_worker(worker_id)
	if w != null and w.role != "owner" and bal["shifts"].has(shift):
		w.shift = shift


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

## Advance this property by dt minutes. The game has already moved the clock.
func step(dt: float) -> void:
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
		entity.path.append_array(layout.find_path(start, goal))
	else:
		entity.path = layout.find_path(start, goal)
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
	var keys := archetype_keys()
	var total := 0.0
	for k in keys:
		total += archetype(k)["weight"]
	var roll := rng.randf() * total
	for k in keys:
		roll -= archetype(k)["weight"]
		if roll <= 0.0:
			return k
	return keys[0]


func _random_name() -> String:
	return "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]


func _arrive() -> void:
	var arch_key := _pick_archetype()
	var a := archetype(arch_key)
	var room_type: String = a["room"]
	var wtp := willingness(arch_key) * rng.randf_range(0.85, 1.15)
	var guest_name := _random_name()
	if arch_key == "family":
		guest_name = "The %s family" % LAST_NAMES[rng.randi() % LAST_NAMES.size()]
	elif arch_key == "couple":
		guest_name = "%s & %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], _random_name()]
	if rates[room_type] > wtp * bal["demand"]["walkaway_price_ratio"]:
		stats["lost_price"] += 1
		ledger["turned_away"] += 1
		_event("lost", "%s saw your $%d %s rate and kept driving." % [guest_name, int(rates[room_type]), room_type_name(room_type)])
		return
	if free_rooms_for(room_type) <= 0:
		stats["lost_vacancy"] += 1
		ledger["turned_away"] += 1
		if has_vacancy():
			_event("lost", "No %s room free for %s." % [room_type_name(room_type).to_lower(), guest_name])
		elif not _full_logged:
			_full_logged = true
			_event("lost", "Every room at %s is taken or out of order. The sign says NO VACANCY." % display_name())
		return
	if queue.size() >= int(cfg["max_line"]):
		stats["lost_line"] += 1
		ledger["turned_away"] += 1
		_event("lost", "%s saw the line out the door and left." % guest_name)
		return
	var g = Guest.new()
	g.id = game.take_id()
	g.archetype = arch_key
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
	g.pos = Vector2(layout.guest_spawn)
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
			_go(g, layout.queue_slot(idx))
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
				if w != null and w.serving == g.id and _at(g, layout.service_spots[i]):
					g.state = "at_desk"
		"waiting_room":
			g.wait += dt
			if g.wait > m["wait_grace"]:
				g.note("room_not_ready", -m["wait_per_minute"] * dt)
			var r = rooms[g.room]
			if r.state == "clean":
				g.state = "to_room"
				_go(g, layout.room_stay_spot(g.room))
			elif g.wait > g.patience * 1.5:
				_refund_and_leave(g)
		"to_room":
			if _at(g, layout.room_stay_spot(g.room)):
				g.state = "staying"
				rooms[g.room].state = "occupied"
		"staying":
			if day() > g.checkout_day or (day() == g.checkout_day and minute_of_day() >= g.checkout_minute):
				g.asleep = false
				_start_checkout(g)
			elif is_sleep_time(g):
				_go(g, layout.room_bed(g.room))
				g.asleep = _at(g, layout.room_bed(g.room))
			else:
				g.asleep = false
				_go(g, layout.room_stay_spot(g.room))
		"early_request":
			g.discount_timer += dt
			if g.discount_timer > bal["early_checkin"]["timeout"]:
				resolve_early(g.id, "no")
		"discount":
			g.discount_timer += dt
			if g.discount_timer > bal["discount"]["timeout"]:
				_event("info", "%s gave up waiting for an answer about their discount." % g.name)
				resolve_discount(g.id, false)
		"leaving":
			if _at(g, layout.exit_cell):
				g.state = "gone"


## Each guest keeps their own hours: bed somewhere between 9:30 and 11:30 PM, up between 5:30 and 7 AM
## (always before check-out). Derived from the guest's id so it needs no extra random draws or save data.
func bedtime(g) -> float:
	return 21.5 * 60.0 + float((g.id * 37) % 120)


func wake_minute(g) -> float:
	return 5.5 * 60.0 + float((g.id * 53) % 90)


func is_sleep_time(g) -> bool:
	var m := minute_of_day()
	return m >= bedtime(g) or m < wake_minute(g)


func _start_checkout(g) -> void:
	var r = rooms[g.room]
	r.state = "dirty"
	r.guest_id = -1
	r.clean_progress = 0.0
	g.pos = Vector2(layout.room_door(g.room))
	g.path = []
	g.target = Vector2i(-1, -1)
	g.state = "queue"
	g.purpose = "checkout"
	g.wait = 0.0
	queue.append(g.id)
	_event("checkout", "%s is heading to the desk to check out. Room %s needs cleaning." % [g.name, room_label(g.room)], {"guest": g.id, "room": g.room})
	if r.broken == "" and rng.randf() < float(cfg["break_chance"]):
		var item: Array = BREAKABLES[rng.randi() % BREAKABLES.size()]
		r.broken = item[0]
		stats["breakages"] += 1
		ledger["breakages"] += 1
		_event("broken", (item[1] % room_label(g.room)) + " It needs fixing before anyone can stay there.", {"room": g.room})


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
	_go(g, layout.exit_cell)


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
		if r.type != room_type or not rentable(r):
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


func _complete_service(_w, g) -> void:
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
		_go(g, layout.room_stay_spot(g.room))
		_event("checkin", "%s checked in to room %s for $%d." % [g.name, room_label(g.room), int(price)], {"guest": g.id})
	else:
		g.state = "waiting_room"
		_go(g, layout.wait_spots[g.id % layout.wait_spots.size()])
		_event("warn", "%s checked in, but room %s isn't clean yet! They're waiting in the lobby." % [g.name, room_label(g.room)], {"guest": g.id, "room": g.room})


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
	if not w.present:
		if on_duty(w):
			w.present = true
			w.pos = Vector2(layout.staff_spawn)
			w.path = []
			w.target = Vector2i(-1, -1)
		else:
			return
	_move(w, dt)
	if w.job.is_empty():
		_choose_job(w)
	match w.job.get("type", ""):
		"desk":
			_do_desk(w, dt)
		"clean":
			_do_clean(w, dt)
		"fix":
			_do_fix(w, dt)
		"travel":
			_go(w, layout.staff_spawn)
			if _at(w, layout.staff_spawn):
				game.start_travel(w, w.job["to"])
		"":
			if w.role == "owner":
				return
			if on_duty(w):
				if w.arrived():
					_go(w, layout.idle_spot)
			else:
				# Shift over: head to the car and go home.
				_go(w, layout.staff_spawn)
				if _at(w, layout.staff_spawn):
					w.present = false


func _choose_job(w) -> void:
	if w.role != "owner" and not on_duty(w):
		return
	match w.role:
		"owner":
			while not w.orders.is_empty() and w.job.is_empty():
				var o: Dictionary = w.orders[0]
				if o.get("prop", index) != index:
					w.job = {"type": "travel", "to": o["prop"]}
					return
				w.orders.pop_front()
				match o["type"]:
					"desk":
						w.job = {"type": "desk", "station": -1}
					"clean":
						var r = rooms[o["room"]]
						if r.state == "dirty" and (r.cleaner_id == -1 or r.cleaner_id == w.id):
							r.cleaner_id = w.id
							w.job = {"type": "clean", "room": o["room"]}
					"fix":
						var r = rooms[o["room"]]
						if r.broken != "" and (r.fixer_id == -1 or r.fixer_id == w.id):
							r.fixer_id = w.id
							w.job = {"type": "fix", "room": o["room"]}
		"clerk":
			w.job = {"type": "desk", "station": -1}
		"housekeeper":
			var best := _nearest_room(w, func(r): return r.state == "dirty" and r.cleaner_id == -1)
			if best != -1:
				rooms[best].cleaner_id = w.id
				w.job = {"type": "clean", "room": best}
		"maintenance":
			var best := _nearest_room(w, func(r): return r.broken != "" and r.fixer_id == -1)
			if best != -1:
				rooms[best].fixer_id = w.id
				w.job = {"type": "fix", "room": best}


## Closest room matching `want`, preferring rooms a guest is waiting for.
func _nearest_room(w, want: Callable) -> int:
	var best := -1
	var best_score := -INF
	for r in rooms:
		if not want.call(r):
			continue
		var score: float = -w.pos.distance_to(Vector2(layout.room_work_spot(r.index)))
		if r.guest_id != -1:
			score += 100.0  # someone is waiting for this room
		if score > best_score:
			best_score = score
			best = r.index
	return best


func _do_desk(w, dt: float) -> void:
	var s: int = w.job["station"]
	if w.role != "owner" and not on_duty(w) and w.serving == -1:
		_leave_station(w)
		return
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
				_go(w, layout.idle_spot)
			return
		stations[s] = w.id
		w.job["station"] = s
	_go(w, layout.stations[s])
	if not _at(w, layout.stations[s]):
		return
	if w.serving == -1:
		if w.role == "owner" and not w.orders.is_empty():
			_leave_station(w)
			return
		var next := -1
		for i in queue.size():
			var cand = guests[queue[i]]
			if not is_early(cand) or can_offer_early(cand):
				next = i
				break
		if next != -1:
			var g = guests[queue[next]]
			queue.remove_at(next)
			g.state = "to_desk"
			_go(g, layout.service_spots[s])
			w.serving = g.id
			w.progress = 0.0
		return
	if not guests.has(w.serving):
		w.serving = -1
		return
	var g = guests[w.serving]
	if g.state != "at_desk":
		return
	if is_early(g) and g.early_state == "":
		# Guest is here before check-in time: ask the player what to do.
		g.state = "early_request"
		g.early_state = "asking"
		g.discount_timer = 0.0
		_event("early", "%s arrived early and asks to check in now." % g.name, {"guest": g.id})
		return
	if is_early(g) and g.early_state != "done":
		return
	w.progress += dt
	var need: float = bal["task_minutes"]["check_in" if g.purpose == "checkin" else "check_out"]
	if w.progress >= need:
		_complete_service(w, g)


func _leave_station(w) -> void:
	for i in stations.size():
		if stations[i] == w.id:
			stations[i] = -1
	w.job = {}


func _do_clean(w, dt: float) -> void:
	var r = rooms[w.job["room"]]
	if r.state != "dirty" or r.cleaner_id != w.id:
		w.job = {}
		return
	var spot: Vector2i = layout.room_work_spot(r.index)
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
			_event("clean", "Room %s is clean. %s can finally go in." % [room_label(r.index), guests[r.guest_id].name])


func repair_minutes(w) -> float:
	var t: Dictionary = bal["task_minutes"]
	return float(t["repair"]) if w.role == "maintenance" else float(t["repair_owner"])


func _do_fix(w, dt: float) -> void:
	var r = rooms[w.job["room"]]
	if r.broken == "" or r.fixer_id != w.id:
		w.job = {}
		return
	var spot: Vector2i = layout.room_work_spot(r.index)
	_go(w, spot)
	if not _at(w, spot):
		return
	r.repair_progress += dt / repair_minutes(w)
	if r.repair_progress >= 1.0:
		var item: String = r.broken
		r.repair_progress = 0.0
		r.broken = ""
		r.fixer_id = -1
		w.job = {}
		stats["repairs"] += 1
		ledger["repairs"] += 1
		var cost: float = bal["repair_parts_cost"]
		cash -= cost
		ledger["upkeep"] += cost
		_event("fixed", "%s fixed the %s in room %s ($%d in parts)." % ["You" if w.role == "owner" else w.name, item, room_label(r.index), int(cost)], {"room": r.index})


## Take a worker off every task (they are leaving this property).
func _release_worker(w) -> void:
	for i in stations.size():
		if stations[i] == w.id:
			stations[i] = -1
	for r in rooms:
		if r.cleaner_id == w.id:
			r.cleaner_id = -1
		if r.fixer_id == w.id:
			r.fixer_id = -1
	if w.serving != -1 and guests.has(w.serving):
		var g = guests[w.serving]
		if g.state in ["to_desk", "at_desk", "early_request"]:
			g.state = "queue"
			queue.push_front(g.id)
	w.serving = -1
	w.job = {}


func add_worker(w) -> void:
	w.pos = Vector2(layout.staff_spawn)
	w.path = []
	w.target = Vector2i(-1, -1)
	w.job = {}
	w.present = true
	workers.append(w)


func remove_worker(w) -> void:
	_release_worker(w)
	workers.erase(w)


# --------------------------------------------------------------------------- day cycle

## Called by the game at midnight: pay wages and upkeep, staff may quit, plan tomorrow.
func close_day(ended_day: int) -> Dictionary:
	var wages := daily_wages()
	var upkeep := daily_upkeep()
	cash -= wages + upkeep
	var stars: Array = ledger["stars"]
	var avg := 0.0
	for s in stars:
		avg += s
	avg = avg / stars.size() if not stars.is_empty() else 0.0
	var parts: float = ledger["upkeep"]  # repair parts bought during the day
	var report := {
		"name": display_name(),
		"key": key,
		"day": ended_day,
		"revenue": ledger["revenue"],
		"refunds": ledger["refunds"],
		"wages": wages,
		"upkeep": upkeep + parts,
		"net": ledger["revenue"] - ledger["refunds"] - wages - upkeep - parts,
		"checkins": ledger["checkins"],
		"checkouts": ledger["checkouts"],
		"walkouts": ledger["walkouts"],
		"turned_away": ledger["turned_away"],
		"breakages": ledger["breakages"],
		"repairs": ledger["repairs"],
		"broken": broken_rooms().size(),
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
	_reset_ledger()
	_schedule_arrivals()
	_refresh_candidates()
	return report


func _refresh_candidates() -> void:
	candidates = []
	for role in STAFF_ROLES:
		if staff_max(role) <= 0:
			continue
		var market: float = bal["staff"][role]["market_wage"]
		for i in int(bal["staff"][role].get("applicants", 2)):
			candidates.append({
				"role": role,
				"name": _random_name(),
				"wage": roundf(market * rng.randf_range(0.85, 1.15)),
			})


# --------------------------------------------------------------------------- save / load

func to_save() -> Dictionary:
	return {
		"key": key, "rates": rates, "early_fee": early_fee,
		"queue": queue, "stations": stations, "reviews": reviews, "arrivals": arrivals,
		"candidates": candidates, "ledger": ledger, "stats": stats,
		"rooms": rooms.map(func(r): return inst_to_dict(r)),
		"workers": staff().map(func(w): return inst_to_dict(w)),
		"guests": guests.values().map(func(g): return inst_to_dict(g)),
	}


func from_save(owner_game, property_index: int, data: Dictionary) -> void:
	game = owner_game
	index = property_index
	key = data.get("key", "motel")
	layout = Layout.for_kind(cfg["layout"])
	rates = data["rates"]
	early_fee = data.get("early_fee", float(bal["early_checkin"]["default_fee"]))
	queue = data["queue"]
	stations = data["stations"]
	reviews = data["reviews"]
	arrivals = data["arrivals"]
	candidates = data["candidates"]
	ledger = data["ledger"]
	for k in ["repairs", "breakages"]:
		ledger[k] = ledger.get(k, 0)
	stats = data["stats"]
	for k in ["repairs", "breakages"]:
		stats[k] = stats.get(k, 0)
	rooms = data["rooms"].map(func(d): return dict_to_inst(d))
	workers = data["workers"].map(func(d): return dict_to_inst(d)).filter(func(w): return w.role != "owner")
	guests = {}
	for d in data["guests"]:
		var g = dict_to_inst(d)
		guests[g.id] = g
