extends Node

# Proves the welcome popup's gate end to end against the editor's simulated
# wallet store: a receipt with no `shown` opens it exactly once, and marking it
# seen closes it for good — including after a full reload of the doc, which is
# what a reinstall or a second device looks like from the client's side.

func _ready() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("GateTester")
	await get_tree().process_frame
	while not CoinsManager.is_loaded():
		await get_tree().process_frame

	print("no receipt at all (a post-migration account)  -> ",
		CoinsManager.has_unseen_rebrand_grant(), "   (expect false)")

	# What the migration writes.
	var receipt := {"at": "2026-08-30T19:15:19Z", "refund": 7870, "gift": 2000,
		"items": [{"key": "wheel", "label": "Wheel cosmetics", "n": 38, "coins": 5690}]}
	CoinsManager._save_partial({CoinsManager.REBRAND_FIELD: receipt})
	await _reload()
	print("receipt, never shown                          -> ",
		CoinsManager.has_unseen_rebrand_grant(), "   (expect true)")

	CoinsManager.mark_rebrand_shown()
	print("right after COLLECT                           -> ",
		CoinsManager.has_unseen_rebrand_grant(), "   (expect false)")

	await _reload()
	print("after a reload (reinstall / second device)    -> ",
		CoinsManager.has_unseen_rebrand_grant(), "   (expect false)")
	print("stored receipt survives the flag write        -> ", CoinsManager.rebrand_receipt)
	get_tree().quit()

func _reload() -> void:
	CoinsManager._loaded_for_uid = ""
	CoinsManager._load_user()
	await get_tree().process_frame
