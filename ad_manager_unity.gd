extends Node

# ── Unity Ads replacement for ad_manager.gd ────────────────────────────────────
#
# What callers use:
#
#   rewarded_ready       is_showing_ad()      show_rewarded(cb)
#   signal ad_closed(seconds_shown: float)
#
# Unity has no RewardedAd class and no loader objects: the ad unit is loaded and
# shown by one pair of calls, and "rewarded" is a property of the ad unit in the
# Unity dashboard, not of the code. The reward arrives as a COMPLETED completion
# state rather than a separate OnUserEarnedReward callback.

# ── Ad units ──────────────────────────────────────────────────────────────────
#
# REWARDED ONLY, deliberately. Lumeo shows exactly one kind of ad: the "watch an
# ad to replay" button, which the player presses on purpose and is paid for.
#
# There used to be interstitials at solo game over, on arrival at the arena
# results board, and on leaving a room. They were removed: Unity's interstitial
# inventory served long, un-skippable video, which is not a thing to drop on a
# player who just lost a round and didn't ask for anything.
#
# The dashboard still has Interstitial_Android and Banner_Android; unused ad units
# cost nothing, and leaving them there keeps the option open. Nothing in this file
# loads or shows them. If interstitials ever come back, they need their own
# frequency cap — there is none here now, because there is nothing to cap.
#
# Ad units are created in the Unity dashboard under Monetization → Ad Units, and
# the ad FORMAT is set there too — Rewarded_Android must be format **Rewarded**.
# Getting that wrong on the dashboard is the single most likely reason an ad unit
# never fills, and nothing in this file can detect it.
#
# (Unmediated integrations pass the ad unit ID to load/show. "Placement" is the
# mediation-side term and does not apply here.)
const REWARDED_AD_UNIT := "Rewarded_Android"

# Android Game ID, Unity dashboard → Monetization → Ad Units.
const GAME_ID := "800274606"

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


# Unity reports load failures for ordinary reasons (no fill right now, network
# blip). Left alone, the slot would stay empty until the next natural reload —
# and the replay button, which is only visible while an ad is ready, would simply
# stop appearing. Retrying on a slow timer costs nothing and keeps it available.
const RELOAD_DELAY_AFTER_FAILURE := 30.0

# Readiness is keyed by ad unit ID. Read-only to callers; _set_ready is the only
# writer.
var _ready_units: Dictionary = {}

var rewarded_ready: bool:
	get: return _ready_units.get(REWARDED_AD_UNIT, false)

var _pending_reward: Callable = Callable()

# ── "an ad is on screen" state ────────────────────────────────────────────────
# The rewarded ad backgrounds the app, but it does NOT stop the world: real time
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

var _plugin: Object = null
var _ads_started := false


# True while the rewarded ad covers the game.
func is_showing_ad() -> bool:
	return _showing


func _mark_shown() -> void:
	_showing = true
	_shown_at = Time.get_ticks_msec() / 1000.0


# Close out the on-screen span and tell everyone how long it lasted. Safe to call
# for an ad that never appeared (failed to show): the span is 0 and listeners
# compensate for nothing.
func _mark_closed() -> void:
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
	# rather than in _ready().
	_load(REWARDED_AD_UNIT)


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
	_mark_shown()
	_plugin.showAd(REWARDED_AD_UNIT)
