extends Control
# Throwaway harness: the LEVEL tab at 2x on the play screen's own backdrop, in
# the states it actually reaches — fresh, mid level-up flare, settled, and the
# 3-digit case. Run WITHOUT --headless.

const TAB := preload("res://level_tab.gd")

var _tabs: Array = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var xs := [40.0, 460.0, 880.0]
	for i in 3:
		var holder := Control.new()
		holder.position = Vector2(xs[i], 100.0)
		holder.scale = Vector2(3.0, 3.0)
		add_child(holder)
		var t = TAB.new()
		holder.add_child(t)
		t.layout_in(Vector2(400.0, 400.0))
		t.position = Vector2.ZERO
		_tabs.append(t)
	await get_tree().create_timer(0.4).timeout
	_tabs[2].set_level(148)        # settles well before the shot
	await get_tree().create_timer(0.9).timeout
	_tabs[1].set_level(8)          # caught mid-flare
	await get_tree().create_timer(0.10).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://tab_shot.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://tab_shot.png"))
	get_tree().quit()

func _draw() -> void:
	# The play screen's backdrop: the project's deep indigo vertical gradient.
	var top := Color(0.05, 0.05, 0.15)
	var bot := Color(0.02, 0.08, 0.22)
	var sz := get_viewport_rect().size
	var steps := 48
	for i in steps:
		var u := float(i) / float(steps)
		draw_rect(Rect2(0.0, sz.y * u, sz.x, sz.y / float(steps) + 1.0),
			top.lerp(bot, u))
