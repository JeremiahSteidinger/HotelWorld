extends RefCounted
## Turns a guest's mood and the reasons behind it into a star rating and review text.

const TEXT := {
	"long_wait": [
		"Waited so long at the desk I aged a full year. Two, if you count the vending machine.",
		"The line at check-in had its own weather system.",
		"I read an entire novel in the check-in line. It was a long novel.",
	],
	"room_not_ready": [
		"Our room was 'almost ready' for longer than our actual vacation.",
		"Sat in the lobby so long the plant and I became friends.",
		"Room wasn't clean when we got there. The previous guest's socks said hi.",
	],
	"overpriced": [
		"Paid luxury prices for a room that smelled faintly of 1987.",
		"For that price I expected the ice machine to sing.",
		"Nice enough, but my wallet is still in therapy.",
	],
	"great_value": [
		"Cheap, clean and the towels were fluffy. What more do you want?",
		"Best deal on this highway. I'd stay again just to brag about it.",
		"Great price! I used the savings to buy a second vending machine snack.",
	],
	"fast_service": [
		"Checked in faster than I could say 'free continental breakfast'.",
		"Zero wait at the desk. Suspiciously efficient. Loved it.",
		"In and out at the desk in a flash. 10/10 would be efficiently processed again.",
	],
	"refused_discount": [
		"Asked for a small discount after the chaos. Got a big 'no'.",
		"They wouldn't budge on the price. Neither will my star rating.",
	],
	"early_checkin": [
		"Got into our room early. After 9 hours of driving, that was everything.",
		"They let us check in early! The bed and I had a beautiful reunion.",
	],
	"no_early": [
		"Arrived at 1, told to come back at 3. Spent two hours admiring the ice machine.",
		"No early check-in, even with empty rooms. Rules are rules, I guess.",
	],
	"early_fee": [
		"Charged me extra just to sleep a bit sooner. Nickel-and-dimed.",
		"Early check-in fee? For a motel? Bold move.",
	],
	"late_checkout": [
		"They let us sleep in and check out late. Best morning of the whole trip.",
		"Late check-out, no fuss. I finished my waffle in peace.",
	],
	"no_late": [
		"Asked for one extra hour in the morning. The answer was a firm 'no'.",
		"No late check-out. Packed my bags at a sprint like it was a game show.",
	],
	"late_fee": [
		"Charged me to stay an extra hour. The clock ticks, and so does the meter.",
		"Late check-out fee at a roadside motel? The sign didn't mention that.",
	],
	"got_discount": [
		"Rough start, but the owner made it right with a discount. Classy.",
		"Things went wrong, but they took care of us. Respect.",
	],
	"walked_out": [
		"Never even got a room. Waited, gave up, drove to the next town.",
		"Stood in line until my patience checked out before I checked in.",
	],
	"left_checkout": [
		"Couldn't even check out. Left the key on the counter and fled.",
	],
	"general_good": [
		"Solid little motel. Bed was comfy, sign was neon. Perfect.",
		"Exactly what a roadside motel should be. Will stop again.",
		"Friendly folks, clean room, decent coffee. Four wheels up.",
	],
	"general_ok": [
		"It was a motel. I slept in it. It's fine.",
		"Room had a bed and a door. Both worked. Good enough.",
	],
	"general_bad": [
		"Not my favourite night. Not my worst. Somewhere close to the worst.",
		"The vibes were off. The ice machine knew it too.",
	],
}

const GOOD_CAUSES := ["great_value", "fast_service", "got_discount", "early_checkin", "late_checkout"]
const BAD_CAUSES := ["long_wait", "room_not_ready", "overpriced", "refused_discount", "walked_out", "left_checkout", "no_early", "early_fee", "no_late", "late_fee"]


static func stars_for_mood(mood: float) -> int:
	return clampi(int(round(mood / 20.0)), 1, 5)


static func pick_cause(notes: Dictionary, stars: int) -> String:
	var best := ""
	if stars <= 3:
		var worst := 0.0
		for c in notes:
			if BAD_CAUSES.has(c) and notes[c] < worst:
				worst = notes[c]
				best = c
	if best == "" and stars >= 3:
		var top := 0.0
		for c in notes:
			if GOOD_CAUSES.has(c) and notes[c] > top:
				top = notes[c]
				best = c
	if best == "":
		best = "general_good" if stars >= 4 else ("general_ok" if stars == 3 else "general_bad")
	return best


static func make(guest, day: int, rng: RandomNumberGenerator, forced_cause := "") -> Dictionary:
	var stars := stars_for_mood(guest.mood)
	var cause: String = forced_cause if forced_cause != "" else pick_cause(guest.notes, stars)
	if forced_cause == "walked_out":
		stars = 1
	var options: Array = TEXT[cause]
	return {
		"stars": stars,
		"cause": cause,
		"text": options[rng.randi_range(0, options.size() - 1)],
		"author": guest.name,
		"archetype": guest.archetype,
		"day": day,
	}


## Average of the most recent reviews, blended with the starting rating while there are few reviews.
static func rating(reviews: Array, start: float, window: int, prior_weight: int) -> float:
	var recent := reviews.slice(maxi(0, reviews.size() - window))
	var prior := maxi(0, prior_weight - recent.size())
	var total := start * prior
	for r in recent:
		total += r["stars"]
	var n := prior + recent.size()
	return total / n if n > 0 else start
