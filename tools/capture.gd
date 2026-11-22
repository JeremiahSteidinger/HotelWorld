extends SceneTree
## Launches the game, plays it with the bot and saves screenshots.
##   godot --path . --script res://tools/capture.gd -- <out_dir>
## (needs a display; use xvfb-run on Linux servers)

const Bot := preload("res://tools/bot.gd")

var main
var frame := 0
var out_dir := "user://"
var shots := [
	# [frame, label, minutes to fast-forward before the shot, action]
	[20, "start_menu", 0.0, ""],
	[40, "day1_morning", 0.0, "new_game"],
	[80, "day1_afternoon", 420.0, ""],
	[100, "night", 520.0, ""],
	[120, "day2_checkout", 560.0, ""],
	[160, "staff_panel", 0.0, "staff"],
	[200, "rates_panel", 0.0, "rates"],
	[240, "reviews_panel", 0.0, "reviews"],
	[280, "day_report", 0.0, "report"],
	[320, "discount", 0.0, "discount"],
	[360, "no_vacancy", 0.0, "fill"],
	[400, "early_ask", 0.0, "early"],
	[440, "early_haggle", 0.0, "haggle"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	for s in shots:
		if frame == s[0] - 10:
			_act(s[3], s[2])
		if frame == s[0]:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/%s.png" % [out_dir, s[1]])
			print("saved ", s[1])
	if frame > shots[-1][0] + 2:
		return true
	return false


func _act(action: String, minutes: float) -> void:
	var ui = main.ui
	match action:
		"new_game":
			main.new_game("campaign")
		"staff":
			ui.close_modal()
			main.sim.cash += 0
			ui.show_staff()
		"rates":
			ui.show_rates()
		"reviews":
			ui.show_reviews()
		"report":
			if not main.sim.reports.is_empty():
				ui.show_report(main.sim.reports[-1])
		"early", "haggle":
			ui.close_modal()
			for gid in main.sim.guests:
				var g = main.sim.guests[gid]
				if g.state == "staying":
					g.state = "early_request"
					g.early_state = "asking" if action == "early" else "haggling"
					ui._show_early(g)
					break
		"fill":
			ui.close_modal()
			for r in main.sim.rooms:
				if r.guest_id == -1:
					r.guest_id = 999
		"discount":
			ui.close_modal()
			for gid in main.sim.guests:
				var g = main.sim.guests[gid]
				if g.state == "staying":
					g.discount_pct = 20
					g.paid = 120
					g.notes = {"long_wait": -30.0}
					ui._show_discount(g)
					break
	if minutes > 0.0:
		ui.close_modal()
		var sim = main.sim
		var target: float = sim.time + minutes
		while sim.time < target:
			Bot.play(sim, "staffed")
			sim.tick(2.0)
		sim.pop_events()
		ui._reports.clear()
		ui._discounts.clear()
		if sim.staff_count("housekeeper") == 0:
			for i in sim.candidates.size():
				if sim.candidates[i]["role"] == "housekeeper":
					sim.hire(i)
					break
