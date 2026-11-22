extends Node2D
## Draws one property: ground tiles, building shells, furniture, cars and characters.
## Reads simulation state every frame; never changes it.

const Layout := preload("res://scripts/sim/layout.gd")
const CharacterView := preload("res://scripts/view/character_view.gd")
const RoomOverlay := preload("res://scripts/view/room_overlay.gd")

const CAR_COLORS := ["car_red", "car_blue", "car_green", "car_yellow"]

var sim                # the Property being shown
var L                  # its Layout
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
	L = s.layout
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
	if L.kind == "hotel":
		return _hotel_tile(c)
	if L.in_lobby(c):
		return "tile_lobby"
	if L.cell_to_room(c) >= 0:
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


func _hotel_tile(c: Vector2i) -> String:
	if L.in_lobby(c):
		return "tile_marble"
	if L.cell_to_room(c) >= 0:
		return "tile_carpet"
	if L.zone(c) == "hall":
		return "tile_hall"
	match c.y:
		10, 12:
			return "tile_road"
		11:
			return "tile_road_line"
		9:
			return "tile_concrete"
		5:
			if c.x <= 21:
				return "tile_concrete"
	if c.y >= 6 and c.y <= 8 and c.x >= 6 and c.x <= 21:
		return "tile_parking" if c.y == 7 else "tile_asphalt"
	return "tile_grass"


func _build_ground() -> void:
	for y in range(-4, L.h + 5):
		for x in range(-6, L.w + 6):
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
	var hotel: bool = L.kind == "hotel"
	_box_sprite("hotel_lobby_shell" if hotel else "lobby_shell", Vector2i(0, 0), 5, 56, Vector2.ZERO, walls)
	if hotel:
		_box_sprite("desk3", Vector2i(1, 1), 1, 22, Layout.to_screen(Vector2(2.0, 1.0)), objects)
	else:
		_box_sprite("desk", Vector2i(1, 1), 1, 22, Layout.to_screen(Vector2(1.5, 1.0)), objects)
	for i in L.room_count():
		var shell := "room_shell"
		if hotel:
			shell = "hotel_room_shell_front" if L.is_front_room(i) else "hotel_room_shell"
		_box_sprite(shell, L.room_origin(i), 2, 56, Vector2.ZERO, walls)
		var bed := _box_sprite("bed_clean", L.room_bed(i), 1, 18, Layout.to_screen(Vector2(L.room_bed(i))), objects)
		_beds.append(bed)
		if sim.rooms[i].type == "suite":
			var o: Vector2i = L.room_origin(i)
			# The room's free corner: not the door, bed or work spot.
			var chair_cell := Vector2i(o.x, o.y + 1) if L.is_front_room(i) else o
			_box_sprite("armchair", chair_cell, 1, 16, Layout.to_screen(Vector2(chair_cell)), objects)
		var car_cell := Vector2i(7 + i, 6 if i % 2 == 0 else 8) if hotel else Vector2i(5 + 2 * i, 4)
		var car := _box_sprite(CAR_COLORS[i % CAR_COLORS.size()], car_cell, 1, 22, Layout.to_screen(Vector2(car_cell)), objects)
		car.visible = false
		_cars.append(car)


func _build_props() -> void:
	var trees: Array
	if L.kind == "hotel":
		_sign = _upright("hotel_sign", Vector2i(2, 7), objects, 2)
		_upright("plant", Vector2i(5, 0), objects, 2)
		_upright("plant", Vector2i(0, 1), objects, 2)
		trees = [Vector2i(-2, 1), Vector2i(-3, 4), Vector2i(-2, 7), Vector2i(23, 0), Vector2i(24, 3), Vector2i(23, 6),
			Vector2i(10, -2), Vector2i(16, -3), Vector2i(-4, -1), Vector2i(2, -3), Vector2i(26, 8), Vector2i(4, 7), Vector2i(1, 8)]
	else:
		_sign = _upright("sign", Vector2i(3, 5), objects, 2)
		_upright("plant", Vector2i(3, 0), objects, 2)
		_box_sprite("ice_machine", Vector2i(4, 0), 1, 34, Layout.to_screen(Vector2(4, 0)), objects)
		trees = [Vector2i(-2, 1), Vector2i(-3, 4), Vector2i(-2, 6), Vector2i(19, 0), Vector2i(20, 3), Vector2i(19, 5),
			Vector2i(8, -2), Vector2i(13, -3), Vector2i(-4, -1), Vector2i(1, -3), Vector2i(22, 6)]
	for c in trees:
		_upright("tree", c, objects, 4)


func _process(_delta: float) -> void:
	if sim == null:
		return
	_sync_rooms()
	_sync_characters()


func _sync_rooms() -> void:
	var sign_name := "hotel_sign" if L.kind == "hotel" else "sign"
	_sign.texture = tex(sign_name if sim.has_vacancy() else sign_name + "_full")
	for r in sim.rooms:
		_beds[r.index].texture = tex("bed_messy" if r.state == "dirty" else "bed_clean")
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
		if not w.present:
			continue
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
