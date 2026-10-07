// The Class Game referee — a MIRROR of class_referee.gd, used by the simulator's bot
// teacher (so the phone can be tested as a STUDENT). Pure logic: fed the class doc
// and the five report shards, returns the merge-write to make (or {}).
"use strict";
const R = require("./rules");

const statusRank = (s) => ({lobby: 0, playing: 1, finished: 2, cancelled: 2}[s] ?? -1);

class Referee {
  constructor(pid, doc) {
    this.pid = pid;
    this.doc = JSON.parse(JSON.stringify(doc));
    this.rows = {};          // uid -> row (+ k)
    this.shardsSeen = new Set();
  }

  get synced() { return this.shardsSeen.size >= R.SHARDS; }

  setShard(k, players) {
    for (const uid of Object.keys(this.rows)) if (this.rows[uid].k === k) delete this.rows[uid];
    for (const [uid, row] of Object.entries(players || {})) this.rows[uid] = {...row, k};
    this.shardsSeen.add(k);
  }

  apply(w) {
    for (const [k, v] of Object.entries(w)) {
      if (v && typeof v === "object" && !Array.isArray(v) && this.doc[k] && typeof this.doc[k] === "object") {
        this.doc[k] = {...this.doc[k], ...v};
      } else {
        this.doc[k] = v;
      }
    }
  }

  status() { return this.doc.status || ""; }
  kicked() { return this.doc.kicked || {}; }
  roster() { return this.doc.roster || {}; }
  out() { return this.doc.out || {}; }
  isKicked(uid) { return uid in this.kicked(); }

  lobbyStudents() {
    const out = [];
    for (const [uid, row] of Object.entries(this.rows)) {
      if (row.st !== "lobby" || this.isKicked(uid) || uid === this.doc.teacher_uid) continue;
      out.push({uid, n: row.n || "Student", j: row.j || 0});
    }
    out.sort((a, b) => (a.j - b.j) || (a.uid < b.uid ? -1 : 1));
    return out;
  }

  lobbyUpkeep(nowUnix) {
    if (this.status() !== "lobby") return {};
    const w = {};
    const full = this.lobbyStudents().length >= R.MAX_STUDENTS;
    if (full !== !!this.doc.full) w.full = full;
    if ((this.doc.expires_unix || 0) - nowUnix < R.LOBBY_REFRESH_BELOW) w.expires_unix = nowUnix + R.LOBBY_TTL;
    return w;
  }

  start(nowMs, nowUnix, seed) {
    if (this.status() !== "lobby") return {error: "not_lobby"};
    const waiting = this.lobbyStudents();
    if (waiting.length < R.MIN_STUDENTS) return {error: "too_few"};
    const roster = {};
    for (const e of waiting.slice(0, R.MAX_STUDENTS)) {
      roster[e.uid] = {n: e.n, d: (this.rows[e.uid] || {}).d || ""};
    }
    return {
      status: "playing", started_at: nowUnix, seed, roster, round: 1,
      round_at_ms: nowMs, alive: Object.keys(roster).length, expires_unix: nowUnix + R.PLAY_TTL,
    };
  }

  aliveUids() { const o = this.out(); return Object.keys(this.roster()).filter((u) => !(u in o)); }

  answer(uid, r) {
    const row = this.rows[uid];
    if (!row) return "pending";
    if (row.st === "out" || row.st === "left") return "failed";
    if ((row.r || 0) >= r) return "done";
    return "pending";
  }

  currentDeadlineMs() { return R.deadlineMs(this.doc.round_at_ms || 0, this.doc.round || 1); }

  progress() {
    const r = this.doc.round || 0;
    const alive = this.aliveUids();
    let done = 0; let failed = 0;
    for (const u of alive) { const a = this.answer(u, r); if (a === "done") done++; else if (a === "failed") failed++; }
    return {round: r, alive: alive.length, done, failed, pending: alive.length - done - failed,
      out: Object.keys(this.out()).length};
  }

  tick(nowMs, nowUnix) {
    if (this.status() !== "playing" || !this.synced) return {};
    const r = this.doc.round || 0;
    if (r <= 0) return {};
    const alive = this.aliveUids();
    const allAnswered = alive.every((u) => this.answer(u, r) !== "pending");
    if (!allAnswered && nowMs < this.currentDeadlineMs()) return {};
    const newOut = {}; const survivors = [];
    for (const u of alive) { if (this.answer(u, r) === "done") survivors.push(u); else newOut[u] = r; }
    if (survivors.length <= 1 || r >= R.MAX_ROUNDS) {
      const w = this.finishWrite({...this.out(), ...newOut}, r, nowUnix);
      if (Object.keys(newOut).length) w.out = newOut;
      w.alive = survivors.length;
      return w;
    }
    // Never send an empty map: in a Firestore merge an empty map REPLACES the field.
    const nw = {round: r + 1, round_at_ms: nowMs, alive: survivors.length, expires_unix: nowUnix + R.PLAY_TTL};
    if (Object.keys(newOut).length) nw.out = newOut;
    return nw;
  }

  endNow(nowUnix) {
    if (this.status() !== "playing") return {};
    const w = this.finishWrite(this.out(), this.doc.round || 0, nowUnix);
    w.ended_early = true;
    return w;
  }

  kick(uid, nowUnix) {
    const w = {kicked: {[uid]: true}};
    if (this.status() === "playing" && uid in this.roster() && !(uid in this.out())) {
      const r = this.doc.round || 1;
      w.out = {[uid]: r};
      w.alive = Math.max(0, this.aliveUids().length - 1);
      if (this.aliveUids().length - 1 <= 1) {
        const f = this.finishWrite({...this.out(), [uid]: r}, r, nowUnix, {[uid]: true});
        return {...f, kicked: w.kicked, out: w.out, alive: w.alive};
      }
    }
    if (this.status() === "lobby") w.expires_unix = Math.max(this.doc.expires_unix || 0, nowUnix + 60);
    return w;
  }

  cancel(nowUnix) {
    return {status: "cancelled", finished_at: nowUnix, expires_unix: nowUnix + R.DONE_TTL};
  }

  finishWrite(finalOut, curRound, nowUnix, alsoKicked = {}) {
    const list = [];
    for (const [uid, e] of Object.entries(this.roster())) {
      if (this.isKicked(uid) || uid in alsoKicked) continue;
      const row = this.rows[uid] || {};
      const rr = row.r || 0; let s = row.s || 0; let t = row.t || 0;
      let rounds = Math.min(rr, curRound);
      if (uid in finalOut) {
        const at = finalOut[uid];
        rounds = Math.max(0, at - 1);
        if (rr >= at) { s = Math.max(0, s - (row.ls || 0)); t = Math.max(0, t - (row.lt || 0)); }
      }
      list.push({uid, n: e.n || "Student", r: rounds, s, t});
    }
    const results = {};
    for (const e of R.rank(list)) results[e.uid] = {n: e.n, r: e.r, s: e.s, t: e.t, p: e.p};
    return {status: "finished", finished_at: nowUnix, results, expires_unix: nowUnix + R.DONE_TTL};
  }
}

module.exports = {Referee, statusRank};
