extends RefCounted
## A simple automated "player" used by tests and the headless balance run.
## strategy: "solo" (owner does everything), "staffed" (hires help), "greedy" (high prices),
##           "pro" (prices to demand, hires, buys the hotel in chapter 2), "idle" (does nothing)

static func play(game, strategy: String) -> void:
	for p in game.properties:
		_answer_guests(p, strategy)
	if strategy == "idle":
		return
	if strategy == "pro":
		for p in game.properties:
			_price(p)
		_maybe_buy(game)
		for p in game.properties:
			if p.key != "motel":
				_staff_hotel(p)
	var motel = game.properties[0]
	if strategy in ["staffed", "pro"] and game.day() >= 3:
		if motel.staff_count("housekeeper") < 1:
			_hire(motel, "housekeeper", "day")
		elif motel.staff_count("clerk") < 1 and game.cash > 2500:
			_hire(motel, "clerk", "evening")
	_drive_owner(game, motel)


static func _answer_guests(p, strategy: String) -> void:
	for g in p.pending_discounts():
		p.resolve_discount(g.id, strategy != "idle" and g.discount_pct <= 20)
	for g in p.pending_early():
		if strategy == "idle":
			p.resolve_early(g.id, "no")
		else:
			p.resolve_early(g.id, "fee" if g.early_state == "asking" else "free")
	for g in p.pending_late():
		if strategy == "idle":
			p.resolve_late(g.id, "no")
		else:
			p.resolve_late(g.id, "fee" if g.late_state == "asking" else "free")


## Price each room type at what its typical guest will pay, given the current rating.
static func _price(p) -> void:
	var sums := {}
	for k in p.archetype_keys():
		var a: Dictionary = p.archetype(k)
		if a["weight"] <= 0.0:
			continue
		var t: String = a["room"]
		if not sums.has(t):
			sums[t] = [0.0, 0.0]
		sums[t][0] += p.willingness(k) * a["weight"]
		sums[t][1] += a["weight"]
	for t in sums:
		p.set_rate(t, sums[t][0] / sums[t][1] * 0.92)


static func _maybe_buy(game) -> void:
	for l in game.listings():
		if l["can_buy"] and game.cash >= l["down"] + 600.0:
			game.buy_property(l["key"])


## A run-down hotel needs a full team: desk on all shifts, housekeepers and a fixer.
static func _staff_hotel(p) -> void:
	var want := [["clerk", "day"], ["clerk", "evening"], ["housekeeper", "day"], ["maintenance", "day"],
		["housekeeper", "day"], ["clerk", "night"], ["housekeeper", "evening"]]
	var have := {}
	for w in p.employees():
		var k: String = w.role + "/" + w.shift
		have[k] = have.get(k, 0) + 1
	for item in want:
		var k: String = item[0] + "/" + item[1]
		if have.get(k, 0) > 0:
			have[k] -= 1
			continue
		if p.game.cash < 300.0:
			return
		_hire(p, item[0], item[1])
		return  # one hire per tick: candidates list changes


static func _drive_owner(game, motel) -> void:
	var o = game.owner_w
	if game.owner_prop() != motel.index:
		if game.owner_prop() != -1 and o.orders.is_empty():
			game.order_go(motel.index)
		return
	if not o.orders.is_empty():
		return
	var line_busy: bool = not motel.queue.is_empty()
	var clerk_on_desk := false
	for w in motel.staff():
		if w.role == "clerk" and w.present and motel.on_duty(w):
			clerk_on_desk = true
	var doing: String = o.job.get("type", "")
	if line_busy and not clerk_on_desk:
		if doing != "desk":
			motel.order_desk()
		return
	var waiting_for := -1
	var dirty := -1
	var broken := -1
	for r in motel.rooms:
		if r.state == "dirty" and r.cleaner_id == -1:
			if r.guest_id != -1:
				waiting_for = r.index
			elif dirty == -1:
				dirty = r.index
		if r.broken != "" and r.fixer_id == -1 and broken == -1:
			broken = r.index
	var pick := waiting_for if waiting_for != -1 else dirty
	if pick != -1 and doing not in ["clean", "fix"]:
		if doing == "desk" and line_busy:
			return
		motel.order_clean(pick)
	elif pick == -1 and broken != -1 and doing not in ["clean", "fix"]:
		if doing == "desk" and line_busy:
			return
		motel.order_fix(broken)
	elif pick == -1 and broken == -1 and doing == "" and not clerk_on_desk:
		motel.order_desk()


static func _hire(p, role: String, shift: String) -> void:
	for i in p.candidates.size():
		if p.candidates[i]["role"] == role:
			if p.hire(i):
				var w = p.workers[-1]
				p.set_wage(w.id, p.bal["staff"][role]["market_wage"])
				p.set_shift(w.id, shift)
			return
