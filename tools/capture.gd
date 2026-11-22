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
	[80, "day2_checkout", 1500.0, ""],
	[120, "staff_panel", 0.0, "staff"],
	[160, "bank", 0.0, "bank"],
	[200, "day_report", 0.0, "report"],
	[240, "discount", 0.0, "discount"],
	[280, "chapter2", 0.0, "chapter"],
	[320, "properties", 0.0, "properties"],
	[360, "hotel", 600.0, "buy"],
	[400, "hotel_evening", 600.0, ""],
	[440, "hotel_staff", 0.0, "staff"],
	[480, "two_property_report", 900.0, "report2"],
	[520, "motel_from_hotel", 0.0, "motel"],
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


func _ff(minutes: float, strategy := "pro") -> void:
	var game = main.game
	var target: float = game.time + minutes
	while game.time < target:
		Bot.play(game, strategy)
		game.tick(2.0)
	game.pop_events()
	main.ui._reports.clear()
	main.ui._discounts.clear()
	main.ui._chapters.clear()


func _act(action: String, minutes: float) -> void:
	var ui = main.ui
	var game = main.game
	match action:
		"new_game":
			main.new_game("campaign")
		"staff":
			ui.close_modal()
			ui.show_staff()
		"bank":
			game.borrow(2000.0)
			game.pop_events()
			ui.show_bank()
		"report", "report2":
			if action == "report2":
				ui.close_modal()
				_ff(minutes)
				minutes = 0.0
			if not game.reports.is_empty():
				ui.show_report(game.reports[-1])
		"chapter":
			ui.close_modal()
			game.repay(game.loans[0]["id"], game.loans[0]["balance"])
			game.cash = 9800.0
			game.time = (game.day()) * 1440.0 - 1.0
			game.tick(2.0)
			game.pop_events()
			ui._reports.clear()
			ui._show_chapter(game.bal["campaign"]["chapters"][0]["win"])
		"properties":
			ui.close_modal()
			ui.show_properties()
		"buy":
			ui.close_modal()
			main.buy_property("hotel")
			game.pop_events()
			game.order_go(1)
			game.owner_w.orders.append({"type": "desk", "prop": 1})
		"motel":
			ui.close_modal()
			main.show_property(0)
		"discount":
			ui.close_modal()
			var p = main.sim
			for gid in p.guests:
				var g = p.guests[gid]
				if g.state == "staying":
					g.discount_pct = 20
					g.paid = 120
					g.notes = {"long_wait": -30.0}
					ui._show_discount(p, g)
					break
	if minutes > 0.0:
		ui.close_modal()
		if action == "buy":
			# Let the bot staff the hotel, but keep the owner's trip to the hotel.
			var game2 = main.game
			var target: float = game2.time + minutes
			while game2.time < target:
				for p in game2.properties:
					Bot._answer_guests(p, "pro")
				Bot._staff_hotel(game2.properties[1])
				game2.tick(2.0)
			game2.pop_events()
			ui._reports.clear()
			ui._discounts.clear()
		else:
			_ff(minutes)
