extends Node
# Renders every LUME 3D background through a real gameplay board, one PNG each, so
# the Godot result can be put side by side with Themes/preview/BG_*.png.
#
#   Godot..._console.exe --path . res://tools/bg_sheet.tscn -- <board> [id ...]
#
# <board> is easy | moderate | hard (default hard, which is the difficulty whose
# camera the Blender previews were framed through). Run WITHOUT --headless.

const Easy := preload("res://easy_game_ui.gd")
const Medium := preload("res://memory_game_ui.gd")
const Hard := preload("res://hard_game_ui.gd")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var board := args[0] if args.size() > 0 else "hard"
	var ids: Array = args.slice(1) if args.size() > 1 else BackgroundScenes.ORDER

	# CoinsManager finishes its (signed-out) load a few frames in and resets
	# selected_theme to "default" as it does, so equip AFTER it has settled or the
	# board builds with no background at all.
	for i in 40:
		await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""

	for id in ids:
		CoinsManager.selected_theme = String(id)
		var dev: Control = (Easy.new() if board == "easy"
			else (Hard.new() if board == "hard" else Medium.new()))
		dev.input_enabled = false
		dev.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dev)
		dev.configure(dev._count, [])
		dev.set_level(12)
		# Let the fit land, the shaders compile and TIME advance far enough that a
		# travelling pulse is somewhere visible rather than at its start.
		for i in 90:
			await get_tree().process_frame
		dev._kick_render()
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "user://bg_%s_%s.png" % [board, id]
		get_viewport().get_texture().get_image().save_png(path)
		print("shot %s  %s" % [id, ProjectSettings.globalize_path(path)])
		dev.queue_free()
		await get_tree().process_frame
	get_tree().quit()
