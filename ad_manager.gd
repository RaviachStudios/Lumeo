extends Node

const REWARDED_ID := "ca-app-pub-4855985167611175/5696511973"
const INTERSTITIAL_ID := "ca-app-pub-4855985167611175/5072180074"
# Dedicated arena/contest interstitial, shown when a race ends and the results
# screen appears. Kept as its own unit so its performance is tracked separately
# from the solo game-over interstitial (INTERSTITIAL_ID).
const ARENA_INTERSTITIAL_ID := "ca-app-pub-4855985167611175/8487558745"

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

func _ready() -> void:
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
	RewardedAdLoader.new().load(REWARDED_ID, AdRequest.new(), cb)

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
	InterstitialAdLoader.new().load(INTERSTITIAL_ID, AdRequest.new(), cb)

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

# Returns whether an ad actually went up, so a caller that needs to know when the
# player is back can decide whether to wait on `ad_closed` at all (nothing will be
# emitted if there was no ad to show).
func try_show_interstitial() -> bool:
	if not interstitial_ready or _interstitial_ad == null:
		return false
	interstitial_ready = false
	_mark_shown()
	_interstitial_ad.show()
	return true

# ── Arena interstitial (dedicated unit) ─────────────────────────────────────────

func _load_arena_interstitial() -> void:
	arena_interstitial_ready = false
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = _on_arena_interstitial_loaded
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void: pass
	InterstitialAdLoader.new().load(ARENA_INTERSTITIAL_ID, AdRequest.new(), cb)

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
	if not arena_interstitial_ready or _arena_interstitial_ad == null:
		return false
	arena_interstitial_ready = false
	_mark_shown()
	_arena_interstitial_ad.show()
	return true
