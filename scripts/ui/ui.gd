extends Control
## All on-screen UI: top bar, notifications, owner panel and management windows.
## Built in code so it is easy to tweak; every window pauses the game while open.

const Layout := preload("res://scripts/sim/layout.gd")

const LOG_COLORS := {
	"angry": Color(1.0, 0.5, 0.45), "lost": Color(0.85, 0.7, 0.55), "warn": Color(1.0, 0.75, 0.35),
	"review": Color(1.0, 0.9, 0.5), "discount": Color(1.0, 0.85, 0.3), "staff": Color(0.6, 0.85, 1.0),
	"checkin": Color(0.6, 1.0, 0.65), "clean": Color(0.6, 0.9, 1.0), "day_end": Color(1, 1, 1),
}

var main
var sim
var _labels := {}
var _speed_buttons := {}
var _log: VBoxContainer
var _owner_status: Label
var _owner_orders: Label
var _hint: Label
var _toast: Label
var _toast_time := 0.0
var modal: Control = null
var modal_kind := ""
var _discounts: Array = []
var _reports: Array = []
var show_reports := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_top_bar()
	_build_log()
	_build_owner_panel()
	_hint = Label.new()
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -34
	_hint.offset_bottom = -10
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast = Label.new()
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 48
	_toast.offset_bottom = 72
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "DejaVu Sans", "Noto Sans"])
	var sym := SystemFont.new()
	sym.font_names = PackedStringArray(["Segoe UI Symbol", "Apple Symbols", "DejaVu Sans", "Noto Sans Symbols2"])
	f.fallbacks = [sym]
	t.default_font = f
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.11, 0.1, 0.16, 0.92)
	panel.border_color = Color(0.95, 0.4, 0.45, 0.9)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


# --------------------------------------------------------------------------- persistent HUD

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.1, 0.16, 0.95)
	sb.set_content_margin_all(6)
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	for k in ["day", "clock", "cash", "rating", "line"]:
		var l := Label.new()
		_labels[k] = l
		row.add_child(l)
	_labels["cash"].add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_labels["rating"].add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for s in [0, 1, 2, 4]:
		var b := Button.new()
		b.text = "II" if s == 0 else "%dx" % s
		b.toggle_mode = true
		b.tooltip_text = "Pause (Space)" if s == 0 else "Speed %dx (keys 1-3)" % s
		b.pressed.connect(func(): main.set_speed(s))
		_speed_buttons[s] = b
		row.add_child(b)
	for item in [["Rates", show_rates], ["Staff", show_staff], ["Reviews", show_reviews], ["Report", show_last_report],
			["Save", func(): main.save_game()], ["Load", func(): main.load_game()], ["?", show_help]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		row.add_child(b)


func _build_log() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(360, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.55)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -372
	p.offset_right = -10
	p.offset_top = 80
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_log)
	p.visible = false


func _build_owner_panel() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(340, 0)
	add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = 10
	p.offset_bottom = -44
	p.offset_top = -44
	var v := VBoxContainer.new()
	p.add_child(v)
	_owner_status = Label.new()
	v.add_child(_owner_status)
	_owner_orders = Label.new()
	_owner_orders.autowrap_mode = TextServer.AUTOWRAP_WORD
	_owner_orders.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	_owner_orders.add_theme_font_size_override("font_size", 13)
	v.add_child(_owner_orders)
	var h := HBoxContainer.new()
	v.add_child(h)
	var desk := Button.new()
	desk.text = "Work the desk"
	desk.tooltip_text = "Send yourself to the front desk (F)"
	desk.pressed.connect(func(): sim.order_desk())
	h.add_child(desk)
	var clr := Button.new()
	clr.text = "Clear to-do list"
	clr.pressed.connect(func(): sim.clear_orders())
	h.add_child(clr)


func set_hint(text: String) -> void:
	_hint.text = text


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 3.0


func refresh() -> void:
	if sim == null:
		return
	_labels["day"].text = "Day %d%s" % [sim.day(), "/%d" % int(sim.bal["goal"]["days"]) if sim.mode == "campaign" else ""]
	_labels["clock"].text = sim.clock_text()
	_labels["cash"].text = "$%s" % _money(sim.cash)
	if sim.mode == "campaign":
		_labels["cash"].text += "  (goal $%s)" % _money(sim.bal["goal"]["cash"])
	_labels["rating"].text = "%s %.1f" % [_stars(sim.rating()), sim.rating()]
	_labels["line"].text = "Line: %d" % sim.queue.size()
	for s in _speed_buttons:
		_speed_buttons[s].button_pressed = (main.speed == s)
	var o = sim.owner()
	_owner_status.text = "You: " + _job_text(o)
	var todo: Array = o.orders.map(func(ord): return "Desk" if ord["type"] == "desk" else "Clean room %d" % (ord["room"] + 1))
	_owner_orders.text = "To-do: " + (", ".join(todo) if not todo.is_empty() else "(nothing queued) - click a dirty room or the desk")


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func _job_text(w) -> String:
	match w.job.get("type", ""):
		"desk":
			if w.serving != -1 and sim.guests.has(w.serving):
				var g = sim.guests[w.serving]
				return "%s %s" % ["Checking in" if g.purpose == "checkin" else "Checking out", g.name]
			return "At the front desk"
		"clean":
			return "Cleaning room %d" % (w.job["room"] + 1) if w.arrived() else "Walking to room %d" % (w.job["room"] + 1)
	return "Idle"


static func _stars(r: float) -> String:
	var full := int(round(r))
	return "★".repeat(full) + "☆".repeat(5 - full)


static func _money(v: float) -> String:
	var neg := v < 0
	var s := str(int(absf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


func push_log(e: Dictionary) -> void:
	if e["type"] in ["arrive", "checkout", "info"] and _log.get_child_count() > 0 and main.speed >= 4:
		return
	var l := Label.new()
	l.text = "%s  %s" % [e["time"], e["text"]]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(340, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", LOG_COLORS.get(e["type"], Color(0.85, 0.85, 0.9)))
	_log.add_child(l)
	_log.move_child(l, 0)
	_log.get_parent().visible = true
	while _log.get_child_count() > 8:
		var last := _log.get_child(_log.get_child_count() - 1)
		_log.remove_child(last)
		last.queue_free()
	if e["type"] == "info":
		toast(e["text"])


# --------------------------------------------------------------------------- modal windows

func is_modal_open() -> bool:
	return modal != null


func close_modal() -> void:
	if modal != null:
		modal.queue_free()
	modal = null
	modal_kind = ""
	_next_popup()


func _open(kind: String, title: String, closable := true, width := 520) -> VBoxContainer:
	if modal != null:
		modal.queue_free()
	modal_kind = kind
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal = dim
	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if closable:
		var x := Button.new()
		x.text = "Close"
		x.pressed.connect(close_modal)
		head.add_child(x)
	v.add_child(HSeparator.new())
	return v


func _text(parent: Control, text: String, size := 15, color := Color(0.9, 0.9, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	if not parent is HBoxContainer and not parent is GridContainer:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func show_rates() -> void:
	var v := _open("rates", "Room rates")
	_text(v, "Set the nightly price for each room type. A better rating means guests accept higher prices. Overpriced rooms upset guests, and if it's far too high they'll drive past.", 13)
	var expect := {
		"single": [sim.willingness("budget"), sim.willingness("business")],
		"double": [sim.willingness("family"), sim.willingness("family")],
	}
	for t in sim.rates:
		var count: int = sim.rooms.filter(func(r): return r.type == t).size()
		var row := HBoxContainer.new()
		v.add_child(row)
		var name_l := _text(row, "%s rooms (%d)" % [sim.bal["room_types"][t]["name"], count])
		name_l.custom_minimum_size = Vector2(170, 0)
		var spin := SpinBox.new()
		spin.min_value = 10
		spin.max_value = 500
		spin.step = 1
		spin.prefix = "$"
		spin.suffix = "/night"
		spin.value = sim.rates[t]
		spin.custom_minimum_size = Vector2(150, 0)
		spin.value_changed.connect(func(val): sim.set_rate(t, val))
		row.add_child(spin)
		var lo: float = expect[t][0]
		var hi: float = expect[t][1]
		var hint := "Guests expect about $%d" % int(lo) if absf(hi - lo) < 1.0 else "Guests expect $%d-$%d" % [int(lo), int(hi)]
		_text(row, "  " + hint, 13, Color(0.75, 0.85, 0.75))
	var erow := HBoxContainer.new()
	v.add_child(erow)
	var el := _text(erow, "Early check-in fee")
	el.custom_minimum_size = Vector2(170, 0)
	var espin := SpinBox.new()
	espin.min_value = 0
	espin.max_value = 200
	espin.prefix = "$"
	espin.value = sim.early_fee
	espin.custom_minimum_size = Vector2(150, 0)
	espin.value_changed.connect(func(val): sim.set_early_fee(val))
	erow.add_child(espin)
	_text(erow, "  offered when guests arrive before 3 PM ($0 = always free)", 13, Color(0.75, 0.85, 0.75))
	var lrow := HBoxContainer.new()
	v.add_child(lrow)
	var ll := _text(lrow, "Late check-out fee")
	ll.custom_minimum_size = Vector2(170, 0)
	var lspin := SpinBox.new()
	lspin.min_value = 0
	lspin.max_value = 200
	lspin.prefix = "$"
	lspin.value = sim.late_fee
	lspin.custom_minimum_size = Vector2(150, 0)
	lspin.value_changed.connect(func(val): sim.set_late_fee(val))
	lrow.add_child(lspin)
	_text(lrow, "  offered when guests ask to stay past 11 AM, up to 1 PM ($0 = always free)", 13, Color(0.75, 0.85, 0.75))
	_text(v, "Daily upkeep: $%d (utilities, laundry, supplies)." % int(sim.daily_upkeep()), 13, Color(0.8, 0.8, 0.85))


func show_staff() -> void:
	var v := _open("staff", "Staff", true, 620)
	_text(v, "Staff work automatically. Clerks run the front desk; housekeepers clean dirty rooms. Wages are paid every night. Staff paid below the going rate might quit.", 13)
	_text(v, "Your team", 18, Color(1, 0.85, 0.6))
	var team: Array = sim.staff()
	if team.is_empty():
		_text(v, "Nobody yet. It's just you!", 14, Color(0.7, 0.7, 0.75))
	for w in team:
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := _text(row, "%s - %s" % [w.name, sim.bal["staff"][w.role]["name"]])
		l.custom_minimum_size = Vector2(260, 0)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 500
		spin.prefix = "$"
		spin.suffix = "/day"
		spin.custom_minimum_size = Vector2(130, 0)
		spin.value = w.wage
		spin.value_changed.connect(func(val): sim.set_wage(w.id, val))
		row.add_child(spin)
		var market: float = sim.bal["staff"][w.role]["market_wage"]
		_text(row, " going rate $%d" % int(market), 12, Color(0.7, 0.8, 0.7))
		_button(row, "Let go", func(): sim.fire(w.id); show_staff())
	_text(v, "Total wages: $%d/day" % int(sim.daily_wages()), 13, Color(0.8, 0.8, 0.85))
	v.add_child(HSeparator.new())
	_text(v, "Applicants (new ones arrive each morning)", 18, Color(1, 0.85, 0.6))
	if sim.candidates.is_empty():
		_text(v, "No applicants today.", 14, Color(0.7, 0.7, 0.75))
	for i in sim.candidates.size():
		var c: Dictionary = sim.candidates[i]
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := _text(row, "%s - %s" % [c["name"], sim.bal["staff"][c["role"]]["name"]])
		l.custom_minimum_size = Vector2(260, 0)
		var w_l := _text(row, "asks $%d/day" % int(c["wage"]))
		w_l.custom_minimum_size = Vector2(130, 0)
		var full: bool = sim.staff_count(c["role"]) >= int(sim.bal["staff"][c["role"]]["max"])
		var b := _button(row, "Hire", func(): sim.hire(i); show_staff())
		b.disabled = full
		if full:
			b.tooltip_text = "You have as many of these as this motel needs."


func show_reviews() -> void:
	var v := _open("reviews", "Reviews", true, 640)
	_text(v, "%s  %.1f average (recent reviews count most)" % [_stars(sim.rating()), sim.rating()], 18, Color(1, 0.85, 0.35))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if sim.reviews.is_empty():
		_text(list, "No reviews yet. Guests review you when they leave.", 14, Color(0.7, 0.7, 0.75))
	var recent: Array = sim.reviews.slice(maxi(0, sim.reviews.size() - 40))
	recent.reverse()
	for r in recent:
		_text(list, "%s  %s (%s, day %d)" % ["★".repeat(r["stars"]) + "☆".repeat(5 - r["stars"]), r["author"],
			sim.bal["archetypes"][r["archetype"]]["name"], r["day"]], 14, Color(1, 0.85, 0.4))
		_text(list, "\"%s\"" % r["text"], 14)


func show_help() -> void:
	var v := _open("help", "How to play", true, 640)
	_text(v, """You own a little roadside motel. Keep guests happy and make money.

- Guests line up at the front desk. Someone has to be AT the desk to check them in or out.
- Check-out is between 7 and 11 AM. Check-in opens at 3 PM. Use the time in between to clean.
- Early birds may ask to check in early: say no, charge a fee (set it under Rates), or let them in free. Some will haggle.
- Guests may call the night before or on check-out morning (before 11 AM) to ask for a late check-out, up to 1 PM. Same choices. Happy guests and extra fees, but their room gets cleaned later.
- When guests check out, their room is dirty. Click a dirty room to go clean it.
- If a guest checks in before their room is clean, they wait in the lobby and get grumpy.
- Waiting too long ruins the mood. Unhappy guests ask for discounts and leave bad reviews.
- Your rating sets how many guests come and how much they'll pay.
- Hire a housekeeper or clerk (Staff) once you can afford them.

Controls
- Left click: room = clean it, desk/lobby/guest = work the desk
- You can queue several jobs; they happen in order.
- Drag, WASD or arrow keys: move the camera. Wheel, pinch or +/-: zoom.
- Space: pause. 1 / 2 / 3: speed. F: go to the front desk. Esc: close window.""", 14)


func show_report(report: Dictionary) -> void:
	var v := _open("report", "End of day %d" % report["day"], false, 460)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	v.add_child(grid)
	var rows := [
		["Room revenue", "$%d" % int(report["revenue"])],
		["Refunds & discounts", "-$%d" % int(report["refunds"])],
		["Staff wages", "-$%d" % int(report["wages"])],
		["Upkeep", "-$%d" % int(report["upkeep"])],
		["Net today", "$%d" % int(report["net"])],
		["Cash", "$%s" % _money(report["cash"])],
		["Check-ins / check-outs", "%d / %d" % [report["checkins"], report["checkouts"]]],
		["Walked out", str(report["walkouts"])],
		["Turned away (price / full / line)", str(report["turned_away"])],
		["Reviews today", "%d (avg %.1f)" % [report["reviews"], report["avg_stars"]] if report["reviews"] > 0 else "0"],
		["Rating", "%.2f" % report["rating"]],
	]
	for r in rows:
		_text(grid, r[0], 14, Color(0.8, 0.8, 0.85))
		var val := _text(grid, r[1], 14)
		if r[0] == "Net today":
			val.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if report["net"] >= 0 else Color(1, 0.5, 0.45))
	for q in report["quits"]:
		_text(v, "%s quit (underpaid)." % q, 14, Color(1, 0.6, 0.5))
	if sim.mode == "campaign":
		var left: int = int(sim.bal["goal"]["days"]) - int(report["day"])
		_text(v, "Goal: $%s cash. %d day%s left." % [_money(sim.bal["goal"]["cash"]), left, "" if left == 1 else "s"], 14, Color(1, 0.85, 0.5))
	var cb := CheckBox.new()
	cb.text = "Show this report every night"
	cb.button_pressed = show_reports
	cb.toggled.connect(func(on): show_reports = on)
	v.add_child(cb)
	_button(v, "Continue", close_modal)


func show_last_report() -> void:
	if sim.reports.is_empty():
		toast("No reports yet. The first one comes at midnight.")
		return
	show_report(sim.reports[-1])


func queue_report(report: Dictionary) -> void:
	if show_reports:
		_reports.append(report)
		_next_popup()


func queue_discount(guest_id: int) -> void:
	_discounts.append(guest_id)
	_next_popup()


func _next_popup() -> void:
	if modal != null:
		return
	while not _discounts.is_empty():
		var gid: int = _discounts.pop_front()
		if sim.guests.has(gid) and sim.guests[gid].state == "discount":
			_show_discount(sim.guests[gid])
			return
		if sim.guests.has(gid) and sim.guests[gid].state == "early_request":
			_show_early(sim.guests[gid])
			return
		if sim.guests.has(gid) and sim.guests[gid].late_state in ["asking", "haggling"]:
			_show_late(sim.guests[gid])
			return
	if not _reports.is_empty():
		show_report(_reports.pop_front())


func _show_discount(g) -> void:
	var v := _open("discount", "Discount request", false, 480)
	var base: float = g.paid
	var amount: float = base * g.discount_pct / 100.0
	var why := "waiting so long"
	if g.notes.get("room_not_ready", 0.0) < g.notes.get("long_wait", 0.0):
		why = "their room not being ready"
	if g.notes.get("overpriced", 0.0) < minf(g.notes.get("long_wait", 0.0), g.notes.get("room_not_ready", 0.0)):
		why = "the price"
	_text(v, "%s (%s) is unhappy about %s." % [g.name, sim.bal["archetypes"][g.archetype]["name"], why])
	_text(v, "Fun fact: this guest %s." % g.quirk, 13, Color(0.75, 0.75, 0.8))
	_text(v, "They'd like %d%% off: $%d." % [g.discount_pct, int(amount)], 18, Color(1, 0.85, 0.35))
	_text(v, "Saying yes costs money but softens their review. Saying no keeps the cash, but they'll be even grumpier.", 13, Color(0.8, 0.8, 0.85))
	var row := HBoxContainer.new()
	v.add_child(row)
	var gid: int = g.id
	_button(row, "Give %d%% off" % g.discount_pct, func(): sim.resolve_discount(gid, true); close_modal())
	_button(row, "Refuse", func(): sim.resolve_discount(gid, false); close_modal())


func _show_early(g) -> void:
	var haggling: bool = g.early_state == "haggling"
	var v := _open("early", "Early check-in" if not haggling else "Guest is haggling", false, 500)
	var arch: String = sim.bal["archetypes"][g.archetype]["name"]
	if haggling:
		_text(v, "%s (%s): \"Any chance you could waive that $%d fee? We've been driving all day.\"" % [g.name, arch, int(sim.early_fee)])
		_text(v, "Insisting on the fee might make them pay grudgingly, or walk back to the line and wait.", 13, Color(0.8, 0.8, 0.85))
	else:
		_text(v, "%s (%s) arrived at %s, before the 3 PM check-in, and asks to check in now. A clean room is free." % [g.name, arch, sim.clock_text()])
		_text(v, "Early check-in makes guests happier. A fee earns money, but some guests hate fees and may haggle.", 13, Color(0.8, 0.8, 0.85))
	_text(v, "Fun fact: this guest %s." % g.quirk, 13, Color(0.75, 0.75, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var gid: int = g.id
	_button(row, "No, wait until 3 PM", func(): sim.resolve_early(gid, "no"); close_modal())
	if sim.early_fee > 0.0:
		_button(row, ("Fee stands ($%d)" if haggling else "Yes, for a $%d fee") % int(sim.early_fee), func(): sim.resolve_early(gid, "fee"); close_modal())
	_button(row, "Waive the fee" if haggling else "Yes, free", func(): sim.resolve_early(gid, "free"); close_modal())


func _show_late(g) -> void:
	var haggling: bool = g.late_state == "haggling"
	var v := _open("late", "Late check-out" if not haggling else "Guest is haggling", false, 520)
	var arch: String = sim.bal["archetypes"][g.archetype]["name"]
	var until: String = sim.late_until_text(g)
	if haggling:
		_text(v, "%s (%s): \"Could you waive that $%d fee? It's only a little longer.\"" % [g.name, arch, int(sim.late_fee)])
		_text(v, "Insisting on the fee might make them pay grudgingly, or just leave at the usual time, unhappy.", 13, Color(0.8, 0.8, 0.85))
	else:
		var when: String = "tomorrow morning" if sim.day() < g.checkout_day else "this morning"
		_text(v, "%s (%s) in room %d calls the desk: they check out %s and would like to stay until %s." % [g.name, arch, g.room + 1, when, until])
		_text(v, "A late check-out makes guests happier and a fee earns money, but room %d can't be cleaned until they leave, and check-in opens at 3 PM." % [g.room + 1], 13, Color(0.8, 0.8, 0.85))
	_text(v, "Fun fact: this guest %s." % g.quirk, 13, Color(0.75, 0.75, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var gid: int = g.id
	_button(row, "No, usual time", func(): sim.resolve_late(gid, "no"); close_modal())
	if sim.late_fee > 0.0:
		_button(row, ("Fee stands ($%d)" if haggling else "Yes, for a $%d fee") % int(sim.late_fee), func(): sim.resolve_late(gid, "fee"); close_modal())
	_button(row, "Waive the fee" if haggling else "Yes, free", func(): sim.resolve_late(gid, "free"); close_modal())


func show_game_over(text: String) -> void:
	_discounts.clear()
	_reports.clear()
	var won: bool = sim.game_over == "won"
	var v := _open("gameover", "You did it!" if won else "Game over", false, 480)
	_text(v, text, 16)
	_text(v, "Day %d  -  cash $%s  -  rating %.1f  -  guests served %d" % [sim.day(), _money(sim.cash), sim.rating(), sim.stats["served"]], 14, Color(0.8, 0.8, 0.85))
	if won:
		_text(v, "Bigger hotels are coming in a future update. You can keep running the motel in sandbox mode.", 13, Color(0.8, 0.9, 0.8))
	var row := HBoxContainer.new()
	v.add_child(row)
	if won:
		_button(row, "Keep playing", func(): sim.mode = "sandbox"; sim.game_over = ""; close_modal())
	_button(row, "New campaign", func(): main.new_game("campaign"))
	_button(row, "Sandbox", func(): main.new_game("sandbox"))


func show_start(has_save: bool) -> void:
	var v := _open("start", "HotelWorld", false, 520)
	_text(v, "Your roadside motel adventure starts here.", 16, Color(1, 0.85, 0.6))
	_text(v, "Campaign: turn $%s into $%s within %d days so you can afford your next property. Go broke for %d nights in a row and the bank takes the keys." % [
		_money(sim.bal["start_cash"]), _money(sim.bal["goal"]["cash"]), int(sim.bal["goal"]["days"]), int(sim.bal["goal"]["bankrupt_days"])], 14)
	_text(v, "Sandbox: no goal, no bankruptcy. Just run the place.", 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "New campaign", func(): main.new_game("campaign"))
	_button(row, "Sandbox", func(): main.new_game("sandbox"))
	if has_save:
		_button(row, "Continue saved game", func(): main.load_game())
	_button(row, "How to play", show_help)
