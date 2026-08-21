extends Control

# Renders the daily-rank reward popup over a stand-in home background and saves a
# PNG per case, so the layout can be reviewed without waiting for a real midnight
# payout. Cases cover the shapes the receipt actually arrives in.
const RankPopup := preload("res://daily_rank_reward_popup.gd")
const PX := Vector2i(1280, 720)

const CASES := [
	["podium", 950, [
		{"diff": "easy", "rank": 1, "reward": 500},
		{"diff": "moderate", "rank": 3, "reward": 150},
		{"diff": "hard", "rank": 7, "reward": 100},
	]],
	["single", 25, [
		{"diff": "hard", "rank": 44, "reward": 25},
	]],
	["two", 350, [
		{"diff": "moderate", "rank": 2, "reward": 300},
		{"diff": "hard", "rank": 12, "reward": 50},
	]],
	["grouped", 1275, [
		{"diff": "easy", "rank": 4, "reward": 100},
		{"diff": "easy", "rank": 1, "reward": 500},
		{"diff": "moderate", "rank": 9, "reward": 100},
		{"diff": "moderate", "rank": 22, "reward": 50},
		{"diff": "hard", "rank": 2, "reward": 300},
		{"diff": "hard", "rank": 31, "reward": 25},
		{"diff": "easy", "rank": 40, "reward": 25},
		{"diff": "hard", "rank": 6, "reward": 100},
		{"diff": "moderate", "rank": 48, "reward": 25},
	]],
]

func _ready() -> void:
	_run()

func _run() -> void:
	for case in CASES:
		var host := Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(host)

		# Stand-in for the home screen behind the modal, so the backdrop and the
		# dialog's shadow are judged against something, not black.
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment(){\n vec2 p = UV - vec2(0.5);\n vec3 c = mix(vec3(0.09,0.06,0.20), vec3(0.03,0.03,0.09), length(p)*1.4);\n COLOR = vec4(c,1.0);\n}"
		var m := ShaderMaterial.new()
		m.shader = sh
		bg.material = m
		host.add_child(bg)

		var p: Control = RankPopup.new()
		p.set("total", int(case[1]))
		p.set("results", (case[2] as Array).duplicate())
		host.add_child(p)

		# Let the entrance settle so the still shows the resting state.
		for i in 90:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://rankpopup_%s_%dx%d.png" % [case[0], img.get_width(), img.get_height()])
		print("wrote ", case[0], "  dialog_h=", p.get("_dialog").size.y)
		host.queue_free()
		await RenderingServer.frame_post_draw
	print("DONE")
	get_tree().quit()
