extends RefCounted
## A property's map: grid cells, zones (lobby, halls, rooms, outside), doors and pathfinding.
## Pure data, so the simulation can run headless. Build one with motel() or hotel().
##
## Roadside Motel (18 x 10):
##   Lobby      x 0..3, y 0..4  (desk at (1,1),(2,1); staff stand at y=0, guests at y=2)
##   Rooms      6 rooms, each 2x2, x 5..16, y 0..1, door on the walkway side
##   Walkway    y = 2, x 4..17
##   Parking    y 3..5, x 4..17
##   Sidewalk   y = 6   (the desk line snakes out here)
##   Road       y 7..9
##
## Maple Grove Hotel (23 x 13):
##   Lobby      x 0..5, y 0..4  (3-station desk at (1..3, 1))
##   Hall       y = 2, x 6..20 (indoors)
##   Rooms      7 back rooms (y 0..1) and 7 front rooms (y 3..4), each 2x2, x 7..20
##   Walkway    y = 5   (the desk line snakes out here)
##   Parking    y 6..8, sidewalk y = 9, road y 10..12

var kind := "motel"
var w := 18
var h := 9
var lobby := Rect2i()
var desk_cells: Array = []
var stations: Array = []
var service_spots: Array = []
var wait_spots: Array = []
var guest_spawn := Vector2i()
var exit_cell := Vector2i()
var staff_spawn := Vector2i()
var idle_spot := Vector2i()
var line: Array = []
## Each room: {origin, door, outside, bed, work, front (bool: door on the back wall), badge (screen pos)}
var rooms: Array = []
var camera_home := Vector2.ZERO
var camera_min := Vector2.ZERO
var camera_max := Vector2.ZERO
var _zone := {}       # Vector2i -> zone name (cells not listed are "out")
var _doors := {}


static func motel():
	var l = new()
	l.kind = "motel"
	l.w = 18
	l.h = 9
	l.lobby = Rect2i(0, 0, 4, 5)
	l.desk_cells = [Vector2i(1, 1), Vector2i(2, 1)]
	l.stations = [Vector2i(1, 0), Vector2i(2, 0)]
	l.service_spots = [Vector2i(1, 2), Vector2i(2, 2)]
	l.wait_spots = [Vector2i(0, 2), Vector2i(0, 3), Vector2i(3, 3), Vector2i(0, 4), Vector2i(3, 4), Vector2i(1, 4)]
	l.guest_spawn = Vector2i(17, 8)
	l.exit_cell = Vector2i(0, 8)
	l.staff_spawn = Vector2i(0, 7)
	l.idle_spot = Vector2i(3, 1)
	l.line = [Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6)]
	for x in range(3, 18):
		l.line.append(Vector2i(x, 6))
	l.camera_home = Vector2(190, 175)
	l.camera_min = Vector2(-500, -150)
	l.camera_max = Vector2(700, 500)
	l._fill_zone(l.lobby, "lobby")
	for i in 6:
		var x0 := 5 + 2 * i
		l._add_room(Vector2i(x0, 0), Vector2i(x0, 1), Vector2i(x0, 2), Vector2i(x0 + 1, 0), Vector2i(x0 + 1, 1), false)
	l._add_door(Vector2i(3, 2), Vector2i(4, 2))
	l._add_door(Vector2i(2, 4), Vector2i(2, 5))
	return l


static func hotel():
	var l = new()
	l.kind = "hotel"
	l.w = 23
	l.h = 13
	l.lobby = Rect2i(0, 0, 6, 5)
	l.desk_cells = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	l.stations = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	l.service_spots = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	l.wait_spots = [Vector2i(0, 3), Vector2i(0, 4), Vector2i(1, 4), Vector2i(5, 3), Vector2i(5, 4), Vector2i(4, 4), Vector2i(0, 2), Vector2i(5, 1)]
	l.guest_spawn = Vector2i(22, 11)
	l.exit_cell = Vector2i(0, 11)
	l.staff_spawn = Vector2i(0, 10)
	l.idle_spot = Vector2i(4, 1)
	l.line = [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5)]
	for x in range(4, 22):
		l.line.append(Vector2i(x, 5))
	l.camera_home = Vector2(240, 230)
	l.camera_min = Vector2(-600, -150)
	l.camera_max = Vector2(900, 650)
	l._fill_zone(l.lobby, "lobby")
	l._fill_zone(Rect2i(6, 2, 15, 1), "hall")
	for i in 7:
		var x0 := 7 + 2 * i
		l._add_room(Vector2i(x0, 0), Vector2i(x0, 1), Vector2i(x0, 2), Vector2i(x0 + 1, 0), Vector2i(x0 + 1, 1), false)
	for i in 7:
		var x0 := 7 + 2 * i
		l._add_room(Vector2i(x0, 3), Vector2i(x0, 3), Vector2i(x0, 2), Vector2i(x0 + 1, 4), Vector2i(x0 + 1, 3), true)
	l._add_door(Vector2i(5, 2), Vector2i(6, 2))
	l._add_door(Vector2i(3, 4), Vector2i(3, 5))
	return l


static func for_kind(k: String):
	return hotel() if k == "hotel" else motel()


func _fill_zone(r: Rect2i, zone_name: String) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			_zone[Vector2i(x, y)] = zone_name


func _add_room(origin: Vector2i, door: Vector2i, outside: Vector2i, bed: Vector2i, work: Vector2i, front: bool) -> void:
	var i := rooms.size()
	var badge: Vector2
	if front:
		# Front-row rooms have low walls: label sits over the room's front edge.
		badge = to_screen(Vector2(origin.x + 1.0, origin.y + 1.5)) + Vector2(0, 14)
	else:
		var c := origin.x + 1
		badge = Vector2((c - origin.y) * 32.0, (c + origin.y) * 16.0) + Vector2(0, -66)
	rooms.append({"origin": origin, "door": door, "outside": outside, "bed": bed, "work": work, "front": front, "badge": badge})
	_fill_zone(Rect2i(origin, Vector2i(2, 2)), "room%d" % i)
	_add_door(door, outside)


func _add_door(a: Vector2i, b: Vector2i) -> void:
	_doors[_door_key(a, b)] = true


func room_count() -> int:
	return rooms.size()


## Bed cells for a room: the main bed (back-right), plus the back-left cell for a second bed.
func room_beds(i: int, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [room_bed(i)]
	if count >= 2:
		cells.push_front(room_origin(i) + (Vector2i(0, 1) if is_front_room(i) else Vector2i.ZERO))
	return cells


## Where a guest settles while staying: next to the bed, the same cell staff work from.
func room_stay_spot(i: int) -> Vector2i:
	return rooms[i]["work"]


## Where a staying guest's luggage sits: just inside the room, by the side wall.
func room_luggage_pos(i: int) -> Vector2:
	var o: Vector2i = rooms[i]["origin"]
	return Vector2(o.x + 0.25, o.y + 1.35)


func queue_slot(index: int) -> Vector2i:
	return line[mini(index, line.size() - 1)]


func room_origin(i: int) -> Vector2i:
	return rooms[i]["origin"]


func room_door(i: int) -> Vector2i:
	return rooms[i]["door"]


func room_bed(i: int) -> Vector2i:
	return rooms[i]["bed"]


func room_work_spot(i: int) -> Vector2i:
	return rooms[i]["work"]


func room_badge_pos(i: int) -> Vector2:
	return rooms[i]["badge"]


func is_front_room(i: int) -> bool:
	return rooms[i]["front"]


func cell_to_room(c: Vector2i) -> int:
	var z: String = _zone.get(c, "out")
	if z.begins_with("room"):
		return int(z.substr(4))
	return -1


func zone(c: Vector2i) -> String:
	return _zone.get(c, "out")


func in_lobby(c: Vector2i) -> bool:
	return lobby.has_point(c)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not desk_cells.has(c)


static func _door_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a
		a = b
		b = t
	return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]


func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not walkable(b):
		return false
	if zone(a) == zone(b):
		return true
	return _doors.has(_door_key(a, b))


## Breadth-first path from `from` to `to`. Excludes the start cell, includes the goal.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from == to or not walkable(to):
		return result
	var came := {from: from}
	var frontier: Array[Vector2i] = [from]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var head := 0
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		if cur == to:
			break
		for d in dirs:
			var nxt: Vector2i = cur + d
			if came.has(nxt) or not can_step(cur, nxt):
				continue
			came[nxt] = cur
			frontier.append(nxt)
	if not came.has(to):
		return result
	var c := to
	while c != from:
		result.push_front(c)
		c = came[c]
	return result


## Isometric projection: grid cell -> screen position of the cell's centre.
static func to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0 + 16.0)


static func to_grid(s: Vector2) -> Vector2i:
	var sy := s.y - 16.0
	var gx := (s.x / 32.0 + sy / 16.0) / 2.0
	var gy := (sy / 16.0 - s.x / 32.0) / 2.0
	return Vector2i(roundi(gx), roundi(gy))
