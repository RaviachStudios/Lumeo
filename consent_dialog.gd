extends CanvasLayer

# The consent prompt itself. Built entirely in code so it has no scene file and no
# dependency on main.tscn — ConsentManager adds it straight to the tree root,
# before the game has finished starting up.
#
# The two buttons are deliberately identical in size, colour and weight. That is
# not a style choice: a refusal that is visually harder to reach than an
# acceptance is a dark pattern, and regulators have treated it as invalidating the
# consent it collects. If you restyle this, keep them symmetrical.

signal answered(granted: bool)

# Same URL as home_screen.gd and the Play Store listing.
const PRIVACY_POLICY_URL := "https://raviachstudios.github.io/Raviach-policy/"

const TITLE_TEXT := "Ads in Simon"

const BODY_TEXT := """Simon is free to play, and ads pay for it.

We can show you ads chosen for you, which means sharing your device's advertising ID with our ad partner, Unity Ads, so it can pick more relevant ones. This earns more, so it keeps the game free.

You can say no. You'll still see ads, just generic ones instead — nothing about you is shared.

You can change this any time under Privacy in the settings."""

const PANEL_BG := Color(0.06, 0.09, 0.19, 1.0)
const PANEL_BORDER := Color(0.30, 0.42, 0.75, 1.0)
const TEXT_COL := Color(0.90, 0.93, 1.0, 1.0)
const BTN_COL := Color(0.16, 0.24, 0.46, 1.0)
const BTN_HOVER := Color(0.22, 0.32, 0.58, 1.0)


func _init() -> void:
	# Above every gameplay layer, and it must keep working while the game behind it
	# is paused during startup.
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallows taps aimed at the game underneath. There is no way to dismiss this
	# without answering — an ignored prompt must not read as a "yes".
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	panel.add_child(col)

	var title := Label.new()
	title.text = TITLE_TEXT
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", TEXT_COL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var body := Label.new()
	body.text = BODY_TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", TEXT_COL)
	col.add_child(body)

	if not PRIVACY_POLICY_URL.is_empty():
		var link := LinkButton.new()
		link.text = "Privacy policy"
		link.add_theme_font_size_override("font_size", 22)
		link.pressed.connect(func() -> void: OS.shell_open(PRIVACY_POLICY_URL))
		col.add_child(link)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	# Refuse first in reading order, and identical to accept in every visual
	# dimension. See the note at the top of this file.
	row.add_child(_make_button("No, generic ads", false))
	row.add_child(_make_button("Yes, that's fine", true))


func _make_button(label: String, grants: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(320, 78)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", TEXT_COL)
	btn.add_theme_color_override("font_hover_color", TEXT_COL)

	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_COL
	normal.set_corner_radius_all(14)
	normal.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BTN_HOVER
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

	btn.pressed.connect(func() -> void: answered.emit(grants))
	return btn
