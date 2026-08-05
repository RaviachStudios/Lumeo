extends Node

# ── Ad units: live inventory is unreachable outside a release build ────────────
#
# Google's own test units. They always fill, they bill nobody, and they are what
# EVERY build that is not a signed release export serves — the editor, a debug
# export, anything a tester is ever handed.
#
# This switch exists because the opposite arrangement (live unit IDs compiled
# into every build) is what put developer-device impressions onto live inventory
# for nine weeks and got this publisher account disabled. Never "temporarily"
# point a development build at a live unit to check that a placement works:
# check it against these, which is the only supported way to test an ad.
const TEST_REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"

const LIVE_REWARDED_ID := "ca-app-pub-4855985167611175/5696511973"
const LIVE_INTERSTITIAL_ID := "ca-app-pub-4855985167611175/5072180074"
# Dedicated arena/contest interstitial, shown when a race ends and the results
# screen appears. Kept as its own unit so its performance is tracked separately
# from the solo game-over interstitial (LIVE_INTERSTITIAL_ID).
const LIVE_ARENA_INTERSTITIAL_ID := "ca-app-pub-4855985167611175/8487558745"

# Second, independent layer, in case a release build ever lands on a machine we
# develop on: every device belonging to the studio or to a tester is registered
# as a test device, so the SDK serves it test ads whatever the build type says.
#
# An ID is the hash the Mobile Ads SDK prints to logcat on that device's first ad
# request ("Use RequestConfiguration.Builder.setTestDeviceIds(...) to get test
# ads on this device"). Add a device here BEFORE it ever runs a release build.
const TEST_DEVICE_IDS: Array[String] = [
	"B599E7CC834524FBDB73BA2FE829DF1B",   # OPPO CPH2645 — primary dev phone
]

# Only a signed release export may resolve a live unit. `release` is absent from
# editor runs and debug exports; the editor check is belt-and-braces for a
# custom template that reports both.
static func _live_ads() -> bool:
	return OS.has_feature("release") and not OS.has_feature("editor")

static func rewarded_id() -> String:
	return LIVE_REWARDED_ID if _live_ads() else TEST_REWARDED_ID

static func interstitial_id() -> String:
	return LIVE_INTERSTITIAL_ID if _live_ads() else TEST_INTERSTITIAL_ID

static func arena_interstitial_id() -> String:
	return LIVE_ARENA_INTERSTITIAL_ID if _live_ads() else TEST_INTERSTITIAL_ID

# ── Full-screen ad frequency cap ───────────────────────────────────────────────
# One cooldown shared by BOTH interstitial placements (game over, arena results /
# exit), so a player bouncing in and out of a results screen can't be served
# back-to-back full-screen ads. Rewarded ads are deliberately exempt: the player
# asks for those by name and gets something for them.
const MIN_SECONDS_BETWEEN_INTERSTITIALS := 120.0

var _last_interstitial_at := -1.0e9

var rewarded_ready: bool = false
var interstitial_ready: bool = false
var arena_interstitial_ready: bool = false

var _rewarded_ad: RewardedAd = null
var _interstitial_ad: InterstitialAd = null
var _arena_interstitial_ad: InterstitialAd = null
var _pending_reward: Callable = Callable()
var _reward_earned: bool = false

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

# True while a full-screen ad (rewarded or either interstitial) covers the game.
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

# ── Start-up: test devices, then consent, then ads ────────────────────────────

var _ads_started := false
# The UMP form is RefCounted and the plugin only hands it to us once, so it has
# to be held for as long as it is on screen or it can be freed mid-display.
var _consent_form: ConsentForm = null

func _ready() -> void:
	# Applied before anything can request an ad, so the test-device list is already
	# in force for the very first request.
	var cfg := RequestConfiguration.new()
	cfg.test_device_ids = TEST_DEVICE_IDS
	MobileAds.set_request_configuration(cfg)
	_gather_consent()

# User Messaging Platform: gather (or confirm we already hold) the user's consent
# BEFORE the SDK is initialized and the first ad is requested. Outside the EEA/UK,
# or with consent already on file, the SDK answers NOT_REQUIRED / OBTAINED and we
# go straight through without showing anything.
#
# Every branch — including every failure — ends at _start_ads(), which runs once.
# Consent that cannot be gathered must never leave the game with no ads AND no
# way to ever load them.
func _gather_consent() -> void:
	var os_name := OS.get_name()
	if os_name != "Android" and os_name != "iOS":
		_start_ads()          # no UMP plugin off-device; nothing to ask
		return
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = false
	UserMessagingPlatform.consent_information.update(
		params, _on_consent_updated, _on_consent_update_failed)

func _on_consent_updated() -> void:
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_form_failed)
	else:
		_start_ads()

func _on_consent_update_failed(_e: FormError) -> void:
	_start_ads()

func _on_consent_form_loaded(form: ConsentForm) -> void:
	_consent_form = form
	if UserMessagingPlatform.consent_information.get_consent_status() \
			== ConsentInformation.ConsentStatus.REQUIRED:
		form.show(func(_e: FormError) -> void:
			_consent_form = null
			_start_ads())
	else:
		_start_ads()

func _on_consent_form_failed(_e: FormError) -> void:
	_start_ads()

func _start_ads() -> void:
	if _ads_started:
		return
	_ads_started = true
	MobileAds.initialize()
	_load_rewarded()
	_load_interstitial()
	_load_arena_interstitial()

# ── Rewarded ──────────────────────────────────────────────────────────────────

func _load_rewarded() -> void:
	rewarded_ready = false
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = _on_rewarded_loaded
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void: pass
	RewardedAdLoader.new().load(rewarded_id(), AdRequest.new(), cb)

func _on_rewarded_loaded(ad: RewardedAd) -> void:
	var content_cb := FullScreenContentCallback.new()
	content_cb.on_ad_dismissed_full_screen_content = func() -> void:
		if _rewarded_ad:
			_rewarded_ad.destroy()
			_rewarded_ad = null
		var earned := _reward_earned
		var cb := _pending_reward
		_reward_earned = false
		_pending_reward = Callable()
		_load_rewarded()
		# Publish the span BEFORE the reward callback: the callback restarts play
		# (the 3-2-1 replay countdown), so the deadlines it re-arms must already
		# have the ad's time credited back to them.
		_mark_closed()
		if earned and cb.is_valid():
			cb.call()
	content_cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		_reward_earned = false
		_pending_reward = Callable()
		if _rewarded_ad:
			_rewarded_ad.destroy()
			_rewarded_ad = null
		_load_rewarded()
		_mark_closed()
	ad.full_screen_content_callback = content_cb
	_rewarded_ad = ad
	rewarded_ready = true

func show_rewarded(on_reward: Callable) -> void:
	if not rewarded_ready or _rewarded_ad == null:
		return
	rewarded_ready = false
	_pending_reward = on_reward
	_reward_earned = false
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_reward_earned = true
	_mark_shown()
	_rewarded_ad.show(listener)

# ── Interstitial ──────────────────────────────────────────────────────────────

func _load_interstitial() -> void:
	interstitial_ready = false
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = _on_interstitial_loaded
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void: pass
	InterstitialAdLoader.new().load(interstitial_id(), AdRequest.new(), cb)

func _on_interstitial_loaded(ad: InterstitialAd) -> void:
	var content_cb := FullScreenContentCallback.new()
	content_cb.on_ad_dismissed_full_screen_content = func() -> void:
		if _interstitial_ad:
			_interstitial_ad.destroy()
			_interstitial_ad = null
		_load_interstitial()
		_mark_closed()
	content_cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		if _interstitial_ad:
			_interstitial_ad.destroy()
			_interstitial_ad = null
		_load_interstitial()
		_mark_closed()
	ad.full_screen_content_callback = content_cb
	_interstitial_ad = ad
	interstitial_ready = true

# Has enough time passed since the last full-screen ad? Shared by both
# interstitial placements — the cooldown is per player, not per placement.
func _interstitial_allowed() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - _last_interstitial_at \
		>= MIN_SECONDS_BETWEEN_INTERSTITIALS

# Returns whether an ad actually went up, so a caller that needs to know when the
# player is back can decide whether to wait on `ad_closed` at all (nothing will be
# emitted if there was no ad to show).
func try_show_interstitial() -> bool:
	if not _interstitial_allowed():
		return false
	if not interstitial_ready or _interstitial_ad == null:
		return false
	interstitial_ready = false
	_last_interstitial_at = Time.get_ticks_msec() / 1000.0
	_mark_shown()
	_interstitial_ad.show()
	return true

# ── Arena interstitial (dedicated unit) ─────────────────────────────────────────

func _load_arena_interstitial() -> void:
	arena_interstitial_ready = false
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = _on_arena_interstitial_loaded
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void: pass
	InterstitialAdLoader.new().load(arena_interstitial_id(), AdRequest.new(), cb)

func _on_arena_interstitial_loaded(ad: InterstitialAd) -> void:
	var content_cb := FullScreenContentCallback.new()
	content_cb.on_ad_dismissed_full_screen_content = func() -> void:
		if _arena_interstitial_ad:
			_arena_interstitial_ad.destroy()
			_arena_interstitial_ad = null
		_load_arena_interstitial()
		_mark_closed()
	content_cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		if _arena_interstitial_ad:
			_arena_interstitial_ad.destroy()
			_arena_interstitial_ad = null
		_load_arena_interstitial()
		_mark_closed()
	ad.full_screen_content_callback = content_cb
	_arena_interstitial_ad = ad
	arena_interstitial_ready = true

# See try_show_interstitial for why this reports whether an ad went up.
func try_show_arena_interstitial() -> bool:
	if not _interstitial_allowed():
		return false
	if not arena_interstitial_ready or _arena_interstitial_ad == null:
		return false
	arena_interstitial_ready = false
	_last_interstitial_at = Time.get_ticks_msec() / 1000.0
	_mark_shown()
	_arena_interstitial_ad.show()
	return true
