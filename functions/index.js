"use strict";

// Server-side leaderboard backend for Simon. Two jobs:
//
//  1. board_top maintenance (event-triggered). The 20-row top list is 100% of
//     the fixed leaderboard read cost. Instead of every client running six
//     top-N queries on warm-up, ONE doc per family holds all three difficulties'
//     top-N lists, and clients read one doc per family. These docs are written
//     ONLY here (Admin SDK bypasses rules; firestore.rules makes board_top
//     client-read-only), so the visible lists can't be forged. We update on a
//     score write, but GATE the write on "does this actually change the top-N?"
//     — so a submit that doesn't crack the top 20 costs one read and no write,
//     and there's no write-hotspot from the 99% of scores that change nothing.
//     Concurrency is handled by a transaction (two entrants at once can't lose
//     each other).
//
//  2. Daily standings (scheduled, once just after midnight UTC). Reads the top
//     50 of each of yesterday's daily boards (only the top 50 earn coins),
//     credits each winner's wallet SERVER-SIDE, writes a receipt into
//     pending_daily_rewards on /users/{uid} for the client to show, then deletes
//     yesterday's daily rows. This removes the old per-open, per-player rank
//     reads (the heaviest read path) and makes the placement snapshot
//     authoritative at day-close. Idempotent via the last_daily_reward_date
//     high-watermark, so a retry (or an old client that still respects the same
//     watermark) never double-pays.

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onRequest} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

const DIFFS = ["easy", "moderate", "hard"];
const TOP_N = 20;
// Only the top 50 of a daily board earn coins (see daily_reward_for_rank in
// coins_manager.gd — 51+ is 0), so the reward job never needs to read further.
const DAILY_REWARD_N = 50;
// Score-histogram shard count. MUST stay <= the client's HIST_SHARDS in
// leaderboard_manager.gd (the client reads shards 0..HIST_SHARDS-1, so a shard a
// writer used but the reader skips would undercount). Only the DAILY histogram is
// written here (all-time is client-maintained); keep both in step.
const HIST_SHARDS = 3;
// Highest shard index ever used (for the 10-shard era). rebuild/cleanup sweep up
// to here so lowering HIST_SHARDS leaves no orphaned, unread shards behind.
const HIST_MAX_SHARD_SWEEP = 16;

function nowUnix() {
  return Math.floor(Date.now() / 1000);
}
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
function utcDate(d) {
  return d.toISOString().slice(0, 10); // "YYYY-MM-DD"
}
function todayUtc() {
  return utcDate(new Date());
}
function yesterdayUtc() {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - 1);
  return utcDate(d);
}

// =====================================================================
// 1) board_top maintenance — event-triggered, gated on a real top-N change
// =====================================================================

// Order- and key-stable serialization so the gate compares by value, not by the
// (arbitrary) key order Firestore hands back for the stored array's map entries.
function serializeList(list) {
  // Fixed field order per entry so the comparison is independent of the key
  // order Firestore returns; JSON of an array is order-deterministic.
  return list.map((e) => JSON.stringify([e.uid, e.score, e.name])).join(",");
}

// Upsert (or remove, when `after` is null) one player's entry in the family's
// materialized top-N for `diff`, inside a transaction, writing only when the
// top-N actually changes. For daily we also roll the doc over to the new day.
async function syncBoardTop(family, diff, before, after, fallbackUid) {
  const src = after || before;
  if (!src) return;
  const uid = typeof src.uid === "string" ? src.uid : fallbackUid;
  if (!uid) return;
  const rowDate = typeof src.date === "string" ? src.date : null;
  // Legacy daily rows (doc id == uid, no `uid`/`date` field) can't be attributed
  // to a day — skip; they age out on their own.
  if (family === "daily" && !rowDate) return;
  // Any daily write/delete for a past day is irrelevant to today's board_top —
  // bail BEFORE opening the transaction so the midnight mass-delete of yesterday's
  // rows doesn't cost one read per deleted row.
  if (family === "daily" && rowDate < todayUtc()) return;

  const ref = db.collection("board_top").doc(family);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    let boards = data.boards || {};
    let docDate = typeof data.date === "string" ? data.date : null;
    let rollover = false;

    if (family === "daily") {
      // A write for an older day than the doc already holds is stale — ignore.
      if (docDate && rowDate < docDate) return;
      // First write of a new day: start the doc fresh (clears every diff so
      // yesterday's lists never linger under today's date).
      if (rowDate !== docDate) {
        boards = {};
        docDate = rowDate;
        rollover = true;
      }
    }

    const oldList = Array.isArray(boards[diff]) ? boards[diff] : [];
    let list = oldList.filter((e) => e && e.uid !== uid);
    if (after) {
      list.push({
        uid,
        name: typeof after.name === "string" ? after.name : "Player",
        score: typeof after.score === "number" ? after.score : 0,
      });
    }
    list.sort((a, b) => b.score - a.score);
    list = list.slice(0, TOP_N);

    // Gate: nothing in the top-N moved → no write (this is what keeps the 99% of
    // score submits that don't crack the top 20 from touching this doc at all).
    if (!rollover && serializeList(list) === serializeList(oldList)) return;

    if (rollover) {
      // Full overwrite to wipe the previous day's other-diff lists.
      tx.set(ref, {date: docDate, boards: {[diff]: list}, updated_unix: nowUnix()});
    } else if (family === "daily") {
      tx.set(ref, {date: rowDate, boards: {[diff]: list}, updated_unix: nowUnix()}, {merge: true});
    } else {
      tx.set(ref, {boards: {[diff]: list}, updated_unix: nowUnix()}, {merge: true});
    }
  });
}

// ---- per-day daily score histogram (server-maintained) --------------------

function histShardName(board, k) {
  return "board_hist/" + board + "_" + k;
}

// Apply {score: delta} to a random shard via atomic increments (creating the doc
// / fields as needed). Matches the { counts: { "<score>": int } } shape the
// client reads and sums across shards.
async function histApply(board, deltas) {
  const counts = {};
  let any = false;
  for (const [score, d] of Object.entries(deltas)) {
    if (d !== 0) {
      counts[String(score)] = FieldValue.increment(d);
      any = true;
    }
  }
  if (!any) return;
  const k = Math.floor(Math.random() * HIST_SHARDS);
  await db.doc(histShardName(board, k)).set({counts}, {merge: true});
}

function scoreOf(d) {
  return d && typeof d.score === "number" ? d.score : 0;
}

// Keep today's per-day daily histogram in step with a daily row write. The
// shipped client never touches daily histograms, so there's no double-count.
async function syncDailyHist(diff, before, after) {
  const src = after || before;
  if (!src) return;
  const date = typeof src.date === "string" ? src.date : null;
  if (!date) return; // legacy row without a date
  if (date < todayUtc()) return; // past day — its histogram is being torn down
  const oldScore = scoreOf(before);
  const newScore = scoreOf(after);
  if (oldScore === newScore) return; // e.g. a name-only edit — nothing to tally
  const deltas = {};
  if (after && newScore > 0) deltas[newScore] = (deltas[newScore] || 0) + 1;
  if (before && oldScore > 0) deltas[oldScore] = (deltas[oldScore] || 0) - 1;
  await histApply("daily_" + diff + "_" + date, deltas);
}

for (const diff of DIFFS) {
  exports["syncGlobal_" + diff] = onDocumentWritten("global_" + diff + "/{uid}", async (event) => {
    const b = event.data.before.exists ? event.data.before.data() : null;
    const a = event.data.after.exists ? event.data.after.data() : null;
    // All-time doc id IS the uid. (All-time histogram stays client-maintained.)
    await syncBoardTop("global", diff, b, a, event.params.uid);
  });
  exports["syncDaily_" + diff] = onDocumentWritten("daily_" + diff + "/{docId}", async (event) => {
    const b = event.data.before.exists ? event.data.before.data() : null;
    const a = event.data.after.exists ? event.data.after.data() : null;
    // Daily doc id is `{date}__{uid}` — uid comes from the row's `uid` field.
    await Promise.all([
      syncBoardTop("daily", diff, b, a, null),
      syncDailyHist(diff, b, a),
    ]);
  });
}

// =====================================================================
// 2) Daily standings — credit rewards + clean up, once just after midnight UTC
// =====================================================================

// Coins for a FINAL daily standing. Mirrors CoinsManager.daily_reward_for_rank.
function dailyRewardForRank(rank) {
  if (rank <= 0) return 0;
  if (rank === 1) return 500;
  if (rank === 2) return 300;
  if (rank === 3) return 150;
  if (rank <= 10) return 100;
  if (rank <= 25) return 50;
  if (rank <= 50) return 25;
  return 0;
}

// Read the top 50 of each of `date`'s daily boards and collect each uid's
// placements: uid -> { total, results:[{diff, rank, reward}] }.
async function collectPayouts(date) {
  const perUser = new Map();
  for (const diff of DIFFS) {
    const snap = await db.collection("daily_" + diff)
        .where("date", "==", date)
        .orderBy("score", "desc")
        .limit(DAILY_REWARD_N)
        .get();
    let rank = 0;
    snap.forEach((doc) => {
      rank += 1;
      const d = doc.data() || {};
      const uid = typeof d.uid === "string" ? d.uid : null;
      if (!uid) return;
      // Simulated rows (see section 2b) place on the board like anyone else —
      // that's the whole point — but they have no wallet to pay into. Skipping
      // them here avoids a pointless /users read each; creditDailyRewards would
      // bail on the missing doc anyway, so this is purely a cost saving.
      if (isSimUid(uid)) return;
      const reward = dailyRewardForRank(rank);
      if (reward <= 0) return;
      const cur = perUser.get(uid) || {total: 0, results: []};
      cur.total += reward;
      cur.results.push({diff, rank, reward});
      perUser.set(uid, cur);
    });
  }
  return perUser;
}

// Credit each winner's wallet and leave a receipt for the client popup.
// Idempotent per user via last_daily_reward_date: if that watermark is already
// at/after `date`, this user was credited (by a prior run or an old client) and
// we skip — so a retry never double-pays.
async function creditDailyRewards(date) {
  const perUser = await collectPayouts(date);
  let credited = 0;
  for (const [uid, payout] of perUser) {
    const ref = db.collection("users").doc(uid);
    const didCredit = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false; // no wallet to credit into
      const u = snap.data() || {};
      const last = typeof u.last_daily_reward_date === "string" ? u.last_daily_reward_date : "";
      if (last >= date) return false; // already credited through this day
      tx.set(ref, {
        coins: FieldValue.increment(payout.total),
        earned_coins: FieldValue.increment(payout.total),
        last_daily_reward_date: date,
        // Deep-merged, so multiple uncollected days accumulate for a player who
        // was away; the client shows and clears them on next open.
        pending_daily_rewards: {[date]: {total: payout.total, results: payout.results, date}},
      }, {merge: true});
      return true;
    });
    if (didCredit) credited += 1;
  }
  return credited;
}

// Delete every daily row for `date` (paged batch deletes). With rewards now
// credited at day-close, the old 14-day retention is unnecessary.
async function deleteDailyRows(date) {
  let deleted = 0;
  for (const diff of DIFFS) {
    const coll = db.collection("daily_" + diff);
    for (;;) {
      const snap = await coll.where("date", "==", date).limit(400).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      deleted += snap.size;
      if (snap.size < 400) break;
    }
  }
  return deleted;
}

// Delete a closed day's per-day daily histogram shards (they're only meaningful
// for that day's live board). Sweeps up to HIST_MAX_SHARD_SWEEP so a prior larger
// shard count leaves nothing behind.
async function deleteDailyHistograms(date) {
  for (const diff of DIFFS) {
    for (let k = 0; k < HIST_MAX_SHARD_SWEEP; k++) {
      await db.doc("board_hist/daily_" + diff + "_" + date + "_" + k).delete().catch(() => {});
    }
  }
}

// Runs at 00:05 UTC daily. Credit BEFORE delete so a failure leaves the rows in
// place for the retry; both steps are individually idempotent.
exports.closeDailyBoards = onSchedule(
    {schedule: "5 0 * * *", timeZone: "Etc/UTC"},
    async () => {
      const date = yesterdayUtc();
      await creditDailyRewards(date);
      await deleteDailyRows(date);
      await deleteDailyHistograms(date);
    },
);

// =====================================================================
// 2b) Simulated daily activity — keep TODAY's boards alive
// =====================================================================
//
// A brand-new day's boards open empty, and on a small player base they can stay
// that way for hours — which reads as a dead game and kills the reason to chase
// a daily rank at all. So the server itself posts the occasional score.
//
// Deliberately narrow in scope:
//   * DAILY ROWS ONLY. Nothing is written to global_{diff} (the all-time boards
//     are a permanent record and stay 100% real) and nothing is written to
//     /users — a simulated player has no wallet, no badges, no profile, no
//     presence anywhere outside the one row. Every row it writes is deleted by
//     closeDailyBoards at 00:05 UTC with the rest of that day's board, so the
//     entire footprint is gone within a day.
//   * One CANDIDATE every 37 minutes, taken with probability 1/2 — so ~19 rows
//     a day spread unevenly across the three difficulties, which is the point:
//     a board that grows in fits and starts looks lived-in, a metronome does not.
//   * Scores are drawn from a truncated Gaussian over [SIM_SCORE_MIN,
//     SIM_SCORE_MAX], i.e. clustered around the middle and rare at either end,
//     so they sit among ordinary human results instead of topping the board.
//
// The rows are written by the Admin SDK (rules bypassed) in exactly the shape a
// real client writes, so syncDaily_* picks them up and they flow into board_top
// and the per-day histogram like any other score. That matters: a row the
// clients can see but the rank arithmetic can't would make ranks disagree with
// the visible list.
//
// SIMULATED UIDS: shaped like a real Firebase uid (28 base62 chars) but with a
// keyed checksum in the last 4 characters, so the server can recognise its own
// rows without keeping a registry document (which would be exactly the kind of
// persistent state this feature is supposed not to leave behind). Used only to
// skip them in the reward pass — see collectPayouts.

const crypto = require("crypto");

// Chance that a given 37-minute slot actually posts a score.
const SIM_CHANCE = 0.5;
// Score range. Inclusive; the distribution below is a Gaussian truncated to it.
const SIM_SCORE_MIN = 4;
const SIM_SCORE_MAX = 13;
const SIM_SCORE_MEAN = (SIM_SCORE_MIN + SIM_SCORE_MAX) / 2;
// ~2 puts the bulk of the mass inside the range, so rejection sampling below
// almost always accepts on the first draw while the tails stay genuinely rare.
const SIM_SCORE_SD = 2.0;
// Longest name we'll post. Matches the player-facing limit in name_picker_screen
// (max_length = 20) so a simulated name can never be one no human could have.
const SIM_NAME_MAX = 20;
// Not a security boundary — it only tags our own rows so the reward pass can
// skip them. A player who worked it out could forge a "simulated" uid, and the
// only thing that buys them is forfeiting their own daily coins.
const SIM_UID_KEY = "simon-sim-daily-v1";
const SIM_UID_LEN = 28;
const SIM_UID_SUM_LEN = 4;
const SIM_B62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

// Each pool is ONE culture, not one region, because the pair is drawn at random
// within a pool and anything broader stitches two languages onto one person:
// a "Southeast Asian" pool produces "Minh Reyes", a "Nordic" one produces "Emil
// Virtanen". Neither is a person. Pools whose surnames inflect for gender are
// split by gender for the same reason ("Anya Ivanov" is as wrong as the above),
// or given only surnames that don't inflect at all (Polish -ak/-czyk, Ukrainian,
// Greek -ou).
//
// Latin script throughout: the game renders names in Godot's default font, which
// has no CJK / Arabic / Hebrew / Devanagari coverage, so a native-script name
// would come out as empty boxes on the board. Romanised spellings carry the same
// international feel and actually render.
//
// `w` is the pick weight. Without it, splitting one culture into finer pools
// would hand that culture a bigger share of the board purely as an artifact of
// how the table is organised. The values sketch a global casual audience.
const SIM_NAMES = [
  { // English
    w: 10,
    first: ["James", "Emma", "Liam", "Olivia", "Noah", "Ava", "Ethan", "Grace",
      "Mason", "Chloe", "Leo", "Ruby", "Owen", "Isla"],
    last: ["Walker", "Bennett", "Hughes", "Carter", "Mitchell", "Foster",
      "Brooks", "Reid", "Palmer", "Doyle"],
  },
  { // Spanish
    w: 6,
    first: ["Mateo", "Lucia", "Diego", "Sofia", "Javier", "Carmen", "Alonso",
      "Elena", "Pablo", "Ines", "Nuria", "Alvaro"],
    last: ["Garcia", "Torres", "Ramirez", "Navarro", "Delgado", "Iglesias",
      "Vargas", "Serrano", "Cabrera", "Molina"],
  },
  { // Portuguese / Brazilian
    w: 5,
    first: ["Tiago", "Beatriz", "Rafael", "Larissa", "Bruno", "Camila",
      "Vitor", "Mariana", "Caio", "Renata"],
    last: ["Silva", "Almeida", "Pereira", "Ribeiro", "Cardoso", "Barbosa",
      "Moreira", "Teixeira", "Rocha", "Pinto"],
  },
  { // French
    w: 3,
    first: ["Hugo", "Chloe", "Louis", "Manon", "Theo", "Camille", "Enzo",
      "Juliette", "Nathan", "Alice"],
    last: ["Dupont", "Lefevre", "Moreau", "Girard", "Bernard", "Fontaine",
      "Chevalier", "Marchand", "Renaud", "Leclerc"],
  },
  { // German
    w: 3,
    first: ["Lukas", "Hanna", "Jonas", "Lena", "Felix", "Mia", "Finn",
      "Greta", "Erik", "Frieda"],
    last: ["Muller", "Schneider", "Fischer", "Weber", "Wagner", "Becker",
      "Hoffmann", "Schulz", "Koehler", "Brandt"],
  },
  { // Italian
    w: 3,
    first: ["Marco", "Giulia", "Luca", "Chiara", "Matteo", "Sara", "Andrea",
      "Elisa", "Davide", "Alessia"],
    last: ["Rossi", "Ferrari", "Esposito", "Bianchi", "Romano", "Greco",
      "Conti", "Marino", "Rizzo", "Gallo"],
  },
  { // Swedish
    w: 2,
    first: ["Emil", "Freja", "Oskar", "Astrid", "Axel", "Linnea", "Elias",
      "Alva", "Viktor", "Maja"],
    last: ["Nilsson", "Lindqvist", "Bergman", "Andersson", "Karlsson",
      "Lundgren", "Sjoberg", "Ekstrom", "Holm", "Palm"],
  },
  { // Danish / Norwegian — one shared name stock, not two languages
    w: 2,
    first: ["Kasper", "Sigrid", "Mathias", "Ida", "Aksel", "Solveig",
      "Henrik", "Kristin", "Marius", "Anne"],
    last: ["Hansen", "Jensen", "Nielsen", "Solberg", "Dahl", "Berg",
      "Haugen", "Sandvik", "Iversen", "Moller"],
  },
  { // Finnish
    w: 1,
    first: ["Eero", "Aino", "Ville", "Sanni", "Onni", "Elina", "Juho",
      "Venla", "Mikael", "Helmi"],
    last: ["Virtanen", "Aalto", "Makinen", "Nieminen", "Korhonen", "Laine",
      "Heikkila", "Salminen", "Rantanen", "Koskinen"],
  },
  { // Polish — surnames here are the non-inflecting kind (no -ski/-ska pairs)
    w: 2,
    first: ["Kacper", "Zofia", "Jakub", "Lena", "Marek", "Agnieszka",
      "Piotr", "Hanna", "Bartosz", "Julia"],
    last: ["Nowak", "Wojcik", "Wozniak", "Kowalczyk", "Mazur", "Krol",
      "Kaczmarek", "Pawlak", "Michalak", "Adamczyk"],
  },
  { // Czech — masculine
    w: 1,
    first: ["Tomas", "Petr", "Jiri", "Vojtech", "Ondrej", "Martin"],
    last: ["Novak", "Svoboda", "Dvorak", "Cerny", "Prochazka", "Kucera",
      "Vesely", "Horak", "Nemec", "Bartos"],
  },
  { // Czech — feminine (surnames take -ova / -a)
    w: 1,
    first: ["Klara", "Anezka", "Tereza", "Marketa", "Barbora", "Eliska"],
    last: ["Novakova", "Svobodova", "Dvorakova", "Cerna", "Prochazkova",
      "Kucerova", "Vesela", "Horakova", "Nemcova", "Bartosova"],
  },
  { // Russian — masculine (romanised)
    w: 2,
    first: ["Dmitri", "Nikita", "Pavel", "Sergei", "Oleg", "Andrei",
      "Maksim", "Roman"],
    last: ["Ivanov", "Sokolov", "Orlov", "Zaitsev", "Popov", "Volkov",
      "Morozov", "Egorov", "Petrov", "Novikov"],
  },
  { // Russian — feminine (surnames take -ova / -ina)
    w: 2,
    first: ["Anya", "Katya", "Irina", "Yulia", "Larisa", "Marina", "Olga",
      "Svetlana"],
    last: ["Ivanova", "Sokolova", "Orlova", "Zaitseva", "Popova", "Volkova",
      "Morozova", "Egorova", "Petrova", "Novikova"],
  },
  { // Ukrainian (romanised) — these surnames don't inflect
    w: 1,
    first: ["Taras", "Vira", "Bohdan", "Oksana", "Andriy", "Yaryna",
      "Danylo", "Ivanna", "Nazar", "Sofiya"],
    last: ["Melnyk", "Kovalenko", "Bondar", "Tkachenko", "Shevchenko",
      "Kravchuk", "Boyko", "Marchenko", "Lysenko", "Kravets"],
  },
  { // Turkish
    w: 3,
    first: ["Emir", "Zeynep", "Kerem", "Elif", "Baris", "Defne", "Mert",
      "Ayse", "Onur", "Selin"],
    last: ["Yilmaz", "Demir", "Kaya", "Sahin", "Celik", "Arslan", "Dogan",
      "Aydin", "Ozturk", "Kurt"],
  },
  { // Greek (romanised) — the -ou/-a surnames, which are the same either way
    w: 1,
    first: ["Nikos", "Eleni", "Yiannis", "Katerina", "Dimitris", "Maria",
      "Stavros", "Despina"],
    last: ["Georgiou", "Ioannou", "Christou", "Antoniou", "Vasiliou",
      "Nikolaou", "Konstantinou", "Stavrou"],
  },
  { // Arabic (romanised)
    w: 3,
    first: ["Omar", "Layla", "Yousef", "Nour", "Karim", "Salma", "Tariq",
      "Rana", "Bilal", "Hala"],
    last: ["Haddad", "Nasser", "Khalil", "Farah", "Sultan", "Mansour",
      "Rahim", "Aziz", "Saleh", "Darwish"],
  },
  { // Hebrew (romanised)
    w: 3,
    first: ["Noam", "Maya", "Itai", "Shira", "Yonatan", "Talia", "Eitan",
      "Roni", "Amit", "Yael"],
    last: ["Levi", "Cohen", "Mizrahi", "Barak", "Peretz", "Shani", "Adler",
      "Golan", "Regev", "Amar"],
  },
  { // North Indian (romanised)
    w: 4,
    first: ["Arjun", "Priya", "Rohan", "Ananya", "Vikram", "Neha", "Aditya",
      "Ishaan", "Diya", "Sanjay"],
    last: ["Sharma", "Kapoor", "Chauhan", "Verma", "Malhotra", "Joshi",
      "Bhatia", "Saxena", "Chopra", "Mehra"],
  },
  { // South Indian (romanised)
    w: 3,
    first: ["Karthik", "Divya", "Aravind", "Lakshmi", "Suresh", "Anitha",
      "Vignesh", "Meera", "Ganesh", "Kavya"],
    last: ["Nair", "Reddy", "Iyer", "Menon", "Rao", "Pillai", "Naidu",
      "Krishnan", "Raman", "Varma"],
  },
  { // Japanese (romanised)
    w: 2,
    first: ["Yuki", "Haruka", "Ren", "Aoi", "Sota", "Mio", "Kaito", "Rin",
      "Daiki", "Nanami"],
    last: ["Tanaka", "Sato", "Nakamura", "Yamamoto", "Kobayashi", "Watanabe",
      "Ishikawa", "Fujimoto", "Ogawa", "Hayashi"],
  },
  { // Korean (romanised)
    w: 2,
    first: ["Minjun", "Jiwoo", "Seoyeon", "Hyun", "Jisoo", "Doyun", "Haeun",
      "Sunwoo", "Yuna", "Taemin"],
    last: ["Kim", "Park", "Lee", "Choi", "Jung", "Kang", "Yoon", "Lim",
      "Shin", "Oh"],
  },
  { // Chinese (romanised)
    w: 3,
    first: ["Wei", "Lian", "Hao", "Xiuying", "Jun", "Meilin", "Feng", "Yan",
      "Bo", "Ting"],
    last: ["Chen", "Wang", "Liu", "Zhang", "Huang", "Zhao", "Wu", "Lin",
      "Xu", "Guo"],
  },
  { // Vietnamese (romanised)
    w: 2,
    first: ["Minh", "Linh", "Thanh", "Huong", "Tuan", "Mai", "Hieu",
      "Trang", "Duc", "Ngoc"],
    last: ["Nguyen", "Tran", "Pham", "Hoang", "Vu", "Dang", "Bui", "Do",
      "Ngo", "Ly"],
  },
  { // Indonesian
    w: 3,
    first: ["Rizky", "Nadia", "Bayu", "Intan", "Andi", "Sari", "Dimas",
      "Putri", "Agus", "Ayu"],
    last: ["Wijaya", "Santoso", "Kusuma", "Hidayat", "Pratama", "Setiawan",
      "Wibowo", "Nugroho", "Halim", "Suparman"],
  },
  { // Thai (romanised)
    w: 2,
    first: ["Ploy", "Chai", "Nok", "Somchai", "Pim", "Anon", "Kwan",
      "Fah", "Wichai", "Ratana"],
    last: ["Sukhum", "Wongchai", "Srisai", "Thongdee", "Boonmee",
      "Saengthong", "Kittisak", "Phanit", "Rattana", "Chaidee"],
  },
  { // Filipino
    w: 3,
    first: ["Andres", "Maricel", "Jomar", "Liza", "Paolo", "Angelica",
      "Nico", "Cristina", "Ramon", "Divina"],
    last: ["Reyes", "Santos", "Bautista", "Ramos", "Mendoza", "Aquino",
      "Villanueva", "Domingo", "Salazar", "Dela Cruz"],
  },
  { // Nigerian — Igbo
    w: 1,
    first: ["Chinedu", "Adaeze", "Emeka", "Ngozi", "Obinna", "Chioma",
      "Kelechi", "Amara", "Ikenna", "Uche"],
    last: ["Okafor", "Okonkwo", "Eze", "Nwosu", "Chukwu", "Obi",
      "Nwachukwu", "Anyanwu", "Okeke", "Ezeani"],
  },
  { // Nigerian — Yoruba
    w: 1,
    first: ["Tunde", "Yewande", "Segun", "Folake", "Femi", "Kemi", "Dayo",
      "Bisi", "Wale", "Titi"],
    last: ["Adeyemi", "Balogun", "Adebayo", "Afolabi", "Ogunleye",
      "Bankole", "Olaniyi", "Adesina", "Oyelaran", "Fashola"],
  },
  { // Ghanaian — Akan
    w: 1,
    first: ["Kwame", "Akosua", "Kofi", "Ama", "Yaw", "Abena", "Kwesi",
      "Adwoa", "Nana", "Efua"],
    last: ["Mensah", "Osei", "Boateng", "Owusu", "Asante", "Agyeman",
      "Amponsah", "Darko", "Ofori", "Addo"],
  },
  { // Kenyan — Kikuyu
    w: 1,
    first: ["Njeri", "Wanjiku", "Muthoni", "Wairimu", "Nyokabi", "Wangari",
      "Njoki", "Wambui"],
    last: ["Mwangi", "Kamau", "Kariuki", "Njoroge", "Maina", "Githinji",
      "Waweru", "Macharia"],
  },
  { // South African — Zulu
    w: 1,
    first: ["Sipho", "Zanele", "Thabo", "Nomsa", "Bongani", "Thandiwe",
      "Sibusiso", "Mandla", "Nandi", "Themba"],
    last: ["Dlamini", "Nkosi", "Zulu", "Mkhize", "Ndlovu", "Khumalo",
      "Mthembu", "Ngcobo", "Sithole", "Zwane"],
  },
  { // West African — Senegal / Mali
    w: 1,
    first: ["Fatou", "Amadou", "Aminata", "Ousmane", "Mariama", "Ibrahima",
      "Awa", "Moussa", "Bineta", "Cheikh"],
    last: ["Diallo", "Traore", "Ndiaye", "Keita", "Diop", "Cisse", "Toure",
      "Sarr", "Camara", "Fofana"],
  },
  { // Ethiopian
    w: 1,
    first: ["Abebe", "Selam", "Dawit", "Meron", "Yonas", "Hanna", "Tigist",
      "Biruk", "Kidist", "Samuel"],
    last: ["Tesfaye", "Girma", "Bekele", "Haile", "Mekonnen", "Alemu",
      "Desta", "Getachew", "Assefa", "Wolde"],
  },
];

function simPick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

// Weighted pick over SIM_NAMES — see the `w` note on the table.
function simPickLocale() {
  let total = 0;
  for (const l of SIM_NAMES) total += l.w;
  let r = Math.random() * total;
  for (const l of SIM_NAMES) {
    r -= l.w;
    if (r < 0) return l;
  }
  return SIM_NAMES[SIM_NAMES.length - 1];
}

// A first name, most of the time with a surname from the SAME pool. Two shapes
// only, and both are shapes a real person types into the name picker:
//   * no initials — "Talia A." reads as a name half-finished in a second
//     alphabet, and it was the single biggest tell on the board;
//   * no handles — no digits, no "josh123". The picker asks for a name, and
//     inventing usernames would put a kind of player on the board that this
//     game's own sign-up flow can't produce.
// The mix of full names and bare first names is the point: a board where every
// row is "First Last" is as obviously generated as one where none of them are.
function simName() {
  const locale = simPickLocale();
  const first = simPick(locale.first);
  if (Math.random() < 0.35) return first;
  const full = first + " " + simPick(locale.last);
  // Over the player-facing limit: drop the surname rather than clip it, since a
  // half-surname is its own kind of tell.
  return full.length > SIM_NAME_MAX ? first : full;
}

// Standard normal via Box-Muller.
function simGaussian() {
  let u = 0;
  while (u === 0) u = Math.random(); // log(0) guard
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * Math.random());
}

// A score in [SIM_SCORE_MIN, SIM_SCORE_MAX] from a Gaussian TRUNCATED to that
// range (redraw on a miss) rather than clamped to it — clamping would pile every
// tail draw onto the two end values, so 4 and 13 would end up the two most common
// scores on the board, which is the opposite of what a bell curve should look like.
function simScore() {
  for (let i = 0; i < 32; i++) {
    const v = Math.round(SIM_SCORE_MEAN + simGaussian() * SIM_SCORE_SD);
    if (v >= SIM_SCORE_MIN && v <= SIM_SCORE_MAX) return v;
  }
  return Math.round(SIM_SCORE_MEAN);
}

// base62 checksum of `body`, keyed so it isn't reproducible from the app.
function simChecksum(body) {
  const mac = crypto.createHmac("sha256", SIM_UID_KEY).update(body).digest();
  let out = "";
  for (let i = 0; i < SIM_UID_SUM_LEN; i++) out += SIM_B62[mac[i] % SIM_B62.length];
  return out;
}

function simUid() {
  const bytes = crypto.randomBytes(SIM_UID_LEN - SIM_UID_SUM_LEN);
  let body = "";
  for (const b of bytes) body += SIM_B62[b % SIM_B62.length];
  return body + simChecksum(body);
}

// True for a uid this function minted. A real Firebase uid passes the length
// test but only matches the checksum with probability 62^-4 (~1 in 15 million),
// and the only consequence of that collision is one player missing one day's
// daily coins — no data loss, nothing permanent.
function isSimUid(uid) {
  if (typeof uid !== "string" || uid.length !== SIM_UID_LEN) return false;
  const body = uid.slice(0, SIM_UID_LEN - SIM_UID_SUM_LEN);
  return uid.slice(-SIM_UID_SUM_LEN) === simChecksum(body);
}

// Mirrors LeaderboardManager.submit_score_daily's expiry so a simulated row is
// swept by exactly the same paths as a real one if closeDailyBoards ever lags.
const SIM_DAILY_RETENTION_DAYS = 14;
const SIM_DAILY_EXPIRES_BUFFER_SECS = 6 * 3600;

function nextMidnightUtc(nowU) {
  return (Math.floor(nowU / 86400) + 1) * 86400;
}

// One 37-minute slot: coin-flip, then (maybe) one row on one difficulty.
exports.simulateDailyScore = onSchedule(
    {schedule: "every 37 minutes", timeZone: "Etc/UTC"},
    async () => {
      if (Math.random() >= SIM_CHANCE) return;
      const diff = simPick(DIFFS);
      const date = todayUtc();
      const uid = simUid();
      const nowU = nowUnix();
      const expiresU = nextMidnightUtc(nowU) +
        SIM_DAILY_RETENTION_DAYS * 86400 + SIM_DAILY_EXPIRES_BUFFER_SECS;
      // Same field set, same doc-id shape (`{date}__{uid}`) as a client write, so
      // every downstream reader (syncDaily_*, board_top, the histogram, the
      // client's own date filter and expiry sweep) treats it identically.
      await db.doc("daily_" + diff + "/" + date + "__" + uid).set({
        uid,
        name: simName(),
        score: simScore(),
        date,
        expires_at: new Date(expiresU * 1000).toISOString().replace(/\.\d{3}Z$/, "Z"),
        expires_unix: expiresU,
      });
    },
);

// =====================================================================
// 3) Arena live rooms — materialized room state, lobby index, expiry sweep
// =====================================================================
//
// Two hot, client-WRITTEN docs used to be client-WATCHED too, so every write
// fanned out a read to every watcher: the room doc (up to 45 members on the
// results board) and the 5-shard lobby index (every browser). We break that
// overlap the same way board_top did — a Cloud Function is the SOLE writer of
// read-only docs the updated client watches/reads, and it COALESCES so a burst
// of raw writes becomes a handful of pushes:
//
//   contests/{cid}       (UNCHANGED — clients still merge-write their own player
//                         key here, so mixed old/new-version rooms still see each
//                         other and the existing rules/paths keep working)
//              -- CF derives -->
//   contest_state/{cid}  read-only summary the updated client WATCHES instead of
//                        the raw room. Status flips (start / finish) flush
//                        instantly; roster/score bursts collapse to ~1 push per
//                        COALESCE window; a keepalive/expiry-only write produces
//                        an identical summary and is gated out (no fan-out).
//   lobby_index/open     the WHOLE open-public-room list in ONE doc; the updated
//                        client READS it once per Refresh (1 read for the list)
//                        instead of holding 5 live shard listeners.
//
// ROLLOUT COMPAT: already-released clients keep watching contests/{cid} and the
// lobby/s{N} shards and pay the old cost among themselves — nothing here touches
// them. The savings land when users update to the Stage-2 client.

// Roster/score bursts on a room collapse to at most one contest_state push per
// this many seconds; status transitions ignore it and flush immediately.
const CONTEST_STATE_COALESCE_SECS = 3;
// Bounds one expiry-sweep pass. Rooms are short-lived, so this rarely fills.
const ROOM_TTL_SWEEP_LIMIT = 200;

// A room is listed in the public lobby only while it's an open, public lobby.
function contestOpenForLobby(d) {
  return !!d && d.is_public === true && d.status === "lobby";
}

// The read-only summary clients watch. A near-mirror of the room doc MINUS the
// volatile expiry/keepalive fields — so a keepalive-only write yields an
// identical summary and gets gated out below (never reaching watchers).
function shapeContestState(cid, d) {
  const players = {};
  const src = (d && typeof d.players === "object" && d.players) || {};
  for (const uid of Object.keys(src)) {
    const p = src[uid] || {};
    players[uid] = {
      name: typeof p.name === "string" ? p.name : "Player",
      is_creator: p.is_creator === true,
      joined_at: Number.isFinite(p.joined_at) ? p.joined_at : 0,
      state: typeof p.state === "string" ? p.state : "lobby",
      score: Number.isFinite(p.score) ? p.score : 0,
      finished_at: Number.isFinite(p.finished_at) ? p.finished_at : 0,
    };
  }
  return {
    id: cid,
    title: typeof d.title === "string" ? d.title : "Contest",
    creator_uid: typeof d.creator_uid === "string" ? d.creator_uid : "",
    creator_name: typeof d.creator_name === "string" ? d.creator_name : "",
    difficulty: typeof d.difficulty === "string" ? d.difficulty : "easy",
    is_public: d.is_public === true,
    status: typeof d.status === "string" ? d.status : "lobby",
    seed: Number.isFinite(d.seed) ? d.seed : 0,
    member_count: Number.isFinite(d.member_count) ? d.member_count : 0,
    started_at: Number.isFinite(d.started_at) ? d.started_at : 0,
    finished_at: Number.isFinite(d.finished_at) ? d.finished_at : 0,
    // The host ended the room (contest_manager.gd _close_room). It rides on top of
    // status "finished" and MUST be mirrored: it is the only thing distinguishing
    // "the host closed this" from "the race ran to its end", and the client renders
    // it as the room's closing message. Dropping it here would leave every watcher
    // on a podium of zeroes instead.
    cancelled: d.cancelled === true,
    players,
  };
}

// Order-independent serialization of a summary for the "did anything visible
// change?" gate. Firestore doesn't guarantee map key order on read-back, so we sort
// the players by uid and emit fixed field order (same idea as serializeList above) —
// otherwise a keepalive/expiry-only write could look "changed" and needlessly push.
function stableContestKey(s) {
  const players = Object.keys(s.players || {}).sort().map((u) => {
    const p = s.players[u];
    return [u, p.state, p.score, p.finished_at, p.name, p.is_creator, p.joined_at];
  });
  return JSON.stringify([
    s.status, s.seed, s.member_count, s.started_at, s.finished_at,
    s.title, s.creator_uid, s.difficulty, s.is_public, s.cancelled, players,
  ]);
}

// Publish a summary, but ONLY if the mirror doesn't already hold a NEWER revision of
// the room. Firestore triggers carry no ordering guarantee and each invocation is a
// read-then-write against this doc, so two events fired back to back — the last
// racer's score write, then the "status: finished" write that immediately follows it —
// can be processed out of order or interleaved. When that happened the older event's
// summary landed last and pinned the mirror at "playing" with nothing left to write
// the room again: every player who had already finished sat on the waiting board until
// their client's watchdog re-read the room (~45s) while the last finisher was looking
// at the podium. `updateTime` on the room doc is its authoritative revision stamp, so
// carrying it here lets us move the mirror forwards only, and the transaction makes
// the check-and-set atomic against a concurrent invocation.
async function publishContestState(ref, summary, srcRev) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const stored = snap.exists ? snap.data() : null;
    if (stored && Number.isFinite(stored.src_rev) &&
        stored.src_rev >= srcRev) return;            // overtaken by a newer revision
    // Identical content: nothing to publish. We deliberately DON'T bump src_rev on
    // its own — that write would still wake every watcher for no visible change,
    // which is the whole cost this gate exists to avoid.
    if (stored && stored.summary &&
        stableContestKey(stored.summary) === stableContestKey(summary)) return;
    tx.set(ref, {summary, updated_unix: nowUnix(), src_rev: srcRev});
  });
}

// A document revision as one comparable number: microseconds since the epoch, taken
// from its commit time. Microseconds (not millis) so two commits landing in the same
// millisecond still order — and it stays well inside a double's exact-integer range.
function revOf(snap) {
  const t = snap && snap.updateTime;
  return t ? t.seconds * 1e6 + Math.floor(t.nanoseconds / 1000) : Date.now() * 1000;
}

// Maintain contest_state/{cid} from a room write, coalescing so we don't push
// on every raw write. `srcRev` is the room revision this event carries (see
// publishContestState).
async function maintainContestState(cid, after, srcRev) {
  const ref = db.collection("contest_state").doc(cid);
  if (!after) {
    // Room gone → drop its mirror.
    await ref.delete().catch(() => {});
    return;
  }
  const summary = shapeContestState(cid, after);
  const snap = await ref.get();
  const stored = snap.exists ? snap.data() : null;
  const prev = stored ? stored.summary : null;
  // Already mirrored this revision or a later one — nothing this event can add.
  if (stored && Number.isFinite(stored.src_rev) && stored.src_rev >= srcRev) return;

  // Start (seed set) and finish (status flip) must be visible instantly — that's
  // what auto-launches every client's match / reveals the final board.
  const transition = !prev || prev.status !== summary.status
      || prev.seed !== summary.seed;
  if (!transition) {
    // No visible change (e.g. a host keepalive / expiry-only write) → skip, so
    // it never fans out to a single watcher.
    if (prev && stableContestKey(prev) === stableContestKey(summary)) return;
    // Coalesce roster/score bursts to ~one push per window.
    const age = nowUnix() - ((stored && stored.updated_unix) || 0);
    if (age < CONTEST_STATE_COALESCE_SECS) {
      // ...but the LAST write of a burst must not be the one that's dropped. Nothing
      // else is coming to flush it, so a player who joined as the third of three
      // within the window would stay invisible to everyone until some unrelated write
      // happened to touch the room. Wait out the window and publish the room as it
      // stands THEN — re-read from the source rather than replaying our own (by then
      // possibly superseded) snapshot, so concurrent skippers all converge on the
      // truth and whoever gets there first makes the rest a no-op.
      await sleep((CONTEST_STATE_COALESCE_SECS - age) * 1000);
      const fresh = await db.collection("contests").doc(cid).get();
      if (!fresh.exists) return;          // gone meanwhile — the delete event cleans up
      // The re-read carries its own (newer) revision stamp — publish under THAT, not
      // this event's, or the flush would be gated out by the very state it just read.
      await publishContestState(ref, shapeContestState(cid, fresh.data()),
          revOf(fresh));
      return;
    }
  }
  await publishContestState(ref, summary, srcRev);
}

// Maintain the one-doc open-public-room list. Touched ONLY when a room ENTERS or
// LEAVES the lobby (open / started / cancelled / emptied) — never on a mere
// player-count bump (live counts are given up; clients refresh them). Entries
// keep o=created_at so the client filters liveness by the same
// now < o + START_WINDOW predicate the shards use, and the sweep prunes them.
async function maintainLobbyIndex(cid, before, after) {
  const wasOpen = contestOpenForLobby(before);
  const isOpen = contestOpenForLobby(after);
  if (wasOpen === isOpen) return;   // no presence change → leave the list alone
  const ref = db.collection("lobby_index").doc("open");
  if (isOpen) {
    await ref.set({rooms: {[cid]: {
      t: typeof after.title === "string" ? after.title : "Contest",
      d: typeof after.difficulty === "string" ? after.difficulty : "easy",
      c: Number.isFinite(after.member_count) ? after.member_count : 1,
      o: Number.isFinite(after.created_at) ? after.created_at : nowUnix(),
      u: typeof after.creator_uid === "string" ? after.creator_uid : "",
    }}, updated_unix: nowUnix()}, {merge: true});
  } else {
    await ref.set(
        {rooms: {[cid]: FieldValue.delete()}, updated_unix: nowUnix()},
        {merge: true});
  }
}

// One trigger drives both derived docs. It writes contest_state/{cid} and
// lobby_index/open — neither re-triggers contests, so there's no loop.
exports.syncContest = onDocumentWritten("contests/{cid}", async (event) => {
  const cid = event.params.cid;
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  // The room revision this event was fired for. Ordering token, not a clock — see
  // publishContestState.
  const srcRev = revOf(event.data.after);
  await Promise.all([
    maintainContestState(cid, after, srcRev),
    maintainLobbyIndex(cid, before, after),
  ]);
});

// Reap abandoned rooms (opened / mid-race but never emptied — app killed, network
// drop). Replaces BOTH the client-side sweep and the per-member keepalive: only
// the host now heartbeats expires_unix, and this deletes anything past it. Each
// delete re-triggers syncContest(after=null), which clears that room's
// contest_state and lobby_index entry.
exports.sweepExpiredRooms = onSchedule({schedule: "every 15 minutes"}, async () => {
  const snap = await db.collection("contests")
      .where("expires_unix", "<", nowUnix())
      .limit(ROOM_TTL_SWEEP_LIMIT)
      .get();
  if (!snap.empty) {
    const batch = db.batch();
    snap.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  await sweepOrphanState();
  await pruneLobbyIndex();
});

// A room write and the delete that follows it are two SEPARATE trigger invocations
// with NO ordering guarantee, so the delete's cleanup can run first and the earlier
// write then re-creates the mirror of a room that no longer exists — a doc nothing
// will ever touch again. Same story for a lobby_index entry re-added by a late
// create event. Neither is visible to players (clients filter both by liveness), but
// both leak forever, so the scheduled sweep collects them.
const STATE_ORPHAN_AGE_SECS = 30 * 60;
// Bounds the orphan pass. The query also matches LIVE long-running rooms' mirrors
// (each costs one existence read to clear), so keep it small — orphans are rare and
// the pass runs every 15 minutes, which drains a backlog quickly enough.
const STATE_ORPHAN_LIMIT = 50;
// Mirrors how long a public room stays listed (START_WINDOW in contest_manager.gd):
// an entry older than this is dead by the same predicate every client applies.
const LOBBY_ENTRY_TTL_SECS = 5 * 60;

async function sweepOrphanState() {
  const snap = await db.collection("contest_state")
      .where("updated_unix", "<", nowUnix() - STATE_ORPHAN_AGE_SECS)
      .limit(STATE_ORPHAN_LIMIT)
      .get();
  if (snap.empty) return;
  for (const doc of snap.docs) {
    const room = await db.collection("contests").doc(doc.id).get();
    if (!room.exists) await doc.ref.delete().catch(() => {});
  }
}

// The dead keys of a lobby `rooms` map: everything no client would list, by the very
// predicate they all apply (o > 0 && now < o + START_WINDOW). Values are
// FieldValue.delete(), so the result merges straight in — and a MERGE naming only
// dead keys is the point: a full rewrite would drop a room claimed in the window
// between the read and the write, which is the race the client-side compaction always
// carried.
function deadLobbyKeys(rooms) {
  const cutoff = nowUnix() - LOBBY_ENTRY_TTL_SECS;
  const dead = {};
  for (const [cid, e] of Object.entries(rooms || {})) {
    // <= , not < : the clients drop an entry the moment now >= o + START_WINDOW, so
    // one sitting exactly on the boundary is already dead to every reader.
    if (!e || !Number.isFinite(e.o) || e.o <= cutoff) dead[cid] = FieldValue.delete();
  }
  return dead;
}

async function pruneLobbyIndex() {
  const ref = db.collection("lobby_index").doc("open");
  const snap = await ref.get();
  if (!snap.exists) return;
  const dead = deadLobbyKeys((snap.data() || {}).rooms);
  if (Object.keys(dead).length === 0) return;
  await ref.set({rooms: dead, updated_unix: nowUnix()}, {merge: true});
}

// Reclaim dead keys from the LEGACY 5-shard lobby index (lobby/s{N}).
//
// Clients still write it — create_contest claims a slot and start/cancel/leave
// tombstone the entry to o=0, because a merge write can't delete a map key — but the
// compaction that used to reclaim those keys ran from watch_lobby(), and the Stage-2
// client never takes that path any more (it reads lobby_index/open instead). So the
// shards only ever grow. Nothing player-visible: every reader filters by the liveness
// predicate above. But the keys are real clutter, and a shard that fills up with them
// costs the next host a compacting rewrite to claim a slot (_lobby_pick_shard).
//
// Cheap enough to be lazy about: 5 reads and at most 5 writes per pass, and an entry
// is only listable for START_WINDOW anyway, so a few hours of junk hurts nobody.
exports.sweepLobbyShards = onSchedule({schedule: "every 3 hours"}, async () => {
  const snap = await db.collection("lobby").get();
  for (const doc of snap.docs) {
    const dead = deadLobbyKeys((doc.data() || {}).rooms);
    if (Object.keys(dead).length === 0) continue;
    await doc.ref.set({rooms: dead}, {merge: true});
  }
});

// =====================================================================
// Manual heal / seed — full recompute of both board_top docs
// =====================================================================

async function topRows(collection, dateEq) {
  let q = db.collection(collection);
  if (dateEq) q = q.where("date", "==", dateEq);
  q = q.orderBy("score", "desc").limit(TOP_N);
  const snap = await q.get();
  const rows = [];
  snap.forEach((doc) => {
    const d = doc.data() || {};
    const uid = typeof d.uid === "string" ? d.uid : doc.id;
    rows.push({
      uid,
      name: typeof d.name === "string" ? d.name : "Player",
      score: typeof d.score === "number" ? d.score : 0,
    });
  });
  return rows;
}

async function rebuildAll() {
  const gBoards = {};
  for (const diff of DIFFS) gBoards[diff] = await topRows("global_" + diff, null);
  await db.collection("board_top").doc("global").set({boards: gBoards, updated_unix: nowUnix()});

  const date = todayUtc();
  const dBoards = {};
  for (const diff of DIFFS) dBoards[diff] = await topRows("daily_" + diff, date);
  await db.collection("board_top").doc("daily").set({date, boards: dBoards, updated_unix: nowUnix()});
}

// Rebuild both board_top docs from the authoritative rows. Safe any time — use
// it to seed after first deploy or to heal drift.
exports.rebuildLeaderboardsNow = onRequest(async (_req, res) => {
  await rebuildAll();
  res.status(200).send("board_top/global and board_top/daily rebuilt.\n");
});

// ---- histogram rebuild (global + today's daily) ---------------------------

// Full re-tally of a board's scores into { "<score>": count }.
async function tallyScores(collection, dateEq) {
  const counts = {};
  let q = db.collection(collection);
  if (dateEq) q = q.where("date", "==", dateEq);
  const snap = await q.get();
  snap.forEach((doc) => {
    const s = scoreOf(doc.data());
    if (s > 0) counts[s] = (counts[s] || 0) + 1;
  });
  return counts;
}

// Overwrite a histogram from an authoritative tally: shard 0 gets the whole
// tally, shards 1..HIST_SHARDS-1 are emptied, and any higher shards left from a
// previous larger HIST_SHARDS are deleted (so a lowered count leaves nothing
// unread behind). Reads sum across shards, so one loaded shard is correct.
async function writeHistogram(board, counts) {
  const fields0 = {};
  for (const [score, c] of Object.entries(counts)) fields0[String(score)] = c;
  await db.doc(histShardName(board, 0)).set({counts: fields0});
  for (let k = 1; k < HIST_SHARDS; k++) {
    await db.doc(histShardName(board, k)).set({counts: {}});
  }
  for (let k = HIST_SHARDS; k < HIST_MAX_SHARD_SWEEP; k++) {
    await db.doc(histShardName(board, k)).delete().catch(() => {});
  }
}

async function rebuildHistograms() {
  const summary = {};
  const date = todayUtc();
  for (const diff of DIFFS) {
    const g = await tallyScores("global_" + diff, null);
    await writeHistogram("global_" + diff, g);
    summary["global_" + diff] = Object.values(g).reduce((a, b) => a + b, 0);

    const d = await tallyScores("daily_" + diff, date);
    await writeHistogram("daily_" + diff + "_" + date, d);
    summary["daily_" + diff + "_" + date] = Object.values(d).reduce((a, b) => a + b, 0);
  }
  return summary;
}

// Rebuild every histogram (all-time + today's daily) from the authoritative rows.
// Run after changing HIST_SHARDS, or to heal drift. Returns {board: rowCount}.
exports.rebuildHistogramsNow = onRequest(async (_req, res) => {
  const summary = await rebuildHistograms();
  res.status(200).json(summary);
});
