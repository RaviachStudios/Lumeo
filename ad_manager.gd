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
		if earned and cb.is_valid():
			cb.call()
	content_cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		_reward_earned = false
		_pending_reward = Callable()
		if _rewarded_ad:
			_rewarded_ad.destroy()
			_rewarded_ad = null
		_load_rewarded()
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
	content_cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		if _interstitial_ad:
			_interstitial_ad.destroy()
			_interstitial_ad = null
		_load_interstitial()
	ad.full_screen_content_callback = content_cb
	_interstitial_ad = ad
	interstitial_ready = true

func try_show_interstitial() -> void:
	if not interstitial_ready or _interstitial_ad == null:
		return
	interstitial_ready = false
	_interstitial_ad.show()

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
	content_cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		if _arena_interstitial_ad:
			_arena_interstitial_ad.destroy()
			_arena_interstitial_ad = null
		_load_arena_interstitial()
	ad.full_screen_content_callback = content_cb
	_arena_interstitial_ad = ad
	arena_interstitial_ready = true

func try_show_arena_interstitial() -> void:
	if not arena_interstitial_ready or _arena_interstitial_ad == null:
		return
	arena_interstitial_ready = false
	_arena_interstitial_ad.show()
