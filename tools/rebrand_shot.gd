extends Node

# Screenshot harness for the rebrand welcome popup — both receipt shapes, plus a
# few frames of the confetti so the shower can be eyeballed. Developer harness,
# not shipped.

const RebrandPopup := preload("res://rebrand_welcome_popup.gd")

# A receipt with every refund row the migration can produce, and a gift-only one.
const _FULL := {
	"at": "2026-08-30T19:15:19Z", "refund": 7870, "gift": 2000,
	"items": [
		{"key": "wheel",  "label": "Wheel cosmetics",   "n": 38, "coins": 5690},
		{"key": "themes", "label": "Old backgrounds",   "n": 10, "coins": 2180},
	],
}
const _BIG := {
	"at": "2026-08-30T19:15:19Z", "refund": 70570, "gift": 2000,
	"items": [
		{"key": "wheel",  "label": "Wheel cosmetics",    "n": 44, "coins": 6710},
		{"key": "skins",  "label": "Special Skins",      "n": 8,  "coins": 52500},
		{"key": "themes", "label": "Old backgrounds",    "n": 20, "coins": 11330},
		{"key": "levels", "label": "Difficulty unlocks", "n": 2,  "coins": 30},
	],
}
const _GIFT := {"at": "2026-08-30T19:15:19Z", "refund": 0, "gift": 2000, "items": []}

func _ready() -> void:
	await get_tree().process_frame
	await _shoot("rebrand_popup_refund", _FULL)
	await _shoot("rebrand_popup_all_rows", _BIG)
	await _shoot("rebrand_popup_gift", _GIFT)
	get_tree().quit()

func _shoot(name: String, receipt: Dictionary) -> void:
	var sky := ColorRect.new()          # stand-in for the home screen behind it
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.color = Color(0.03, 0.04, 0.12)
	add_child(sky)
	var p = RebrandPopup.new()
	p.receipt = receipt
	add_child(p)
	# Long enough for the entrance ceremony to finish and the confetti to fill.
	await get_tree().create_timer(1.8).timeout
	await _shot(name)
	await get_tree().create_timer(0.35).timeout
	await _shot(name + "_b")            # second frame: the confetti has moved
	p.queue_free()
	sky.queue_free()
	await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % name)
	print("shot  %s" % ProjectSettings.globalize_path("user://%s.png" % name))
