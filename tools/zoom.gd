extends Node
# Throwaway: crop-and-magnify a rendered PNG so a small part of a shot can be read.
#   Godot ... res://tools/zoom.tscn -- <png> <x> <y> <w> <h> <scale> [out]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(ProjectSettings.globalize_path(String(a[0])))
	var r := Rect2i(int(a[1]), int(a[2]), int(a[3]), int(a[4]))
	var s := int(a[5])
	var sub := img.get_region(r)
	sub.resize(r.size.x * s, r.size.y * s, Image.INTERPOLATE_NEAREST)
	var out := String(a[6]) if a.size() > 6 else "res://zoom.png"
	sub.save_png(out)
	print("wrote ", out, " ", sub.get_size())
	get_tree().quit()
