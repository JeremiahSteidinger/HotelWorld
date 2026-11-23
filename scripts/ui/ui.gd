extends Control
## All on-screen UI: top bar, notifications, owner panel and management windows.
## Built in code so it is easy to tweak; every window pauses the game while open.

const Layout := preload("res://scripts/sim/layout.gd")

const LOG_COLORS := {
	"angry": Color(1.0, 0.5, 0.45), "lost": Color(0.85, 0.7, 0.55), "warn": Color(1.0, 0.75, 0.35),
	"review": Color(1.0, 0.9, 0.5), "discount": Color(1.0, 0.85, 0.3), "staff": Color(0.6, 0.85, 1.0),
	"checkin": Color(0.6, 1.0, 0.65), "clean": Color(0.6, 0.9, 1.0), "day_end": Color(1, 1, 1),
	"broken": Color(1.0, 0.6, 0.3), "fixed": Color(0.7, 0.95, 0.6), "bank": Color(0.75, 0.95, 0.75),
	"travel": Color(0.8, 0.8, 1.0), "bought": Color(1.0, 0.9, 0.5), "chapter": Color(1.0, 0.9, 0.5),
}

var main
var game        # the whole business
var sim         # the property on screen
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
var _discounts: Array = []   # [property index, guest id]
var _reports: Array = []
var _chapters: Array = []
var _tabs: HBoxContainer
var _goal: Label
var _drive_btn: Button
var show_reports := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_top_bar()
	_build_sub_bar()
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
	_toast.offset_top = 84
	_toast.offset_bottom = 108
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
			["Bank", show_bank], ["Properties", show_properties],
			["Save", func(): main.save_game()], ["Load", func(): main.load_game()], ["?", show_help]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		row.add_child(b)


## Second row: one tab per property you own, plus the campaign goal.
func _build_sub_bar() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = 44
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	row.add_child(_tabs)
	_goal = Label.new()
	_goal.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	_goal.add_theme_color_override("font_outline_color", Color.BLACK)
	_goal.add_theme_constant_override("outline_size", 5)
	_goal.add_theme_font_size_override("font_size", 14)
	_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_goal)


func rebuild_tabs() -> void:
	if _tabs == null or game == null:
		return
	for c in _tabs.get_children():
		c.queue_free()
	if game.properties.size() < 2:
		return
	for p in game.properties:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("prop", p.index)
		b.tooltip_text = "View %s (Tab switches)" % p.display_name()
		var i: int = p.index
		b.pressed.connect(func(): main.show_property(i))
		_tabs.add_child(b)


func _refresh_tabs() -> void:
	for b in _tabs.get_children():
		var p = game.properties[b.get_meta("prop")]
		var here := " (you)" if game.owner_prop() == p.index else ""
		b.text = "%s  %.1f★  line %d%s" % [p.display_name(), p.rating(), p.queue.size(), here]
		b.button_pressed = p == sim


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
	p.offset_top = 84
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
	_drive_btn = Button.new()
	_drive_btn.text = "Drive here"
	_drive_btn.tooltip_text = "Drive to the property you're looking at"
	_drive_btn.pressed.connect(func(): game.order_go(sim.index))
	h.add_child(_drive_btn)
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
	if sim == null or game == null:
		return
	var campaign: bool = game.mode == "campaign"
	_labels["day"].text = "Day %d%s" % [game.day(), "/%d" % int(game.chapter_info()["days"]) if campaign else ""]
	_labels["clock"].text = game.clock_text()
	_labels["cash"].text = "$%s" % _money(game.cash)
	if not game.loans.is_empty():
		_labels["cash"].text += "  (owe $%s)" % _money(game.debt())
	_labels["rating"].text = "%s %.1f" % [_stars(sim.rating()), sim.rating()]
	_labels["line"].text = "Line: %d" % sim.queue.size()
	for s in _speed_buttons:
		_speed_buttons[s].button_pressed = (main.speed == s)
	_refresh_tabs()
	if campaign and game.game_over == "":
		var c: Dictionary = game.chapter_info()
		var what := "net worth" if c["type"] == "net_worth" else "saved"
		_goal.text = "Chapter %d goal: %s $%s of $%s by day %d" % [game.chapter, what, _money(game.goal_value()), _money(c["amount"]), int(c["days"])]
		if c.has("needs") and not game.owns(c["needs"]):
			_goal.text += " (buy the hotel first)"
	else:
		_goal.text = "Net worth $%s" % _money(game.net_worth()) if game.properties.size() > 1 or not game.loans.is_empty() else ""
	var o = game.owner_w
	var at: int = game.owner_prop()
	if at == -1:
		_owner_status.text = "You: driving to %s (%d min)" % [game.properties[game.travel["to"]].display_name(), int(ceil(game.travel_minutes_left()))]
	else:
		_owner_status.text = "You: " + _job_text(o, game.properties[at])
		if game.properties.size() > 1:
			_owner_status.text += " at " + game.properties[at].display_name()
	var many: bool = game.properties.size() > 1
	var todo: Array = o.orders.map(func(ord): return _order_text(ord, many))
	_owner_orders.text = "To-do: " + (", ".join(todo) if not todo.is_empty() else "(nothing queued) - click a dirty or broken room, or the desk")
	_drive_btn.visible = many
	_drive_btn.disabled = at == sim.index or (not o.orders.is_empty() and o.orders[-1]["prop"] == sim.index)
	_drive_btn.text = "Drive to %s" % sim.display_name()


func _order_text(ord: Dictionary, many: bool) -> String:
	var p = game.properties[ord["prop"]]
	var where := " (%s)" % p.display_name() if many else ""
	match ord["type"]:
		"desk":
			return "Desk" + where
		"clean":
			return "Clean room %s%s" % [p.room_label(ord["room"]), where]
		"fix":
			return "Fix room %s%s" % [p.room_label(ord["room"]), where]
		"go":
			return "Drive to %s" % p.display_name()
	return ord["type"]


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func _job_text(w, p) -> String:
	match w.job.get("type", ""):
		"desk":
			if w.serving != -1 and p.guests.has(w.serving):
				var g = p.guests[w.serving]
				return "%s %s" % ["Checking in" if g.purpose == "checkin" else "Checking out", g.name]
			return "At the front desk"
		"clean":
			return "Cleaning room %s" % p.room_label(w.job["room"]) if w.arrived() else "Walking to room %s" % p.room_label(w.job["room"])
		"fix":
			return "Fixing room %s" % p.room_label(w.job["room"]) if w.arrived() else "Walking to room %s" % p.room_label(w.job["room"])
		"travel":
			return "Walking to the car"
	if not w.present:
		return "Off shift"
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


## A short tag for log lines once you own more than one property.
func _prop_tag(e: Dictionary) -> String:
	if game == null or game.properties.size() < 2 or not e.has("prop"):
		return ""
	return "[%s] " % game.properties[e["prop"]].cfg["layout"].capitalize()


func push_log(e: Dictionary) -> void:
	if e["type"] in ["arrive", "checkout", "info"] and _log.get_child_count() > 0 and main.speed >= 4:
		return
	var l := Label.new()
	l.text = "%s  %s%s" % [e["time"], _prop_tag(e), e["text"]]
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


func _spin(lo: float, hi: float, value: float, prefix := "$", suffix := "", width := 150, step := 1.0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.prefix = prefix
	spin.suffix = suffix
	spin.value = value
	spin.custom_minimum_size = Vector2(width, 0)
	return spin


func _title(base: String) -> String:
	return "%s - %s" % [base, sim.display_name()] if game.properties.size() > 1 else base


func show_rates() -> void:
	var v := _open("rates", _title("Room rates"))
	_text(v, "Set the nightly price for each room type. A better rating means guests accept higher prices. Overpriced rooms upset guests, and if it's far too high they'll drive past.", 13)
	var expect := {}
	for k in sim.archetype_keys():
		var a: Dictionary = sim.archetype(k)
		if a["weight"] <= 0.0:
			continue
		if not expect.has(a["room"]):
			expect[a["room"]] = []
		expect[a["room"]].append(sim.willingness(k))
	for t in sim.rates:
		var count: int = sim.rooms.filter(func(r): return r.type == t).size()
		var row := HBoxContainer.new()
		v.add_child(row)
		var name_l := _text(row, "%s rooms (%d)" % [sim.room_type_name(t), count])
		name_l.custom_minimum_size = Vector2(170, 0)
		var spin := _spin(10, 800, sim.rates[t], "$", "/night")
		spin.value_changed.connect(func(val): sim.set_rate(t, val))
		row.add_child(spin)
		var vals: Array = expect.get(t, [])
		if not vals.is_empty():
			var lo: float = vals.min()
			var hi: float = vals.max()
			var hint := "Guests expect about $%d" % int(lo) if absf(hi - lo) < 1.0 else "Guests expect $%d-$%d" % [int(lo), int(hi)]
			_text(row, "  " + hint, 13, Color(0.75, 0.85, 0.75))
	var erow := HBoxContainer.new()
	v.add_child(erow)
	var el := _text(erow, "Early check-in fee")
	el.custom_minimum_size = Vector2(170, 0)
	var espin := _spin(0, 200, sim.early_fee)
	espin.value_changed.connect(func(val): sim.set_early_fee(val))
	erow.add_child(espin)
	_text(erow, "  offered when guests arrive before 3 PM ($0 = always free)", 13, Color(0.75, 0.85, 0.75))
	var lrow := HBoxContainer.new()
	v.add_child(lrow)
	var ll := _text(lrow, "Late check-out fee")
	ll.custom_minimum_size = Vector2(170, 0)
	var lspin := _spin(0, 200, sim.late_fee)
	lspin.value_changed.connect(func(val): sim.set_late_fee(val))
	lrow.add_child(lspin)
	_text(lrow, "  offered when guests ask to stay past 11 AM, up to 1 PM ($0 = always free)", 13, Color(0.75, 0.85, 0.75))
	_text(v, "Daily upkeep: $%d (utilities, laundry, supplies)." % int(sim.daily_upkeep()), 13, Color(0.8, 0.8, 0.85))


func _shift_text(shift: String) -> String:
	var sh: Dictionary = sim.bal["shifts"][shift]
	return "%s %s-%s" % [sh["name"], _hour(sh["hours"][0]), _hour(sh["hours"][1])]


static func _hour(h: int) -> String:
	h = h % 24
	return "%d %s" % [12 if h % 12 == 0 else h % 12, "AM" if h < 12 else "PM"]


func show_staff() -> void:
	var v := _open("staff", _title("Staff"), true, 760)
	_text(v, "Staff work automatically during their shift. Clerks run the front desk, housekeepers clean, maintenance techs fix broken rooms. Wages are paid every night. Staff paid below the going rate might quit.", 13)
	# Who is on when: the desk needs someone from 7 AM (check-outs) until late (check-ins).
	var cov := HBoxContainer.new()
	v.add_child(cov)
	for role in ["clerk", "housekeeper", "maintenance"]:
		if sim.staff_max(role) <= 0:
			continue
		var c: Dictionary = sim.coverage(role)
		var parts := []
		for sh in sim.bal["shifts"]:
			parts.append("%s %d" % [sim.bal["shifts"][sh]["name"], c[sh]])
		var col := Color(0.75, 0.85, 0.75)
		if role == "clerk" and (c["day"] == 0 or c["evening"] == 0):
			col = Color(1, 0.75, 0.45)
		_text(cov, "%ss: %s   " % [sim.bal["staff"][role]["name"], ", ".join(parts)], 12, col)
	if sim.coverage("clerk")["evening"] == 0 or sim.coverage("clerk")["day"] == 0:
		_text(v, "Tip: with no clerk on a shift, someone (you!) has to work the desk then, or guests walk out.", 12, Color(1, 0.75, 0.45))
	_text(v, "Your team", 18, Color(1, 0.85, 0.6))
	var team: Array = sim.staff()
	if team.is_empty():
		_text(v, "Nobody yet. It's just you!", 14, Color(0.7, 0.7, 0.75))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, mini(team.size(), 6) * 36)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for w in team:
		var row := HBoxContainer.new()
		list.add_child(row)
		var l := _text(row, "%s - %s" % [w.name, sim.bal["staff"][w.role]["name"]])
		l.custom_minimum_size = Vector2(250, 0)
		var opt := OptionButton.new()
		var shifts: Array = sim.bal["shifts"].keys()
		for i in shifts.size():
			opt.add_item(_shift_text(shifts[i]), i)
		opt.selected = shifts.find(w.shift)
		opt.custom_minimum_size = Vector2(170, 0)
		var wid: int = w.id
		opt.item_selected.connect(func(i): sim.set_shift(wid, shifts[i]); show_staff())
		row.add_child(opt)
		var spin := _spin(0, 500, w.wage, "$", "/day", 120)
		spin.value_changed.connect(func(val): sim.set_wage(wid, val))
		row.add_child(spin)
		var market: float = sim.bal["staff"][w.role]["market_wage"]
		_text(row, " rate $%d " % int(market), 12, Color(0.7, 0.8, 0.7))
		_button(row, "Let go", func(): sim.fire(wid); show_staff())
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
		l.custom_minimum_size = Vector2(250, 0)
		var w_l := _text(row, "asks $%d/day, starts on %s" % [int(c["wage"]), _shift_text(sim.default_shift(c["role"]))])
		w_l.custom_minimum_size = Vector2(330, 0)
		var full: bool = sim.staff_count(c["role"]) >= sim.staff_max(c["role"])
		var b := _button(row, "Hire", func(): sim.hire(i); show_staff())
		b.disabled = full
		if full:
			b.tooltip_text = "You have as many of these as %s needs." % sim.display_name()


func show_reviews() -> void:
	var v := _open("reviews", _title("Reviews"), true, 640)
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


func show_bank() -> void:
	var v := _open("bank", "Bank", true, 620)
	_text(v, "Borrow against your properties to hire sooner or fix things faster. Loans are paid back daily over %d days (%.1f%% interest a day on what's left). Paying early saves interest." % [
		int(game.bal["bank"]["loan_days"]), game.bal["bank"]["loan_rate"] * 100.0], 13)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	v.add_child(grid)
	for row in [["Cash", "$" + _money(game.cash)], ["Properties worth", "$" + _money(game.total_value())],
			["You owe", "$" + _money(game.debt())], ["Net worth", "$" + _money(game.net_worth())],
			["Daily loan payments", "$" + _money(game.daily_loan_payments())], ["Bank will lend up to", "$" + _money(game.credit_limit())]]:
		_text(grid, row[0], 14, Color(0.8, 0.8, 0.85))
		_text(grid, row[1], 14)
	v.add_child(HSeparator.new())
	_text(v, "Your loans", 18, Color(1, 0.85, 0.6))
	if game.loans.is_empty():
		_text(v, "No loans. Debt-free!", 14, Color(0.7, 0.7, 0.75))
	for l in game.loans:
		var row := HBoxContainer.new()
		v.add_child(row)
		var t := _text(row, "%s: $%s left, $%d/day, %d days to go" % [l["name"], _money(l["balance"]), int(l["payment"]), int(l["days_left"])], 14)
		t.custom_minimum_size = Vector2(380, 0)
		var lid: int = l["id"]
		var part := minf(1000.0, l["balance"])
		var b1 := _button(row, "Pay $%s" % _money(part), func(): game.repay(lid, part); show_bank())
		b1.disabled = game.cash < part
		var b2 := _button(row, "Pay off", func(): game.repay(lid, game.get_loan(lid).get("balance", 0.0)); show_bank())
		b2.disabled = game.cash < l["balance"]
	v.add_child(HSeparator.new())
	var limit: float = game.credit_limit()
	var row := HBoxContainer.new()
	v.add_child(row)
	_text(row, "New loan: ")
	var spin := _spin(500, maxf(500.0, limit), minf(2000.0, maxf(500.0, limit)), "$", "", 150, 500.0)
	row.add_child(spin)
	var pay_l := _text(row, "", 13, Color(0.75, 0.85, 0.75))
	var update_pay := func(val):
		pay_l.text = "  about $%d/day for %d days" % [int(game.payment_for(val, game.bal["bank"]["loan_rate"], int(game.bal["bank"]["loan_days"]))), int(game.bal["bank"]["loan_days"])]
	spin.value_changed.connect(update_pay)
	update_pay.call(spin.value)
	var b := _button(row, "Borrow", func(): game.borrow(spin.value); show_bank())
	b.disabled = limit < 500.0
	if limit < 500.0:
		b.tooltip_text = "The bank won't lend you more right now."
	if game.mode == "campaign" and game.chapter_info()["type"] == "savings":
		_text(v, "Note: the chapter goal counts savings (cash minus loans), so borrowing doesn't get you there by itself.", 12, Color(1, 0.85, 0.5))


func show_properties() -> void:
	var v := _open("properties", "Properties", true, 660)
	_text(v, "You own", 18, Color(1, 0.85, 0.6))
	for p in game.properties:
		var row := HBoxContainer.new()
		v.add_child(row)
		var t := _text(row, "%s - %d rooms, %s %.1f, worth $%s%s" % [p.display_name(), p.rooms.size(), _stars(p.rating()), p.rating(),
			_money(p.cfg["value"]), ", %d out of order" % p.broken_rooms().size() if not p.broken_rooms().is_empty() else ""], 14)
		t.custom_minimum_size = Vector2(470, 0)
		var i: int = p.index
		_button(row, "View", func(): main.show_property(i); close_modal())
	var listing: Array = game.listings()
	if listing.is_empty():
		return
	v.add_child(HSeparator.new())
	_text(v, "For sale", 18, Color(1, 0.85, 0.6))
	for l in listing:
		_text(v, "%s - $%s" % [l["name"], _money(l["price"])], 16, Color(1, 0.95, 0.8))
		_text(v, l["blurb"], 13)
		_text(v, "Down payment $%s (%d%%), then a $%s mortgage: about $%d/day for %d days." % [
			_money(l["down"]), int(round(l["down"] / l["price"] * 100.0)), _money(l["mortgage"]), int(l["payment"]), l["days"]], 13, Color(0.8, 0.9, 0.8))
		_text(v, "You'll need staff there: you can't be in two places at once, and it's a %d-minute drive." % int(game.bal["travel_minutes"]), 12, Color(0.8, 0.8, 0.85))
		var row := HBoxContainer.new()
		v.add_child(row)
		var k: String = l["key"]
		var b := _button(row, "Buy with a mortgage", func(): close_modal(); main.buy_property(k))
		b.disabled = not l["can_buy"]
		var b2 := _button(row, "Pay in full", func(): close_modal(); main.buy_property(k, true))
		b2.disabled = not l["can_buy"] or game.cash < l["price"]
		if not l["can_buy"]:
			_text(v, l["why"], 13, Color(1, 0.7, 0.5))


func show_help() -> void:
	var v := _open("help", "How to play", true, 680)
	_text(v, """You own a little roadside motel. Keep guests happy and make money, then buy a hotel.

- Guests line up at the front desk. Someone has to be AT the desk to check them in or out.
- Check-out is between 7 and 11 AM. Check-in opens at 3 PM. Use the time in between to clean.
- Early birds may ask to check in early: say no, charge a fee (set it under Rates), or let them in free.
- Guests may call the night before or on check-out morning (before 11 AM) to ask for a late check-out, up to 1 PM. Same choices, but their room gets cleaned later.
- When guests check out, their room is dirty, and sometimes something breaks. Click a room to clean or fix it.
- Broken rooms can't be rented until they're fixed. A maintenance tech fixes them twice as fast as you.
- Unhappy guests ask for discounts and leave bad reviews. Your rating sets how many guests come and what they pay.
- Staff work one shift each: Day 7 AM-3 PM, Evening 3-11 PM, Night 11 PM-7 AM.
- Bank: borrow against your properties, pay it back daily. Properties: buy the Maple Grove Hotel in chapter 2.
- With two properties, the tabs under the top bar switch views. You drive between them (it takes a while).

Controls
- Left click: room = clean/fix it, desk/lobby/guest = work the desk. Jobs at the other property: you drive there first.
- Drag, WASD or arrow keys: move the camera. Wheel, pinch or +/-: zoom. Tab: next property.
- Space: pause. 1 / 2 / 3: speed. F: go to the front desk. Esc: close window.""", 14)


func show_report(report: Dictionary) -> void:
	var props: Array = report["props"]
	var v := _open("report", "End of day %d" % report["day"], false, 460 + 140 * maxi(0, props.size() - 1))
	var grid := GridContainer.new()
	grid.columns = 1 + props.size()
	grid.add_theme_constant_override("h_separation", 30)
	v.add_child(grid)
	var multi := props.size() > 1
	if multi:
		_text(grid, "", 14)
		for pr in props:
			_text(grid, pr["name"], 14, Color(1, 0.85, 0.6))
	var rows := [
		["Room revenue", func(pr): return "$%d" % int(pr["revenue"])],
		["Refunds & discounts", func(pr): return "-$%d" % int(pr["refunds"])],
		["Staff wages", func(pr): return "-$%d" % int(pr["wages"])],
		["Upkeep & repairs", func(pr): return "-$%d" % int(pr["upkeep"])],
		["Net", func(pr): return "$%d" % int(pr["net"])],
		["Check-ins / check-outs", func(pr): return "%d / %d" % [pr["checkins"], pr["checkouts"]]],
		["Walked out", func(pr): return str(pr["walkouts"])],
		["Turned away", func(pr): return str(pr["turned_away"])],
		["Broke / fixed / still broken", func(pr): return "%d / %d / %d" % [pr.get("breakages", 0), pr.get("repairs", 0), pr.get("broken", 0)]],
		["Reviews today", func(pr): return "%d (avg %.1f)" % [pr["reviews"], pr["avg_stars"]] if pr["reviews"] > 0 else "0"],
		["Rating", func(pr): return "%.2f" % pr["rating"]],
	]
	for r in rows:
		_text(grid, r[0], 14, Color(0.8, 0.8, 0.85))
		for pr in props:
			var val := _text(grid, r[1].call(pr), 14)
			if r[0] == "Net":
				val.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if pr["net"] >= 0 else Color(1, 0.5, 0.45))
	var money := GridContainer.new()
	money.columns = 2
	money.add_theme_constant_override("h_separation", 30)
	v.add_child(HSeparator.new())
	v.add_child(money)
	var lines := []
	if report["loan_payments"] > 0.0:
		lines.append(["Loan payments", "-$%d (interest $%d)" % [int(report["loan_payments"]), int(report["interest"])]])
	lines.append(["Net today" + (" (all properties)" if multi else ""), "$%d" % int(report["net"])])
	lines.append(["Cash", "$%s" % _money(report["cash"])])
	if report["debt"] > 0.0:
		lines.append(["Debt / net worth", "$%s / $%s" % [_money(report["debt"]), _money(report["net_worth"])]])
	for l in lines:
		_text(money, l[0], 14, Color(0.8, 0.8, 0.85))
		var val := _text(money, l[1], 14)
		if l[0].begins_with("Net today"):
			val.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if report["net"] >= 0 else Color(1, 0.5, 0.45))
	for pr in props:
		for q in pr["quits"]:
			_text(v, "%s quit %s (underpaid)." % [q, pr["name"]], 14, Color(1, 0.6, 0.5))
	if game.mode == "campaign" and game.game_over == "":
		var left: int = int(game.chapter_info()["days"]) - int(report["day"])
		_text(v, "%s %d day%s left." % [game.goal_text(), left, "" if left == 1 else "s"], 14, Color(1, 0.85, 0.5))
	var cb := CheckBox.new()
	cb.text = "Show this report every night"
	cb.button_pressed = show_reports
	cb.toggled.connect(func(on): show_reports = on)
	v.add_child(cb)
	_button(v, "Continue", close_modal)


func show_last_report() -> void:
	if game.reports.is_empty():
		toast("No reports yet. The first one comes at midnight.")
		return
	show_report(game.reports[-1])


func queue_report(report: Dictionary) -> void:
	if show_reports:
		_reports.append(report)
		_next_popup()


func queue_discount(prop_index: int, guest_id: int) -> void:
	_discounts.append([prop_index, guest_id])
	_next_popup()


func queue_chapter(text: String) -> void:
	_chapters.append(text)
	_next_popup()


func _next_popup() -> void:
	if modal != null:
		return
	while not _discounts.is_empty():
		var item: Array = _discounts.pop_front()
		if item[0] >= game.properties.size():
			continue
		var p = game.properties[item[0]]
		var gid: int = item[1]
		if p.guests.has(gid) and p.guests[gid].state == "discount":
			_show_discount(p, p.guests[gid])
			return
		if p.guests.has(gid) and p.guests[gid].state == "early_request":
			_show_early(p, p.guests[gid])
			return
		if p.guests.has(gid) and p.guests[gid].late_state in ["asking", "haggling"]:
			_show_late(p, p.guests[gid])
			return
	if not _reports.is_empty():
		show_report(_reports.pop_front())
		return
	if not _chapters.is_empty():
		_show_chapter(_chapters.pop_front())


func _where(p) -> String:
	return " at %s" % p.display_name() if game.properties.size() > 1 else ""


func _show_discount(p, g) -> void:
	var v := _open("discount", "Discount request", false, 480)
	var base: float = g.paid
	var amount: float = base * g.discount_pct / 100.0
	var why := "waiting so long"
	if g.notes.get("room_not_ready", 0.0) < g.notes.get("long_wait", 0.0):
		why = "their room not being ready"
	if g.notes.get("overpriced", 0.0) < minf(g.notes.get("long_wait", 0.0), g.notes.get("room_not_ready", 0.0)):
		why = "the price"
	_text(v, "%s (%s)%s is unhappy about %s." % [g.name, p.archetype(g.archetype)["name"], _where(p), why])
	_text(v, "Fun fact: this guest %s." % g.quirk, 13, Color(0.75, 0.75, 0.8))
	_text(v, "They'd like %d%% off: $%d." % [g.discount_pct, int(amount)], 18, Color(1, 0.85, 0.35))
	_text(v, "Saying yes costs money but softens their review. Saying no keeps the cash, but they'll be even grumpier.", 13, Color(0.8, 0.8, 0.85))
	var row := HBoxContainer.new()
	v.add_child(row)
	var gid: int = g.id
	_button(row, "Give %d%% off" % g.discount_pct, func(): p.resolve_discount(gid, true); close_modal())
	_button(row, "Refuse", func(): p.resolve_discount(gid, false); close_modal())


func _show_early(p, g) -> void:
	var haggling: bool = g.early_state == "haggling"
	var v := _open("early", "Early check-in" if not haggling else "Guest is haggling", false, 500)
	var arch: String = p.archetype(g.archetype)["name"]
	if haggling:
		_text(v, "%s (%s): \"Any chance you could waive that $%d fee? We've been driving all day.\"" % [g.name, arch, int(p.early_fee)])
		_text(v, "Insisting on the fee might make them pay grudgingly, or walk back to the line and wait.", 13, Color(0.8, 0.8, 0.85))
	else:
		_text(v, "%s (%s) arrived%s at %s, before the 3 PM check-in, and asks to check in now. A clean room is free." % [g.name, arch, _where(p), game.clock_text()])
		_text(v, "Early check-in makes guests happier. A fee earns money, but some guests hate fees and may haggle.", 13, Color(0.8, 0.8, 0.85))
	_text(v, "Fun fact: this guest %s." % g.quirk, 13, Color(0.75, 0.75, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var gid: int = g.id
	_button(row, "No, wait until 3 PM", func(): p.resolve_early(gid, "no"); close_modal())
	if p.early_fee > 0.0:
		_button(row, ("Fee stands ($%d)" if haggling else "Yes, for a $%d fee") % int(p.early_fee), func(): p.resolve_early(gid, "fee"); close_modal())
	_button(row, "Waive the fee" if haggling else "Yes, free", func(): p.resolve_early(gid, "free"); close_modal())


func _show_late(p, g) -> void:
	var haggling: bool = g.late_state == "haggling"
	var v := _open("late", "Late check-out" if not haggling else "Guest is haggling", false, 520)
	var arch: String = p.archetype(g.archetype)["name"]
	var until: String = p.late_until_text(g)
	if haggling:
		_text(v, "%s (%s): \"Could you waive that $%d fee? It's only a little longer.\"" % [g.name, arch, int(p.late_fee)])
		_text(v, "Insisting on the fee might make them pay grudgingly, or just leave at the usual time, unhappy.", 13, Color(0.8, 0.8, 0.85))
	else:
		var when: String = "tomorrow morning" if game.day() < g.checkout_day else "this morning"
		_text(v, "%s (%s) in room %s%s calls the desk: they check out %s and would like to stay until %s." % [g.name, arch, p.room_label(g.room), _where(p), when, until])
		_text(v, "A late check-out makes guests happier and a fee earns money, but room %s can't be cleaned until they leave, and check-in opens at 3 PM." % p.room_label(g.room), 13, Color(0.8, 0.8, 0.85))
	_text(v, "Fun fact: this guest %s." % g.quirk, 13, Color(0.75, 0.75, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var gid: int = g.id
	_button(row, "No, usual time", func(): p.resolve_late(gid, "no"); close_modal())
	if p.late_fee > 0.0:
		_button(row, ("Fee stands ($%d)" if haggling else "Yes, for a $%d fee") % int(p.late_fee), func(): p.resolve_late(gid, "fee"); close_modal())
	_button(row, "Waive the fee" if haggling else "Yes, free", func(): p.resolve_late(gid, "free"); close_modal())


func _show_chapter(text: String) -> void:
	var v := _open("chapter", "Chapter complete!", false, 520)
	_text(v, text, 16)
	_text(v, "Next: %s" % game.chapter_info()["title"], 18, Color(1, 0.85, 0.6))
	_text(v, game.goal_text(), 14)
	_text(v, "New: the Bank lends money, staff work shifts, things break (hire a maintenance tech), and you can own more than one property.", 13, Color(0.8, 0.9, 0.8))
	var row := HBoxContainer.new()
	v.add_child(row)
	_button(row, "See what's for sale", show_properties)
	_button(row, "Continue", close_modal)


func show_game_over(text: String) -> void:
	_discounts.clear()
	_reports.clear()
	_chapters.clear()
	var won: bool = game.game_over == "won"
	var v := _open("gameover", "You did it!" if won else "Game over", false, 480)
	_text(v, text, 16)
	var served := 0
	for p in game.properties:
		served += p.stats["served"]
	_text(v, "Day %d  -  cash $%s  -  net worth $%s  -  guests served %d" % [game.day(), _money(game.cash), _money(game.net_worth()), served], 14, Color(0.8, 0.8, 0.85))
	var row := HBoxContainer.new()
	v.add_child(row)
	if won:
		_button(row, "Keep playing", func(): game.mode = "sandbox"; game.game_over = ""; close_modal())
	_button(row, "New campaign", func(): main.new_game("campaign"))
	_button(row, "Sandbox", func(): main.new_game("sandbox"))


func show_start(has_save: bool) -> void:
	var v := _open("start", "HotelWorld", false, 540)
	_text(v, "Your roadside motel adventure starts here.", 16, Color(1, 0.85, 0.6))
	var chapters: Array = game.bal["campaign"]["chapters"]
	_text(v, "Campaign: start with $%s and a 6-room motel." % _money(game.bal["start_cash"]), 14)
	for c in chapters:
		_text(v, "  %s: %s" % [c["title"], c["goal"].format({"amount": _money(c["amount"]), "days": int(c["days"])})], 14)
	_text(v, "Go broke for %d nights in a row and the bank takes the keys." % int(game.bal["campaign"]["bankrupt_days"]), 14)
	_text(v, "Sandbox: no goal, no bankruptcy. The hotel is for sale whenever you can afford it.", 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "New campaign", func(): main.new_game("campaign"))
	_button(row, "Sandbox", func(): main.new_game("sandbox"))
	if has_save:
		_button(row, "Continue saved game", func(): main.load_game())
	_button(row, "How to play", show_help)
