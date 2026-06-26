extends Node

# Real-money coin purchases via Google Play Billing.
#
# Owns a single BillingClient, queries the three consumable coin SKUs on
# startup, exposes localized prices for the UI, launches buy flows, and
# credits coins on a successful purchase.
#
# Per the locked-in scope for the first cut, verification is CLIENT-SIDE:
# - We credit on a PURCHASED, acknowledged-or-pending purchase update.
# - We immediately consume the token so the same SKU can be re-bought.
# - Tokens we've already credited are persisted to user:// so an app crash
#   between credit and consume can't double-grant when the Play store
#   re-delivers the same purchase on the next launch.
# Server-verified credit (COINS_PURCHASE_PLAN.md, Phase 3) can be slotted
# in later by changing only _credit() — the rest of the flow stays put.
#
# Editor builds: the Play Billing singleton isn't present, so buy()
# simulates the round-trip (spinner → credit → success) so the popup's UI
# flow stays testable off-device. Coins still land in the wallet via
# CoinsManager, which already has its own editor-sim Firestore.

signal products_loaded                      # localized prices ready for the UI
signal purchase_started(sku: String)
signal purchase_succeeded(sku: String, coins: int)
signal purchase_failed(sku: String, reason: String)
# A slow / deferred payment method (cash, family approval, …) returned with the
# purchase still in Play's PENDING state. We don't credit until it clears.
signal purchase_pending(sku: String)

# Pack catalog. SKU ids match the consumable in-app products created in
# Play Console. coins is the local credit amount — for the first cut this
# is the source of truth; moving it server-side is the documented follow-up.
#
# Display order (left→right, top→bottom) matches the popup grid: 4 columns,
# 2 rows.
const PACKS: Array = [
	{"sku": "coins_1", "coins": 100,   "label": "Starter"},
	{"sku": "coins_2", "coins": 300,   "label": "Handful"},
	{"sku": "coins_3", "coins": 700,   "label": "Pouch"},
	{"sku": "coins_4", "coins": 1000,  "label": "Sack"},
	{"sku": "coins_5", "coins": 5000,  "label": "Chest"},
	{"sku": "coins_6", "coins": 10000, "label": "Vault"},
	{"sku": "coins_7", "coins": 25000, "label": "Treasury"},
	{"sku": "coins_8", "coins": 50000, "label": "Jackpot"},
]

# Non-consumable in-app product: a one-time purchase that disables interstitial
# ads forever for the signed-in player. Acknowledged (not consumed) and reflected
# in the wallet doc via CoinsManager.set_remove_ads_owned so the entitlement
# survives reinstall (Play replays it on first connect).
const REMOVE_ADS_SKU := "no_ads"

const _TOKEN_STORE_PATH := "user://purchase_history.cfg"
const _SECTION := "credited"
# Editor purchase simulation delay — long enough that the "Processing…" overlay
# is actually visible so the UI flow can be sanity-checked off-device.
const _EDITOR_SIM_DELAY := 0.8

var _billing: BillingClient
var _is_editor := OS.get_name() != "Android"
var _connected := false
var _billing_initialised := false         # lazy: BillingClient is built on first use
var _pending_query := false               # query queued before connection landed
var _prices: Dictionary = {}              # sku -> localized price string (e.g. "$0.99")
var _coins_for_sku: Dictionary = {}       # sku -> coins (built from PACKS)
var _known_skus: Dictionary = {}          # full set of SKUs we recognise (packs + remove_ads)
var _credited_tokens: Dictionary = {}     # token -> true, persisted across launches
var _in_flight: Dictionary = {}           # sku -> true while a buy is processing
# Set when a query_purchases was issued specifically to recover an in-flight
# buy whose on_purchase_updated callback never arrived (see _notification).
var _resync_pending := false

func _ready() -> void:
	for p in PACKS:
		var sku := String(p["sku"])
		_coins_for_sku[sku] = int(p["coins"])
		_known_skus[sku] = true
	_known_skus[REMOVE_ADS_SKU] = true
	_load_credited_tokens()

	if _is_editor:
		# Editor: no billing singleton, but seed the cache with placeholder Play
		# Store prices so the popup looks identical to what ships on-device.
		# These are display-only — the actual prices on Android come from
		# query_product_details and are localised by Play automatically.
		_prices["coins_1"] = "$0.49"
		_prices["coins_2"] = "$0.99"
		_prices["coins_3"] = "$1.99"
		_prices["coins_4"] = "$2.99"
		_prices["coins_5"] = "$5.99"
		_prices["coins_6"] = "$9.99"
		_prices["coins_7"] = "$19.99"
		_prices["coins_8"] = "$39.99"
		_prices[REMOVE_ADS_SKU] = "$2.99"
		call_deferred("emit_signal", "products_loaded")
		return

	# We deliberately DO NOT create the BillingClient here. WHY: instantiating
	# it calls _plugin_singleton.initPlugin() and start_connection(), both of
	# which attach Activity-level callbacks on Android. Doing that during the
	# autoload phase races with Firebase auth / Google Sign-In's own Activity
	# wiring, and on some devices the sign-in intent stops launching at all.
	# Initialisation is deferred to ensure_initialised(), which the loading
	# screen calls during boot (once Firebase has wired up) so the popup opens
	# with prices already cached.

# Recover stuck in-flight purchases when the user returns from the Play sheet.
# WHY: GodotGooglePlayBilling 3.2.0 only emits on_purchase_updated when the
# Billing response is OK *and* purchases is non-null. USER_CANCELED,
# ITEM_ALREADY_OWNED, network errors and a few pending-flow edge cases are
# silently swallowed by the plugin — the buy() spinner would otherwise sit
# forever. On focus regain we re-query purchases (credits anything that
# actually landed via the existing _handle_purchase path) and then clear
# whatever remains so the UI can unstick.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if _is_editor or _in_flight.is_empty():
		return
	if _billing != null and _billing.is_ready():
		_resync_pending = true
		_billing.query_purchases(BillingClient.ProductType.INAPP)
	else:
		# Billing isn't around to verify — unstick the popup so the user can retry.
		_fail_in_flight("user_canceled")

# Build and connect the BillingClient on demand. Idempotent: safe to call from
# every popup open. Returns true if the plugin is available (Android with the
# billing singleton present), false otherwise.
func ensure_initialised() -> bool:
	if _is_editor:
		return true
	if _billing_initialised:
		return _billing != null
	_billing_initialised = true
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		return false
	_billing = BillingClient.new()
	add_child(_billing)
	_billing.connected.connect(_on_connected)
	_billing.disconnected.connect(_on_disconnected)
	_billing.connect_error.connect(_on_connect_error)
	_billing.query_product_details_response.connect(_on_product_details)
	_billing.query_purchases_response.connect(_on_query_purchases)
	_billing.on_purchase_updated.connect(_on_purchase_updated)
	_billing.consume_purchase_response.connect(_on_consume_response)
	_billing.acknowledge_purchase_response.connect(_on_acknowledge_response)
	_billing.start_connection()
	return true

# --- public API used by the popup ---

func is_available() -> bool:
	if _is_editor:
		return true                              # editor simulates purchases
	if not _billing_initialised:
		# Caller hasn't opened the popup yet; pretend it's available so the UI
		# doesn't render an "unsupported" state. Real availability is gated
		# again inside buy() once ensure_initialised has run.
		return true
	return _billing != null and _billing.is_ready()

func price_for(sku: String) -> String:
	return String(_prices.get(sku, ""))

# True once a localized price has been cached for every SKU we recognise
# (coin packs + remove_ads). The loading screen waits on this so the popup
# opens with prices already in place rather than flashing "LOADING…" buttons.
func prices_ready() -> bool:
	for p in PACKS:
		if not _prices.has(String(p["sku"])):
			return false
	if not _prices.has(REMOVE_ADS_SKU):
		return false
	return true

func coins_for(sku: String) -> int:
	return int(_coins_for_sku.get(sku, 0))

# True if the player has previously purchased the remove-ads entitlement.
# Reads through to the wallet, which is the durable source of truth (Play
# replays the original purchase on first connect after a reinstall, and the
# wallet doc carries the flag across sessions while offline).
func owns_remove_ads() -> bool:
	return CoinsManager.has_remove_ads

func is_busy(sku: String = "") -> bool:
	if sku.is_empty():
		return not _in_flight.is_empty()
	return bool(_in_flight.get(sku, false))

# Launch the Play purchase sheet for `sku`. Failure conditions (no billing,
# already mid-flow) surface via purchase_failed so the popup can show them.
func buy(sku: String) -> void:
	if _in_flight.has(sku):
		return
	if not _known_skus.has(sku):
		purchase_failed.emit(sku, "unknown_sku")
		return
	# Block re-buy of the non-consumable up front so the popup never even
	# launches the Play sheet for a player who already owns the entitlement.
	if sku == REMOVE_ADS_SKU and owns_remove_ads():
		purchase_failed.emit(sku, "already_owned")
		return
	if _is_editor:
		_in_flight[sku] = true
		purchase_started.emit(sku)
		# Simulated success after a short delay so the spinner shows.
		await get_tree().create_timer(_EDITOR_SIM_DELAY).timeout
		_in_flight.erase(sku)
		if sku == REMOVE_ADS_SKU:
			CoinsManager.set_remove_ads_owned(sku)
			purchase_succeeded.emit(sku, 0)
		else:
			var coins := coins_for(sku)
			CoinsManager.credit_purchased_coins(coins, sku)
			purchase_succeeded.emit(sku, coins)
		return
	# Late lazy-init guard — should already be true if the popup opened, but
	# keep it here so buy() works even if called from another entry point.
	ensure_initialised()
	if _billing == null or not _billing.is_ready():
		purchase_failed.emit(sku, "billing_unavailable")
		return
	_in_flight[sku] = true
	purchase_started.emit(sku)
	# The plugin's purchase() returns a billing-result dict synchronously when
	# the sheet failed to launch (network, item unavailable). When it did launch
	# we wait for on_purchase_updated to land asynchronously.
	var res: Dictionary = _billing.purchase(sku)
	var code := int(res.get("response_code", BillingClient.BillingResponseCode.OK))
	if code != BillingClient.BillingResponseCode.OK:
		_in_flight.erase(sku)
		purchase_failed.emit(sku, _reason_for_code(code))

# --- billing connection plumbing ---

func _on_connected() -> void:
	_connected = true
	if _pending_query or _prices.is_empty():
		_pending_query = false
		_query_products()
	# Recover any prior-session unconsumed purchases (in case we crashed between
	# crediting and consuming, or the user closed the app on the buy sheet).
	_billing.query_purchases(BillingClient.ProductType.INAPP)

func _on_disconnected() -> void:
	_connected = false

func _on_connect_error(code: int, _msg: String) -> void:
	_connected = false
	# Surface to any waiting buy() — there isn't one in normal flow (buy()
	# rejects up front when not available), but be defensive.
	for sku in _in_flight.keys():
		purchase_failed.emit(String(sku), _reason_for_code(code))
	_in_flight.clear()

func _query_products() -> void:
	if _billing == null:
		return
	var ids := PackedStringArray()
	for p in PACKS:
		ids.append(String(p["sku"]))
	ids.append(REMOVE_ADS_SKU)
	_billing.query_product_details(ids, BillingClient.ProductType.INAPP)

func _on_product_details(response: Dictionary) -> void:
	# Plugin shape (GodotGooglePlayBilling 3.2.0): top-level key is
	# "product_details" — NOT "product_details_list" / "products" as some
	# older docs suggest. Each entry carries one_time_purchase_offer_details_list
	# (a LIST of offers), and the formatted_price lives inside each offer.
	var list: Variant = response.get("product_details",
		response.get("product_details_list", response.get("products", [])))
	if not (list is Array):
		return
	for item in list:
		if not (item is Dictionary):
			continue
		var sku := String((item as Dictionary).get("product_id", ""))
		if sku.is_empty():
			continue
		var price := _extract_price(item)
		if not price.is_empty():
			_prices[sku] = price
	products_loaded.emit()

func _extract_price(item: Dictionary) -> String:
	# One-time consumables: pick the first offer's formatted_price out of
	# one_time_purchase_offer_details_list. Fall back to the singular key
	# (older plugin builds) and a flattened formatted_price (defensive).
	var offers: Variant = item.get("one_time_purchase_offer_details_list", null)
	if offers is Array and (offers as Array).size() > 0:
		var first: Variant = (offers as Array)[0]
		if first is Dictionary:
			var fp := String((first as Dictionary).get("formatted_price", ""))
			if not fp.is_empty():
				return fp
	var otp: Variant = item.get("one_time_purchase_offer_details", null)
	if otp is Dictionary:
		var fp2 := String((otp as Dictionary).get("formatted_price", ""))
		if not fp2.is_empty():
			return fp2
	return String(item.get("formatted_price", ""))

# --- purchase delivery ---

func _on_purchase_updated(response: Dictionary) -> void:
	var code := int(response.get("response_code", BillingClient.BillingResponseCode.OK))
	if code == BillingClient.BillingResponseCode.USER_CANCELED:
		_fail_in_flight("user_canceled")
		return
	if code != BillingClient.BillingResponseCode.OK:
		_fail_in_flight(_reason_for_code(code))
		return
	var purchases: Variant = response.get("purchases", [])
	if not (purchases is Array):
		return
	for p in purchases:
		if p is Dictionary:
			_handle_purchase(p)

func _on_query_purchases(response: Dictionary) -> void:
	# Same payload shape; treat as a passive sync of in-flight items.
	var purchases: Variant = response.get("purchases", [])
	if purchases is Array:
		for p in purchases:
			if p is Dictionary:
				_handle_purchase(p)
	# If this query was kicked off by a focus-regain to recover a stuck buy()
	# (see _notification), anything that's still in flight after the response
	# wasn't reported by Play — card declined, network error, or the user
	# canceled. The plugin doesn't tell us which (its onPurchasesUpdated only
	# fires for OK), so we surface a generic "not completed" message and let
	# the player retry. user_canceled would be silent and hide real declines.
	if _resync_pending:
		_resync_pending = false
		if not _in_flight.is_empty():
			_fail_in_flight("purchase_failed")

func _handle_purchase(p: Dictionary) -> void:
	var state := int(p.get("purchase_state", BillingClient.PurchaseState.UNSPECIFIED_STATE))
	if state == BillingClient.PurchaseState.PENDING:
		# Slow payment methods (cash-at-counter, family approval, the "slow test
		# card") land here. We mustn't credit until Play flips this to PURCHASED,
		# but the popup needs to stop spinning and tell the player coins will
		# arrive later. Clear in-flight + signal so the UI can show that.
		var pending_sku := _sku_from_purchase(p)
		if not pending_sku.is_empty():
			_in_flight.erase(pending_sku)
			purchase_pending.emit(pending_sku)
		return
	if state != BillingClient.PurchaseState.PURCHASED:
		# Unknown / unspecified — nothing to do.
		return
	var token := String(p.get("purchase_token", ""))
	if token.is_empty():
		return
	var sku := _sku_from_purchase(p)
	if sku.is_empty() or not _known_skus.has(sku):
		# Unknown SKU — still consume so it doesn't pile up.
		_billing.consume_purchase(token)
		return
	if sku == REMOVE_ADS_SKU:
		# Non-consumable: acknowledge (don't consume) and record the entitlement.
		# Play replays the original purchase on first connect after a reinstall,
		# so re-handling this codepath on a fresh device must be safe — the
		# wallet flag is already set, so we just re-acknowledge (idempotent on
		# Play's side) and quietly exit.
		var already := CoinsManager.has_remove_ads
		CoinsManager.set_remove_ads_owned(sku)
		_billing.acknowledge_purchase(token)
		_in_flight.erase(sku)
		if not already:
			purchase_succeeded.emit(sku, 0)
		return
	# Idempotent: if we've credited this token before (crashed mid-consume on a
	# previous run, plugin replaying on startup, …), just re-consume.
	if _credited_tokens.has(token):
		_billing.consume_purchase(token)
		return
	_credit(sku, token)

func _sku_from_purchase(p: Dictionary) -> String:
	# GodotGooglePlayBilling 3.2.0 emits the SKU list under "product_ids"
	# (plural). The Kotlin side puts a String[] there, which Godot's JNI bridge
	# marshals as a PackedStringArray, NOT a plain Array — checking only `is
	# Array` here used to fall through to the empty fallback, leaving the SKU
	# blank and silently consuming the purchase without crediting coins.
	# Handle both shapes plus "products"/"product_id" as defensive fallbacks
	# for other plugin versions.
	var pids: Variant = p.get("product_ids", p.get("products", null))
	if pids is PackedStringArray:
		var ps := pids as PackedStringArray
		if ps.size() > 0:
			return ps[0]
	if pids is Array:
		var a := pids as Array
		if a.size() > 0:
			return String(a[0])
	return String(p.get("product_id", ""))

func _credit(sku: String, token: String) -> void:
	var coins := coins_for(sku)
	_credited_tokens[token] = true
	_save_credited_tokens()
	CoinsManager.credit_purchased_coins(coins, sku)
	_billing.consume_purchase(token)
	_in_flight.erase(sku)
	purchase_succeeded.emit(sku, coins)

func _on_consume_response(_response: Dictionary) -> void:
	# Nothing actionable here — the credit already happened. We just keep the
	# slot open so the BillingClient stops re-emitting on_purchase_updated for
	# this token, which it does for unconsumed consumables.
	pass

func _on_acknowledge_response(_response: Dictionary) -> void:
	# Same shape as the consume callback. Acknowledging is fire-and-forget from
	# our point of view — the entitlement is already persisted via CoinsManager,
	# and Play will keep replaying the purchase until ack lands, which is exactly
	# the recovery we want.
	pass

func _fail_in_flight(reason: String) -> void:
	for sku in _in_flight.keys():
		purchase_failed.emit(String(sku), reason)
	_in_flight.clear()

func _reason_for_code(code: int) -> String:
	match code:
		BillingClient.BillingResponseCode.USER_CANCELED: return "user_canceled"
		BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE: return "no_network"
		BillingClient.BillingResponseCode.BILLING_UNAVAILABLE: return "billing_unavailable"
		BillingClient.BillingResponseCode.ITEM_UNAVAILABLE: return "item_unavailable"
		BillingClient.BillingResponseCode.NETWORK_ERROR: return "no_network"
		BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED: return "already_owned"
		_: return "purchase_failed"

# --- credited-token persistence ---

func _load_credited_tokens() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_TOKEN_STORE_PATH) != OK:
		return
	if not cfg.has_section(_SECTION):
		return
	for key in cfg.get_section_keys(_SECTION):
		_credited_tokens[key] = true

func _save_credited_tokens() -> void:
	var cfg := ConfigFile.new()
	for token in _credited_tokens.keys():
		cfg.set_value(_SECTION, token, true)
	cfg.save(_TOKEN_STORE_PATH)
