extends Node2D
## Draws the motel: ground tiles, building shells, furniture, cars and characters.
## Reads simulation state every frame; never changes it.

const Layout := preload("res://scripts/sim/layout.gd")
const CharacterView := preload("res://scripts/view/character_view.gd")
const RoomOverlay := preload("res://scripts/view/room_overlay.gd")

const CAR_COLORS := ["car_red", "car_blue", "car_green", "car_yellow"]

var sim
var ground := Node2D.new()
var walls := Node2D.new()
var objects := Node2D.new()
var overlay: Node2D
var _tex := {}
var _chars := {}       # "g12" / "w3" -> CharacterView
var _beds: Array = []
var _cars: Array = []
var _sign: Sprite2D


func setup(s) -> void:
	sim = s
	for c in get_children():
		c.queue_free()
	ground = Node2D.new()
	walls = Node2D.new()
	objects = Node2D.new()
	objects.y_sort_enabled = true
	overlay = RoomOverlay.new()
	overlay.sim = sim
	overlay.z_index = 50
	add_child(ground)
	add_child(walls)
	add_child(objects)
	add_child(overlay)
	_chars = {}
	_beds = []
	_cars = []
	_build_ground()
	_build_buildings()
	_build_props()


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://art/%s.png" % name)
	return _tex[name]


static func top(c: Vector2i) -> Vector2:
	return Vector2((c.x - c.y) * 32.0, (c.x + c.y) * 16.0)


func _ground_tile(c: Vector2i) -> String:
	if Layout.LOBBY.has_point(c):
		return "tile_lobby"
	if Layout.cell_to_room(c) >= 0:
		return "tile_carpet"
	if c.y == 9:
		return "tile_road"
	if c.y == 8:
		return "tile_road_line"
	if c.y == 7:
		return "tile_road"
	if c.y == 6:
		return "tile_concrete"
	if c.x >= 4 and c.x <= 17:
		if c.y == 2:
			return "tile_concrete"
		if c.y == 4:
			return "tile_parking"
		if c.y == 3 or c.y == 5:
			return "tile_asphalt"
	if c == Vector2i(2, 5):
		return "tile_concrete"
	return "tile_grass"


func _build_ground() -> void:
	for y in range(-4, 13):
		for x in range(-6, 24):
			var c := Vector2i(x, y)
			var s := Sprite2D.new()
			s.texture = tex(_ground_tile(c))
			s.centered = false
			s.position = top(c) - Vector2(32, 0)
			ground.add_child(s)


func _box_sprite(tex_name: String, origin: Vector2i, depth: int, height: int, sort_at: Vector2, parent: Node2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(tex_name)
	s.centered = false
	s.position = sort_at
	s.offset = top(origin) - Vector2(depth * 32, height) - sort_at
	parent.add_child(s)
	return s


func _upright(tex_name: String, cell: Vector2i, parent: Node2D, foot := 4) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(tex_name)
	s.centered = false
	s.position = Layout.to_screen(Vector2(cell))
	s.offset = Vector2(-s.texture.get_width() / 2.0, -s.texture.get_height() + foot)
	parent.add_child(s)
	return s


func _build_buildings() -> void:
	_box_sprite("lobby_shell", Vector2i(0, 0), 5, 56, Vector2.ZERO, walls)
	_box_sprite("desk", Vector2i(1, 1), 1, 22, Layout.to_screen(Vector2(1.5, 1.0)), objects)
	for i in Layout.ROOM_COUNT:
		_box_sprite("room_shell", Layout.room_origin(i), 2, 56, Vector2.ZERO, walls)
		var room_beds: Array = []
		for cell in Layout.room_beds(i, _bed_count(i)):
			room_beds.append(_box_sprite("bed_clean", cell, 1, 18, Layout.to_screen(Vector2(cell)), objects))
		_beds.append(room_beds)
		var car_cell := Vector2i(5 + 2 * i, 4)
		var car := _box_sprite(CAR_COLORS[i % CAR_COLORS.size()], car_cell, 1, 22, Layout.to_screen(Vector2(car_cell)), objects)
		car.visible = false
		_cars.append(car)


## Double rooms get two beds, everything else one.
func _bed_count(i: int) -> int:
	if i < sim.rooms.size() and sim.rooms[i].type == "double":
		return 2
	return 1


func _build_props() -> void:
	_sign = _upright("sign", Vector2i(3, 5), objects, 2)
	_upright("plant", Vector2i(3, 0), objects, 2)
	_box_sprite("ice_machine", Vector2i(4, 0), 1, 34, Layout.to_screen(Vector2(4, 0)), objects)
	for c in [Vector2i(-2, 1), Vector2i(-3, 4), Vector2i(-2, 6), Vector2i(19, 0), Vector2i(20, 3), Vector2i(19, 5),
			Vector2i(8, -2), Vector2i(13, -3), Vector2i(-4, -1), Vector2i(1, -3), Vector2i(22, 6)]:
		_upright("tree", c, objects, 4)


func _process(_delta: float) -> void:
	if sim == null:
		return
	_sync_rooms()
	_sync_characters()


func _sync_rooms() -> void:
	_sign.texture = tex("sign" if sim.has_vacancy() else "sign_full")
	for r in sim.rooms:
		for bed in _beds[r.index]:
			bed.texture = tex("bed_messy" if r.state == "dirty" else "bed_clean")
		var has_guest: bool = r.guest_id != -1 and sim.guests.has(r.guest_id) and sim.guests[r.guest_id].state in ["staying", "to_room", "waiting_room"]
		_cars[r.index].visible = has_guest and sim.guests[r.guest_id].archetype != "budget"


func _sync_characters() -> void:
	var seen := {}
	for gid in sim.guests:
		var g = sim.guests[gid]
		var key := "g%d" % gid
		seen[key] = true
		var v = _view(key, "guest_" + g.archetype)
		v.visible = g.state != "staying"
		v.sync_guest(g, sim)
	for w in sim.workers:
		var key := "w%d" % w.id
		seen[key] = true
		var v = _view(key, w.role)
		v.sync_worker(w, sim)
	for key in _chars.keys():
		if not seen.has(key):
			_chars[key].queue_free()
			_chars.erase(key)


func _view(key: String, sprite_name: String):
	if not _chars.has(key):
		var v = CharacterView.new()
		v.frames = [tex(sprite_name + "_0"), tex(sprite_name + "_1")]
		objects.add_child(v)
		_chars[key] = v
	return _chars[key]


func characters_at(world_pos: Vector2) -> Array:
	var out := []
	for key in _chars:
		var v = _chars[key]
		if v.visible and Rect2(v.position + Vector2(-10, -34), Vector2(20, 36)).has_point(world_pos):
			out.append(key)
	return out
