#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// One-off Firestore migration for the Lumeo rebrand.
//
// The old wheel is no longer a play device on any difficulty (see game.gd) and
// every shader theme has been delisted from the shop (shop_screen.gd CATEGORIES),
// so everything players bought for the old look is dead inventory. This script,
// for EVERY doc in /users:
//
//   1. prices that dead inventory at the catalog prices frozen in PRICES below,
//   2. credits the refund + a flat REBRAND_GIFT to coins / earned_coins,
//   3. wipes the dead inventory so the old items stop showing up in-game,
//   4. writes the `rebrand_v1` receipt the welcome popup renders.
//
// The receipt is ALSO the popup's gate, and both halves of that gate live here:
//   * eligibility — only docs that exist when this runs get the field, so an
//     account created afterwards can never see the popup. No date check.
//   * once-only  — the client opens the popup when `rebrand_v1` exists and the
//     separate `rebrand_v1_shown` flag is not set; Collect sets that flag.
//     A scalar and not a key inside the receipt on purpose: the receipt holds
//     `items`, an array, and the Android SDK refuses a client write carrying
//     one — which is exactly how 1.0.56 shipped a popup that replayed forever.
// The coins are already banked by the time the popup opens; Collect is a
// celebration, not a transaction.
//
// DRY RUN BY DEFAULT — prints the full per-user before/after and writes a JSON
// report. Nothing is written to Firestore without --apply.
//
//   node tools/rebrand_migrate.js                 # dry run, all users
//   node tools/rebrand_migrate.js --uid <UID>     # dry run, one user
//   node tools/rebrand_migrate.js --apply         # for real (backs up first)
//
// Auth: reuses the `firebase` CLI's stored refresh token (~/.config/configstore/
// firebase-tools.json) — run `firebase login` first. No service-account key.
// ─────────────────────────────────────────────────────────────────────────────

const os = require("os");
const fs = require("fs");
const path = require("path");

const PROJECT = "simon-6bc39";
const COLL = "users";
const REBRAND_GIFT = 2000;
const RECEIPT_FIELD = "rebrand_v1";

// Prices FROZEN at rebrand time, copied from CoinsManager / ButtonFrames. This is
// deliberately a snapshot and not a read of the live catalog: pruning a catalog
// entry later must never change what an old player was owed. `levels` are the
// historical difficulty prices (moderate/hard cost 10/20 before commit a1e53e7
// made every difficulty free).
const PRICES = {
  "outer_circle": {
    "default": 0, "crimson": 80, "emerald": 80, "azure": 80, "amethyst": 80,
    "amber": 80, "rose": 80, "silver": 110, "gold": 130, "pinkdots": 150,
    "zebra": 180, "candy": 200, "tiger": 220, "sunset": 240, "leopard": 250,
    "ocean": 260, "prism": 300, "starry": 300
  },
  "inner_circle": {
    "default": 0, "crimson": 80, "emerald": 80, "azure": 80, "amethyst": 80,
    "amber": 80, "rose": 80, "silver": 110, "gold": 130, "bubbles": 150,
    "target": 160, "star": 180, "smiley": 200, "paw": 200, "bolt": 200,
    "swirl": 220, "crescent": 220, "melody": 230, "clover": 240, "daisy": 250,
    "yinyang": 260, "diamond": 280, "rainbow": 300
  },
  "level_number": {
    "classic": 0, "neon": 120, "sky": 120, "lavender": 140, "mint": 140,
    "inferno": 150, "bubblegum": 160, "script": 180, "candy": 200, "gold": 250
  },
  "skins": {
    "casino": 4500, "arcade": 5000, "lunapark": 5500, "racing": 7000,
    "pirate": 7200, "submarine": 7500, "phantom": 7800, "inferno": 8000
  },
  "themes": {
    "midnight": 80, "indigo": 80, "sunset": 80, "crimson": 80, "slate": 80,
    "skybound": 80, "forest": 350, "desert": 350, "clouds": 400, "speedway": 450,
    "kitty": 550, "rainbow": 600, "neon": 800, "castle": 900, "inferno": 1000,
    "fairies": 1000, "aurora": 1050, "reef": 1200, "deepspace": 1600,
    // Retired from the catalog before the rebrand (deleted in 7f2fb74), but three
    // wallets still hold it. Priced at what it last sold for.
    "cosmos": 600
  },
  "levels": { "moderate": 10, "hard": 20 }
};

// The four refund rows the popup can show, in display order. `label` is what the
// player reads; `key` is what the receipt stores.
const ROWS = [
  { key: "wheel",  label: "Wheel cosmetics" },
  { key: "skins",  label: "Special Skins" },
  { key: "themes", label: "Old backgrounds" },
  { key: "levels", label: "Difficulty unlocks" }
];

// A background id survives the wipe only if it is one of the eight modelled 3D
// backgrounds, which are the only themes still on sale. Everything else in
// owned_themes is a delisted shader theme.
const isLiveTheme = (id) => id === "default" || id.startsWith("bg_");

// ─── auth ────────────────────────────────────────────────────────────────────

const CLI_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLI_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
let TOKEN = null;

async function auth() {
  const cfgPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
  if (!fs.existsSync(cfgPath)) throw new Error("firebase CLI config not found — run `firebase login`");
  const refresh = JSON.parse(fs.readFileSync(cfgPath, "utf8")).tokens?.refresh_token;
  if (!refresh) throw new Error("no refresh token in the firebase CLI config — run `firebase login`");
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: CLI_ID, client_secret: CLI_SECRET,
      refresh_token: refresh, grant_type: "refresh_token"
    })
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("auth failed: " + JSON.stringify(j));
  TOKEN = j.access_token;
}

const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

async function api(url, opts = {}) {
  const r = await fetch(url, {
    ...opts,
    headers: { authorization: "Bearer " + TOKEN, "content-type": "application/json", ...(opts.headers || {}) }
  });
  if (r.status === 401) { await auth(); return api(url, opts); }   // token aged out mid-run
  const j = await r.json();
  if (j.error) throw new Error(url + " -> " + JSON.stringify(j.error));
  return j;
}

// ─── Firestore value codec ───────────────────────────────────────────────────

function decode(v) {
  if ("nullValue" in v) return null;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(decode);
  if ("mapValue" in v) return decodeFields(v.mapValue.fields || {});
  return null;
}
const decodeFields = (f) => Object.fromEntries(Object.entries(f).map(([k, v]) => [k, decode(v)]));

function encode(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === "boolean") return { booleanValue: v };
  // Every number this script writes is a coin count or an item count — always an
  // int, and it MUST land as one: the rules check `coins is int`, and the client
  // reads it with int().
  if (typeof v === "number") return { integerValue: String(Math.round(v)) };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  return { mapValue: { fields: encodeFields(v) } };
}
const encodeFields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, encode(v)]));

// ─── read ────────────────────────────────────────────────────────────────────

async function listUsers(onlyUid) {
  if (onlyUid) {
    const d = await api(`${BASE}/${COLL}/${encodeURIComponent(onlyUid)}`);
    return [{ uid: onlyUid, data: decodeFields(d.fields || {}) }];
  }
  let out = [], token;
  do {
    const u = new URL(`${BASE}/${COLL}`);
    u.searchParams.set("pageSize", "300");
    if (token) u.searchParams.set("pageToken", token);
    const j = await api(u.toString());
    for (const d of j.documents || []) {
      out.push({ uid: d.name.split("/").pop(), data: decodeFields(d.fields || {}) });
    }
    token = j.nextPageToken;
  } while (token);
  return out;
}

// ─── the plan for one user ───────────────────────────────────────────────────

// Sum the prices of every owned id in one `owned_*` map. Unknown ids (a hand-
// edited doc, an item that predates the frozen table) price at 0 and are
// reported so they can't vanish silently.
function priceMap(owned, table, unknown, where) {
  let coins = 0, n = 0;
  if (!owned || typeof owned !== "object") return { coins, n };
  for (const [id, on] of Object.entries(owned)) {
    if (!on) continue;
    if (id === "default" || id === "classic") continue;      // free, never bought
    n++;
    if (!(id in table)) { unknown.push(`${where}:${id}`); continue; }
    coins += table[id];
  }
  return { coins, n };
}

function planFor(uid, d) {
  const unknown = [];
  const wheel = ["outer_circle", "inner_circle", "level_number"].reduce((acc, cat) => {
    const r = priceMap(d["owned_" + cat], PRICES[cat], unknown, cat);
    return { coins: acc.coins + r.coins, n: acc.n + r.n };
  }, { coins: 0, n: 0 });
  const skins = priceMap(d.owned_skins, PRICES.skins, unknown, "skins");
  const levels = priceMap(d.owned_levels, PRICES.levels, unknown, "levels");

  // Themes are split, not wiped wholesale: the eight bg_* backgrounds are still
  // on sale and stay owned; only the delisted shader themes are refunded.
  const ownedThemes = (d.owned_themes && typeof d.owned_themes === "object") ? d.owned_themes : {};
  const keptThemes = {}, deadThemes = [];
  for (const [id, on] of Object.entries(ownedThemes)) {
    if (!on) continue;
    if (isLiveTheme(id)) { keptThemes[id] = true; continue; }
    deadThemes.push(id);
    if (!(id in PRICES.themes)) unknown.push("themes:" + id);
  }
  const themes = { coins: deadThemes.reduce((s, id) => s + (PRICES.themes[id] || 0), 0), n: deadThemes.length };

  const per = { wheel, skins, themes, levels };
  const refund = ROWS.reduce((s, r) => s + per[r.key].coins, 0);
  const total = refund + REBRAND_GIFT;

  const coinsBefore = Number.isInteger(d.coins) ? d.coins : 0;
  const earnedBefore = Number.isInteger(d.earned_coins) ? d.earned_coins : 0;

  // A player equipping a theme they are about to stop owning has to be moved off
  // it, or they'd be wearing something that is no longer in their wallet. Default
  // is the guaranteed-owned fallback (and the shop always lists its card).
  const selectedTheme = String(d.selected_theme || "default");
  const themeReset = !isLiveTheme(selectedTheme);

  const receipt = {
    at: new Date().toISOString(),
    refund,
    gift: REBRAND_GIFT,
    // Only non-empty rows — the popup renders exactly what it finds here, so a
    // player with no old purchases gets the gift-only layout for free.
    items: ROWS.filter(r => per[r.key].coins > 0)
               .map(r => ({ key: r.key, label: r.label, n: per[r.key].n, coins: per[r.key].coins }))
  };

  const writes = {
    coins: coinsBefore + total,
    earned_coins: earnedBefore + total,
    // Cleared to {} / "" rather than deleted: the Android Firestore plugin's
    // set_document(merge) has no FieldValue.delete, so the client can only ever
    // write an empty map here — keeping the shapes identical on both sides.
    owned_outer_circle: {},
    owned_inner_circle: {},
    owned_level_number: {},
    equipped_outer_circle: "default",
    equipped_inner_circle: "default",
    equipped_level_number: "classic",
    owned_skins: {},
    selected_skin: "",
    simon_mode: "manual",
    owned_levels: {},
    owned_themes: keptThemes,
    [RECEIPT_FIELD]: receipt
  };
  if (themeReset) writes.selected_theme = "default";

  return {
    uid,
    name: String(d.name || "(no name)"),
    already: Object.prototype.hasOwnProperty.call(d, RECEIPT_FIELD),
    coinsBefore, coinsAfter: coinsBefore + total,
    per, refund, gift: REBRAND_GIFT, total,
    deadThemes, keptThemes: Object.keys(keptThemes),
    selectedThemeBefore: selectedTheme, themeReset,
    unknown, writes
  };
}

// ─── write ───────────────────────────────────────────────────────────────────

// One PATCH per doc with an explicit updateMask, which is a merge: fields not
// named are untouched (badges, streaks, daily_tasks, purchase_history, the
// real-money has_remove_ads flag — none of it is in the mask).
async function applyOne(p) {
  const fields = encodeFields(p.writes);
  const u = new URL(`${BASE}/${COLL}/${encodeURIComponent(p.uid)}`);
  for (const k of Object.keys(p.writes)) u.searchParams.append("updateMask.fieldPaths", k);
  await api(u.toString(), { method: "PATCH", body: JSON.stringify({ fields }) });
}

// ─── report ──────────────────────────────────────────────────────────────────

const money = (n) => n.toLocaleString("en-US");
const pad = (s, n) => String(s).slice(0, n).padEnd(n);
const rpad = (s, n) => String(s).padStart(n);

function printPlan(plans, apply) {
  console.log("");
  console.log(apply ? "APPLYING" : "DRY RUN — nothing will be written");
  console.log("");
  console.log(pad("player", 22), rpad("coins", 9), "→", rpad("coins", 9),
              rpad("wheel", 7), rpad("skins", 7), rpad("bgs", 7), rpad("lvl", 5),
              rpad("refund", 8), rpad("total", 8), " notes");
  console.log("─".repeat(120));
  for (const p of plans) {
    const notes = [];
    if (p.already) notes.push("ALREADY MIGRATED — skipped");
    if (p.themeReset) notes.push(`equipped ${p.selectedThemeBefore} → default`);
    if (p.deadThemes.length) notes.push(`-${p.deadThemes.length} bg`);
    if (p.keptThemes.length) notes.push(`keeps ${p.keptThemes.length}`);
    if (p.unknown.length) notes.push("UNPRICED " + p.unknown.join(","));
    console.log(
      pad(p.name, 22), rpad(money(p.coinsBefore), 9), "→", rpad(money(p.coinsAfter), 9),
      rpad(money(p.per.wheel.coins), 7), rpad(money(p.per.skins.coins), 7),
      rpad(money(p.per.themes.coins), 7), rpad(money(p.per.levels.coins), 5),
      rpad(money(p.refund), 8), rpad(money(p.total), 8), " " + notes.join(" · ")
    );
  }
  console.log("─".repeat(120));
  const live = plans.filter(p => !p.already);
  const sum = (f) => live.reduce((s, p) => s + f(p), 0);
  console.log(`${live.length} of ${plans.length} docs to migrate` +
              (plans.length - live.length ? ` (${plans.length - live.length} already carry ${RECEIPT_FIELD})` : ""));
  console.log(`  refunds : ${money(sum(p => p.refund))}` +
              `  (wheel ${money(sum(p => p.per.wheel.coins))}` +
              ` · skins ${money(sum(p => p.per.skins.coins))}` +
              ` · backgrounds ${money(sum(p => p.per.themes.coins))}` +
              ` · difficulties ${money(sum(p => p.per.levels.coins))})`);
  console.log(`  gifts   : ${money(sum(() => REBRAND_GIFT))}  (${money(REBRAND_GIFT)} × ${live.length})`);
  console.log(`  GRANTED : ${money(sum(p => p.total))} coins`);
  console.log(`  popups  : ${live.filter(p => p.refund > 0).length} itemised · ` +
              `${live.filter(p => p.refund === 0).length} gift-only`);
  const unpriced = live.filter(p => p.unknown.length);
  if (unpriced.length) {
    console.log("");
    console.log(`  ⚠ ${unpriced.length} doc(s) own ids missing from the frozen price table — they price at 0.`);
    console.log("    Add them to PRICES before applying, or accept the 0.");
  }
}

// ─── main ────────────────────────────────────────────────────────────────────

(async () => {
  const argv = process.argv.slice(2);
  const apply = argv.includes("--apply");
  const uidArg = argv.includes("--uid") ? argv[argv.indexOf("--uid") + 1] : null;
  const outDir = argv.includes("--out") ? argv[argv.indexOf("--out") + 1] : "firestore_snapshot";

  await auth();
  const users = await listUsers(uidArg);
  const plans = users.map(u => planFor(u.uid, u.data)).sort((a, b) => b.total - a.total);
  printPlan(plans, apply);

  fs.mkdirSync(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const report = path.join(outDir, `rebrand_plan_${stamp}.json`);
  fs.writeFileSync(report, JSON.stringify({ project: PROJECT, gift: REBRAND_GIFT, apply, plans }, null, 2));
  console.log("");
  console.log("plan written to " + report);

  if (!apply) {
    console.log("re-run with --apply to write it.");
    return;
  }

  // Full pre-write copy of every doc we are about to touch — the report above
  // only records the deltas, this is what a revert would be rebuilt from.
  const backup = path.join(outDir, `rebrand_backup_${stamp}.json`);
  fs.writeFileSync(backup, JSON.stringify(Object.fromEntries(users.map(u => [u.uid, u.data])), null, 2));
  console.log("pre-write backup at " + backup);

  let done = 0, failed = [];
  for (const p of plans) {
    if (p.already) continue;
    try { await applyOne(p); done++; }
    catch (e) { failed.push(p.uid); console.error(`  FAILED ${p.uid} (${p.name}): ${e.message}`); }
  }
  console.log("");
  console.log(`migrated ${done} doc(s)` + (failed.length ? `, ${failed.length} FAILED: ${failed.join(", ")}` : ""));
  console.log("re-run without --apply to verify: every doc should read ALREADY MIGRATED.");
})().catch(e => { console.error("ERROR " + e.message); process.exit(1); });
