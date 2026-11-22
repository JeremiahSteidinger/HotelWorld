extends SceneTree
## Headless balance check:
##   godot --headless --script res://tools/sim_30_days.gd
## Plays 30 days with several automated strategies and prints how each one does.

const Sim := preload("res://scripts/sim/sim.gd")
const Bot := preload("res://tools/bot.gd")


func _init() -> void:
	var bal: Dictionary = Sim.load_balance()
	var verbose := OS.get_cmdline_user_args().has("--verbose")
	for strategy in ["idle", "solo", "staffed", "greedy", "pro"]:
		var totals := {"cash": 0.0, "rating": 0.0, "won": 0}
		var seeds := [1, 2, 3, 4, 5]
		for s in seeds:
			var sim = Sim.new()
			sim.new_game(bal, "sandbox", s)
			if strategy == "greedy":
				sim.set_rate("single", 85)
				sim.set_rate("double", 125)
			var reached_goal := -1
			while sim.day() <= 30:
				Bot.play(sim, strategy)
				sim.tick(5.0)
				sim.pop_events()
				if reached_goal == -1 and sim.cash >= bal["goal"]["cash"]:
					reached_goal = sim.day()
			if verbose and s == 1:
				for r in sim.reports:
					print("  [%s] day %2d  rev %5d  net %5d  cash %6d  in %d out %d walk %d lost %d  rating %.2f" % [
						strategy, r["day"], r["revenue"], r["net"], r["cash"], r["checkins"], r["checkouts"], r["walkouts"], r["turned_away"], r["rating"]])
			totals["cash"] += sim.cash
			totals["rating"] += sim.rating()
			if reached_goal != -1:
				totals["won"] += 1
			print("%-8s seed %d: cash $%6d  rating %.2f  served %3d  walkouts %3d  lost(price/vacancy/line) %d/%d/%d  goal day %s" % [
				strategy, s, sim.cash, sim.rating(), sim.stats["served"], sim.stats["walkouts"],
				sim.stats["lost_price"], sim.stats["lost_vacancy"], sim.stats["lost_line"], str(reached_goal)])
		print("== %s: avg cash $%d, avg rating %.2f, reached goal %d/%d\n" % [
			strategy, totals["cash"] / seeds.size(), totals["rating"] / seeds.size(), totals["won"], seeds.size()])
	quit()
