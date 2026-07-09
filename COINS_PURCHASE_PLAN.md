# Real-Money Coin Purchases — Implementation Plan

Goal: let players buy coin packs with real money. Coins are a **consumable**
in-app product on Google Play. Purchases are **verified server-side** in a
Firebase Cloud Function before any coins are credited.

## Decisions (locked)

- **Store / payments:** Google Play Billing (mandatory for digital goods on Play).
- **Verification:** server-verified via a Firebase Cloud Function + Google Play
  Developer API. The client never credits purchased coins itself.
- **Billing plugin:** community/official `GodotGooglePlayBilling` plugin
  (Godot 4.x). No custom AAR to maintain for this.

## Architecture

```
Shop "COINS" tab  ──buy(sku)──▶  PurchaseManager (autoload)
                                      │ start_connection / query_product_details / purchase
                                      ▼
                          GodotGooglePlayBilling plugin
                                      │ on_purchase_updated(token, sku)
                                      ▼
                          PurchaseManager ──callable──▶  Cloud Function: verifyPurchase
                                                              │ 1. Google Play Developer API: purchases.products.get
                                                              │ 2. check state == purchased, token not already used
                                                              │ 3. /users/{uid}.coins += pack amount (FieldValue.increment)
                                                              │ 4. record token in /purchases/{token}
                                                              │ 5. consume via Developer API (or signal client to consume)
                                                              ▼
                          PurchaseManager  ── reload wallet ──▶ CoinsManager._load_user()
                                          ── consume_purchase(token) (cleanup local state)
```

The **coins-per-pack amount lives only in the Cloud Function** (the
authoritative source). The client's pack list is for display/pricing UI only —
a tampered client cannot change how many coins a SKU grants.

---

## Phase 0 — Google Play Console & API prerequisites

1. **Create consumable products.** Play Console → Monetize → Products →
   In-app products. Create one per pack, e.g.:
   - `coins_500` — "500 Coins"
   - `coins_1200` — "1,200 Coins" (best value badge)
   - `coins_3000` — "3,000 Coins"
   Mark each **consumable**, set prices, activate.
2. **Billing permission.** Ensure the export adds `com.android.vending.BILLING`
   (the plugin's export config normally handles this — verify in the merged
   `AndroidManifest.xml`).
3. **Service account for verification.** Google Cloud Console → create a service
   account → grant it access in Play Console (Users & permissions → invite the
   service-account email → "View financial data" + "Manage orders" on this app).
   Download its JSON key for the Cloud Function. Linking can take a few hours to
   propagate before the Developer API will answer.
4. **License testers.** Play Console → Setup → License testing — add test Gmail
   accounts so they can buy without being charged. Purchases must be made from a
   build uploaded to a Play track (internal testing is fine).

---

## Phase 1 — Install the billing plugin

1. Download `GodotGooglePlayBilling` for Godot 4.6 and copy it into `addons/`
   (same place as `GodotFirebaseAndroid`, `admob`).
2. Enable it in Project → Project Settings → Plugins.
3. Confirm it shows up as an Android plugin in `export_presets.cfg` (alongside
   the existing AdMob/Firebase entries).

Plugin API used (exact names):
- Methods: `start_connection()`, `is_ready()`, `query_product_details(ids, type)`,
  `purchase(product_id)`, `consume_purchase(purchase_token)`,
  `acknowledge_purchase(token)`.
- Signals: `connected`, `disconnected`, `connect_error`,
  `query_product_details_response`, `on_purchase_updated`,
  `consume_purchase_response`.

---

## Phase 2 — `purchase_manager.gd` autoload

New autoload, sibling to `AdManager`/`CoinsManager`. Register it in
`project.godot` `[autoload]` (e.g. `PurchaseManager="*res://purchase_manager.gd"`).

Responsibilities: own the plugin connection, expose the pack catalog for the UI,
launch buy flows, route every completed purchase through the Cloud Function, then
reload the wallet and consume the token.

```gdscript
extends Node

# Display/pricing catalog only. The AUTHORITATIVE coins-per-sku mapping lives in
# the Cloud Function — never trust this list to grant coins.
const PACKS := [
    {"sku": "coins_500",  "coins": 500,  "label": "500 Coins"},
    {"sku": "coins_1200", "coins": 1200, "label": "1,200 Coins", "tag": "BEST VALUE"},
    {"sku": "coins_3000", "coins": 3000, "label": "3,000 Coins"},
]

signal products_loaded                 # price strings ready for the UI
signal purchase_started
signal purchase_succeeded(coins: int)  # after server credit + wallet reload
signal purchase_failed(reason: String)

var _billing                            # the GodotGooglePlayBilling singleton, or null in editor
var _prices: Dictionary = {}            # sku -> localized price string
var _is_editor := OS.get_name() != "Android"

func _ready() -> void:
    if _is_editor:
        return
    if not Engine.has_singleton("GodotGooglePlayBilling"):
        return
    _billing = Engine.get_singleton("GodotGooglePlayBilling")
    _billing.connect("connected", _on_connected)
    _billing.connect("query_product_details_response", _on_details)
    _billing.connect("on_purchase_updated", _on_purchase_updated)
    _billing.connect("consume_purchase_response", func(_r): pass)
    _billing.start_connection()

func price_for(sku: String) -> String:
    return _prices.get(sku, "")

func buy(sku: String) -> void:
    if _is_editor or _billing == null or not _billing.is_ready():
        purchase_failed.emit("billing_unavailable")
        return
    purchase_started.emit()
    _billing.purchase(sku)

func _on_connected() -> void:
    var ids: Array = []
    for p in PACKS: ids.append(p["sku"])
    _billing.query_product_details(ids, 0)   # 0 = in-app product type

func _on_details(result) -> void:
    # Cache localized price strings from result for the shop cards.
    # (shape depends on plugin version — map sku -> formatted price)
    products_loaded.emit()

func _on_purchase_updated(purchases) -> void:
    for p in purchases:
        # Send token + sku to the Cloud Function. DO NOT credit coins here.
        _verify(p)   # p has purchase_token + product_id (see plugin payload)

func _verify(purchase) -> void:
    var token := String(purchase.get("purchase_token", ""))
    var sku := String(purchase.get("product_id", ""))
    var ok := await FirebaseManager.call_function("verifyPurchase",
        {"token": token, "sku": sku})       # helper added in Phase 3
    if not ok.get("granted", false):
        purchase_failed.emit(String(ok.get("error", "verify_failed")))
        return
    _billing.consume_purchase(token)        # let the SKU be bought again
    await CoinsManager.reload()             # re-read /users/{uid} from server
    purchase_succeeded.emit(int(ok.get("coins", 0)))
```

> Editor builds keep working: `PurchaseManager.buy()` just emits
> `purchase_failed("billing_unavailable")`, so the shop's COINS tab can disable
> its buttons off-device.

---

## Phase 3 — Cloud Function: `verifyPurchase`

This is the security boundary. Add a Firebase Functions project (`functions/`),
deployed to the same Firebase project as `google-services.json`.

```js
// functions/index.js  (Node)
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { google } = require("googleapis");
admin.initializeApp();

// AUTHORITATIVE coin amounts. Single source of truth.
const PACK_COINS = { coins_500: 500, coins_1200: 1200, coins_3000: 3000 };
const PACKAGE_NAME = "com.raviachstudios.simon";   // matches export_presets.cfg package/unique_name

exports.verifyPurchase = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "");
  const uid = context.auth.uid;
  const { token, sku } = data;
  const coins = PACK_COINS[sku];
  if (!coins) throw new functions.https.HttpsError("invalid-argument", "bad sku");

  // 1. Verify with Google Play.
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const publisher = google.androidpublisher({ version: "v3", auth });
  const res = await publisher.purchases.products.get({
    packageName: PACKAGE_NAME, productId: sku, token,
  });
  const p = res.data;
  if (p.purchaseState !== 0)   // 0 = purchased
    return { granted: false, error: "not_purchased" };

  // 2. Replay guard + atomic credit in one transaction.
  const db = admin.firestore();
  const tokenRef = db.doc(`purchases/${token}`);
  const userRef = db.doc(`users/${uid}`);
  const granted = await db.runTransaction(async (tx) => {
    if ((await tx.get(tokenRef)).exists) return false;   // already credited
    tx.set(tokenRef, { uid, sku, coins, at: admin.firestore.FieldValue.serverTimestamp() });
    tx.set(userRef, { coins: admin.firestore.FieldValue.increment(coins) }, { merge: true });
    return true;
  });
  if (!granted) return { granted: true, coins: 0 };   // idempotent re-send

  // 3. Consume server-side so the SKU is repurchasable even if the client dies.
  await publisher.purchases.products.consume({
    packageName: PACKAGE_NAME, productId: sku, token,
  });
  return { granted: true, coins };
});
```

Add a small helper to `firebase_manager.gd` (or wherever the plugin's callable
support lives) — `call_function(name, args) -> Dictionary` — so `PurchaseManager`
can invoke it. If the GodotFirebaseAndroid plugin lacks callable-functions
support, expose the function as an HTTPS endpoint and call it with `HTTPClient`
plus the user's ID token in the `Authorization` header.

---

## Phase 4 — Firestore data model & rules

**New collection `/purchases/{purchaseToken}`** — one doc per granted token:
`{ uid, sku, coins, at }`. Acts as the replay guard.

**`firestore.rules`:**
- `/purchases/**` — `allow read, write: if false;` (only the Cloud Function's
  admin SDK touches it; the admin SDK bypasses rules).
- `/users/{uid}` — **known limitation:** today the client writes `coins`
  directly (earn-at-game-over, daily claim). Purchased coins now come in via the
  function's `increment`, but the client's `_save_partial({"coins": balance})`
  writes an *absolute* value and can clobber a concurrent increment.

  Mitigation in this plan: `CoinsManager.reload()` after every purchase pulls the
  server total before the next client write, so the increment isn't lost in
  normal flow. **Recommended hardening (follow-up):** move *all* coin credits
  (earn + daily) server-side too and lock `coins` to read-only for clients in the
  rules. Out of scope for the first cut but noted so we don't forget.

**`coins_manager.gd` change:** add a public `reload()` that re-runs `_load_user()`
and awaits its completion, so `PurchaseManager` can refresh the wallet after a
verified grant. (`_load_user` already exists; just needs an awaitable wrapper +
guard against concurrent loads.)

---

## Phase 5 — Shop UI: the COINS tab

`shop_screen.gd` is data-driven, so this is mostly additive.

1. Add a category to `CATEGORIES`:
   ```gdscript
   { "key": "coins", "label": "GET COINS", "icon": "diamond",
     "accent": Color(1.00, 0.78, 0.22) },
   ```
   (Consider placing it first so it's the landing tab.)
2. In `_render_category`, branch on `"coins"` to build a bespoke panel (like the
   `simon`/`skins` panels) — a grid of pack cards. Reuse `_make_big_coin` and the
   card styling already in the file.
3. Each pack card shows: coin amount, optional "BEST VALUE" tag, and a buy button
   whose label is the **localized price string** from
   `PurchaseManager.price_for(sku)` (never a hard-coded "$0.99").
4. Button `pressed` → `PurchaseManager.buy(sku)`. Disable buttons when
   `PurchaseManager` reports billing unavailable (editor / no Play).
5. Wire feedback:
   - `PurchaseManager.purchase_started` → show a "Processing…" spinner/overlay.
   - `PurchaseManager.purchase_succeeded(coins)` → close spinner, play a coin
     burst, refresh the coin pill (the existing `CoinsManager.balance_changed`
     fires from `reload()`).
   - `PurchaseManager.purchase_failed(reason)` → toast/dismiss.
6. `PurchaseManager.products_loaded` → (re)label the buttons once prices arrive.

---

## Phase 6 — Testing

1. Build a signed AAB, upload to **internal testing**, install via the Play test
   link (sideloaded debug APKs cannot complete real billing flows).
2. Sign in as a **license tester**; buy each pack — verify the function logs show
   verification + grant, `/purchases/{token}` is written, and the wallet reloads
   with the right total.
3. Force a duplicate `on_purchase_updated` (kill the app mid-flow, reopen) — the
   replay guard must grant **once**.
4. Verify consume works: the same SKU can be bought again after a successful flow.
5. Cancel/decline a purchase — wallet unchanged, no token written.

---

## Security checklist

- [ ] Coin amounts authoritative only in the Cloud Function (`PACK_COINS`).
- [ ] Every grant gated by `purchases.products.get` returning purchaseState 0.
- [ ] Replay guard via `/purchases/{token}` inside a Firestore transaction.
- [ ] Credit via `FieldValue.increment`, not absolute write.
- [ ] `/purchases` collection unwritable by clients.
- [ ] (Follow-up) move earn/daily credits server-side and lock `coins` read-only.

## iOS note

There's an `ios/` folder in the repo. If you ship on the App Store, coins must go
through **StoreKit / Apple IAP** separately (Apple's equivalent of this whole
plan, with App Store Server API verification). This plan covers Android/Play only.

---

## Sources

- Godot — Android in-app purchases (official `GodotGooglePlayBilling` API/signals):
  https://docs.godotengine.org/en/stable/tutorials/platform/android/android_in_app_purchases.html
- Godot Google Play Billing plugin (Asset Store):
  https://store.godotengine.org/asset/godot-foundation/godot-google-play-billing/
- Google Play — verify purchases (Developer API `purchases.products`):
  https://developer.android.com/google/play/billing/security
