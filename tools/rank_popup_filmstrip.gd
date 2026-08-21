extends Control

# Grabs the popup's entrance at fixed beats and tiles the frames into one image,
# so the choreography (dialog pop -> cards dealt in -> total lands -> shine) can
# be reviewed as a strip instead of a video.
const RankPopup := preload("res://daily_rank_reward_popup.gd")
const SHOTS := [0, 4, 8, 13, 19, 26, 34, 46]     # frames after the popup is added
const COLS := 2
const SCALE := 2                                  # downscale factor per cell

func _ready() -> void:
	_run()

func _run() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){\n vec2 p = UV - vec2(0.5);\n vec3 c = mix(vec3(0.09,0.06,0.20), vec3(0.03,0.03,0.09), length(p)*1.4);\n COLOR = vec4(c,1.0);\n}"
	var m := ShaderMaterial.new()
	m.shader = sh
	bg.material = m
	add_child(bg)

	var p: Control = RankPopup.new()
	p.set("total", 950)
	p.set("results", [
		{"diff": "easy", "rank": 1, "reward": 500},
		{"diff": "moderate", "rank": 3, "reward": 150},
		{"diff": "hard", "rank": 7, "reward": 100}])
	add_child(p)

	var frames: Array[Image] = []
	var f := 0
	var want := 0
	while want < SHOTS.size():
		await RenderingServer.frame_post_draw
		if f == SHOTS[want]:
			var img := get_viewport().get_texture().get_image()
			img.resize(img.get_width() / SCALE, img.get_height() / SCALE, Image.INTERPOLATE_LANCZOS)
			frames.append(img)
			want += 1
		f += 1

	var cw := frames[0].get_width()
	var ch := frames[0].get_height()
	var rows := int(ceil(float(frames.size()) / float(COLS)))
	var sheet := Image.create(cw * COLS + (COLS - 1) * 6, ch * rows + (rows - 1) * 6,
		false, frames[0].get_format())
	sheet.fill(Color(0.02, 0.02, 0.05))
	for i in frames.size():
		var cx := (i % COLS) * (cw + 6)
		var cy := (i / COLS) * (ch + 6)
		sheet.blit_rect(frames[i], Rect2i(0, 0, cw, ch), Vector2i(cx, cy))
	sheet.save_png("user://rankpopup_filmstrip.png")
	print("filmstrip: %d frames at %dx%d" % [frames.size(), cw, ch])
	get_tree().quit()
