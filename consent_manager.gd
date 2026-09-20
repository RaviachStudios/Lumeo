extends Node

# ── Ad consent (GDPR / ePrivacy) ───────────────────────────────────────────────
#
# Personalized ads are built on personal data, and in the EEA/UK you must ask
# before collecting it and be able to show that the player answered. AdMob's UMP
# SDK used to do this for us; it can't any more, because UMP serves the consent
# message off an AdMob Application ID and ours belongs to a disabled account.
#
# LevelPlay ships no consent UI either — it only ACCEPTS an answer, via
# LevelPlay.setConsent plus the `do_not_sell` metadata flag. So this file is the
# missing half: it decides whether to ask, asks, stores the answer, and hands it
# to the SDK before the first ad request.
#
# Under mediation this matters MORE than it did with a single network, not less:
# the answer is forwarded to every network in the auction, so one missing consent
# is a missing consent at a dozen ad vendors at once.
#
# Three rules are load-bearing. Break any of them and the answer stops being a
# lawful basis, whatever the dialog says:
#
#   1. Ask BEFORE the ad SDK initializes. See ad_manager_levelplay.gd _ready().
#   2. Refusing must be exactly as easy as accepting — same size, same weight,
#      same screen, no pre-ticked boxes. See consent_dialog.gd.
#   3. The player can change their mind later. Wire open_settings() to a Privacy
#      row in the settings/profile screen.
#
# A refusal is NOT the end of monetization: it means contextual (non-personalized)
# ads, which still fill and still pay, just less.

const SAVE_PATH := "user://ad_consent.cfg"

# Bump this whenever what we disclose materially changes — a new ad vendor, a new
# purpose. Every stored answer below the current version is treated as unanswered
# and the player is asked again, because they never agreed to the new thing.
# v2: the ad partner changed from Unity Ads alone to Unity LevelPlay mediation,
# which forwards the answer to every network in its auction. That is a materially
# wider set of recipients than anyone consented to under v1, so every stored v1
# answer is treated as unanswered and the player is asked again.
const DISCLOSURE_VERSION := 2

# EU 27 + the three non-EU EEA states + the UK. Consent is legally required for
# users here; elsewhere it is not, so we don't spend first-launch goodwill asking.
const CONSENT_REQUIRED_COUNTRIES := [
	"AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
	"HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
	"SI", "ES", "SE",          # EU 27
	"IS", "LI", "NO",          # EEA
	"GB",                      # UK (UK GDPR)
]

signal consent_resolved(granted: bool)

var _granted := false
var _answered := false
var _resolving := false
var _dialog: CanvasLayer = null


func _ready() -> void:
	_load()


# ── Public API ────────────────────────────────────────────────────────────────

# True when the player is on record as allowing personalized ads. False both for
# an explicit refusal AND for "not asked yet", which is the correct default: no
# answer is not consent.
func personalized_allowed() -> bool:
	return _answered and _granted


func has_answered() -> bool:
	return _answered


# The one call ad_manager_levelplay.gd makes at startup. Resolves consent — from
# storage, from the region check, or by asking — then reports the result exactly
# once through `on_done`.
#
# Every path ends in a call to `on_done`, including every failure. A consent
# system that can wedge is worse than no ads: it leaves the game unable to ever
# load one.
func ensure_consent(on_done: Callable) -> void:
	if _answered:
		on_done.call(_granted)
		return

	# Every unresolved caller waits on the signal, INCLUDING the one that starts
	# the resolution below. _finish() is the single place an answer becomes final
	# and it emits `consent_resolved` on every path, so routing the callback
	# through the signal is what makes "on_done is called exactly once, always"
	# true — calling it directly from the two resolution paths instead is how it
	# came to be missed on both of them.
	#
	# Connected BEFORE the branch, because the region path below resolves
	# synchronously and would otherwise emit into nothing.
	consent_resolved.connect(func(g: bool) -> void: on_done.call(g), CONNECT_ONE_SHOT)

	if _resolving:
		# A second caller arrived mid-prompt; it is now waiting on the signal, so
		# don't stack a second dialog on top of the first.
		return

	_resolving = true

	if not _consent_required():
		# Outside the EEA/UK there is nothing to ask, and personalization is
		# permitted by default. Recorded so we don't re-run the region check every
		# launch, and so a player who later travels keeps a stable experience.
		_record(true)
		_finish(true)
		return

	_show_dialog()


# Re-opens the dialog so the player can change a previous answer. Required: a
# consent you cannot withdraw is not a consent. Call this from a "Privacy" /
# "Ad settings" row.
func open_settings() -> void:
	if _dialog != null:
		return
	_show_dialog()


# ── Region ────────────────────────────────────────────────────────────────────

# An unknown country deliberately counts as "required". Failing safe here costs
# us a prompt shown to someone who didn't need one; failing the other way means
# serving personalized ads in the EEA with no consent on file.
func _consent_required() -> bool:
	var country := _country_code()
	if country.is_empty():
		return true
	return country in CONSENT_REQUIRED_COUNTRIES


func _country_code() -> String:
	if Engine.has_singleton("GodotLevelPlay"):
		var plugin := Engine.get_singleton("GodotLevelPlay")
		var code: String = plugin.getCountryCode()
		if not code.is_empty():
			return code.to_upper()
	# Off-device (editor, desktop) there is no plugin. The locale's region suffix
	# is the only hint available and is good enough for a development run.
	var locale := OS.get_locale()          # e.g. "en_US", "de_DE"
	var parts := locale.split("_")
	if parts.size() >= 2:
		return parts[1].substr(0, 2).to_upper()
	return ""


# ── Dialog ────────────────────────────────────────────────────────────────────

func _show_dialog() -> void:
	var dlg := preload("res://consent_dialog.gd").new() as CanvasLayer
	_dialog = dlg
	dlg.answered.connect(_on_dialog_answered)
	get_tree().root.add_child(dlg)


func _on_dialog_answered(granted: bool) -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	_record(granted)
	if _resolving:
		_finish(granted)
	else:
		# Reached through open_settings(): ads are already running, so the new
		# answer only has to be pushed down to the SDK.
		_apply_to_sdk(granted)
		consent_resolved.emit(granted)


func _finish(granted: bool) -> void:
	_resolving = false
	_apply_to_sdk(granted)
	consent_resolved.emit(granted)


func _apply_to_sdk(granted: bool) -> void:
	if Engine.has_singleton("GodotLevelPlay"):
		Engine.get_singleton("GodotLevelPlay").setConsent(granted)


# ── Storage ───────────────────────────────────────────────────────────────────
#
# The timestamp and version are not decoration: "we asked, on this date, about
# this disclosure, and they said X" is the record you'd need if anyone asks.

func _record(granted: bool) -> void:
	_granted = granted
	_answered = true
	var cfg := ConfigFile.new()
	cfg.set_value("consent", "granted", granted)
	cfg.set_value("consent", "version", DISCLOSURE_VERSION)
	cfg.set_value("consent", "timestamp", Time.get_unix_time_from_system())
	cfg.set_value("consent", "country", _country_code())
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("ConsentManager: could not save consent (%d)" % err)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var version: int = cfg.get_value("consent", "version", 0)
	if version < DISCLOSURE_VERSION:
		return          # stale disclosure — ask again
	_granted = cfg.get_value("consent", "granted", false)
	_answered = true
	_apply_to_sdk(_granted)


# Development helper: forget the answer so the dialog shows again next launch.
func reset() -> void:
	_answered = false
	_granted = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
