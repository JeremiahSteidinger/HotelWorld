extends RefCounted
## The whole business: one clock, one bank account, loans, the campaign, and the properties you own.
## Pure logic (no nodes) so it can be unit-tested and fast-forwarded headless.
## Time unit: game minutes. `time` counts minutes since day 1, 00:00.

const Property := preload("res://scripts/sim/property.gd")
const Worker := preload("res://scripts/sim/worker.gd")
const Layout := preload("res://scripts/sim/layout.gd")

const MIN_PER_DAY := 1440.0
const SAVE_VERSION := 2

var bal: Dictionary = {}
var rng := RandomNumberGenerator.new()
var mode := "campaign"   # or "sandbox"
var chapter := 1         # campaign chapter (index into balance "campaign.chapters", 1-based)

var time := 0.0
var cash := 0.0
var properties: Array = []   # owned properties, in the order they were bought
var loans: Array = []        # [{id, kind: "loan"/"mortgage", name, balance, rate, payment, days_left}]
var owner_w                  # the owner (a Worker). Lives in one property's workers, or is on the road.
var travel := {}             # while driving: {"from": index, "to": index, "eta": time}
var commutes: Array = []     # shared staff on the road: [{"worker": Worker, "from": index, "to": index, "eta": time}]
var reports: Array = []      # one per day, see _end_of_day()
var next_id := 1
var neg_days := 0
var game_over := ""          # "", "won", "bankrupt", "out_of_time"
var events: Array = []       # notifications for the UI: {type, text, day, time, prop?, ...}
var _bank_today := {"payments": 0.0, "interest": 0.0}


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
	chapter = 1
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	time = bal["start_hour"] * 60.0
	cash = bal["start_cash"]
	properties = []
	loans = []
	travel = {}
	commutes = []
	reports = []
	next_id = 1
	neg_days = 0
	game_over = ""
	events = []
	_bank_today = {"payments": 0.0, "interest": 0.0}
	var motel = _add_property(bal["start_property"])
	owner_w = Worker.new()
	owner_w.id = take_id()
	owner_w.role = "owner"
	owner_w.name = "You"
	motel.add_worker(owner_w)
	owner_w.pos = Vector2(motel.layout.stations[0])
	owner_w.orders.append({"type": "desk", "prop": 0})


func _add_property(key: String):
	var p = Property.new()
	p.setup(self, key, properties.size())
	properties.append(p)
	return p


func take_id() -> int:
	next_id += 1
	return next_id - 1


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


func prop(key: String):
	for p in properties:
		if p.key == key:
			return p
	return null


func owns(key: String) -> bool:
	return prop(key) != null


## Index of the property the owner is at, or -1 while driving.
func owner_prop() -> int:
	for p in properties:
		if p.workers.has(owner_w):
			return p.index
	return -1


func travel_minutes_left() -> float:
	return maxf(0.0, travel.get("eta", time) - time)


func add_event(type: String, text: String, extra := {}) -> void:
	var e := {"type": type, "text": text, "day": day(), "time": clock_text()}
	e.merge(extra)
	events.append(e)


func pop_events() -> Array:
	var e := events
	events = []
	return e


# --------------------------------------------------------------------------- owner

## Drive to another property. Orders after this one happen there.
func order_go(to_index: int) -> void:
	if to_index == owner_prop() and owner_w.orders.is_empty():
		return
	owner_w.orders.append({"type": "go", "prop": to_index})


func clear_orders() -> void:
	owner_w.orders.clear()


## Called by a property when the owner reaches their car.
func start_travel(w, to_index: int) -> void:
	var from_p = properties[owner_prop()]
	from_p.remove_worker(w)
	w.job = {}
	travel = {"from": from_p.index, "to": to_index, "eta": time + float(bal["travel_minutes"])}
	add_event("travel", "You drive to %s (about %d minutes)." % [properties[to_index].display_name(), int(bal["travel_minutes"])])


func _update_travel() -> void:
	if travel.is_empty() or time < travel["eta"]:
		return
	var p = properties[travel["to"]]
	travel = {}
	p.add_worker(owner_w)
	add_event("travel", "You arrived at %s." % p.display_name(), {"prop": p.index})


# --------------------------------------------------------------------------- shared staff

## Can this role be shared between properties?
func can_share(role: String) -> bool:
	return bool(bal["staff"].get(role, {}).get("can_share", false))


## Mileage paid for one trip between properties.
func trip_cost() -> float:
	return roundf(float(bal["travel_miles"]) * float(bal["mileage_rate"]) * 100.0) / 100.0


## Everyone employed by property `index`, wherever they are right now (here, at another property, or driving).
func employees(index: int) -> Array:
	var out := []
	for p in properties:
		for w in p.workers:
			if w.role != "owner" and w.home == index:
				out.append(w)
	for c in commutes:
		if c["worker"].home == index:
			out.append(c["worker"])
	return out


## Index of the property a staff member is at, or -1 while driving (or not found).
func where_is(w) -> int:
	for p in properties:
		if p.workers.has(w):
			return p.index
	return -1


func commute_of(w) -> Dictionary:
	for c in commutes:
		if c["worker"] == w:
			return c
	return {}


## Staff of `role` on the road to property `to_index`.
func commuters_to(to_index: int, role: String) -> int:
	return commutes.filter(func(c): return c["to"] == to_index and c["worker"].role == role).size()


## Where a shared worker idle at `here` should drive to help, or -1 to stay put.
## Home comes first; otherwise the property with the most unclaimed work for the role that has
## nobody of that role on duty or on the way. Only leaves if the shift has time for the drive plus one job.
func help_target(w, here: int) -> int:
	if not w.shared or not can_share(w.role) or properties.size() < 2:
		return -1
	var p_here = properties[here]
	if p_here.shift_minutes_left(w) < float(bal["travel_minutes"]) + p_here.job_minutes(w):
		return -1
	var best := -1
	var best_need := 0
	for p in properties:
		if p.index == here:
			continue
		var need: int = p.open_work(w.role)
		if need <= 0 or p.has_cover(w.role) or commuters_to(p.index, w.role) > 0:
			continue
		if p.index == w.home:
			need += 1000
		if need > best_need:
			best_need = need
			best = p.index
	return best


## Called by a property when a shared worker reaches their car. Mileage is charged to the property they drive to.
func start_commute(w, to_index: int) -> void:
	var from_p = properties[where_is(w)]
	var to_p = properties[to_index]
	from_p.remove_worker(w)
	w.job = {}
	commutes.append({"worker": w, "from": from_p.index, "to": to_index, "eta": time + float(bal["travel_minutes"])})
	var cost := trip_cost()
	cash -= cost
	to_p.ledger["mileage"] += cost
	var why: String = to_p.work_text(w.role)
	add_event("travel", "%s drives from %s to %s%s ($%.2f mileage)." % [w.name, from_p.display_name(), to_p.display_name(), why, cost],
		{"prop": to_index})


func _update_commutes() -> void:
	for c in commutes.duplicate():
		if time < c["eta"]:
			continue
		commutes.erase(c)
		var p = properties[c["to"]]
		p.add_worker(c["worker"])
		add_event("travel", "%s arrived at %s." % [c["worker"].name, p.display_name()], {"prop": p.index})


## Take a staff member off the payroll wherever they are.
func dismiss(w) -> void:
	var c := commute_of(w)
	if not c.is_empty():
		commutes.erase(c)
		return
	var at := where_is(w)
	if at >= 0:
		properties[at].remove_worker(w)


# --------------------------------------------------------------------------- bank

func total_value() -> float:
	var v := 0.0
	for p in properties:
		v += float(p.cfg["value"])
	return v


func debt() -> float:
	var d := 0.0
	for l in loans:
		d += l["balance"]
	return d


func net_worth() -> float:
	return cash + total_value() - debt()


## Daily payment that pays off `amount` in `days` days at `rate` interest per day.
static func payment_for(amount: float, rate: float, days: int) -> float:
	if days <= 0:
		return amount
	if rate <= 0.0:
		return amount / days
	return amount * rate / (1.0 - pow(1.0 + rate, -days))


## How much more the bank will lend: a share of what your properties are worth, minus what you owe.
func credit_limit() -> float:
	var b: Dictionary = bal["bank"]
	var limit: float = b["loan_to_value"] * total_value() - debt()
	return maxf(0.0, floorf(limit / 100.0) * 100.0)


func daily_loan_payments() -> float:
	var t := 0.0
	for l in loans:
		t += minf(l["payment"], l["balance"] * (1.0 + l["rate"]))
	return t


func borrow(amount: float) -> bool:
	var b: Dictionary = bal["bank"]
	amount = roundf(amount)
	if amount < 100.0 or amount > credit_limit():
		add_event("info", "The bank won't lend you $%d right now. Your limit is $%d." % [int(amount), int(credit_limit())])
		return false
	var days := int(b["loan_days"])
	var rate: float = b["loan_rate"]
	loans.append({"id": take_id(), "kind": "loan", "name": "Business loan", "balance": amount, "rate": rate,
		"payment": payment_for(amount, rate, days), "days_left": days})
	cash += amount
	add_event("bank", "The bank lent you $%d. You'll pay about $%d a day for %d days." % [int(amount), int(loans[-1]["payment"]), days])
	return true


func get_loan(loan_id: int) -> Dictionary:
	for l in loans:
		if l["id"] == loan_id:
			return l
	return {}


## Pay down a loan early. Interest is only charged on what's left, so this saves money.
func repay(loan_id: int, amount: float) -> bool:
	var l := get_loan(loan_id)
	if l.is_empty():
		return false
	amount = minf(roundf(amount), l["balance"])
	if amount <= 0.0 or amount > cash:
		add_event("info", "You don't have enough cash for that payment.")
		return false
	cash -= amount
	l["balance"] -= amount
	_bank_today["payments"] += amount
	if l["balance"] < 0.5:
		loans.erase(l)
		add_event("bank", "%s paid off!" % l["name"])
	else:
		l["payment"] = payment_for(l["balance"], l["rate"], int(l["days_left"]))
		add_event("bank", "Paid $%d off the %s. $%d left." % [int(amount), l["name"].to_lower(), int(l["balance"])])
	return true


func _pay_loans() -> void:
	for l in loans.duplicate():
		var interest: float = l["balance"] * l["rate"]
		var principal: float = minf(l["payment"] - interest, l["balance"])
		l["days_left"] = int(l["days_left"]) - 1
		if l["days_left"] <= 0:
			principal = l["balance"]
		cash -= interest + principal
		l["balance"] -= principal
		_bank_today["payments"] += interest + principal
		_bank_today["interest"] += interest
		if l["balance"] < 0.5:
			loans.erase(l)
			add_event("bank", "%s is paid off!" % l["name"])


# --------------------------------------------------------------------------- properties for sale

## Properties you could buy: [{key, name, price, down, mortgage, payment, can_buy, why}]
func listings() -> Array:
	var out := []
	for k in bal["properties"]:
		var c: Dictionary = bal["properties"][k]
		if owns(k) or not c.has("price"):
			continue
		var b: Dictionary = bal["bank"]
		var price: float = c["price"]
		var down: float = roundf(price * b["down_payment"])
		var why := ""
		if mode == "campaign" and chapter < int(c.get("chapter", 1)):
			why = "Finish chapter %d first." % (chapter)
		elif cash < down:
			why = "You need $%d cash for the down payment." % int(down)
		out.append({"key": k, "name": c["name"], "price": price, "down": down, "mortgage": price - down,
			"payment": payment_for(price - down, b["mortgage_rate"], int(b["mortgage_days"])),
			"days": int(b["mortgage_days"]), "rooms": c["rooms"].size(), "blurb": c.get("blurb", ""),
			"can_buy": why == "", "why": why})
	return out


## Buy a property with a down payment and a mortgage for the rest (or pay it all if pay_full).
func buy_property(key: String, pay_full := false) -> bool:
	for l in listings():
		if l["key"] != key:
			continue
		if not l["can_buy"]:
			add_event("info", l["why"])
			return false
		if pay_full:
			if cash < l["price"]:
				add_event("info", "You need $%d to pay in full." % int(l["price"]))
				return false
			cash -= l["price"]
		else:
			var b: Dictionary = bal["bank"]
			cash -= l["down"]
			loans.append({"id": take_id(), "kind": "mortgage", "name": "Mortgage on %s" % l["name"], "balance": l["mortgage"],
				"rate": float(b["mortgage_rate"]), "payment": l["payment"], "days_left": l["days"]})
		var p = _add_property(key)
		add_event("bought", "You bought %s! It's a bit run down: %d rooms are out of order." % [p.display_name(), p.broken_rooms().size()], {"prop": p.index})
		return true
	return false


# --------------------------------------------------------------------------- campaign

func chapter_info() -> Dictionary:
	var chapters: Array = bal["campaign"]["chapters"]
	return chapters[clampi(chapter - 1, 0, chapters.size() - 1)]


## Progress toward the current chapter's goal (the number the goal is measured on).
func goal_value() -> float:
	match chapter_info()["type"]:
		"net_worth":
			return net_worth()
		_:
			return cash - debt()


func goal_met() -> bool:
	var c := chapter_info()
	if c.has("needs") and not owns(c["needs"]):
		return false
	return goal_value() >= float(c["amount"])


func goal_text() -> String:
	var c := chapter_info()
	return c["goal"].format({"amount": money(c["amount"]), "days": int(c["days"])})


## 12345.6 -> "12,345"
static func money(v: float) -> String:
	var neg := v < 0
	var s := str(int(absf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


# --------------------------------------------------------------------------- main loop

func tick(minutes: float) -> void:
	while minutes > 0.0 and game_over == "":
		var to_midnight := MIN_PER_DAY - minute_of_day()
		var dt := minf(minf(minutes, 0.5), to_midnight)
		time += dt
		_update_travel()
		_update_commutes()
		for p in properties:
			p.step(dt)
		minutes -= dt
		if minute_of_day() < 0.0001 or MIN_PER_DAY - minute_of_day() < 0.0001:
			time = roundf(time / MIN_PER_DAY) * MIN_PER_DAY
			_end_of_day()


## Midnight: each property pays wages and upkeep, the bank takes its payments, then the daily report.
func _end_of_day() -> void:
	var ended_day := day() - 1
	var prop_reports := []
	for p in properties:
		prop_reports.append(p.close_day(ended_day))
	_pay_loans()
	var net: float = -_bank_today["interest"]
	for r in prop_reports:
		net += r["net"]
	var report := {
		"day": ended_day,
		"props": prop_reports,
		"loan_payments": _bank_today["payments"],
		"interest": _bank_today["interest"],
		"net": net,
		"cash": cash,
		"debt": debt(),
		"net_worth": net_worth(),
	}
	_bank_today = {"payments": 0.0, "interest": 0.0}
	reports.append(report)
	_event_day_end(report)
	_check_game_over(ended_day)


func _event_day_end(report: Dictionary) -> void:
	add_event("day_end", "Day %d is over. Net: $%d." % [report["day"], int(report["net"])], {"report": report})


func _check_game_over(ended_day: int) -> void:
	if mode != "campaign":
		return
	var c := chapter_info()
	if goal_met():
		var chapters: Array = bal["campaign"]["chapters"]
		if chapter < chapters.size():
			chapter += 1
			neg_days = 0
			add_event("chapter", c["win"], {"chapter": chapter})
		else:
			game_over = "won"
			add_event("game_over", c["win"])
		return
	neg_days = neg_days + 1 if cash < 0.0 else 0
	if neg_days >= int(bal["campaign"]["bankrupt_days"]):
		game_over = "bankrupt"
		add_event("game_over", "Bankrupt! The bank took the keys.")
	elif ended_day >= int(c["days"]):
		game_over = "out_of_time"
		add_event("game_over", "Day %d came and went without reaching the goal: %s" % [ended_day, goal_text()])


# --------------------------------------------------------------------------- save / load

func to_save() -> Dictionary:
	return {
		"version": SAVE_VERSION, "mode": mode, "chapter": chapter, "time": time, "cash": cash,
		"loans": loans, "travel": travel, "reports": reports, "next_id": next_id, "neg_days": neg_days,
		"game_over": game_over, "rng_state": rng.state, "bank_today": _bank_today,
		"owner": inst_to_dict(owner_w), "owner_at": owner_prop(),
		"commutes": commutes.map(func(c): return {"worker": inst_to_dict(c["worker"]), "from": c["from"], "to": c["to"], "eta": c["eta"]}),
		"props": properties.map(func(p): return p.to_save()),
	}


func from_save(balance: Dictionary, data: Dictionary) -> void:
	bal = balance
	if int(data.get("version", 0)) == 1:
		data = _upgrade_v1(data)
	for k in ["mode", "chapter", "time", "cash", "loans", "travel", "reports", "next_id", "neg_days", "game_over"]:
		set(k, data[k])
	rng.state = data["rng_state"]
	_bank_today = data.get("bank_today", {"payments": 0.0, "interest": 0.0})
	events = []
	properties = []
	for i in data["props"].size():
		var p = Property.new()
		p.from_save(self, i, data["props"][i])
		properties.append(p)
	commutes = []
	for c in data.get("commutes", []):
		commutes.append({"worker": dict_to_inst(c["worker"]), "from": c["from"], "to": c["to"], "eta": c["eta"]})
	owner_w = dict_to_inst(data["owner"])
	var at: int = data["owner_at"]
	if at >= 0:
		properties[at].workers.insert(0, owner_w)


## Saves from milestone 1 had a single motel and no bank. Wrap them up as a v2 save.
static func _upgrade_v1(d: Dictionary) -> Dictionary:
	var owner_d: Dictionary = {}
	var staff: Array = []
	for wd in d["workers"]:
		if wd.get("role", "") == "owner":
			owner_d = wd
		else:
			wd["shift"] = "evening" if wd.get("role", "") == "clerk" else "day"
			wd["present"] = true
			staff.append(wd)
	for o in owner_d.get("orders", []):
		o["prop"] = 0
	var new_reports := []
	for r in d["reports"]:
		var pr: Dictionary = r.duplicate()
		pr["name"] = "Roadside Motel"
		pr["key"] = "motel"
		new_reports.append({"day": r["day"], "props": [pr], "loan_payments": 0.0, "interest": 0.0, "net": r["net"],
			"cash": r["cash"], "debt": 0.0, "net_worth": r["cash"]})
	return {
		"version": SAVE_VERSION, "mode": d["mode"], "chapter": 1, "time": d["time"], "cash": d["cash"],
		"loans": [], "travel": {}, "reports": new_reports, "next_id": d["next_id"], "neg_days": d["neg_days"],
		"game_over": d["game_over"], "rng_state": d["rng_state"], "owner": owner_d, "owner_at": 0,
		"props": [{
			"key": "motel", "rates": d["rates"], "early_fee": d.get("early_fee", 20.0), "queue": d["queue"],
			"stations": d["stations"], "reviews": d["reviews"], "arrivals": d["arrivals"],
			"candidates": d["candidates"], "ledger": d["ledger"], "stats": d["stats"],
			"rooms": d["rooms"], "workers": staff, "guests": d["guests"],
		}],
	}


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
	if typeof(data) != TYPE_DICTIONARY or not int(data.get("version", 0)) in [1, SAVE_VERSION]:
		return false
	from_save(balance, data)
	return true
