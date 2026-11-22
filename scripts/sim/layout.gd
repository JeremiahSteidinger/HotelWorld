extends RefCounted
## Motel map: grid cells, zones (lobby, rooms, outside), doors and pathfinding.
## Pure data, so the simulation can run headless.
##
## Grid (x right-down, y left-down on screen in isometric view):
##   Lobby      x 0..3, y 0..4  (desk at (1,1),(2,1); staff stand at y=0, guests at y=2)
##   Rooms      6 rooms, each 2x2, x 5..16, y 0..1, door on the walkway side
##   Walkway    y = 2, x 4..17
##   Parking    y 3..5, x 4..17
##   Sidewalk   y = 6   (the desk line snakes out here)
##   Road       y 7..8

const W := 18
const H := 9
const ROOM_COUNT := 6
const LOBBY := Rect2i(0, 0, 4, 5)
const DESK_CELLS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
const STATIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
const SERVICE_SPOTS: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
const WAIT_SPOTS: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 3), Vector2i(3, 3), Vector2i(0, 4), Vector2i(3, 4), Vector2i(1, 4)]
const GUEST_SPAWN := Vector2i(17, 8)
const EXIT_CELL := Vector2i(0, 8)
const STAFF_SPAWN := Vector2i(0, 7)
const IDLE_SPOT := Vector2i(3, 1)

static var _line: Array[Vector2i] = []
static var _doors: Dictionary = {}


static func line_cells() -> Array[Vector2i]:
	if _line.is_empty():
		_line = [Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6)]
		for x in range(3, W):
			_line.append(Vector2i(x, 6))
	return _line


static func queue_slot(index: int) -> Vector2i:
	var cells := line_cells()
	return cells[mini(index, cells.size() - 1)]


static func room_cells(i: int) -> Array[Vector2i]:
	var x0 := 5 + 2 * i
	return [Vector2i(x0, 0), Vector2i(x0 + 1, 0), Vector2i(x0, 1), Vector2i(x0 + 1, 1)]


static func room_origin(i: int) -> Vector2i:
	return Vector2i(5 + 2 * i, 0)


static func room_door(i: int) -> Vector2i:
	return Vector2i(5 + 2 * i, 1)


static func room_bed(i: int) -> Vector2i:
	return Vector2i(6 + 2 * i, 0)


static func room_work_spot(i: int) -> Vector2i:
	return Vector2i(6 + 2 * i, 1)


static func cell_to_room(c: Vector2i) -> int:
	if c.y < 0 or c.y > 1 or c.x < 5 or c.x > 16:
		return -1
	return (c.x - 5) / 2


static func zone(c: Vector2i) -> String:
	if LOBBY.has_point(c):
		return "lobby"
	var r := cell_to_room(c)
	if r >= 0:
		return "room%d" % r
	return "out"


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


static func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not DESK_CELLS.has(c)


static func _door_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a
		a = b
		b = t
	return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]


static func _ensure_doors() -> void:
	if not _doors.is_empty():
		return
	_doors[_door_key(Vector2i(3, 2), Vector2i(4, 2))] = true
	_doors[_door_key(Vector2i(2, 4), Vector2i(2, 5))] = true
	for i in ROOM_COUNT:
		_doors[_door_key(room_door(i), room_door(i) + Vector2i(0, 1))] = true


static func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not walkable(b):
		return false
	if zone(a) == zone(b):
		return true
	_ensure_doors()
	return _doors.has(_door_key(a, b))


## Breadth-first path from `from` to `to`. Excludes the start cell, includes the goal.
static func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
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
