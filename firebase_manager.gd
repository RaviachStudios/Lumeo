extends Node

signal signed_in(uid: String, display_name: String)
signal sign_in_failed(error: String)
signal signed_out
# Emitted on any change to the canonical display name (name-picker submit,
# or a sign-out that clears it). Subscribers persist it (CoinsManager) and
# propagate it (LeaderboardManager rename).
signal display_name_changed(new_name: String)
# Account-deletion outcome. On success this fires alongside `signed_out` (the
# same local-state reset applies either way); on failure the account and its
# data are untouched and the caller should let the player retry.
signal account_deleted
signal account_delete_failed(error: String)

const SAVE_PATH := "user://user_profile.cfg"

# In the editor we simulate auth so the whole flow is testable without a device.
var _is_editor := OS.get_name() != "Android"

var uid: String = ""
var display_name: String = ""   # the name the user explicitly chose
var google_name: String = ""    # the name Google reports (used only as a suggestion)

func _ready() -> void:
	_load_profile()
	if _is_editor:
		return
	Firebase.auth.auth_success.connect(_on_auth_success)
	Firebase.auth.auth_failure.connect(_on_auth_failure)
	Firebase.auth.sign_out_success.connect(_on_sign_out)
	if Firebase.auth.is_signed_in():
		var user: Dictionary = Firebase.auth.get_current_user_data()
		_apply_user(user)

func is_signed_in() -> bool:
	if _is_editor:
		return not uid.is_empty()
	return Firebase.auth.is_signed_in()

func has_display_name() -> bool:
	return not display_name.is_empty()

# What to pre-fill the name picker with.
func name_suggestion() -> String:
	return display_name if not display_name.is_empty() else google_name

func sign_in() -> void:
	if _is_editor:
		# Simulate a fresh Google sign-in for editor testing.
		_apply_user({"uid": "editor_test_uid", "name": "Test Player"})
		signed_in.emit(uid, display_name)
		return
	Firebase.auth.sign_in_with_google()

func set_display_name(name: String) -> void:
	if name == display_name:
		return
	display_name = name
	_save_profile()
	display_name_changed.emit(display_name)

func sign_out_user() -> void:
	if _is_editor:
		_on_sign_out(true)
		return
	Firebase.auth.sign_out()

# Permanently deletes the signed-in player's account and every server-side
# trace of it: Arena/contest membership, leaderboard rows, the wallet doc
# (coins, cosmetics, purchase history), then the Firebase Auth user itself.
# The social/shared data is purged FIRST, while still authenticated — Firestore
# rules key every delete on request.auth, so doing it after the auth account
# is gone would just get rejected.
#
# Does NOT touch the Google Play purchase record for the non-consumable
# "remove ads" upgrade: Play still owns that, so PurchaseManager's normal
# startup query re-grants it for free next time this Google account signs in.
# Consumable coins already converted to balance have no such replay — once
# the wallet doc is gone, real-money coins bought with it are gone for good.
func delete_account() -> Dictionary:
	if not is_signed_in():
		return {"ok": false, "error": "not_signed_in"}
	for c in await ContestManager.load_my_contests():
		await ContestManager.leave_contest(String(c.get("id", "")))
	await LeaderboardManager.delete_all_my_rows()
	await CoinsManager.delete_wallet_doc()

	if _is_editor:
		_on_sign_out(true)
		account_deleted.emit()
		return {"ok": true}

	Firebase.auth.delete_current_user()
	var success: bool = await Firebase.auth.user_deleted
	if not success:
		account_delete_failed.emit("delete_failed")
		return {"ok": false, "error": "delete_failed"}
	_on_sign_out(true)
	account_deleted.emit()
	return {"ok": true}

# Sets uid + google_name. Only keeps a chosen display_name if it belongs to
# THIS uid (so a different account on the same device must pick a new name).
func _apply_user(user_data: Dictionary) -> void:
	var new_uid: String = user_data.get("uid", "")
	google_name = user_data.get("name", "")
	if new_uid != uid:
		# Different account than the one cached locally: drop the old chosen name.
		display_name = ""
		_save_profile()
	uid = new_uid

func _on_auth_success(user_data: Dictionary) -> void:
	_apply_user(user_data)
	signed_in.emit(uid, display_name)

func _on_auth_failure(error: String) -> void:
	sign_in_failed.emit(error)

func _on_sign_out(success: bool) -> void:
	if success:
		uid = ""
		display_name = ""
		google_name = ""
		_save_profile()
		LeaderboardManager.reset_session()
		signed_out.emit()

func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "uid", uid)
	cfg.set_value("profile", "display_name", display_name)
	cfg.save(SAVE_PATH)

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	uid = cfg.get_value("profile", "uid", "")
	display_name = cfg.get_value("profile", "display_name", "")
