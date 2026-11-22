extends RefCounted
## A guest room. state: "clean", "dirty" or "occupied".
## guest_id is the guest who is staying in, or has reserved, the room.

var index := 0
var type := "single"
var state := "clean"
var guest_id := -1
var cleaner_id := -1
var clean_progress := 0.0  # 0..1 while being cleaned
