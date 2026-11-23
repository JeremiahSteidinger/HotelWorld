extends SceneTree
## Headless balance check:
##   godot --headless --path . --script res://tools/sim_30_days.gd [-- --verbose] [-- --campaign-only]
## Chapter 1: plays 30 days with several automated strategies and prints how each one does.
## Chapter 2: plays the full campaign with the "pro" bot (buys the hotel) to the end (day 100).

const Game := preload("res://scripts/sim/game.gd")
const Bot := preload("res://tools/bot.gd")


func _init() -> void:
	var bal: Dictionary = Game.load_balance()
	var args := OS.get_cmdline_user_args()
	var verbose := args.has("--verbose")
	var seeds := [1, 2, 3, 4, 5]
	if not args.has("--campaign-only"):
		for strategy in ["idle", "solo", "staffed", "greedy", "pro"]:
			var totals := {"cash": 0.0, "rating": 0.0, "won": 0}
			for s in seeds:
				var game = Game.new()
				game.new_game(bal, "campaign", s)  # campaign: chapter 1 can't buy the hotel yet
				var motel = game.properties[0]
				if strategy == "greedy":
					motel.set_rate("single", 85)
					motel.set_rate("double", 125)
				var reached_goal := -1
				while game.day() <= 30 and game.game_over == "":
					Bot.play(game, strategy)
					game.tick(5.0)
					game.pop_events()
					if reached_goal == -1 and game.cash - game.debt() >= bal["campaign"]["chapters"][0]["amount"]:
						reached_goal = game.day()
				totals["cash"] += game.cash
				totals["rating"] += motel.rating()
				if reached_goal != -1:
					totals["won"] += 1
				print("%-8s seed %d: cash $%6d  rating %.2f  served %3d  walkouts %3d  lost(price/vacancy/line) %d/%d/%d  broke %d  goal day %s" % [
					strategy, s, game.cash, motel.rating(), motel.stats["served"], motel.stats["walkouts"],
					motel.stats["lost_price"], motel.stats["lost_vacancy"], motel.stats["lost_line"], motel.stats["breakages"], str(reached_goal)])
			print("== %s: avg cash $%d, avg rating %.2f, reached goal %d/%d\n" % [
				strategy, totals["cash"] / seeds.size(), totals["rating"] / seeds.size(), totals["won"], seeds.size()])
	# Full campaign with the pro bot.
	var wins := 0
	for s in seeds:
		var game = Game.new()
		game.new_game(bal, "campaign", s)
		var ch2_day := -1
		var bought := -1
		while game.game_over == "":
			Bot.play(game, "pro")
			game.tick(5.0)
			for e in game.pop_events():
				if e["type"] == "chapter":
					ch2_day = game.day()
				if e["type"] == "bought":
					bought = game.day()
			if verbose and s == 1 and game.minute_of_day() < 5.0 and not game.reports.is_empty():
				var r: Dictionary = game.reports[-1]
				var parts := []
				for pr in r["props"]:
					parts.append("%s rev %5d net %5d in %2d walk %d broken %d rating %.2f" % [pr["key"], pr["revenue"], pr["net"], pr["checkins"], pr["walkouts"], pr["broken"], pr["rating"]])
				print("  day %2d cash %6d debt %6d worth %6d | %s" % [r["day"], r["cash"], r["debt"], r["net_worth"], " | ".join(parts)])
		if game.game_over == "won":
			wins += 1
		var hotel = game.prop("hotel")
		print("campaign seed %d: %s on day %d, chapter 2 from day %s, hotel bought day %s, net worth $%d, cash $%d, debt $%d, hotel rating %s" % [
			s, game.game_over, game.day(), str(ch2_day), str(bought), game.net_worth(), game.cash, game.debt(),
			"%.2f" % hotel.rating() if hotel != null else "-"])
	print("== campaign (pro): won %d/%d" % [wins, seeds.size()])
	quit()
