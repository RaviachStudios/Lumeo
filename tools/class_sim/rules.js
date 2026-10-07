// Class Game rules — a hand-kept MIRROR of class_rules.gd. The simulator's bots and
// bot teacher must time rounds exactly like the app does, or the phone under test
// will (correctly) count them out. Change a number in class_rules.gd -> change it here.
"use strict";

const VERSION = 2;
const MAX_ROUNDS = 15;
const ROUND_CHOICES = [10, 15];
const DEFAULT_ROUNDS = 15;
const validRounds = (n) => (ROUND_CHOICES.includes(n) ? n : DEFAULT_ROUNDS);
const MAX_STUDENTS = 45;
const MIN_STUDENTS = 2;
const SHARDS = 5;
const LIMITS = [10.0, 14.0, 18.0];
const BANNER_FIRST = 4.0;
const BANNER_NEXT = 1.5;
const PRE_SEQUENCE = 0.6;
const SLACK = 6.0;
const LATE_LIMIT = 4.5;
const HARD_FLASH = 0.42;
const HARD_GAP = 0.13;
const HARD_SPEED_INC = 0.038;
const LOBBY_TTL = 60 * 60;
const LOBBY_REFRESH_BELOW = 10 * 60;
const PLAY_TTL = 30 * 60;
const DONE_TTL = 10 * 60;
const MAX_POINTS = 100;

const limit = (r) => LIMITS[Math.min(Math.max(Math.floor((r - 1) / 5), 0), LIMITS.length - 1)];
const banner = (r) => (r <= 1 ? BANNER_FIRST : BANNER_NEXT);
const flashTime = (r) => Math.max(0.18, HARD_FLASH - (r - 1) * HARD_SPEED_INC);
const flashGap = (r) => Math.max(0.08, HARD_GAP - (r - 1) * HARD_SPEED_INC * 0.5);
const playback = (r) => PRE_SEQUENCE + r * (flashTime(r) + flashGap(r));
const deadlineMs = (roundAtMs, r) =>
  roundAtMs + Math.trunc((banner(r) + playback(r) + limit(r) + SLACK) * 1000);
const expectedEndMs = (roundAtMs, r) =>
  roundAtMs + Math.trunc((banner(r) + playback(r) + limit(r)) * 1000);

function points(timeLeft, lim) {
  if (lim <= 0) return 1;
  const v = Math.ceil(MAX_POINTS * Math.min(Math.max(timeLeft, 0), lim) / lim);
  return Math.min(Math.max(v, 1), MAX_POINTS);
}

// Same polynomial hash as ClassRules.shard_of (NOT String.hash()).
function shardOf(uid) {
  let h = 0;
  for (const ch of uid) h = (h * 31 + ch.codePointAt(0)) % 1000003;
  return h % SHARDS;
}
const shardId = (pid, k) => `${pid}_${k}`;

// rows: [{uid, n, s, c, t}] -> sorted by score, then rounds completed, then time;
// adds p (shared place on exact ties).
function rank(rows) {
  const out = rows.map((e) => ({...e}));
  out.sort((a, b) => (b.s - a.s) || (b.c - a.c) || (a.t - b.t) || (a.n < b.n ? -1 : a.n > b.n ? 1 : 0));
  out.forEach((e, i) => {
    const prev = out[i - 1];
    e.p = (i > 0 && prev.c === e.c && prev.s === e.s && prev.t === e.t) ? prev.p : i + 1;
  });
  return out;
}

module.exports = {
  VERSION, MAX_ROUNDS, ROUND_CHOICES, DEFAULT_ROUNDS, validRounds, MAX_POINTS, MAX_STUDENTS, MIN_STUDENTS, SHARDS, SLACK, LATE_LIMIT,
  LOBBY_TTL, LOBBY_REFRESH_BELOW, PLAY_TTL, DONE_TTL,
  limit, banner, playback, deadlineMs, expectedEndMs, points, shardOf, shardId, rank,
};
