extends Node

# ── Unity Ads replacement for ad_manager.gd ────────────────────────────────────
#
# Drop-in: the public surface is identical to the AdMob version, so game.gd and
# contest_detail_screen.gd need no changes. What callers use, and what is
# preserved here:
#
#   rewarded_ready / interstitial_ready / arena_interstitial_ready
#   is_showing_ad()      show_rewarded(cb)
#   try_show_interstitial()      try_show_arena_interstitial()
#   signal ad_closed(seconds_shown: float)
#
# What changed underneath: Unity has no RewardedAd / InterstitialAd classes and no
# loader objects. Every ad unit is loaded and shown by the same pair of calls, and
# "rewarded" is a property of the ad unit in the Unity dashboard, not of the code.
# The reward arrives as a COMPLETED completion state rather than a separate
# OnUserEarnedReward callback — so the earned-then-dismissed dance the AdMob
# version had to do collapses into one signal.

# ── Ad units ──────────────────────────────────────────────────────────────────
#
# Ad units are created in the Unity dashboard under Monetization → Ad Units, and
# the ad FORMAT is set there too — Rewarded for the first, Interstitial for the
# other two. Getting that wrong on the dashboard is the single most likely reason
# an ad unit never fills, and nothing in this file can detect it.
#
# (Unmediated integrations pass the ad unit ID to load/show. "Placement" is the
# mediation-side term and does not apply here.)
const REWARDED_AD_UNIT := "Rewarded_Android"
const INTERSTITIAL_AD_UNIT := "Interstitial_Android"

# The AdMob build had a dedicated arena unit so the arena's interstitial revenue
# could be read separately from the solo game-over one. The Unity dashboard has no
# equivalent unit yet, so both currently point at the same inventory — which works,
# and only costs the split in reporting.
#
# Aliasing is safe because readiness is tracked per ad unit ID (see _ready_units):
# with one shared ID there is one shared slot, so showing the arena ad correctly
# marks the game-over ad as spent too. Two flags over one ad would double-show.
#
# To restore separate reporting: create an Interstitial-format ad unit named
# Arena_Interstitial_Android on the dashboard, then change this one line.
const ARENA_INTERSTITIAL_AD_UNIT := INTERSTITIAL_AD_UNIT

# Android Game ID, Unity dashboard → Monetization → Ad Units.
const GAME_ID := "800274606"

# Banner_Android also exists on the dashboard but is unused: Simon has no banner
# surface, and an unused ad unit costs nothing. Deleting it would be fine too.

# ── Live vs test ──────────────────────────────────────────────────────────────
#
# Unity's test mode is ONE boolean handed to initialize(), not a parallel set of
# test ad unit IDs — so unlike the AdMob setup there is no way for a live ad unit
# to leak into a development build by being pasted into the wrong constant.
# Developer impressions on live inventory are what got the AdMob account disabled;
# this is the whole defence and it is one flag, evaluated in one place.
#
# `release` is absent from editor runs and debug exports; the editor check is
# belt-and-braces for a custom template that reports both.
static func _live_ads() -> bool:
	return OS.has_feature("release") and not OS.has_feature("editor")


# ── Full-screen ad frequency cap ───────────────────────────────────────────────
# One cooldown shared by BOTH interstitial ad units (game over, arena results /
# exit), so a player bouncing in and out of a results screen can't be served
# back-to-back full-screen ads. Rewarded ads are deliberately exempt: the player
# asks for those by name and gets something for them.
const MIN_SECONDS_BETWEEN_INTERSTITIALS := 120.0

# Unity reports load failures for ordinary reasons (no fill right now, network
# blip). The AdMob version dropped these on the floor and the slot stayed empty
# until the next natural reload; retrying on a slow timer costs nothing and keeps
# inventory available.
const RELOAD_DELAY_AFTER_FAILURE := 30.0

var _last_interstitial_at := -1.0e9

# Readiness is keyed by ad unit ID, not by role, so that two roles sharing one ad
# unit share one slot. Read-only to callers; _set_ready is the only writer.
var _ready_units: Dictionary = {}

var rewarded_ready: bool:
	get: return _ready_units.get(REWARDED_AD_UNIT, false)

var interstitial_ready: bool:
	get: return _ready_units.get(INTERSTITIAL_AD_UNIT, false)

var arena_interstitial_ready: bool:
	get: return _ready_units.get(ARENA_INTERSTITIAL_AD_UNIT, false)

var _pending_reward: Callable = Callable()

# ── "an ad is on screen" state ────────────────────────────────────────────────
# A full-screen ad backgrounds the app, but it does NOT stop the world: real time
# keeps passing, so a wall-clock deadline the game is holding gets silently charged
# for the ad the player was made to watch.
#
# So the ad's on-screen span is published here and callers credit it back —
# see game.gd's per-press window. `ad_closed` carries how long the ad was actually
# up (0 if it never showed), which is exactly what a deadline needs in order to be
# pushed forward by the lost time.
#
# Note this is for deadlines that are PRIVATE to this device. The arena's straggler
# grace deliberately does NOT compensate: it's a property of the room, shared by
# every client, and stretching it here would only make this device disagree with
# the others about when the race ends.
signal ad_closed(seconds_shown: float)

var _showing := false
var _shown_at := 0.0
var _showing_ad_unit := ""

var _plugin: Object = null
var _ads_started := false


# True while a full-screen ad (rewarded or either interstitial) covers the game.
func is_showing_ad() -> bool:
	return _showing


func _mark_shown(ad_unit: String) -> void:
	_showing = true
	_showing_ad_unit = ad_unit
	_shown_at = Time.get_ticks_msec() / 1000.0


# Close out the on-screen span and tell everyone how long it lasted. Safe to call
# for an ad that never appeared (failed to show): the span is 0 and listeners
# compensate for nothing.
func _mark_closed() -> void:
	_showing_ad_unit = ""
	if not _showing:
		ad_closed.emit(0.0)
		return
	_showing = false
	ad_closed.emit(Time.get_ticks_msec() / 1000.0 - _shown_at)


# ── Start-up: consent, then the SDK, then ads ─────────────────────────────────

func _ready() -> void:
	if not Engine.has_singleton("GodotUnityAds"):
		return          # editor or desktop: every public call below no-ops
	_plugin = Engine.get_singleton("GodotUnityAds")

	# String form, not `_plugin.initialized.connect(...)`: the singleton's signals
	# are registered from Java at runtime, so they aren't resolvable as properties.
	_plugin.connect("initialized", _on_initialized)
	_plugin.connect("init_failed", _on_init_failed)
	_plugin.connect("ad_loaded", _on_ad_loaded)
	_plugin.connect("ad_load_failed", _on_ad_load_failed)
	_plugin.connect("ad_show_failed", _on_ad_show_failed)
	_plugin.connect("ad_closed", _on_plugin_ad_closed)

	# Consent first, ALWAYS. ConsentManager pushes the answer into the SDK before
	# calling back, so by the time _start_ads runs the personalization flag is
	# already in place for the very first request.
	ConsentManager.ensure_consent(func(_granted: bool) -> void: _start_ads())


func _start_ads() -> void:
	if _ads_started or _plugin == null:
		return
	_ads_started = true

	if GAME_ID.is_empty():
		push_error("AdManager: GAME_ID is empty — set it from the Unity dashboard.")
		return

	_plugin.initialize(GAME_ID, not _live_ads())


func _on_initialized() -> void:
	# Nothing can be loaded before init completes, so this is where loading starts
	# rather than in _ready(). Deduplicated: while the arena unit is aliased to the
	# main interstitial, loading the same ID twice would race two loads onto one slot.
	for ad_unit in _all_ad_units():
		_load(ad_unit)


func _all_ad_units() -> Array[String]:
	var units: Array[String] = [REWARDED_AD_UNIT, INTERSTITIAL_AD_UNIT]
	if not units.has(ARENA_INTERSTITIAL_AD_UNIT):
		units.append(ARENA_INTERSTITIAL_AD_UNIT)
	return units


func _on_init_failed(message: String) -> void:
	push_warning("AdManager: Unity Ads init failed — %s" % message)


# ── Load plumbing ─────────────────────────────────────────────────────────────

func _load(ad_unit: String) -> void:
	_set_ready(ad_unit, false)
	if _plugin != null:
		_plugin.loadAd(ad_unit)


func _set_ready(ad_unit: String, value: bool) -> void:
	_ready_units[ad_unit] = value


func _on_ad_loaded(ad_unit: String) -> void:
	_set_ready(ad_unit, true)


func _on_ad_load_failed(ad_unit: String, message: String) -> void:
	_set_ready(ad_unit, false)
	push_warning("AdManager: load failed for %s — %s" % [ad_unit, message])
	await get_tree().create_timer(RELOAD_DELAY_AFTER_FAILURE).timeout
	# Don't stack a reload on top of one the show path already kicked off.
	if not _is_ready(ad_unit):
		_load(ad_unit)


func _is_ready(ad_unit: String) -> bool:
	return _ready_units.get(ad_unit, false)


# ── Show plumbing ─────────────────────────────────────────────────────────────
#
# Unity guarantees exactly one of ad_show_failed / ad_closed per show(), so both
# handlers below end the on-screen span and neither can leave `_showing` stuck
# true — which would make is_showing_ad() lie for the rest of the session.

func _on_ad_show_failed(ad_unit: String, message: String) -> void:
	push_warning("AdManager: show failed for %s — %s" % [ad_unit, message])
	_pending_reward = Callable()
	_load(ad_unit)
	_mark_closed()


func _on_plugin_ad_closed(ad_unit: String, completion_state: String) -> void:
	var earned := completion_state == "COMPLETED"
	var cb := _pending_reward
	_pending_reward = Callable()

	_load(ad_unit)

	# Publish the span BEFORE the reward callback: the callback restarts play
	# (the 3-2-1 replay countdown), so the deadlines it re-arms must already
	# have the ad's time credited back to them.
	_mark_closed()

	if ad_unit == REWARDED_AD_UNIT and earned and cb.is_valid():
		cb.call()


# ── Rewarded ──────────────────────────────────────────────────────────────────

func show_rewarded(on_reward: Callable) -> void:
	if not rewarded_ready or _plugin == null:
		return
	_set_ready(REWARDED_AD_UNIT, false)
	_pending_reward = on_reward
	_mark_shown(REWARDED_AD_UNIT)
	_plugin.showAd(REWARDED_AD_UNIT)


# ── Interstitial ──────────────────────────────────────────────────────────────

# Has enough time passed since the last full-screen ad? Shared by both
# interstitial ad units — the cooldown is per player, not per ad unit.
func _interstitial_allowed() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - _last_interstitial_at \
		>= MIN_SECONDS_BETWEEN_INTERSTITIALS


# Returns whether an ad actually went up, so a caller that needs to know when the
# player is back can decide whether to wait on `ad_closed` at all (nothing will be
# emitted if there was no ad to show).
func try_show_interstitial() -> bool:
	return _try_show_interstitial(INTERSTITIAL_AD_UNIT, interstitial_ready)


# See try_show_interstitial for why this reports whether an ad went up.
func try_show_arena_interstitial() -> bool:
	return _try_show_interstitial(ARENA_INTERSTITIAL_AD_UNIT, arena_interstitial_ready)


func _try_show_interstitial(ad_unit: String, is_ready: bool) -> bool:
	if not _interstitial_allowed():
		return false
	if not is_ready or _plugin == null:
		return false
	_set_ready(ad_unit, false)
	_last_interstitial_at = Time.get_ticks_msec() / 1000.0
	_mark_shown(ad_unit)
	_plugin.showAd(ad_unit)
	return true
