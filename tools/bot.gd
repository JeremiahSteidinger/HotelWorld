extends RefCounted
## A simple automated "player" used by tests and the headless balance run.
## strategy: "solo" (owner does everything), "staffed" (hires help), "greedy" (high prices), "idle" (does nothing)

static func play(sim, strategy: String) -> void:
	if strategy == "idle":
		for g in sim.pending_discounts():
			sim.resolve_discount(g.id, false)
		return
	for g in sim.pending_discounts():
		sim.resolve_discount(g.id, g.discount_pct <= 20)
	if strategy == "pro":
		# Price rooms at what the typical guest will pay, given the current rating.
		sim.set_rate("single", (sim.willingness("budget") * 0.5 + sim.willingness("business") * 0.5) * 0.92)
		sim.set_rate("double", sim.willingness("family") * 0.92)
	if strategy in ["staffed", "pro"] and sim.day() >= 3:
		if sim.staff_count("housekeeper") < 1:
			_hire(sim, "housekeeper")
		elif sim.staff_count("clerk") < 1 and sim.cash > 2500:
			_hire(sim, "clerk")
	var o = sim.owner()
	if not o.orders.is_empty():
		return
	var line_busy: bool = not sim.queue.is_empty()
	var clerk_on_desk: bool = sim.staff_count("clerk") > 0
	var doing: String = o.job.get("type", "")
	if line_busy and not clerk_on_desk:
		# Clean rooms that guests are waiting for first, otherwise work the desk.
		if doing != "desk":
			sim.order_desk()
		return
	var waiting_for := -1
	var dirty := -1
	for r in sim.rooms:
		if r.state == "dirty" and r.cleaner_id == -1:
			if r.guest_id != -1:
				waiting_for = r.index
			elif dirty == -1:
				dirty = r.index
	var pick := waiting_for if waiting_for != -1 else dirty
	if pick != -1 and doing != "clean":
		if doing == "desk" and line_busy:
			return
		sim.order_clean(pick)
	elif pick == -1 and doing == "" and not clerk_on_desk:
		sim.order_desk()


static func _hire(sim, role: String) -> void:
	for i in sim.candidates.size():
		if sim.candidates[i]["role"] == role:
			sim.hire(i)
			sim.set_wage(sim.workers[-1].id, sim.bal["staff"][role]["market_wage"])
			return
