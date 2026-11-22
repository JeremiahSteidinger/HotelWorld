extends Node2D
## Room status badges above each room, plus the hover highlight for clickable things.

const Layout := preload("res://scripts/sim/layout.gd")

var sim
var hover_room := -1
var hover_desk := false
var _pulse := 0.0


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _diamond(origin: Vector2, w: float, d: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for g in [Vector2(0, 0), Vector2(w, 0), Vector2(w, d), Vector2(0, d), Vector2(0, 0)]:
		var p: Vector2 = origin + g
		pts.append(Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0))
	return pts


func _draw() -> void:
	if sim == null:
		return
	var font := ThemeDB.fallback_font
	if hover_room >= 0:
		draw_polyline(_diamond(Vector2(Layout.room_origin(hover_room)), 2, 2), Color(1, 1, 0.5, 0.9), 2.0)
	if hover_desk:
		draw_polyline(_diamond(Vector2(0, 0), 4, 5), Color(1, 1, 0.5, 0.9), 2.0)
	for r in sim.rooms:
		var c := Layout.room_badge_pos(r.index)
		var label := "Clean"
		var col := Color(0.3, 0.75, 0.4)
		if r.state == "occupied":
			label = "Occupied"
			col = Color(0.45, 0.45, 0.6)
		elif r.state == "dirty":
			label = "Cleaning" if r.cleaner_id != -1 and r.clean_progress > 0.0 else "Dirty"
			col = Color(0.35, 0.55, 0.9) if label == "Cleaning" else Color(0.75, 0.45, 0.2)
		elif r.guest_id != -1:
			label = "Reserved"
			col = Color(0.3, 0.65, 0.55)
		var waiting: bool = sim.waiting_guests_for_room(r.index)
		var text := "%d %s %s" % [r.index + 1, "S" if r.type == "single" else "D", label]
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var rect := Rect2(c.x - size.x / 2 - 4, c.y - 8, size.x + 8, 14)
		if waiting:
			var a := 0.5 + 0.5 * sin(_pulse * 6.0)
			draw_rect(rect.grow(2), Color(1, 0.2, 0.2, a))
		draw_rect(rect, col)
		draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)
		draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		if r.state == "dirty" and r.clean_progress > 0.0:
			draw_rect(Rect2(rect.position.x, rect.end.y + 1, rect.size.x, 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(rect.position.x, rect.end.y + 1, rect.size.x * r.clean_progress, 3), Color(0.5, 0.85, 1.0))
		if r.cleaner_id != -1 and r.clean_progress == 0.0:
			draw_string(font, Vector2(rect.end.x + 2, rect.position.y + 11), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
