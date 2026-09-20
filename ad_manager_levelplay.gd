extends Node

# ── LevelPlay (Unity's ex-ironSource mediation) ────────────────────────────────
#
# Replaces ad_manager_unity.gd. Same public surface, so nothing that already
# called AdManager had to change:
#
#   rewarded_ready       is_showing_ad()      show_rewarded(cb)
#   signal ad_closed(seconds_shown: float)
#
# and three additions for the game-over screen:
#
#   interstitial_ready   show_interstitial()   signal interstitial_finished
#
# WHY mediation at all: Unity Ads on its own bids against nobody. LevelPlay runs
# an auction across every network you enable on the dashboard (Unity Ads included,
# via the adapter listed in export_plugin.gd) and serves whoever pays most for
# that impression. The code cost is this file; the revenue difference is the point.
#
# ── The single most important difference from Unity Ads ───────────────────────
#
# There is NO test-mode boolean. Unity Ads had one flag that made every ad a free
# test creative, and _live_ads() was the whole defence against billing ourselves
# for developer impressions. LevelPlay has no such flag: ads are live from the
# first request, and "test" means a device you registered in the dashboard under
# Test Devices, verified through the Test Suite.
#
# So the defence has to be different in kind, and it is: on a debug build this
# manager does not initialize the SDK at all (see _should_run_ads). No init, no
# requests, no impressions, nothing to charge anyone for. Debug builds instead get
# the Test Suite, which is what you actually want for checking the integration.
# If you ever need real ads in a hand-built debug APK, register that device on the
# dashboard first and flip FORCE_ADS_IN_DEBUG below — deliberately awkward,
# because getting it wrong is what got an AdMob account disabled once already.

# ── Dashboard identifiers ─────────────────────────────────────────────────────
#
# LevelPlay dashboard → your app. The App Key identifies the APP; the two ad unit
# IDs identify the ad units under it. All three are copied verbatim — an ad unit ID
# from the wrong app initializes fine and then never fills, with no error saying so.
#
# The App Key is a DIFFERENT value from the ad unit IDs (it is short, ~8 characters,
# and lives on the dashboard under App Settings / SDK Integration, next to the app
# name — not on the Ad Units page). Without it _start_ads() bails with a pushed
# error and no ad ever loads, so this is the one field that blocks everything.
const APP_KEY := "27a21e7e5"
const INTERSTITIAL_AD_UNIT := "t80zvr7rlv90r4op"        # dashboard name: lumeo_inter
const REWARDED_AD_UNIT := "0g9ab47aerk4ud1a"            # dashboard name: lumeo_reward

# Optional dashboard PLACEMENT names — not the ad unit names. "lumeo_inter" and
# "lumeo_reward" are the ad units above; a placement is a named slot inside one,
# used for per-placement reporting and dashboard-side caps. We have none, so both
# stay empty and each ad unit's default placement is used.
#
# The rewarded ad unit's dashboard reward (name "multiply_coins", amount 1) is
# informational here and deliberately unused: the payout is computed by the game
# from the run's own earnings (see game_over.gd COIN_MULTIPLIER), because "4x what
# you just earned" is not a number the dashboard can know. The reward callback is
# treated purely as "the player watched it through".
const INTERSTITIAL_PLACEMENT := ""
const REWARDED_PLACEMENT := ""

# Escape hatch — see the header. Only ever true on a device registered as a test
# device in the LevelPlay dashboard, and never in a commit that ships.
const FORCE_ADS_IN_DEBUG := false

# ── Frequency policy for the interstitial ─────────────────────────────────────
#
# CURRENTLY OFF, deliberately: all three are 0, so an interstitial is offered at
# every single game over. That is the chosen behaviour, not an oversight.
#
# The knobs are kept — wired up and tested — because this is the setting most
# likely to want tuning once there is real retention data, and re-deriving the
# pacing machinery later is much more work than leaving three constants at 0:
#
#   MIN_GAMES_BETWEEN   at most one interstitial per N finished games.
#   MIN_SECONDS_BETWEEN wall-clock floor, so a run of 20-second games can't
#                       squeeze past the game counter.
#   SKIP_FIRST_GAMES    a brand-new install sees no interstitial at all until it
#                       has finished this many games.
#
# What to watch, since nothing here will now stop it: an interstitial on every
# game over is the setting that most reliably teaches people to close the app at
# game over, and a shorter session is worth less than the extra impressions gain.
# If day-1 retention or games-per-session drops after this ships, this block is
# the first thing to move — 3 / 180.0 / 3 is a reasonable conservative baseline.
#
# The rewarded ad needs no policy either way: the player asks for it by name and
# is paid for it.
const MIN_GAMES_BETWEEN := 0
const MIN_SECONDS_BETWEEN := 0.0
const SKIP_FIRST_GAMES := 0

# Where the counters live between launches. A cap that resets every launch is not
# a cap.
const PREFS_PATH := "user://ad_policy.cfg"

# LevelPlay reports load failures for ordinary reasons (no fill right now, a
# network blip). Left alone the slot stays empty until the next natural reload —
# and the replay button, which is only visible while an ad is ready, would simply
# stop appearing. Retrying on a slow timer costs nothing.
const RELOAD_DELAY_AFTER_FAILURE := 30.0

# Signal payload discriminators, matching GodotLevelPlay.kt.
const KIND_INTERSTITIAL := "interstitial"
const KIND_REWARDED := "rewarded"


# ── State ─────────────────────────────────────────────────────────────────────

var _ready_kinds: Dictionary = {KIND_INTERSTITIAL: false, KIND_REWARDED: false}

var rewarded_ready: bool:
	get: return _ready_kinds.get(KIND_REWARDED, false) and not is_showing_ad()

var interstitial_ready: bool:
	get: return _ready_kinds.get(KIND_INTERSTITIAL, false) and not is_showing_ad()

var _pending_reward: Callable = Callable()

# onAdRewarded arrives BEFORE onAdClosed, so the reward is latched here and paid
# out on close. Paying on the reward callback instead would restart gameplay
# underneath an ad that is still covering the screen.
var _reward_earned := false

# ── "an ad is on screen" state ────────────────────────────────────────────────
#
# A full-screen ad backgrounds the app but does NOT stop the world: real time
# keeps passing, so a wall-clock deadline the game is holding gets silently
# charged for the ad the player was made to watch.
#
# The ad's on-screen span is published here and callers credit it back — see
# game.gd's per-press window. `ad_closed` carries how long the ad was actually up
# (0 if it never showed), which is exactly what a deadline needs to be pushed
# forward by the lost time.
#
# Note this is for deadlines PRIVATE to this device. The arena's straggler grace
# deliberately does not compensate: it is a property of the room shared by every
# client, and stretching it here would only make this device disagree with the
# others about when the race ends.
signal ad_closed(seconds_shown: float)

# Fired once per show_interstitial() call, whether the ad played, was skipped, or
# never appeared at all. The game-over screen waits on this before it does
# anything else, so it must fire on EVERY path — an interstitial that silently
# fails to report leaves the player staring at a dead screen.
signal interstitial_finished

var _showing := false
var _shown_at := 0.0
var _showing_kind := ""

var _plugin: Object = null
var _ads_started := false

# Interstitial pacing counters, persisted across launches.
var _games_finished := 0
var _last_interstitial_game := -1
var _last_interstitial_time := 0.0


# True while any full-screen ad covers the game.
func is_showing_ad() -> bool:
	return _showing


# ── Start-up: consent, then the SDK, then ads ─────────────────────────────────

func _ready() -> void:
	_load_prefs()
	if not Engine.has_singleton("GodotLevelPlay"):
		return          # editor or desktop: every public call below no-ops
	_plugin = Engine.get_singleton("GodotLevelPlay")

	# String form, not `_plugin.initialized.connect(...)`: the singleton's signals
	# are registered from Java at runtime, so they are not resolvable as properties.
	_plugin.connect("initialized", _on_initialized)
	_plugin.connect("init_failed", _on_init_failed)
	_plugin.connect("ad_loaded", _on_ad_loaded)
	_plugin.connect("ad_load_failed", _on_ad_load_failed)
	_plugin.connect("ad_displayed", _on_ad_displayed)
	_plugin.connect("ad_display_failed", _on_ad_display_failed)
	_plugin.connect("ad_rewarded", _on_ad_rewarded)
	_plugin.connect("ad_closed", _on_plugin_ad_closed)

	if not _should_run_ads():
		print("AdManager: debug build — LevelPlay not initialized (no live requests).")
		return

	# Consent FIRST, always. ConsentManager pushes the answer into the SDK before
	# calling back, so by the time _start_ads runs the personalization flag is
	# already in place for the very first request.
	ConsentManager.ensure_consent(func(_granted: bool) -> void: _start_ads())


# Ads run on release builds only — see the header for why this is a hard gate
# rather than a test-mode flag.
func _should_run_ads() -> bool:
	if FORCE_ADS_IN_DEBUG:
		return true
	return OS.has_feature("release") and not OS.has_feature("editor")


func _start_ads() -> void:
	if _ads_started or _plugin == null:
		return
	_ads_started = true

	if APP_KEY.is_empty():
		push_error("AdManager: APP_KEY is empty — set it from the LevelPlay dashboard.")
		return

	# The Firebase uid doubles as the LevelPlay user id, so dashboard reporting and
	# any future server-to-server reward callback line up with our own accounts.
	# Signed-out players just get "".
	_plugin.initialize(
		APP_KEY, FirebaseManager.uid, INTERSTITIAL_AD_UNIT, REWARDED_AD_UNIT, false)


func _on_initialized() -> void:
	# Nothing can be loaded before init completes, and the plugin's ad objects do
	# not even exist until then — so this, not _ready(), is where loading starts.
	_load(KIND_REWARDED)
	if _interstitials_allowed():
		_load(KIND_INTERSTITIAL)


func _on_init_failed(message: String) -> void:
	push_warning("AdManager: LevelPlay init failed — %s" % message)


# ── Load plumbing ─────────────────────────────────────────────────────────────

func _load(kind: String) -> void:
	_ready_kinds[kind] = false
	if _plugin == null:
		return
	if kind == KIND_INTERSTITIAL and not _interstitials_allowed():
		# A player who bought remove-ads will never be shown one, so don't fetch it.
		# Checked here rather than only at the call sites so the reload that follows
		# every close and every failure is covered by the same rule. A wallet that
		# loads mid-session flips this; nothing re-arms the load, which is correct —
		# the entitlement only ever moves in the "fewer ads" direction.
		return
	if kind == KIND_REWARDED:
		_plugin.loadRewarded()
	else:
		_plugin.loadInterstitial()


func _on_ad_loaded(kind: String) -> void:
	_ready_kinds[kind] = true


func _on_ad_load_failed(kind: String, message: String) -> void:
	_ready_kinds[kind] = false
	push_warning("AdManager: load failed for %s — %s" % [kind, message])
	await get_tree().create_timer(RELOAD_DELAY_AFTER_FAILURE).timeout
	# Don't stack a reload on top of one a show path already kicked off.
	if not bool(_ready_kinds.get(kind, false)):
		_load(kind)


# ── Show plumbing ─────────────────────────────────────────────────────────────
#
# Exactly one of ad_display_failed / ad_closed follows every show, so neither
# handler can leave `_showing` stuck true — which would make is_showing_ad() lie
# for the rest of the session and freeze game.gd's _process.

func _mark_shown(kind: String) -> void:
	_showing = true
	_showing_kind = kind
	_shown_at = Time.get_ticks_msec() / 1000.0


# Close out the on-screen span and tell everyone how long it lasted. Safe to call
# for an ad that never appeared: the span is 0 and listeners compensate for
# nothing.
func _mark_closed() -> void:
	var kind := _showing_kind
	_showing_kind = ""
	if not _showing:
		ad_closed.emit(0.0)
	else:
		_showing = false
		ad_closed.emit(Time.get_ticks_msec() / 1000.0 - _shown_at)
	if kind == KIND_INTERSTITIAL:
		interstitial_finished.emit()


func _on_ad_displayed(_kind: String) -> void:
	pass


func _on_ad_display_failed(kind: String, message: String) -> void:
	push_warning("AdManager: show failed for %s — %s" % [kind, message])
	# The pending reward callback is dropped, not called: the reward is for
	# watching, and nothing was watched.
	_pending_reward = Callable()
	_reward_earned = false
	_load(kind)
	_mark_closed()


# The only place a reward is earned. Latched, not paid — see _reward_earned.
func _on_ad_rewarded(_kind: String, _reward_name: String, _amount: String) -> void:
	_reward_earned = true


func _on_plugin_ad_closed(kind: String) -> void:
	var earned := _reward_earned
	_reward_earned = false
	var cb := _pending_reward
	_pending_reward = Callable()

	# Queue the next one immediately; the load takes seconds and the next
	# opportunity may be moments away.
	_load(kind)

	if kind == KIND_INTERSTITIAL:
		_note_interstitial_shown()

	# Publish the span BEFORE the reward callback: the callback resumes play (the
	# 3-2-1 replay countdown), so the deadlines it re-arms must already have the
	# ad's time credited back to them.
	_mark_closed()

	if kind == KIND_REWARDED and earned and cb.is_valid():
		cb.call()


# ── Rewarded ──────────────────────────────────────────────────────────────────
#
# Opt-in and paid for, so no cap and no remove-ads suppression: a player who
# bought "remove ads" bought freedom from ads they didn't ask for, not from the
# button they press themselves to quadruple their coins. Taking that away would
# make the purchase a downgrade.

func show_rewarded(on_reward: Callable) -> void:
	if not rewarded_ready or _plugin == null:
		return
	_ready_kinds[KIND_REWARDED] = false
	_pending_reward = on_reward
	_reward_earned = false
	_mark_shown(KIND_REWARDED)
	_plugin.showRewarded(REWARDED_PLACEMENT)


# ── Interstitial ──────────────────────────────────────────────────────────────

# Whether an interstitial may be shown AT ALL right now: the entitlement check and
# the pacing rules, in one place. `can_show_interstitial` below is what callers ask.
func _interstitials_allowed() -> bool:
	# Paid the ads away — this is exactly the ad they paid to never see again.
	if CoinsManager.has_remove_ads:
		return false
	return true


# True when an interstitial is loaded AND policy permits it. The game-over screen
# calls this before deciding whether to wait for one.
func can_show_interstitial() -> bool:
	if not _interstitials_allowed():
		return false
	if not interstitial_ready:
		return false
	if _games_finished < SKIP_FIRST_GAMES:
		return false
	if _last_interstitial_game >= 0:
		if _games_finished - _last_interstitial_game < MIN_GAMES_BETWEEN:
			return false
		if Time.get_unix_time_from_system() - _last_interstitial_time < MIN_SECONDS_BETWEEN:
			return false
	return true


# Show the game-over interstitial. ALWAYS ends in `interstitial_finished`, even
# when nothing was shown, so the caller has one thing to await regardless of
# whether policy allowed it, an ad was loaded, or the show failed.
func show_interstitial() -> void:
	if not can_show_interstitial() or _plugin == null:
		# Deferred, not immediate: a caller that connects to the signal on the line
		# after this call must still hear it.
		call_deferred("emit_signal", "interstitial_finished")
		return
	_ready_kinds[KIND_INTERSTITIAL] = false
	_mark_shown(KIND_INTERSTITIAL)
	_plugin.showInterstitial(INTERSTITIAL_PLACEMENT)


# Count a finished game. Called from game.gd's _game_over, and it is what the
# per-N-games cap counts — not shows, so quitting to home mid-run doesn't advance
# the player toward the next ad.
func note_game_finished() -> void:
	_games_finished += 1
	_save_prefs()


func _note_interstitial_shown() -> void:
	_last_interstitial_game = _games_finished
	_last_interstitial_time = Time.get_unix_time_from_system()
	_save_prefs()


# ── Pacing persistence ────────────────────────────────────────────────────────

func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return
	_games_finished = int(cfg.get_value("ads", "games_finished", 0))
	_last_interstitial_game = int(cfg.get_value("ads", "last_interstitial_game", -1))
	_last_interstitial_time = float(cfg.get_value("ads", "last_interstitial_time", 0.0))


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ads", "games_finished", _games_finished)
	cfg.set_value("ads", "last_interstitial_game", _last_interstitial_game)
	cfg.set_value("ads", "last_interstitial_time", _last_interstitial_time)
	cfg.save(PREFS_PATH)


# ── Diagnostics ───────────────────────────────────────────────────────────────
#
# LevelPlay's Test Suite lists every network configured for the app and fires a
# test ad per ad unit — the fastest way to tell "the dashboard is wrong" from "the
# code is wrong". Debug builds only, and it needs the SDK initialized, so call
# open_test_suite() from a hidden debug row after flipping FORCE_ADS_IN_DEBUG.

func open_test_suite() -> void:
	if _plugin != null:
		_plugin.launchTestSuite()


func sdk_version() -> String:
	if _plugin == null:
		return ""
	return _plugin.getSdkVersion()
