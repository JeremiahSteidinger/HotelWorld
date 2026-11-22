extends Node2D
## One walking person (guest or worker) with mood / patience / progress indicators.

const Layout := preload("res://scripts/sim/layout.gd")

var frames: Array = []
var sprite := Sprite2D.new()
var _anim := 0.0
var _last_pos := Vector2.INF
var _moving := false
var _mood := -1.0
var _bar := -1.0          # 0..1 progress/patience bar, -1 hides it
var _bar_color := Color.WHITE
var _bubble := ""         # short text shown above the head
var _bubble_color := Color.WHITE


func _ready() -> void:
	sprite.centered = false
	sprite.texture = frames[0]
	sprite.offset = Vector2(-9, -31)
	add_child(sprite)


func _place(grid_pos: Vector2, delta: float) -> void:
	var p := Layout.to_screen(grid_pos)
	_moving = _last_pos != Vector2.INF and p.distance_to(_last_pos) > 0.01
	if _moving:
		var dx := p.x - _last_pos.x
		if absf(dx) > 0.01:
			sprite.flip_h = dx < 0
		_anim += delta
	else:
		_anim = 0.0
	_last_pos = p
	position = p
	sprite.texture = frames[int(_anim / 0.18) % 2] if _moving else frames[0]


func sync_guest(g, sim) -> void:
	_place(g.pos, get_process_delta_time())
	_mood = g.mood
	_bar = -1.0
	_bubble = ""
	match g.state:
		"queue", "to_desk":
			if sim.is_early(g):
				_bubble = "3 PM"
				_bubble_color = Color(0.8, 0.8, 0.9)
				queue_redraw()
				return
			_bar = 1.0 - clampf(g.wait / g.patience, 0.0, 1.0)
			_bar_color = Color(0.3, 0.8, 0.3).lerp(Color(0.9, 0.2, 0.2), 1.0 - _bar)
			if g.purpose == "checkout":
				_bubble = "OUT"
				_bubble_color = Color(0.6, 0.8, 1.0)
		"waiting_room":
			_bar = 1.0 - clampf(g.wait / (g.patience * 1.5), 0.0, 1.0)
			_bar_color = Color(0.9, 0.6, 0.2)
			_bubble = "ROOM?"
			_bubble_color = Color(1.0, 0.6, 0.3)
		"early_request":
			_bubble = "EARLY?"
			_bubble_color = Color(0.7, 0.9, 1.0)
		"discount":
			_bubble = "%d%% OFF?" % g.discount_pct
			_bubble_color = Color(1.0, 0.85, 0.3)
		"staying":
			var m: float = sim.minute_of_day()
			if m >= 22 * 60 or m < 6 * 60:
				_bubble = "z z"
				_bubble_color = Color(0.75, 0.8, 1.0)
		"leaving":
			_mood = g.mood
	queue_redraw()


func sync_worker(w, sim) -> void:
	_place(w.pos, get_process_delta_time())
	_mood = -1.0
	_bar = -1.0
	_bubble = ""
	if w.job.get("type", "") == "clean" and w.arrived():
		_bar = sim.rooms[w.job["room"]].clean_progress
		_bar_color = Color(0.4, 0.7, 1.0)
	elif w.serving != -1 and sim.guests.has(w.serving) and sim.guests[w.serving].state == "at_desk":
		var g = sim.guests[w.serving]
		var need: float = sim.bal["task_minutes"]["check_in" if g.purpose == "checkin" else "check_out"]
		_bar = clampf(w.progress / need, 0.0, 1.0)
		_bar_color = Color(0.4, 0.7, 1.0)
	if w.role == "owner":
		_bubble = "YOU"
		_bubble_color = Color(1.0, 0.45, 0.4)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y := -38.0
	if _bar >= 0.0:
		draw_rect(Rect2(-9, y, 18, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-8, y + 1, 16 * _bar, 2), _bar_color)
		y -= 6.0
	if _mood >= 0.0:
		var c := Color(0.95, 0.3, 0.25)
		if _mood >= 65.0:
			c = Color(0.35, 0.85, 0.35)
		elif _mood >= 40.0:
			c = Color(0.95, 0.8, 0.25)
		draw_circle(Vector2(10, -30), 3.5, Color(0, 0, 0, 0.6))
		draw_circle(Vector2(10, -30), 2.5, c)
	if _bubble != "":
		var size := font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		var r := Rect2(-size.x / 2 - 2, y - 9, size.x + 4, 10)
		draw_rect(r, Color(0.1, 0.1, 0.15, 0.85))
		draw_string(font, Vector2(r.position.x + 2, r.position.y + 8), _bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, _bubble_color)
