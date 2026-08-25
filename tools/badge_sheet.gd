extends Node

# Contact sheet for the achievement art: every badge in BadgeManager.BADGES drawn
# earned on the left half and locked on the right, plus one row per daily-task
# emblem. Saves a PNG per page. Developer harness, not shipped.

const COLS := 8
const CELL := 116.0
const PAD := 10.0

class Cell extends Control:
	var art := "star"
	var accent := Color.WHITE
	var earned := true
	var num := 0
	func _draw() -> void:
		BadgeIcons.draw_badge(self, size, art, accent, earned, num)

var _root: Control

func _ready() -> void:
	_root = Control.new()
	_root.size = Vector2(1280, 720)
	add_child(_root)
	var entries: Array = []
	for b in BadgeManager.BADGES:
		entries.append({"art": String(b["art"]), "accent": BadgeManager.CAT_COLORS[String(b["cat"])],
			"num": int(b.get("num", 0)), "label": String(b["name"])})
	for t in DailyTasks.TASKS:
		entries.append({"art": String(t["art"]), "accent": t["accent"],
			"num": int(t.get("num", 0)), "label": String(t["name"])})
	var page := 0
	var per_page := COLS * 5
	while page * per_page < entries.size():
		for ch in _root.get_children():
			ch.queue_free()
		await get_tree().process_frame
		for i in range(page * per_page, mini((page + 1) * per_page, entries.size())):
			var e: Dictionary = entries[i]
			var k := i - page * per_page
			for earned in [true, false]:
				var cell := Cell.new()
				cell.art = e["art"]; cell.accent = e["accent"]; cell.num = e["num"]
				cell.earned = earned
				cell.size = Vector2(CELL, CELL)
				cell.position = Vector2(
					PAD + float(k % COLS) * (CELL + PAD) + (0.0 if earned else CELL * 0.5),
					PAD + float(k / COLS) * (CELL + PAD + 16.0))
				if not earned:
					cell.position.y += 0.0
					cell.scale = Vector2.ONE * 0.42
					cell.position += Vector2(CELL * 0.62, CELL * 0.58)
				_root.add_child(cell)
				if earned:
					var l := Label.new()
					l.text = String(e["label"])
					l.add_theme_font_size_override("font_size", 11)
					l.position = cell.position + Vector2(-4, CELL - 2)
					l.size = Vector2(CELL + 8, 14)
					l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					_root.add_child(l)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://badge_sheet_%d.png" % page)
		print("shot  %s" % ProjectSettings.globalize_path("user://badge_sheet_%d.png" % page))
		page += 1
	get_tree().quit()
