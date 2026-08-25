extends Control

# Arena hub (THE COLOSSEUM): the entry point into live multiplayer. Two choices —
# CREATE a room, or JOIN one. Join then asks Private (enter the shared ID) or
# Public (browse the open-rooms lobby). Rooms are live and synchronous, so there's
# no persistent "my contests" list here anymore — you create/join and drop straight
# into the room.

const ArenaUI := preload("res://arena_ui.gd")
const ArenaFX := preload("res://arena_fx.gd")

# The crown (Create) and door (Join) choices are drawn well above their base
# size so they read as the two big entrances on the enlarged stage (~20% larger
# than the previous 2.0 for a chunkier, more premium footprint).
const ACTION_SCALE := 2.4

# Difficulty choices offered on the Create-contest popup.
const DIFF_ORDER: Array[String] = ["easy", "moderate", "hard"]
const DIFF_ACCENT := {
	"easy": Color(0.28, 0.82, 0.45),
	"moderate": Color(1.00, 0.72, 0.25),
	"hard": Color(0.95, 0.32, 0.40),
}

var game_manager: Node

var _bg: ColorRect
var _fx: ArenaFX
var _back: Button
var _title: Label
var _subtitle: Label

# Primary actions.
var _create_btn: Button
var _join_btn: Button

# When this client is already seated in a live room, BOTH entrances are replaced by
# a single centered "return to your room" card showing the room's ID — you can only
# be in one room at a time, so there's nothing to create or join. `_return_cid` holds
# that room's ID (empty when there's no such room); `_room_btn` is the single card.
var _return_cid := ""
var _room_btn: Button
# Signature of the room card currently drawn ("cid:host:label"), so the async
# validation can skip a redundant rebuild (and its icon bake) when it confirms exactly
# what the cache already painted — the common case for a seated player.
var _room_card_sig := ""

var _toast: Label

# Create-contest popup (name + difficulty + visibility, all on one modal).
var _scrim: ColorRect
var _create_modal: Panel
var _cname_edit: LineEdit
var _cmsg: Label
var _cdiff := "easy"
var _cpublic := true
var _cdiff_btns: Array[Dictionary] = []   # {"btn": Button, "diff": String}
var _cvis_btns: Array[Dictionary] = []    # {"btn": Button, "public": bool}
var _create_modal_base_y := 0.0           # resting Y (no keyboard)
var _create_modal_shift := 0.0            # current upward lift so fields clear the keyboard

# Join-choice modal (Private / Public).
var _choice_modal: Panel

# Public-rooms lobby popup (shown in-place instead of a separate screen). Lists the
# open, still-in-lobby public rooms with a Join button on each.
var _lobby_scrim: ColorRect
var _lobby_modal: Panel
var _lobby_scroll: ScrollContainer
var _lobby_list: VBoxContainer
var _lobby_status: Label        # loading / empty message overlaid on the list area
var _lobby_count: Label
var _lobby_prev: Button
var _lobby_next: Button
var _lobby_page_lbl: Label
var _lobby_refresh: Button      # re-reads the CF-maintained index (1 read per press)
var _lobby_tick: Timer          # 1s: local countdown pills / retires dead rows (no reads)
var _lobby_rows: Array = []
var _lobby_page := 0
var _lobby_busy := false

# Join-by-ID input: revealed inline inside the join-choice modal when Private is
# picked (a room-ID field + Join button slide in below the Private option).
var _id_edit: LineEdit
var _id_msg: Label
var _id_join_btn: Button
var _private_expanded := false
var _choice_modal_base_y := 0.0  # resting Y of the choice modal (no keyboard)
var _choice_modal_shift := 0.0   # current upward lift so the field clears the keyboard

var _busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_bg("hub")
	add_child(_bg)

	# Ambient flourish (spotlights / confetti / winged Simon fly-by) behind the UI.
	_fx = ArenaFX.new()
	add_child(_fx)
	_fx.setup(get_viewport_rect().size)

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

	_title = ArenaUI.title("ARENA")
	add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Race friends in a live memory showdown"
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.add_theme_color_override("font_color", ArenaUI.MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)

	_create_btn = ArenaUI.action_card("CREATE CONTEST", "", "crown", ArenaUI.ACCENT, true, ArenaUI.TORCH, ACTION_SCALE)
	_create_btn.pressed.connect(_on_create)
	add_child(_create_btn)

	_join_btn = ArenaUI.action_card("JOIN CONTEST", "", "door", ArenaUI.JOIN_BLUE, false, ArenaUI.JOIN_CYAN, ACTION_SCALE)
	_join_btn.pressed.connect(_on_join)
	add_child(_join_btn)

	_build_toast()

	_layout()
	get_viewport().size_changed.connect(_layout)

	# If we're already in a live room (e.g. the host backed out of their own lobby, or
	# force-quit mid-game and relaunched), reflect it as the single "return to your room"
	# card instead of the CREATE / JOIN entrances. Paint it FIRST off the synchronous
	# cache (ContestManager restored the room's id/title/host from the user doc at
	# startup) so there's no CREATE/JOIN flash before the network confirms. Then validate
	# async: active_room() reads the room to confirm/refresh it, or — if the pointer is
	# stale (room deleted, we were kicked, or the race finished) — self-heals and we fall
	# back to the two entrances.
	if ContestManager.has_cached_room():
		_show_room_card(ContestManager.cached_room_id(),
			ContestManager.cached_room_title(), ContestManager.cached_room_is_host())
	_refresh_active_room()

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	if _fx:
		_fx.relayout(sz)
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 52)
		_title.position = Vector2(0, 60)
	if _subtitle:
		_subtitle.size = Vector2(sz.x, 26)
		_subtitle.position = Vector2(0, 120)

	# The crown (Create) and door (Join) now stand directly on the enlarged
	# podium, evenly spaced either side of the championship shield — no
	# separate menu row below it anymore. Card footprint is derived from the
	# (scaled) icon + pedestal so the 3x choices are never clipped. When the player
	# is already in a room, a SINGLE card (the room ID) takes the shield's spot
	# instead — see _refresh_active_room.
	if _room_btn:
		var ps: Vector2 = _room_btn.get_meta("plaque_size")
		var crest: float = _room_btn.get_meta("crest")
		ArenaUI.layout_action_card(_room_btn, ArenaFX.side_slot_pos(sz, 0.0),
			Vector2(ps.x + 60.0, ps.y + crest + 90.0))
	elif _create_btn:
		var ps: Vector2 = _create_btn.get_meta("plaque_size")
		var crest: float = _create_btn.get_meta("crest")
		var cw := ps.x + 60.0
		var ch := ps.y + crest + 90.0
		ArenaUI.layout_action_card(_create_btn, ArenaFX.side_slot_pos(sz, -1.0), Vector2(cw, ch))
		ArenaUI.layout_action_card(_join_btn, ArenaFX.side_slot_pos(sz, 1.0), Vector2(cw, ch))

	if _toast:
		_toast.size = Vector2(sz.x, 30)
		_toast.position = Vector2(0, sz.y - 40)
	_layout_choice_modal(sz)
	_layout_create_modal(sz)
	_layout_lobby_modal(sz)

# ---------------- create / join ----------------

func _on_create() -> void:
	if not _require_account():
		return
	_open_create_modal()

func _on_join() -> void:
	if not _require_account():
		return
	if _choice_modal == null:
		_build_choice_modal()
	_collapse_private()
	_choice_modal.visible = true

# ---------------- active-room reflection ----------------

# A player can be in at most one Arena room at a time. When we already hold one, the
# two CREATE / JOIN entrances are replaced by a SINGLE centered card engraved with the
# room's NAME: tapping it drops straight back into that lobby. There's nothing to
# create or join while you're seated, so the one card is the whole hub.
#
# This is the async VALIDATOR: active_room() reads the room (self-healing/persisting a
# stale pointer) and reconciles the hub to the truth — confirming the card the cache
# already painted, or reverting to the entrances if the pointer was stale. The instant
# paint happens separately in _ready off the synchronous cache; this corrects it.
func _refresh_active_room() -> void:
	var room: Dictionary = await ContestManager.active_room()
	if not is_inside_tree():
		return
	var cid := String(room.get("id", ""))
	if cid.is_empty():
		# No live room — either we never had one, or the cached pointer we optimistically
		# painted from turned out stale and active_room() just self-healed it. Either way
		# the two entrances are the correct state; revert to them if a room card is up.
		if not _return_cid.is_empty():
			_show_entrances()
		return
	# Live room confirmed — (re)paint the return card with the authoritative title/host.
	_show_room_card(cid, String(room.get("title", "Contest")),
		String(room.get("creator_uid", "")) == FirebaseManager.uid)

# Paints the hub for "seated in a room": folds away both entrances and shows the
# single centered return card, engraved with the room's NAME. Host reads as the gold
# crown (your room), a guest as the blue door (a room you entered). Rebuilds the card
# if one is already up (so the async validation can refresh a cache-painted label).
func _show_room_card(cid: String, title: String, is_host: bool) -> void:
	_return_cid = cid
	if _create_btn:
		_create_btn.visible = false
	if _join_btn:
		_join_btn.visible = false
	var label := title if not title.is_empty() else "Your room"
	# Already showing exactly this card? Leave it (skips a needless icon rebuild/bake).
	var sig := "%s:%s:%s" % [cid, is_host, label]
	if _room_btn != null and sig == _room_card_sig:
		return
	_room_card_sig = sig
	if _room_btn:
		_room_btn.queue_free()
		_room_btn = null
	var accent: Color = ArenaUI.ACCENT if is_host else ArenaUI.JOIN_BLUE
	var glow: Color = ArenaUI.TORCH if is_host else ArenaUI.JOIN_CYAN
	var crest := "crown" if is_host else "door"
	_room_btn = ArenaUI.action_card(label, "", crest, accent, true, glow, ACTION_SCALE)
	_room_btn.pressed.connect(func() -> void: game_manager.show_contest_detail(cid))
	add_child(_room_btn)

	# The ID lives on the subtitle now (still shareable) alongside the "tap to return".
	_subtitle.text = ("Your room · ID %s — tap to jump back in" % cid) if is_host \
		else ("You're in room · ID %s — tap to jump back in" % cid)
	_layout()

# Paints the hub for "not in a room": the two CREATE / JOIN entrances, no return card.
# Used when the cache-painted card is validated away as stale.
func _show_entrances() -> void:
	_return_cid = ""
	_room_card_sig = ""
	if _room_btn:
		_room_btn.queue_free()
		_room_btn = null
	if _create_btn:
		_create_btn.visible = true
	if _join_btn:
		_join_btn.visible = true
	_subtitle.text = "Race friends in a live memory showdown"
	_layout()

# ---------------- create-contest popup ----------------

# Everything needed to spin up a room lives on one modal: a name field (with a
# dice icon that drops in a funny name), a difficulty picker, and a Public/Private
# toggle. "Create" makes the room and drops straight into its lobby.
func _open_create_modal() -> void:
	if _create_modal == null:
		_build_create_modal()
	_cname_edit.text = ""
	_cmsg.text = ""
	_cdiff = "easy"
	_cpublic = true
	_refresh_create_selection()
	# Clear the stage behind the modal: the two big CREATE / JOIN entrances step
	# aside so the popup owns the screen (they return when it's dismissed).
	_set_action_cards_visible(false)
	_scrim.visible = true
	_create_modal.visible = true
	# The arena FX is hidden behind the blur scrim now — freeze it so the phone
	# isn't animating an invisible crowd under a full-screen blur.
	if _fx:
		_fx.pause()
	_cname_edit.grab_focus()

func _close_create_modal() -> void:
	if _cname_edit:
		_cname_edit.release_focus()
	if _create_modal:
		_create_modal.visible = false
	if _scrim:
		_scrim.visible = false
	if _fx:
		_fx.resume()
	_set_action_cards_visible(true)

# Show/hide the two primary entrances (Create / Join) behind the create popup. When
# the player is in a room the entrances are permanently folded away (the single room
# card stands in their place), so never re-reveal them here.
func _set_action_cards_visible(on: bool) -> void:
	var show := on and _room_btn == null
	if _create_btn:
		_create_btn.visible = show
	if _join_btn:
		_join_btn.visible = show

const CREATE_MODAL_W := 440.0
const CREATE_MODAL_H := 452.0
const CREATE_MODAL_TOP_MARGIN := 10.0   # modal top never lifts past this many px from the top

func _build_create_modal() -> void:
	# Dim scrim behind the modal — catches outside taps to dismiss and blocks the arena.
	# A screen-texture shader gives the arena behind it a soft blur and a deeper dark
	# wash (~25% more opaque than the old flat 0.6 scrim) so the popup reads as the
	# clear focus. Sampling `hint_screen_texture` captures everything drawn before the
	# scrim (the arena backdrop) — the modal is drawn after, so it stays crisp.
	_scrim = ColorRect.new()
	_scrim.color = Color(1, 1, 1, 1)
	_scrim.material = _make_scrim_blur_material()
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_create_modal())
	add_child(_scrim)

	_create_modal = _make_premium_panel(ArenaUI.ACCENT)
	_create_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_create_modal.visible = false
	add_child(_create_modal)

	var title := Label.new()
	title.text = "Create Contest"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 18)
	title.size = Vector2(CREATE_MODAL_W, 34)
	_create_modal.add_child(title)

	# --- name field + dice shuffle ---
	_cname_edit = LineEdit.new()
	_cname_edit.placeholder_text = "Name your room"
	_cname_edit.max_length = ContestManager.TITLE_MAX
	_cname_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cname_edit.add_theme_font_size_override("font_size", 22)
	_cname_edit.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66))
	_cname_edit.add_theme_color_override("font_placeholder_color", Color(0.62, 0.66, 0.86, 0.5))
	_cname_edit.add_theme_color_override("caret_color", ArenaUI.GOLD)
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.05, 0.07, 0.17, 0.96)
	fs.set_corner_radius_all(14)
	fs.corner_detail = 6
	fs.border_color = Color(1.0, 0.82, 0.40, 0.9)
	fs.set_border_width_all(2)
	fs.content_margin_left = 14
	fs.content_margin_right = 14
	_cname_edit.add_theme_stylebox_override("normal", fs)
	var ff := fs.duplicate() as StyleBoxFlat
	ff.border_color = ArenaUI.GOLD.lightened(0.16)
	_cname_edit.add_theme_stylebox_override("focus", ff)
	# Enter / "Done" on the name field must NEVER create the room directly — it only
	# dismisses the keyboard. Android's soft keyboard emits text_submitted whenever it's
	# closed (e.g. tapping the 🎲 dice or anywhere off the field), not just on the Done
	# key; wiring that straight to _do_create() made the room create itself ~1s after the
	# keyboard closed, without the player ever tapping Create. (The full-screen wizard
	# guards the same quirk.)
	_cname_edit.text_submitted.connect(func(_t: String) -> void: _cname_edit.release_focus())
	_create_modal.add_child(_cname_edit)

	var dice := _sculpt_button("", ArenaUI.SAND)
	dice.name = "dice"
	var dice_icon := ArenaIcon.new()
	dice_icon.kind = "dice"
	dice_icon.col = ArenaUI.SAND.lightened(0.5)
	dice_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_icon.offset_bottom = -5.0   # sit on the button body, clear of its base shadow
	dice.add_child(dice_icon)
	dice.pressed.connect(func() -> void:
		_cname_edit.text = ContestManager.random_title())
	_create_modal.add_child(dice)

	# --- difficulty picker ---
	_create_modal.add_child(_caption("How hard is the game?", "diff_cap"))
	_cdiff_btns.clear()
	for diff in DIFF_ORDER:
		var accent: Color = DIFF_ACCENT[diff]
		var b := _seg_button(ContestManager.diff_label(diff), accent)
		b.pressed.connect(func() -> void:
			_cdiff = diff
			_refresh_create_selection())
		_create_modal.add_child(b)
		_cdiff_btns.append({"btn": b, "diff": diff})

	# --- visibility toggle ---
	_create_modal.add_child(_caption("Who can join your room?", "vis_cap"))
	_cvis_btns.clear()
	var vis_opts := [
		{"public": true, "kind": "globe", "label": "Public", "accent": ArenaUI.ACCENT},
		{"public": false, "kind": "lock", "label": "Private", "accent": ArenaUI.SAND},
	]
	for opt in vis_opts:
		var is_pub: bool = opt["public"]
		var b := _vis_seg_button(String(opt["kind"]), String(opt["label"]), opt["accent"])
		b.pressed.connect(func() -> void:
			_cpublic = is_pub
			_refresh_create_selection())
		_create_modal.add_child(b)
		_cvis_btns.append({"btn": b, "public": is_pub})

	_cmsg = Label.new()
	_cmsg.add_theme_font_size_override("font_size", 15)
	_cmsg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_cmsg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cmsg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_modal.add_child(_cmsg)

	var cancel := _sculpt_button("Cancel", Color(0.62, 0.42, 0.42))
	cancel.add_theme_font_size_override("font_size", 22)
	cancel.add_theme_color_override("font_color", Color(0.94, 0.82, 0.80))
	cancel.name = "cancel"
	cancel.pressed.connect(_close_create_modal)
	_create_modal.add_child(cancel)

	var create := _sculpt_button("Create  ▶", ArenaUI.ACCENT, true)
	create.add_theme_font_size_override("font_size", 23)
	create.add_theme_color_override("font_color", Color(1.0, 0.98, 0.90))
	create.name = "create"
	create.pressed.connect(_do_create)
	_create_modal.add_child(create)

	_layout_create_modal(get_viewport_rect().size)

# A blur-+-darken material for the create-popup scrim: box-blurs the captured screen
# behind it and mixes in a deep navy wash. The wash alpha (0.75) is the old 0.6 scrim
# raised by 25%, so the arena reads as clearly pushed back behind the popup.
func _make_scrim_blur_material() -> ShaderMaterial:
	# A 3x3 (9-tap) box blur with a wider step gives essentially the same soft
	# backdrop as a dense 5x5 kernel at roughly a third of the per-pixel texture
	# reads — this is a full-screen pass, so the tap count is the main cost on
	# phones. filter_linear lets each tap average four texels, widening the reach.
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 3.6;
uniform vec4 tint : source_color = vec4(0.02, 0.02, 0.05, 0.75);
void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur;
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			float wgt = 1.0 - 0.16 * float(abs(x) + abs(y));
			col += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * ps).rgb * wgt;
			total += wgt;
		}
	}
	col /= total;
	col = mix(col, tint.rgb, tint.a);
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

# A bright, legible gold section caption used inside the create modal. Brighter and
# a touch larger than the old muted label (which read as dim brown on the panel), with
# a soft dark shadow so the question stands clearly off the tablet.
func _caption(text: String, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.18))
	l.add_theme_color_override("font_shadow_color", Color(0.03, 0.02, 0.01, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A compact segmented-toggle button, sculpted in 3D (see _sculpt_button). Unselected
# reads as a dark bevelled tablet with a faint accent rim; selected lifts into a glossy
# accent-coloured cap. _set_seg_selected flips the look via the art's `selected` meta.
func _seg_button(text: String, accent: Color) -> Button:
	var b := _sculpt_button(text, accent)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", accent.lightened(0.3))
	return b

# A segmented toggle carrying a custom-drawn icon (globe / lock) beside its label,
# centred as one unit. The native button text is left blank; the icon + label live
# in a centred overlay row and are recoloured together by _set_seg_selected (which
# reads the "vis_icon"/"vis_label" metas).
func _vis_seg_button(kind: String, text: String, accent: Color) -> Button:
	var b := _sculpt_button("", accent)
	var tint := accent.lightened(0.3)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -4.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)

	var icon := ArenaIcon.new()
	icon.kind = kind
	icon.col = tint
	icon.custom_minimum_size = Vector2(23, 23)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", tint)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	b.set_meta("vis_icon", icon)
	b.set_meta("vis_label", lbl)
	return b

func _set_seg_selected(b: Button, on: bool) -> void:
	var accent: Color = b.get_meta("accent")
	var art: Control = b.get_meta("art")
	art.set_meta("selected", on)
	art.queue_redraw()
	var col := Color(1.0, 1.0, 0.98) if on else accent.lightened(0.3)
	b.add_theme_color_override("font_color", col)
	# Icon/label toggles carry their text in a centred overlay row, not the native
	# label — recolour those directly (the lock tints; the globe keeps its own hues).
	if b.has_meta("vis_label"):
		(b.get_meta("vis_label") as Label).add_theme_color_override("font_color", col)
		var icon: ArenaIcon = b.get_meta("vis_icon")
		icon.col = col
		icon.queue_redraw()

func _refresh_create_selection() -> void:
	for d in _cdiff_btns:
		_set_seg_selected(d["btn"], String(d["diff"]) == _cdiff)
	for d in _cvis_btns:
		_set_seg_selected(d["btn"], bool(d["public"]) == _cpublic)

# ================= sculpted 3D buttons + premium panel =================
# The create modal's controls are sculpted per-vertex (bevel, gradient, rim light,
# convex sheen, contact shadow) rather than flat styleboxes, matching the wizard's
# AAA look. Each Button keeps its native label (so emoji still render) but paints its
# body through a child "art" Control drawn *behind* the text (show_behind_parent).

# Build a Button whose 3D bevelled body is painted by a child art Control behind the
# native label. `primary` gives it the always-lit glossy gold cap (the Create CTA);
# toggles start unselected and light up via _set_seg_selected. The art is stashed in
# meta "art" and the accent in meta "accent".
func _sculpt_button(text: String, accent: Color, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.85))
	b.add_theme_constant_override("outline_size", 3)
	b.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.01, 0.5))
	b.add_theme_constant_override("shadow_offset_y", 2)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)

	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = false
	art.show_behind_parent = true       # paint the body behind the native label
	art.set_meta("accent", accent)
	art.set_meta("selected", primary)   # primary reads as permanently lit
	art.set_meta("primary", primary)
	art.set_meta("pressed", false)
	art.draw.connect(_draw_sculpt_btn.bind(art))
	art.resized.connect(art.queue_redraw)
	b.add_child(art)

	b.set_meta("art", art)
	b.set_meta("accent", accent)
	# Held → the face darkens + the bloom dims (the label stays put, so no vertical sink).
	b.button_down.connect(func() -> void:
		art.set_meta("pressed", true); art.queue_redraw())
	b.button_up.connect(func() -> void:
		art.set_meta("pressed", false); art.queue_redraw())
	return b

func _draw_sculpt_btn(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var accent: Color = c.get_meta("accent", Color.WHITE)
	var lit: bool = bool(c.get_meta("selected", false))
	var pressed: bool = bool(c.get_meta("pressed", false))
	var R: float = minf(h * 0.5, 26.0)

	# ---- soft contact shadow anchoring the button to the panel ----
	for i in range(5):
		var t := float(i) / 5.0
		var sw: float = w - 20.0 + t * 24.0
		var sy: float = h - 6.0 + t * 5.0
		var srect := Rect2((w - sw) * 0.5, sy, sw, 11.0)
		var sa: float = 0.24 * (1.0 - t)
		c.draw_colored_polygon(_rr_points(srect, 6.0), Color(0.0, 0.0, 0.02, sa))

	var body := Rect2(1.0, 1.0, w - 2.0, h - 5.0)
	var body_pts := _rr_points(body, R)

	# ---- lit: a tight accent bloom hugging the body ----
	if lit:
		for i in range(5):
			var g: float = 1.0 + i * 2.2
			var bpts := _rr_points(body.grow(g), R + g)
			bpts.append(bpts[0])
			c.draw_polyline(bpts, Color(accent.r, accent.g, accent.b,
				(0.10 if pressed else 0.17) * (1.0 - float(i) / 5.0)), 3.0, true)

	# ---- bevelled body: a vertical gradient reads as a lit convex cap ----
	var top_col: Color
	var bot_col: Color
	if lit:
		top_col = accent.lightened(0.42)
		bot_col = accent.darkened(0.34)
	else:
		top_col = Color(0.15, 0.16, 0.26).lerp(accent, 0.16)
		bot_col = Color(0.05, 0.05, 0.11).lerp(accent, 0.08)
	if pressed:
		top_col = top_col.darkened(0.12)
		bot_col = bot_col.darkened(0.12)
	_fill_grad_v(c, body_pts, body.position.y, body.position.y + body.size.y, top_col, bot_col)

	# ---- rim: a bright bevel edge tracing the body ----
	var rim: Color = accent.lightened(0.5) if lit else accent.lightened(0.15)
	var rim_pts := _rr_points(body, R)
	rim_pts.append(rim_pts[0])
	c.draw_polyline(rim_pts, Color(rim.r, rim.g, rim.b, 0.6 if lit else 0.32), 2.0, true)

	# ---- specular highlight riding the top edge + a darker shade line along the base ----
	c.draw_line(Vector2(R * 0.8, body.position.y + 2.6), Vector2(w - R * 0.8, body.position.y + 2.6),
		Color(1.0, 1.0, 1.0, 0.5 if lit else 0.20), 1.6, true)
	c.draw_line(Vector2(R, body.position.y + body.size.y - 2.2),
		Vector2(w - R, body.position.y + body.size.y - 2.2), Color(0.0, 0.0, 0.02, 0.36), 1.6, true)

	# ---- convex sheen pooled in the upper third so the surface bulges gently ----
	var sheen_ctr := Vector2(w * 0.5, body.position.y + body.size.y * 0.32)
	c.draw_set_transform(sheen_ctr, 0.0, Vector2(1.0, 0.5))
	for i in range(5):
		var t := float(i) / 5.0
		c.draw_circle(Vector2.ZERO, lerpf(body.size.y * 0.14, body.size.x * 0.42, t),
			Color(1.0, 1.0, 1.0, (0.11 if lit else 0.05) * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- premium modal panel: a dark bevelled tablet inside a double gold frame ----

# A more premium modal shell than the plain stone_panel: a deep gradient body, a crisp
# double gold rim, a top interior sheen, a header rule + gem under the title, and small
# forged corner rivets. Body fill + drop shadow come from the Panel stylebox; the framing
# ornaments are painted by a child art Control (added first, so it sits under the content).
func _make_premium_panel(accent: Color) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.clip_contents = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.08, 0.12, 0.98)
	s.set_corner_radius_all(26)
	s.corner_detail = 8
	s.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	s.set_border_width_all(2)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.38)
	s.shadow_size = 26
	p.add_theme_stylebox_override("panel", s)

	var art := Control.new()
	art.name = "ornaments"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = false
	art.set_meta("accent", accent)
	art.draw.connect(_draw_modal_ornaments.bind(art))
	art.resized.connect(art.queue_redraw)
	p.add_child(art)
	return p

func _draw_modal_ornaments(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 4.0 or h <= 4.0:
		return
	var accent: Color = c.get_meta("accent", ArenaUI.ACCENT)
	var R := 26.0

	# ---- top interior sheen: a soft reflected-light gradient down from the top edge ----
	for i in range(10):
		var t := float(i) / 10.0
		var yy := 6.0 + t * (h * 0.30)
		var a := 0.06 * (1.0 - t)
		c.draw_line(Vector2(18.0, yy), Vector2(w - 18.0, yy), Color(0.55, 0.62, 0.95, a), 2.0, true)

	# ---- crisp inner gold hairline just inside the border (the "double frame" read) ----
	var inner := Rect2(6.0, 6.0, w - 12.0, h - 12.0)
	var inner_pts := _rr_points(inner, R - 6.0)
	inner_pts.append(inner_pts[0])
	c.draw_polyline(inner_pts, Color(accent.r, accent.g, accent.b, 0.42), 1.4, true)
	# a brighter specular skimming the top inner edge
	c.draw_line(Vector2(R * 0.8, 8.0), Vector2(w - R * 0.8, 8.0), Color(1.0, 0.96, 0.80, 0.32), 1.4, true)

	# ---- header rule + centre gem under the title (a small heraldic divider) ----
	var hy := 60.0
	var gold := Color(1.0, 0.82, 0.36)
	var gold_hi := Color(1.0, 0.95, 0.72)
	var half := minf(w * 0.30, 150.0)
	for dir: float in [-1.0, 1.0]:
		var steps := 20
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var x0 := w * 0.5 + dir * (12.0 + t0 * half)
			var x1 := w * 0.5 + dir * (12.0 + t1 * half)
			c.draw_line(Vector2(x0, hy), Vector2(x1, hy),
				Color(gold.r, gold.g, gold.b, (1.0 - t0) * 0.7), 2.0, true)
	c.draw_circle(Vector2(w * 0.5, hy), 8.0, Color(gold.r, gold.g, gold.b, 0.12))
	var gr := 4.5
	var gpts := PackedVector2Array([
		Vector2(w * 0.5, hy - gr), Vector2(w * 0.5 + gr, hy),
		Vector2(w * 0.5, hy + gr), Vector2(w * 0.5 - gr, hy)])
	c.draw_colored_polygon(gpts, gold)
	c.draw_polyline(PackedVector2Array([gpts[0], gpts[1], gpts[2], gpts[3], gpts[0]]), gold_hi, 1.0, true)
	c.draw_circle(Vector2(w * 0.5 - 1.0, hy - 1.2), 1.0, Color(1, 1, 1, 0.85))

	# ---- small forged rivets in the four corners ----
	var m := 18.0
	for corner in [Vector2(m, m), Vector2(w - m, m), Vector2(m, h - m), Vector2(w - m, h - m)]:
		c.draw_circle(corner, 3.2, Color(0.28, 0.17, 0.03))
		c.draw_circle(corner, 2.1, Color(gold.r, gold.g, gold.b, 0.9))
		c.draw_circle(corner - Vector2(0.5, 0.7), 0.8, Color(1.0, 0.99, 0.86, 0.9))

# Trace a clockwise rounded-rectangle perimeter (used for gradient fills + outlines).
func _rr_points(rect: Rect2, r: float, seg := 6) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],            # top-right
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],    # bottom-right
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],             # bottom-left
		[rect.position + Vector2(r, r), PI],                                 # top-left
	]
	for cn in corners:
		var ctr: Vector2 = cn[0]
		var a0: float = cn[1]
		for i in seg + 1:
			var a: float = a0 + (float(i) / seg) * (PI * 0.5)
			pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	return pts

# Fill a polygon with a smooth vertical (top→bottom) gradient via per-vertex colours.
func _fill_grad_v(c: Control, pts: PackedVector2Array, y0: float, y1: float, top: Color, bot: Color) -> void:
	var cols := PackedColorArray()
	var span: float = maxf(y1 - y0, 0.001)
	for p in pts:
		cols.append(top.lerp(bot, clampf((p.y - y0) / span, 0.0, 1.0)))
	c.draw_polygon(pts, cols)

func _layout_create_modal(sz: Vector2) -> void:
	if _create_modal == null:
		return
	var w := CREATE_MODAL_W
	var h := CREATE_MODAL_H
	_create_modal.size = Vector2(w, h)
	_create_modal_base_y = sz.y * 0.5 - h * 0.5
	_create_modal.position = Vector2(sz.x * 0.5 - w * 0.5, _create_modal_base_y - _create_modal_shift)
	if _scrim:
		_scrim.position = Vector2.ZERO
		_scrim.size = sz

	var pad := 30.0
	var inner := w - pad * 2.0
	# name field + dice on one row
	var dice_w := 54.0
	var gap := 10.0
	var name_y := 66.0
	_cname_edit.position = Vector2(pad, name_y)
	_cname_edit.size = Vector2(inner - dice_w - gap, 50.0)
	var dice: Button = _create_modal.get_node("dice")
	dice.position = Vector2(pad + inner - dice_w, name_y)
	dice.size = Vector2(dice_w, 50.0)

	# difficulty
	var dcap: Label = _create_modal.get_node("diff_cap")
	dcap.position = Vector2(0, 130); dcap.size = Vector2(w, 22)
	var dy := 158.0
	var dseg_w := (inner - gap * 2.0) / 3.0
	var dx := pad
	for d in _cdiff_btns:
		var b: Button = d["btn"]
		b.position = Vector2(dx, dy); b.size = Vector2(dseg_w, 48.0)
		dx += dseg_w + gap

	# visibility
	var vcap: Label = _create_modal.get_node("vis_cap")
	vcap.position = Vector2(0, 220); vcap.size = Vector2(w, 22)
	var vy := 248.0
	var vseg_w := (inner - gap) / 2.0
	var vx := pad
	for d in _cvis_btns:
		var b: Button = d["btn"]
		b.position = Vector2(vx, vy); b.size = Vector2(vseg_w, 50.0)
		vx += vseg_w + gap

	_cmsg.position = Vector2(0, 312); _cmsg.size = Vector2(w, 22)

	var btn_y := 344.0
	var btn_w := (inner - gap) / 2.0
	var cancel: Button = _create_modal.get_node("cancel")
	cancel.position = Vector2(pad, btn_y); cancel.size = Vector2(btn_w, 56.0)
	var create: Button = _create_modal.get_node("create")
	create.position = Vector2(pad + btn_w + gap, btn_y); create.size = Vector2(btn_w, 56.0)

func _do_create() -> void:
	if _busy:
		return
	_busy = true
	# Blank name? Give it a funny one (and show it) rather than a bland default.
	if _cname_edit.text.strip_edges().is_empty():
		_cname_edit.text = ContestManager.random_title()
	_cmsg.add_theme_color_override("font_color", ArenaUI.MUTED)
	_cmsg.text = "Creating…"
	var res: Dictionary = await ContestManager.create_contest(_cdiff, _cname_edit.text, _cpublic)
	_busy = false
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_close_create_modal()
		game_manager.show_contest_detail(String(res.get("id", "")))
		return
	_cmsg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	match String(res.get("error", "")):
		"auth":         _cmsg.text = "Sign in and pick a name first."
		"in_room":      _cmsg.text = "You already have a room open."
		"id_collision": _cmsg.text = "Couldn't allocate an ID. Try again."
		# One line: _cmsg is a fixed 22px row with no autowrap.
		"lobby_full":   _cmsg.text = "Public lobby is full (%d rooms) — try again shortly." % ContestManager.LOBBY_MAX
		_:              _cmsg.text = "Couldn't create the room. Try again."

# Both create and join need a signed-in player with a chosen name.
func _require_account() -> bool:
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		return true
	_show_toast("Sign in and pick a name to play the Arena.")
	return false

# Reveal the room-ID field + Join button below the Private option and grow the
# modal to fit; a second tap collapses it again.
func _toggle_private() -> void:
	if _private_expanded:
		_collapse_private()
		return
	_private_expanded = true
	_id_edit.text = ""
	_id_msg.text = ""
	_id_edit.visible = true
	_id_join_btn.visible = true
	_id_msg.visible = true
	_layout_choice_modal(get_viewport_rect().size)
	_id_edit.grab_focus()

func _collapse_private() -> void:
	_private_expanded = false
	if _id_edit:
		_id_edit.visible = false
		_id_edit.release_focus()
	if _id_join_btn:
		_id_join_btn.visible = false
	if _id_msg:
		_id_msg.visible = false
	_layout_choice_modal(get_viewport_rect().size)

func _do_join() -> void:
	if _busy:
		return
	var code := _id_edit.text.strip_edges().to_upper()
	if code.length() != ContestManager.ID_LEN:
		_id_msg.text = "Enter the %d-character room ID." % ContestManager.ID_LEN
		return
	_busy = true
	_id_msg.text = "Joining…"
	var res: Dictionary = await ContestManager.join_contest(code)
	_busy = false
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_choice_modal.visible = false
		_collapse_private()
		game_manager.show_contest_detail(code)
		return
	match String(res.get("error", "")):
		"not_found": _id_msg.text = "No room found with that ID."
		"ended":     _id_msg.text = "That room has already started."
		"closed":    _id_msg.text = "That room has closed."
		"full":      _id_msg.text = "That room is full."
		"in_room":   _id_msg.text = "Leave your current room first."
		"auth":      _id_msg.text = "Sign in and pick a name first."
		_:           _id_msg.text = "Couldn't join. Try again."

# ---------------- toast ----------------

func _build_toast() -> void:
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)

func _show_toast(msg: String) -> void:
	# Keep the toast above any open popup (the lobby modal is added later).
	move_child(_toast, get_child_count() - 1)
	_toast.text = msg
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

# ---------------- join-choice modal ----------------

func _build_choice_modal() -> void:
	# Premium shell + 3D sculpted buttons, matching the Create-contest popup.
	_choice_modal = _make_premium_panel(ArenaUI.SAND)
	_choice_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_modal.visible = false
	add_child(_choice_modal)

	var title := Label.new()
	title.name = "title"
	title.text = "Join Contest"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 18)
	title.size = Vector2(CHOICE_MODAL_W, 34)
	_choice_modal.add_child(title)

	var private_btn := _make_choice_button("lock", "Private")
	private_btn.name = "private"
	private_btn.pressed.connect(_toggle_private)
	_choice_modal.add_child(private_btn)

	# Room-ID field + Join button — hidden until Private is picked, then revealed
	# inline directly below the Private option.
	_id_edit = LineEdit.new()
	_id_edit.name = "id_edit"
	_id_edit.visible = false
	_id_edit.placeholder_text = "ROOM ID"
	_id_edit.max_length = ContestManager.ID_LEN
	_id_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_id_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_id_edit.add_theme_font_size_override("font_size", 26)
	# Room codes are 6 digits — strip anything that isn't a number as it's typed.
	_id_edit.text_changed.connect(func(t: String) -> void:
		var digits := ""
		for c in t:
			if c >= "0" and c <= "9":
				digits += c
		if digits != t:
			_id_edit.text = digits
			_id_edit.caret_column = digits.length())
	_id_edit.text_submitted.connect(func(_t: String) -> void: _do_join())
	_choice_modal.add_child(_id_edit)

	_id_join_btn = _sculpt_button("Join", Color(0.30, 0.80, 0.52), true)
	_id_join_btn.name = "id_join"
	_id_join_btn.visible = false
	_id_join_btn.add_theme_font_size_override("font_size", 20)
	_id_join_btn.add_theme_color_override("font_color", Color.WHITE)
	_id_join_btn.pressed.connect(_do_join)
	_choice_modal.add_child(_id_join_btn)

	_id_msg = Label.new()
	_id_msg.name = "id_msg"
	_id_msg.visible = false
	_id_msg.add_theme_font_size_override("font_size", 15)
	_id_msg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_id_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_id_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_modal.add_child(_id_msg)

	var public_btn := _make_choice_button("globe", "Public")
	public_btn.name = "public"
	public_btn.pressed.connect(func() -> void:
		_choice_modal.visible = false
		_collapse_private()
		_open_lobby_modal())
	_choice_modal.add_child(public_btn)

	var cancel := _sculpt_button("Cancel", Color(0.62, 0.42, 0.42))
	cancel.name = "cancel"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.add_theme_color_override("font_color", Color(0.94, 0.82, 0.80))
	cancel.pressed.connect(func() -> void:
		_choice_modal.visible = false
		_collapse_private())
	_choice_modal.add_child(cancel)
	_layout_choice_modal(get_viewport_rect().size)

# A join-choice option: a sculpted button carrying an icon pinned to a fixed left
# column and a single bold, premium gold headline. Both options share the same
# icon/text columns so the two rows read as a tidy aligned list.
func _make_choice_button(kind: String, title_text: String) -> Button:
	var b := _sculpt_button("", ArenaUI.ACCENT, true)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26.0
	row.offset_right = -16.0
	row.offset_bottom = -5.0   # sit on the button's body, clear of its base shadow
	row.add_theme_constant_override("separation", 15)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)

	var icon := ArenaIcon.new()
	icon.kind = kind
	icon.col = Color(1.0, 0.88, 0.62)   # warm gold, matching the headline
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var t := Label.new()
	t.text = title_text
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.add_theme_font_size_override("font_size", 24)
	# Premium: warm gold headline with a crisp dark outline and a soft drop shadow.
	t.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.18))
	t.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01, 0.92))
	t.add_theme_constant_override("outline_size", 4)
	t.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)
	return b

const CHOICE_MODAL_W := 400.0
const CHOICE_MODAL_H := 302.0            # collapsed (Private / Public / Cancel)
const CHOICE_MODAL_H_EXPANDED := 388.0   # with the room-ID row revealed
const CHOICE_MODAL_TOP_MARGIN := 10.0    # modal top never lifts past this many px from the top

func _layout_choice_modal(sz: Vector2) -> void:
	if _choice_modal == null:
		return
	var w := CHOICE_MODAL_W
	var h := CHOICE_MODAL_H_EXPANDED if _private_expanded else CHOICE_MODAL_H
	_choice_modal.size = Vector2(w, h)
	_choice_modal_base_y = sz.y * 0.5 - h * 0.5
	_choice_modal.position = Vector2(sz.x * 0.5 - w * 0.5, _choice_modal_base_y - _choice_modal_shift)

	var pad := 30.0
	var bw := w - pad * 2.0
	var priv: Button = _choice_modal.get_node("private")
	priv.position = Vector2(pad, 74.0); priv.size = Vector2(bw, 56.0)

	# When Private is picked, the ID field + Join button occupy a row below it and
	# push the Public / Cancel options down.
	var extra := 0.0
	if _private_expanded:
		var row_y := 140.0
		var join_w := 106.0
		var gap := 10.0
		_id_edit.position = Vector2(pad, row_y)
		_id_edit.size = Vector2(bw - join_w - gap, 52.0)
		_id_join_btn.position = Vector2(pad + bw - join_w, row_y)
		_id_join_btn.size = Vector2(join_w, 52.0)
		_id_msg.position = Vector2(0, row_y + 56.0)
		_id_msg.size = Vector2(w, 20.0)
		extra = 86.0

	var pub: Button = _choice_modal.get_node("public")
	pub.position = Vector2(pad, 140.0 + extra); pub.size = Vector2(bw, 56.0)
	var cancel: Button = _choice_modal.get_node("cancel")
	cancel.position = Vector2(pad, 214.0 + extra); cancel.size = Vector2(bw, 52.0)

# ---------------- public-rooms lobby popup ----------------

# The public lobby now lives as an in-place popup on the arena hub (no screen swap):
# a premium panel over a blurred scrim listing the open public rooms, each with a
# Join button.
#
# The list is LIVE: while the popup is open we hold ContestManager's lobby-index
# listeners (watch_lobby), so rooms appear, change player count and disappear on
# their own — there is nothing to refresh by hand. At most ContestManager.LOBBY_MAX
# rooms can be open, shown LOBBY_PAGE at a time; the footer pages through them.
# A 1s tick updates the per-row countdowns and retires rows whose 5-minute start
# window ran out (expiry is a local time predicate, so it needs no server event).

# Wider than the other popups on purpose: each row packs name · diff · players ·
# countdown · Join, and the fixed right-hand columns used to squeeze the name column
# down to ~100px (even short titles clipped). The extra width all flows into the name.
const LOBBY_MODAL_W := 680.0
const LOBBY_ROW_H := 56.0
const LOBBY_JOIN_W := 88.0
const LOBBY_LEVEL_W := 74.0
const LOBBY_REG_W := 66.0
const LOBBY_TIME_W := 56.0    # "4:12" countdown column
const LOBBY_COL_GAP := 16.0   # breathing room between name · diff · players · time · join
const LOBBY_PAGE := 20        # rows per page (5 pages covers ContestManager.LOBBY_MAX)

func _open_lobby_modal() -> void:
	if _lobby_modal == null:
		_build_lobby_modal()
	_set_action_cards_visible(false)
	_lobby_scrim.visible = true
	_lobby_modal.visible = true
	if _fx:
		_fx.pause()
	_layout_lobby_modal(get_viewport_rect().size)
	_lobby_page = 0
	_lobby_rows = []
	# One read of the CF-maintained index; a local 1s tick keeps the countdowns
	# moving and retires expired rows (no further reads until the player refreshes).
	_lobby_tick.start()
	_do_lobby_refresh()

func _close_lobby_modal() -> void:
	_stop_lobby_watch()
	if _lobby_modal:
		_lobby_modal.visible = false
	if _lobby_scrim:
		_lobby_scrim.visible = false
	if _fx:
		_fx.resume()
	_set_action_cards_visible(true)

# Halt the local countdown tick when the list leaves the screen. (There are no live
# listeners now — the list is read once on open and again on each Refresh press.)
func _stop_lobby_watch() -> void:
	# No live listeners to drop anymore — the list is Refresh-driven. Just halt the
	# local countdown tick.
	if _lobby_tick:
		_lobby_tick.stop()

func _exit_tree() -> void:
	_stop_lobby_watch()

func _build_lobby_modal() -> void:
	# Blur-+-darken scrim (same material as the create popup); an outside tap dismisses.
	_lobby_scrim = ColorRect.new()
	_lobby_scrim.color = Color(1, 1, 1, 1)
	_lobby_scrim.material = _make_scrim_blur_material()
	_lobby_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_lobby_scrim.visible = false
	_lobby_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_lobby_modal())
	add_child(_lobby_scrim)

	_lobby_modal = _make_premium_panel(ArenaUI.ACCENT)
	_lobby_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_lobby_modal.visible = false
	add_child(_lobby_modal)

	var title := Label.new()
	title.name = "title"
	title.text = "Public Contests"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_modal.add_child(title)

	_lobby_scroll = ScrollContainer.new()
	_lobby_scroll.name = "scroll"
	_lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lobby_modal.add_child(_lobby_scroll)
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 8)
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_scroll.add_child(_lobby_list)

	# Loading / empty message shown over the list area.
	_lobby_status = Label.new()
	_lobby_status.name = "status"
	_lobby_status.add_theme_font_size_override("font_size", 17)
	_lobby_status.add_theme_color_override("font_color", ArenaUI.MUTED)
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_status.visible = false
	_lobby_modal.add_child(_lobby_status)

	_lobby_count = Label.new()
	_lobby_count.name = "count"
	_lobby_count.add_theme_font_size_override("font_size", 14)
	_lobby_count.add_theme_color_override("font_color", ArenaUI.MUTED)
	_lobby_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_modal.add_child(_lobby_count)

	# Pager (replaces the old Reshuffle: with a live list there is nothing to re-roll).
	_lobby_prev = _sculpt_button("‹", ArenaUI.SAND)
	_lobby_prev.name = "prev"
	_lobby_prev.add_theme_font_size_override("font_size", 24)
	_lobby_prev.add_theme_color_override("font_color", ArenaUI.SAND.lightened(0.35))
	_lobby_prev.pressed.connect(func() -> void: _lobby_turn_page(-1))
	_lobby_modal.add_child(_lobby_prev)

	_lobby_page_lbl = Label.new()
	_lobby_page_lbl.name = "page"
	_lobby_page_lbl.add_theme_font_size_override("font_size", 16)
	_lobby_page_lbl.add_theme_color_override("font_color", ArenaUI.SAND.lightened(0.35))
	_lobby_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_page_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lobby_page_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_modal.add_child(_lobby_page_lbl)

	_lobby_next = _sculpt_button("›", ArenaUI.SAND)
	_lobby_next.name = "next"
	_lobby_next.add_theme_font_size_override("font_size", 24)
	_lobby_next.add_theme_color_override("font_color", ArenaUI.SAND.lightened(0.35))
	_lobby_next.pressed.connect(func() -> void: _lobby_turn_page(1))
	_lobby_modal.add_child(_lobby_next)

	_lobby_tick = Timer.new()
	_lobby_tick.wait_time = 1.0
	_lobby_tick.timeout.connect(_on_lobby_tick)
	add_child(_lobby_tick)

	_lobby_refresh = _sculpt_button("⟳  Refresh", ArenaUI.ACCENT, true)
	_lobby_refresh.name = "refresh"
	_lobby_refresh.add_theme_font_size_override("font_size", 18)
	_lobby_refresh.add_theme_color_override("font_color", Color(1.0, 0.98, 0.90))
	_lobby_refresh.pressed.connect(_do_lobby_refresh)
	_lobby_modal.add_child(_lobby_refresh)

	var close := _sculpt_button("Close", Color(0.62, 0.42, 0.42))
	close.name = "close"
	close.add_theme_font_size_override("font_size", 19)
	close.add_theme_color_override("font_color", Color(0.94, 0.82, 0.80))
	close.pressed.connect(_close_lobby_modal)
	_lobby_modal.add_child(close)

	_layout_lobby_modal(get_viewport_rect().size)

func _layout_lobby_modal(sz: Vector2) -> void:
	if _lobby_modal == null:
		return
	if _lobby_scrim:
		_lobby_scrim.position = Vector2.ZERO
		_lobby_scrim.size = sz
	var w := minf(LOBBY_MODAL_W, sz.x - 32.0)
	var h := minf(600.0, sz.y - 60.0)
	_lobby_modal.size = Vector2(w, h)
	_lobby_modal.position = Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5 - h * 0.5)

	var pad := 24.0
	var inner := w - pad * 2.0
	_lobby_modal.get_node("title").set("position", Vector2(0, 18))
	_lobby_modal.get_node("title").set("size", Vector2(w, 34))

	var list_top := 64.0
	var btn_h := 50.0
	var bottom_reserve := btn_h + 24.0 + 22.0   # buttons + count line + margins
	var list_h := h - list_top - bottom_reserve
	if _lobby_scroll:
		_lobby_scroll.position = Vector2(pad, list_top)
		_lobby_scroll.size = Vector2(inner, maxf(list_h, 100.0))
		_lobby_list.custom_minimum_size = Vector2(inner, 0)
	if _lobby_status:
		_lobby_status.position = Vector2(pad, list_top)
		_lobby_status.size = Vector2(inner, maxf(list_h, 100.0))

	var by := h - btn_h - 18.0
	if _lobby_count:
		_lobby_count.position = Vector2(0, by - 22.0)
		_lobby_count.size = Vector2(w, 20)
	var gap := 14.0
	var bw := (inner - gap) * 0.5
	# Left half: ‹ page x/y ›. Right half: Close.
	var arrow_w := 46.0
	if _lobby_prev:
		_lobby_prev.position = Vector2(pad, by)
		_lobby_prev.size = Vector2(arrow_w, btn_h)
	if _lobby_next:
		_lobby_next.position = Vector2(pad + bw - arrow_w, by)
		_lobby_next.size = Vector2(arrow_w, btn_h)
	if _lobby_page_lbl:
		_lobby_page_lbl.position = Vector2(pad + arrow_w, by)
		_lobby_page_lbl.size = Vector2(maxf(bw - arrow_w * 2.0, 10.0), btn_h)
	if _lobby_modal.has_node("close"):
		# Right half splits into Refresh + Close.
		var rhalf_x := pad + bw + gap
		var rgap := 10.0
		var rw := (bw - rgap) * 0.5
		if _lobby_refresh:
			_lobby_refresh.position = Vector2(rhalf_x, by)
			_lobby_refresh.size = Vector2(rw, btn_h)
		var close: Button = _lobby_modal.get_node("close")
		close.position = Vector2(rhalf_x + rw + rgap, by)
		close.size = Vector2(rw, btn_h)
	# Reflow rows so columns line up at the new width.
	if _lobby_list and not _lobby_list.get_children().is_empty():
		_lobby_render()

# Load the open-public-room list with ONE read of the CF-maintained index doc
# (lobby_index/open). Called on open and on every Refresh press — there are no live
# listeners, so the list is only as fresh as the last press. That's the deliberate
# trade-off that kills the per-room-event fan-out to every browser.
func _do_lobby_refresh() -> void:
	if _lobby_busy:
		return
	_lobby_busy = true
	if _lobby_refresh:
		_lobby_refresh.disabled = true
	for c in _lobby_list.get_children():
		c.queue_free()
	_lobby_status.text = "Finding contests…"
	_lobby_status.visible = true
	var rows: Array = await ContestManager.refresh_lobby()
	if not is_inside_tree() or _lobby_modal == null or not _lobby_modal.visible:
		_lobby_busy = false
		return
	_lobby_busy = false
	if _lobby_refresh:
		_lobby_refresh.disabled = false
	_lobby_rows = rows
	_lobby_render()

# Once a second, purely LOCALLY (no reads): move the countdowns and retire rows whose
# start window has closed — expiry is a time predicate, so it needs no server event.
func _on_lobby_tick() -> void:
	if _lobby_modal == null or not _lobby_modal.visible or _lobby_busy:
		return
	var now := int(Time.get_unix_time_from_system())
	var before := _lobby_rows.size()
	_lobby_rows = _lobby_rows.filter(func(r): return int(r.get("deadline", 0)) > now)
	if _lobby_rows.size() != before:
		_lobby_render()
		return
	# Same row set — just move the clocks, no rebuild.
	for child in _lobby_list.get_children():
		var lbl: Variant = child.get_node_or_null("time")
		if lbl is Label:
			var left := int(child.get_meta("deadline", 0)) - now
			(lbl as Label).text = _fmt_left(left)
			(lbl as Label).add_theme_color_override("font_color", _time_color(left))

func _lobby_turn_page(step: int) -> void:
	var pages := _lobby_page_count()
	_lobby_page = clampi(_lobby_page + step, 0, pages - 1)
	_lobby_render()

func _lobby_page_count() -> int:
	return maxi(1, int(ceil(float(_lobby_rows.size()) / float(LOBBY_PAGE))))

func _lobby_render() -> void:
	for c in _lobby_list.get_children():
		c.queue_free()
	var has := not _lobby_rows.is_empty()
	_lobby_status.visible = not has
	var pages := _lobby_page_count()
	# A live list can shrink under the viewer — never strand them past the end.
	_lobby_page = clampi(_lobby_page, 0, pages - 1)
	if _lobby_prev:
		_lobby_prev.disabled = _lobby_page <= 0
	if _lobby_next:
		_lobby_next.disabled = _lobby_page >= pages - 1
	if _lobby_page_lbl:
		_lobby_page_lbl.text = "Page %d / %d" % [_lobby_page + 1, pages]
	if not has:
		_lobby_status.text = "No public contests open right now.\nTap ⟳ Refresh, or create your own!"
		_lobby_count.text = ""
		return
	var first := _lobby_page * LOBBY_PAGE
	var page_rows: Array = _lobby_rows.slice(first, first + LOBBY_PAGE)
	_lobby_count.text = "%d open %s · showing %d–%d" % [
		_lobby_rows.size(), "room" if _lobby_rows.size() == 1 else "rooms",
		first + 1, first + page_rows.size()]
	var w := _lobby_scroll.size.x if _lobby_scroll.size.x > 4.0 else (LOBBY_MODAL_W - 48.0)
	for row: Dictionary in page_rows:
		_lobby_list.add_child(_make_lobby_row(row, w))

# "4:12" / "0:07" — time left for the host to start, floored at zero.
func _fmt_left(secs: int) -> String:
	var s: int = maxi(secs, 0)
	return "%d:%02d" % [s / 60, s % 60]

func _time_color(secs: int) -> Color:
	if secs <= 15:
		return Color(0.97, 0.45, 0.52)      # about to close
	if secs <= 60:
		return Color(1.00, 0.75, 0.35)
	return Color(0.72, 0.80, 0.98)

func _make_lobby_row(c: Dictionary, row_w: float) -> Control:
	var mine: bool = bool(c.get("is_creator", false))
	var count := int(c.get("member_count", 1))
	var is_full := count >= ContestManager.MAX_MEMBERS

	var join_x := row_w - LOBBY_JOIN_W - 12.0
	var time_x := join_x - LOBBY_COL_GAP - LOBBY_TIME_W
	var reg_x := time_x - LOBBY_COL_GAP - LOBBY_REG_W
	var level_x := reg_x - LOBBY_COL_GAP - LOBBY_LEVEL_W
	var title_w := maxf(50.0, level_x - 14.0 - LOBBY_COL_GAP)

	var row := Panel.new()
	row.custom_minimum_size = Vector2(row_w, LOBBY_ROW_H)
	# The tick handler updates the clock in place off this.
	row.set_meta("deadline", int(c.get("deadline", 0)))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.5) if mine else Color(0.06, 0.08, 0.18, 0.55)
	s.set_corner_radius_all(12)
	var rim := ArenaUI.GOLD if mine else Color(0.42, 0.47, 0.75)
	s.border_color = Color(rim.r, rim.g, rim.b, 0.7 if mine else 0.20)
	s.set_border_width_all(2 if mine else 1)
	row.add_theme_stylebox_override("panel", s)

	var nm := Label.new()
	nm.text = ArenaUI.clamp_title(String(c.get("title", "Contest")))
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.3) if mine else Color(0.90, 0.93, 1.0))
	nm.position = Vector2(14.0, 0); nm.size = Vector2(title_w, LOBBY_ROW_H)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	_lobby_cell(row, ContestManager.diff_label(String(c.get("difficulty", "easy"))), level_x, LOBBY_LEVEL_W,
		_lobby_diff_color(String(c.get("difficulty", "easy"))), 15)
	_lobby_cell(row, "%d/%d" % [count, ContestManager.MAX_MEMBERS], reg_x, LOBBY_REG_W,
		Color(0.72, 0.80, 0.98), 15)
	# How long the host still has to press Start (see ContestManager.START_WINDOW).
	var left := int(c.get("deadline", 0)) - int(Time.get_unix_time_from_system())
	var time_lbl := _lobby_cell(row, _fmt_left(left), time_x, LOBBY_TIME_W,
		_time_color(left), 15)
	time_lbl.name = "time"

	var btn: Button
	if mine:
		btn = ArenaUI.pill_button("View", ArenaUI.SAND)
	elif is_full:
		btn = ArenaUI.pill_button("Full", Color(0.5, 0.5, 0.55))
		btn.disabled = true
	else:
		btn = ArenaUI.pill_button("Join", Color(0.30, 0.80, 0.52), true)
	btn.add_theme_font_size_override("font_size", 16)
	btn.size = Vector2(LOBBY_JOIN_W, 40)
	btn.position = Vector2(join_x, (LOBBY_ROW_H - 40) * 0.5)
	var cid := String(c.get("id", ""))
	if mine or not is_full:
		btn.pressed.connect(func() -> void: _on_lobby_join(cid))
	row.add_child(btn)
	return row

func _lobby_cell(row: Control, text: String, x: float, w: float, col: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.position = Vector2(x, 0); l.size = Vector2(w, LOBBY_ROW_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return l

func _lobby_diff_color(diff: String) -> Color:
	match diff:
		"easy":     return Color(0.40, 0.85, 0.55)
		"moderate": return Color(1.00, 0.75, 0.35)
		"hard":     return Color(0.97, 0.45, 0.52)
	return Color(0.82, 0.86, 1.0)

func _on_lobby_join(cid: String) -> void:
	if _lobby_busy or cid.is_empty():
		return
	_lobby_busy = true
	_lobby_status.text = "Joining…"
	_lobby_status.visible = true
	for c in _lobby_list.get_children():
		c.queue_free()
	var res: Dictionary = await ContestManager.join_contest(cid)
	if not is_inside_tree():
		return
	_lobby_busy = false
	if bool(res.get("ok", false)):
		_close_lobby_modal()
		game_manager.show_contest_detail(cid)
		return
	# Failed — re-show the list and toast the reason.
	_lobby_status.visible = false
	_lobby_render()
	match String(res.get("error", "")):
		"not_found":     _show_toast("That room just closed.")
		"ended":         _show_toast("That race has already started.")
		"closed":        _show_toast("That room just closed.")
		"full":          _show_toast("That room is full.")
		"in_room":       _show_toast("Leave your current room first.")
		"auth":          _show_toast("Sign in and pick a name first.")
		_:               _show_toast("Couldn't join. Try again.")
	# Drop the stale row immediately; the index listener catches up a beat later.
	var err := String(res.get("error", ""))
	if err == "not_found" or err == "full" or err == "ended" or err == "closed":
		_lobby_rows = _lobby_rows.filter(func(r): return String(r.get("id", "")) != cid)
		_lobby_render()

# Lift the join-choice modal (when its room-ID field is focused) and the create
# modal so their inputs clear the on-screen keyboard, easing back down on close.
func _process(delta: float) -> void:
	var choice_h := CHOICE_MODAL_H_EXPANDED if _private_expanded else CHOICE_MODAL_H
	_lift_modal(delta, _choice_modal, _id_edit, _choice_modal_base_y, choice_h,
		CHOICE_MODAL_TOP_MARGIN,
		func(v: float) -> void: _choice_modal_shift = v, _choice_modal_shift)
	_lift_modal(delta, _create_modal, _cname_edit, _create_modal_base_y, CREATE_MODAL_H,
		CREATE_MODAL_TOP_MARGIN,
		func(v: float) -> void: _create_modal_shift = v, _create_modal_shift)

# Ease a modal up so its focused field clears the on-screen keyboard, then back
# down when the keyboard closes. Shared by the join-choice and create popups.
func _lift_modal(delta: float, modal: Panel, edit: LineEdit, base_y: float, modal_h: float,
		top_margin: float, set_shift: Callable, cur_shift: float) -> void:
	if modal == null:
		return
	var target := 0.0
	if modal.visible:
		var kb_h := float(DisplayServer.virtual_keyboard_get_height())
		if kb_h > 0.0 and edit != null and edit.has_focus():
			var vsz := get_viewport_rect().size
			var win_h := float(get_window().size.y)
			var kb_design := kb_h * (vsz.y / maxf(win_h, 1.0))
			var keyboard_top := vsz.y - kb_design
			var modal_bottom := base_y + modal_h
			var overlap := modal_bottom - (keyboard_top - 16.0)
			var max_shift := maxf(base_y - top_margin, 0.0)
			target = clampf(overlap, 0.0, max_shift)
	var new_shift: float = lerpf(cur_shift, target, clampf(delta * 12.0, 0.0, 1.0))
	set_shift.call(new_shift)
	modal.position.y = base_y - new_shift
