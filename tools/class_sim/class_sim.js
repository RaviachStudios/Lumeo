#!/usr/bin/env node
// Class Game simulator — test Class Games with ONE phone.
//
//   node tools/class_sim/class_sim.js <command> [options]
//
// Commands
//   whoami                         check credentials / project
//   make-teacher <email|uid>       set users/{uid}.role = "teacher"
//   unmake-teacher <email|uid>     remove the role
//   students <PID> [opts]          bot STUDENTS join your phone's class and play
//   teacher [opts]                 a bot TEACHER opens a class (prints the code) for
//                                  your phone to join as a student, plus bot classmates
//   inspect <PID>                  print the class doc and every report row
//   cleanup <PID>                  delete the class and its 5 report shards
//   selftest                       offline: run full games on an in-memory store
//                                  (no network, no credentials) and check the results
//
// Bot options (students / teacher)
//   --count N        bot students (default 8; teacher mode: --students N)
//   --fail P         chance a normal bot misses a round (0 points, plays on; default 0.12)
//   --perfect N      N bots never miss (keeps a game alive to the last round)
//   --ghost N        N bots go silent from round 2 (app killed / lost connection)
//   --late N         N bots report round 2 AFTER the deadline (reconnect too late)
//   --quit N         N bots leave mid-game in round 3
//   --lobby-leave N  N bots join then leave the lobby before the start
//   --burst          all bots join within one second (shard contention)
//   --join-secs S    spread joins over S seconds (default 6)
// Teacher-only options
//   --rounds N       the teacher's pick: 10 or 15 (default 15)
//   --auto-start S   start S seconds after a non-bot student joins (default: press Enter)
//   --start-after S  start S seconds after the class opens, phone or not (bots-only runs)
//   --pause-at R --pause-for S   the teacher "drops" when round R starts, for S seconds
//   --cancel-at R    cancel the class when round R starts (0 = in the lobby)
//   --end-at R       press End Game 3 s into round R
//   --kick-phone-at R  remove the (non-bot) phone student during round R
//
// Credentials, in order: GOOGLE_APPLICATION_CREDENTIALS (service-account key or ADC
// file), else your Firebase CLI login (`firebase login`) is turned into a temporary
// ADC file billed to the project. Writes go to PRODUCTION Firestore — every doc this
// tool creates is a normal class doc that the server sweep deletes when it expires;
// `cleanup` removes one immediately.
"use strict";

const path = require("path");
const fs = require("fs");
const os = require("os");
const {execSync} = require("child_process");
const R = require("./rules");
const {Referee, statusRank} = require("./referee");

const PROJECT = process.env.FIREBASE_PROJECT || "simon-6bc39";
const FUNCTIONS_DIR = path.join(__dirname, "..", "..", "functions");

// ---------------------------------------------------------------------------
// Stores
// ---------------------------------------------------------------------------

class FirestoreStore {
  constructor(db, FieldValue) { this.db = db; this.FieldValue = FieldValue; }
  async get(p) { const s = await this.db.doc(p).get(); return s.exists ? s.data() : null; }
  async set(p, data, merge) { await this.db.doc(p).set(data, {merge: !!merge}); }
  async del(p) { await this.db.doc(p).delete(); }
  listen(p, cb) {
    return this.db.doc(p).onSnapshot((s) => cb(s.exists ? s.data() : null),
        (e) => console.error("listener error", p, e.message));
  }
}

// In-memory stand-in with Firestore merge semantics, for `selftest`.
class MemoryStore {
  constructor() { this.docs = {}; this.subs = {}; this.queue = []; this.writes = 0; this.reads = 0; }
  async get(p) { this.reads++; return this.docs[p] ? clone(this.docs[p]) : null; }
  async set(p, data, merge) {
    this.writes++;
    if (!merge || !this.docs[p]) this.docs[p] = clone(data); else deepMerge(this.docs[p], data);
    for (const cb of this.subs[p] || []) this.queue.push([cb, p]);
  }
  async del(p) { delete this.docs[p]; }
  listen(p, cb) {
    (this.subs[p] = this.subs[p] || []).push(cb);
    if (this.docs[p]) this.queue.push([cb, p]);
    return () => { this.subs[p] = (this.subs[p] || []).filter((c) => c !== cb); };
  }
  flush() {
    while (this.queue.length) {
      const [cb, p] = this.queue.shift();
      this.reads++;
      cb(this.docs[p] ? clone(this.docs[p]) : null);
    }
  }
}
const clone = (o) => JSON.parse(JSON.stringify(o));
function deepMerge(dst, src) {
  for (const [k, v] of Object.entries(src)) {
    // Like Firestore: an EMPTY map in a merge write replaces the field outright.
    if (v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length && dst[k] && typeof dst[k] === "object") deepMerge(dst[k], v);
    else dst[k] = clone(v);
  }
}

// ---------------------------------------------------------------------------
// Bot students
// ---------------------------------------------------------------------------

const NAMES = ["Maya", "Noam", "Lia", "Omer", "Tamar", "Itai", "Noa", "Yoav", "Shira", "Ariel",
  "Eden", "Roni", "Gal", "Amit", "Yael", "Ido", "Daniel", "Michal", "Ben", "Hila", "Tom", "Adi",
  "Uri", "Neta", "Ella", "Lior", "Avi", "Dana", "Ron", "Gili", "Rotem", "Shai", "Tal", "Yuval",
  "Ofir", "Liron", "Sapir", "Matan", "Inbar", "Erez", "Keren", "Nir", "Oren", "Rina", "Zohar",
  "Alon", "Bar"];

function makeBots(opts, runTag) {
  const n = opts.count;
  const bots = [];
  let i = 0;
  const take = (k, kind) => { for (let j = 0; j < k && i < n; j++, i++) bots.push(kind); };
  take(opts.perfect, "perfect");
  take(opts.ghost, "ghost");
  take(opts.late, "late");
  take(opts.quit, "quit");
  take(opts.lobbyLeave, "lobby_leave");
  while (i < n) { bots.push("normal"); i++; }
  return bots.map((kind, idx) => ({
    uid: `bot_${runTag}_${String(idx).padStart(2, "0")}`,
    n: `${NAMES[idx % NAMES.length]}${idx >= NAMES.length ? idx : ""}`.slice(0, 20),
    kind,
    skill: kind === "perfect" ? 0.95 : 0.3 + Math.random() * 0.6,
    joinAt: 0, joined: false, left: false,
    r: 0, s: 0, t: 0, out: false, plan: null,
  }));
}

class BotStudents {
  constructor(store, pid, bots, opts, log) {
    this.store = store; this.pid = pid; this.bots = bots; this.opts = opts; this.log = log;
    this.doc = null; this.unsub = null;
  }
  start(nowMs) {
    const spread = this.opts.burst ? 1000 : this.opts.joinSecs * 1000;
    this.bots.forEach((b, i) => { b.joinAt = nowMs + Math.floor(spread * (i + 1) / (this.bots.length + 1)); });
    this.unsub = this.store.listen(`classes/${this.pid}`, (d) => {
      if (!d) return;
      if (this.doc && statusRank(d.status) < statusRank(this.doc.status)) return;
      this.doc = d;
    });
  }
  stop() { if (this.unsub) this.unsub(); }
  async write(b, row) {
    const k = R.shardOf(b.uid);
    await this.store.set(`class_reports/${R.shardId(this.pid, k)}`, {players: {[b.uid]: row}}, true);
  }
  async tick(nowMs) {
    const d = this.doc;
    if (!d) return;
    for (const b of this.bots) {
      if (d.status === "lobby") {
        if (!b.joined && nowMs >= b.joinAt) {
          b.joined = true;
          await this.write(b, {n: b.n, d: "bot", j: Math.floor(nowMs / 1000), st: "lobby",
            r: 0, s: 0, t: 0, ls: 0, lt: 0, f: 0});
        } else if (b.kind === "lobby_leave" && b.joined && !b.left && nowMs >= b.joinAt + 2000) {
          b.left = true;
          await this.write(b, {n: b.n, st: "left"});
          this.log(`  ${b.n} left the lobby`);
        }
        continue;
      }
      if (d.status !== "playing") continue;
      if (b.out || !(d.roster || {})[b.uid] || (d.out || {})[b.uid] !== undefined) continue;
      const r = d.round || 0;
      if (b.r >= r) continue;
      if (b.kind === "ghost" && r >= 2) continue;                     // silent
      if (!b.plan || b.plan.r !== r) {
        const lim = R.limit(r);
        const startMs = (d.round_at_ms || 0) + Math.trunc((R.banner(r) + R.playback(r)) * 1000);
        let used = lim * Math.min(1.0, Math.max(0.12, (0.25 + Math.random() * 0.75) * (1.15 - b.skill)));
        let fail = b.kind !== "perfect" && Math.random() < this.opts.fail;
        let at = startMs + Math.trunc(used * 1000);
        if (b.kind === "late" && r === 2) at = R.deadlineMs(d.round_at_ms || 0, r) + 2500;
        if (b.kind === "quit" && r === 3) { fail = "quit"; at = startMs + 1500; }
        b.plan = {r, at, used, fail, pts: R.points(lim - used, lim)};
      }
      if (nowMs < b.plan.at) continue;
      if (b.plan.fail === "quit") {
        b.out = true;
        await this.write(b, {n: b.n, st: "left", f: r, r: b.r, s: b.s, t: b.t});
        this.log(`  ${b.n} left mid-game (round ${r})`);
      } else if (b.plan.fail) {
        // A miss: 0 points for this round, and the bot plays on.
        b.r = r;
        await this.write(b, {n: b.n, d: "bot", st: "in", r, ls: 0, lt: 0});
      } else {
        const ms = Math.trunc(b.plan.used * 1000);
        b.r = r; b.s += b.plan.pts; b.t += ms; b.c = (b.c || 0) + 1;
        await this.write(b, {n: b.n, d: "bot", st: "in", r, w: r, c: b.c, s: b.s, t: b.t,
          ls: b.plan.pts, lt: ms, f: 0});
        if (b.kind === "late" && r === 2) this.log(`  ${b.n} reported round 2 late (after the deadline)`);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Bot teacher (runs the SAME referee rules as the app)
// ---------------------------------------------------------------------------

class BotTeacher {
  constructor(store, pid, opts, log) {
    this.store = store; this.pid = pid; this.opts = opts; this.log = log;
    this.ref = null; this.unsubs = []; this.pausedUntil = 0; this.lastRound = -1;
    this.humanJoinedAt = 0; this.startRequested = false; this.endAt = 0; this.kicked = false;
  }
  async create(nowMs) {
    this.createdMs = nowMs;
    const now = Math.floor(nowMs / 1000);
    const doc = {
      v: R.VERSION, teacher_uid: `simteacher_${this.pid}`, teacher_name: "Sim Teacher",
      status: "lobby", created_at: now, started_at: 0, finished_at: 0,
      expires_unix: now + R.LOBBY_TTL, full: false, seed: 0, round: 0, round_at_ms: 0, alive: 0,
    };
    await this.store.set(`classes/${this.pid}`, doc, false);
    this.ref = new Referee(this.pid, doc);
    for (let k = 0; k < R.SHARDS; k++) {
      const p = `class_reports/${R.shardId(this.pid, k)}`;
      this.ref.setShard(k, {});
      this.unsubs.push(this.store.listen(p, (d) => this.ref.setShard(k, (d && d.players) || {})));
    }
    if (this.opts.cancelAt === 0) { await this.write(this.ref.cancel(now)); this.log("teacher cancelled in lobby"); }
  }
  stop() { this.unsubs.forEach((u) => u()); }
  async write(w) { if (!w || !Object.keys(w).length) return; this.ref.apply(w); await this.store.set(`classes/${this.pid}`, w, true); }
  async resync() {
    for (let k = 0; k < R.SHARDS; k++) {
      const d = await this.store.get(`class_reports/${R.shardId(this.pid, k)}`);
      this.ref.setShard(k, (d && d.players) || {});
    }
  }
  humans() {
    return Object.entries(this.ref.rows).filter(([u]) => !u.startsWith("bot_")).map(([u, r]) => ({uid: u, ...r}));
  }
  async tick(nowMs) {
    const now = Math.floor(nowMs / 1000);
    if (!this.ref) return;
    if (nowMs < this.pausedUntil) return;
    if (this.pausedUntil && nowMs >= this.pausedUntil) {
      this.pausedUntil = 0;
      this.log("teacher is back — re-reading the shards");
      await this.resync();
    }
    const st = this.ref.status();
    if (st === "lobby") {
      const h = this.humans().filter((x) => x.st === "lobby");
      if (h.length && !this.humanJoinedAt) { this.humanJoinedAt = nowMs; this.log(`phone student joined: ${h.map((x) => x.n).join(", ")}`); }
      await this.write(this.ref.lobbyUpkeep(now));
      const auto = this.opts.autoStart >= 0 && this.humanJoinedAt && nowMs >= this.humanJoinedAt + this.opts.autoStart * 1000;
      const timed = this.opts.startAfter >= 0 && nowMs >= this.createdMs + this.opts.startAfter * 1000;
      if (auto || timed || this.startRequested) {
        this.startRequested = false;
        this.opts.startAfter = -1;
        const w = this.ref.start(nowMs, now, 1 + Math.floor(Math.random() * 2147483646), this.opts.rounds);
        if (w.error) this.log(`can't start: ${w.error}`);
        else { await this.write(w); this.log(`STARTED with ${Object.keys(w.roster).length} students`); }
      }
      return;
    }
    if (st !== "playing") return;
    const r = this.ref.doc.round;
    if (r !== this.lastRound) {
      this.lastRound = r;
      const p = this.ref.progress();
      this.log(`round ${r}: ${p.alive} still in, ${p.out} out`);
      if (this.opts.cancelAt === r) { await this.write(this.ref.cancel(now)); this.log("teacher CANCELLED the class"); return; }
      if (this.opts.pauseAt === r) {
        this.pausedUntil = nowMs + this.opts.pauseFor * 1000;
        this.log(`teacher DROPS for ${this.opts.pauseFor}s (students should see "waiting for teacher")`);
        return;
      }
      if (this.opts.endAt === r) this.endAt = nowMs + 3000;
    }
    if (this.endAt && nowMs >= this.endAt) { this.endAt = 0; await this.write(this.ref.endNow(now)); this.log("teacher pressed END GAME"); return; }
    if (this.opts.kickPhoneAt === r && !this.kicked) {
      const h = this.humans().find((x) => x.uid in this.ref.roster());
      if (h) { this.kicked = true; await this.write(this.ref.kick(h.uid, now)); this.log(`teacher removed ${h.n}`); return; }
    }
    await this.write(this.ref.tick(nowMs, now));
  }
}

function printResults(doc, log) {
  const res = Object.entries(doc.results || {}).map(([uid, e]) => ({uid, ...e})).sort((a, b) => a.p - b.p);
  log(`\nRESULTS${doc.ended_early ? " (ended early)" : ""}:`);
  log(`(ended: ${doc.end_reason || "?"} after round ${doc.round} of ${doc.max_rounds || 15})`);
  for (const e of res) log(`  #${String(e.p).padEnd(3)} ${e.n.padEnd(20)} ${String(e.s).padStart(4)} pts  ${String(e.c).padStart(2)} rounds  ${(e.t / 1000).toFixed(1)}s  ${e.uid.startsWith("bot_") ? "" : "<- phone"}`);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function parseOpts(argv) {
  const o = {count: 8, fail: 0.12, perfect: 0, ghost: 0, late: 0, quit: 0, lobbyLeave: 0, burst: false,
    joinSecs: 6, autoStart: -1, startAfter: -1, rounds: 15, pauseAt: -1, pauseFor: 45, cancelAt: -1, endAt: -1, kickPhoneAt: -1};
  const pos = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const num = () => Number(argv[++i]);
    switch (a) {
      case "--count": case "--students": o.count = num(); break;
      case "--fail": o.fail = num(); break;
      case "--perfect": o.perfect = num(); break;
      case "--ghost": o.ghost = num(); break;
      case "--late": o.late = num(); break;
      case "--quit": o.quit = num(); break;
      case "--lobby-leave": o.lobbyLeave = num(); break;
      case "--burst": o.burst = true; break;
      case "--join-secs": o.joinSecs = num(); break;
      case "--auto-start": o.autoStart = num(); break;
      case "--start-after": o.startAfter = num(); break;
      case "--rounds": o.rounds = num(); break;
      case "--pause-at": o.pauseAt = num(); break;
      case "--pause-for": o.pauseFor = num(); break;
      case "--cancel-at": o.cancelAt = num(); break;
      case "--end-at": o.endAt = num(); break;
      case "--kick-phone-at": o.kickPhoneAt = num(); break;
      default: pos.push(a);
    }
  }
  o.pos = pos;
  return o;
}

async function connect() {
  const {createRequire} = require("module");
  const req = createRequire(path.join(FUNCTIONS_DIR, "index.js"));
  const admin = req("firebase-admin");
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    const cfg = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
    if (!fs.existsSync(cfg)) throw new Error("No credentials: run `firebase login` (or set GOOGLE_APPLICATION_CREDENTIALS).");
    const tok = JSON.parse(fs.readFileSync(cfg, "utf8")).tokens || {};
    if (!tok.refresh_token) throw new Error("Firebase CLI isn't logged in: run `firebase login`.");
    const root = execSync("npm root -g").toString().trim();
    const api = require(path.join(root, "firebase-tools", "lib", "api.js"));
    const adc = path.join(os.tmpdir(), `class_sim_adc_${process.pid}.json`);
    fs.writeFileSync(adc, JSON.stringify({type: "authorized_user", client_id: api.clientId(),
      client_secret: api.clientSecret(), refresh_token: tok.refresh_token, quota_project_id: PROJECT}), {mode: 0o600});
    process.env.GOOGLE_APPLICATION_CREDENTIALS = adc;
    process.on("exit", () => { try { fs.unlinkSync(adc); } catch (_) { /* gone */ } });
  }
  admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: PROJECT});
  const db = admin.firestore();
  return {admin, store: new FirestoreStore(db, admin.firestore.FieldValue)};
}

// Real-time loop: tick every 250 ms until `done()`.
async function runLoop(tickers, done, maxMs = 60 * 60 * 1000) {
  const t0 = Date.now();
  while (!done() && Date.now() - t0 < maxMs) {
    for (const t of tickers) await t(Date.now());
    await new Promise((r) => setTimeout(r, 250));
  }
}

async function cmdStudents(o) {
  const pid = o.pos[1];
  if (!/^[0-9]{6}$/.test(pid || "")) throw new Error("usage: students <PID> [--count N ...]");
  const {store} = await connect();
  const d = await store.get(`classes/${pid}`);
  if (!d) throw new Error(`No class ${pid}.`);
  if (d.status !== "lobby") throw new Error(`Class ${pid} is ${d.status}; bots can only join a lobby.`);
  const tag = Math.random().toString(36).slice(2, 6);
  const bots = makeBots(o, tag);
  console.log(`${bots.length} bots joining class ${pid}: ${bots.map((b) => `${b.n}(${b.kind})`).join(", ")}`);
  const bs = new BotStudents(store, pid, bots, o, console.log);
  bs.start(Date.now());
  let lastRound = 0;
  await runLoop([async (now) => {
    await bs.tick(now);
    const c = bs.doc;
    if (c && c.status === "playing" && c.round !== lastRound) {
      lastRound = c.round;
      console.log(`round ${c.round}: ${c.alive} still in, ${Object.keys(c.out || {}).length} out`);
    }
  }], () => bs.doc && (bs.doc.status === "finished" || bs.doc.status === "cancelled"));
  if (bs.doc.status === "finished") printResults(bs.doc, console.log);
  else console.log(`class ${bs.doc.status}`);
  bs.stop();
  process.exit(0);
}

async function cmdTeacher(o) {
  const {store} = await connect();
  let pid = "";
  for (let i = 0; i < 6; i++) {
    const p = String(100000 + Math.floor(Math.random() * 900000));
    if (!(await store.get(`classes/${p}`))) { pid = p; break; }
  }
  if (!pid) throw new Error("couldn't allocate a class code");
  const t = new BotTeacher(store, pid, o, (m) => console.log(m));
  await t.create(Date.now());
  console.log(`\n   CLASS CODE:  ${pid}\n\nOn the phone: ARENA > JOIN YOUR CLASS > ${pid}`);
  console.log(o.startAfter >= 0 ? `Starting ${o.startAfter}s after opening.`
    : o.autoStart >= 0 ? `Auto-start ${o.autoStart}s after the phone joins.` : "Press ENTER to start the game.");
  const bots = makeBots(o, Math.random().toString(36).slice(2, 6));
  const bs = new BotStudents(store, pid, bots, o, console.log);
  bs.start(Date.now());
  if (o.autoStart < 0 && o.startAfter < 0) {
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", () => { t.startRequested = true; });
  }
  await runLoop([(now) => bs.tick(now), (now) => t.tick(now)],
      () => ["finished", "cancelled"].includes(t.ref.status()));
  if (t.ref.status() === "finished") printResults(t.ref.doc, console.log);
  console.log("\nThe class stays readable for 10 min (podium), then the server sweep deletes it.");
  console.log(`Delete now: node tools/class_sim/class_sim.js cleanup ${pid}`);
  t.stop(); bs.stop();
  process.exit(0);
}

async function cmdInspect(o) {
  const pid = o.pos[1];
  const {store} = await connect();
  const d = await store.get(`classes/${pid}`);
  console.log(JSON.stringify(d, null, 2));
  for (let k = 0; k < R.SHARDS; k++) {
    const s = await store.get(`class_reports/${R.shardId(pid, k)}`);
    const players = (s && s.players) || {};
    console.log(`shard ${k}: ${Object.keys(players).length} rows`);
    for (const [u, r] of Object.entries(players)) console.log(`   ${u.padEnd(30)} ${JSON.stringify(r)}`);
  }
  process.exit(0);
}

async function cmdCleanup(o) {
  const pid = o.pos[1];
  if (!/^[0-9]{6}$/.test(pid || "")) throw new Error("usage: cleanup <PID>");
  const {store} = await connect();
  await store.del(`classes/${pid}`);
  for (let k = 0; k < R.SHARDS; k++) await store.del(`class_reports/${R.shardId(pid, k)}`);
  console.log(`deleted class ${pid} and its shards`);
  process.exit(0);
}

async function resolveUid(admin, who) {
  if (!who.includes("@")) return who;
  return (await admin.auth().getUserByEmail(who)).uid;
}

async function cmdRole(o, on) {
  const who = o.pos[1];
  if (!who) throw new Error(`usage: ${on ? "make-teacher" : "unmake-teacher"} <email|uid>`);
  const {admin, store} = await connect();
  const uid = await resolveUid(admin, who);
  await store.set(`users/${uid}`, {role: on ? "teacher" : admin.firestore.FieldValue.delete()}, true);
  console.log(`${uid}: ${on ? "is now a teacher" : "is no longer a teacher"} (restart the app to pick it up)`);
  process.exit(0);
}

async function cmdWhoami() {
  const {store} = await connect();
  await store.get("classes/000000");
  console.log(`OK — connected to ${PROJECT}`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// selftest — whole games on an in-memory store, virtual clock, no network
// ---------------------------------------------------------------------------

async function selftest() {
  let fails = 0;
  const check = (c, m) => { console.log(`  ${c ? "ok  " : "FAIL"} ${m}`); if (!c) fails++; };

  console.log("== rules parity");
  check(R.limit(1) === 10 && R.limit(6) === 14 && R.limit(15) === 18, "limits");
  check(R.points(10, 10) === 100 && R.points(0, 10) === 1 && R.points(5, 10) === 50, "points");
  check(R.shardOf("u00") === shardOfGd("u00") && R.shardOf("bot_ab_07") === shardOfGd("bot_ab_07"), "shard hash");
  const rk = R.rank([{uid: "a", n: "A", c: 10, s: 300, t: 5}, {uid: "b", n: "B", c: 8, s: 410, t: 5},
    {uid: "c", n: "C", c: 9, s: 300, t: 1}]);
  check(rk[0].uid === "b" && rk[1].uid === "a" && rk[2].uid === "c", "score first (410 > 300), then rounds completed");

  for (const scenario of [
    {name: "mixed class, 15 rounds", o: {count: 20, fail: 0.15, perfect: 2, ghost: 2, late: 1, quit: 1, lobbyLeave: 1}},
    {name: "10 rounds chosen", o: {count: 6, fail: 0.3, perfect: 1, rounds: 10}},
    {name: "perfect pair reaches round 15", o: {count: 2, fail: 0, perfect: 2}},
    {name: "full class + overflow (47 join)", o: {count: 47, fail: 0.2, perfect: 1, burst: true}},
    {name: "nobody completes round 1", o: {count: 5, fail: 1.0}},
    {name: "teacher drops mid-game", o: {count: 10, fail: 0.1, perfect: 3, pauseAt: 3, pauseFor: 60}},
    {name: "teacher ends early", o: {count: 6, fail: 0, perfect: 6, endAt: 4}},
  ]) {
    console.log(`== ${scenario.name}`);
    const o = {...parseOpts([]), ...scenario.o, autoStart: 0};
    const store = new MemoryStore();
    let now = 1_800_000_000_000;
    const log = () => {};
    const t = new BotTeacher(store, "424242", o, log);
    await t.create(now);
    const bots = makeBots(o, "st");
    // A stand-in "phone" student so auto-start has a human to wait for.
    bots.push({uid: "phone_user", n: "Phone", kind: "normal", skill: 0.8, joinAt: 0, joined: false, left: false, r: 0, s: 0, t: 0, out: false, plan: null});
    const bs = new BotStudents(store, "424242", bots, o, log);
    bs.start(now);
    store.flush();
    let steps = 0;
    while (!["finished", "cancelled"].includes(t.ref.status()) && steps < 40000) {
      now += 250;
      await bs.tick(now); store.flush();
      await t.tick(now); store.flush();
      steps++;
    }
    const doc = t.ref.doc;
    doc.out = doc.out || {};
    // What students actually SEE is the stored doc, not the referee's local copy.
    const stored = store.docs["classes/424242"] || {};
    check(JSON.stringify(Object.keys(stored.out || {}).sort()) === JSON.stringify(Object.keys(doc.out).sort()),
        `stored out map keeps every out (${Object.keys(stored.out || {}).length}/${Object.keys(doc.out).length})`);
    check(doc.status === "finished", `finished (round ${doc.round}, ${(steps * 0.25).toFixed(0)}s simulated)`);
    const roster = Object.keys(doc.roster || {});
    const results = doc.results || {};
    check(Object.keys(results).length === roster.length, `results for every rostered student (${roster.length})`);
    check(roster.length <= R.MAX_STUDENTS, "roster within 45");
    const byKind = (k) => bots.filter((b) => b.kind === k && roster.includes(b.uid));
    const bank = doc.bank || {};
    const outs = Object.keys(doc.out);
    const quitters = byKind("quit").map((b) => b.uid);
    check(outs.every((u) => quitters.includes(u)), `only leavers are out (${outs.length} out, ${quitters.length} quit)`);
    for (const b of byKind("ghost")) check(((bank[b.uid] || {}).c || 0) <= 1 && !(b.uid in doc.out), `ghost ${b.n}: still in, completed <= 1 round`);
    for (const b of byKind("late")) check(results[b.uid].c <= doc.round - 1 || doc.round < 2, `late ${b.n}: late round 2 not credited (c=${results[b.uid].c})`);
    for (const b of bots.filter((x) => x.kind === "lobby_leave")) check(!roster.includes(b.uid), `lobby leaver ${b.n} not rostered`);
    const sorted = Object.values(results).sort((a, b) => a.p - b.p);
    let mono = true;
    for (let i = 1; i < sorted.length; i++) if (sorted[i].s > sorted[i - 1].s) mono = false;
    check(mono, "ranked by score");
    const maxR = scenario.o.rounds || 15;
    check((doc.max_rounds || 15) === maxR, `max_rounds ${maxR}`);
    if (doc.end_reason === "max") check(doc.round === maxR, `stopped exactly at round ${maxR}`);
    if (doc.end_reason === "none_completed") {
      const r = doc.round;
      check(Object.keys(bank).every((u) => (bank[u].c || 0) < r || (bank[u].a || 0) < r), `nobody completed round ${r}`);
    }
    if (scenario.o.perfect === 2 && scenario.o.count === 2) check(doc.round === 15 && sorted[0].c === 15 && sorted[1].c === 15, "both completed all 15");
    if (scenario.o.fail === 1.0 && !scenario.o.perfect) check(doc.end_reason === "none_completed" && doc.round === 1, "ends after round 1 (nobody completed it)");
    if (scenario.o.endAt) check(doc.ended_early === true && doc.end_reason === "teacher", "ended_early flag");
    console.log(`     ended: ${doc.end_reason} at round ${doc.round}/${maxR}`);
    console.log(`     writes=${store.writes} listener-reads=${store.reads}`);
  }
  console.log(`\nRESULT: ${fails ? "FAIL" : "PASS"} (${fails} failures)`);
  process.exit(fails ? 1 : 0);
}

// Independent re-statement of ClassRules.shard_of, to catch a drift in rules.js.
function shardOfGd(uid) {
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 31 + uid.charCodeAt(i)) % 1000003;
  return h % 5;
}

(async () => {
  const o = parseOpts(process.argv.slice(2));
  try {
    switch (o.pos[0]) {
      case "whoami": return await cmdWhoami();
      case "make-teacher": return await cmdRole(o, true);
      case "unmake-teacher": return await cmdRole(o, false);
      case "students": return await cmdStudents(o);
      case "teacher": o.count = o.count ?? 8; return await cmdTeacher(o);
      case "inspect": return await cmdInspect(o);
      case "cleanup": return await cmdCleanup(o);
      case "selftest": return await selftest();
      default:
        console.log(fs.readFileSync(__filename, "utf8").split("\n").slice(1, 37).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
        process.exit(o.pos[0] ? 1 : 0);
    }
  } catch (e) {
    console.error("error:", e.message);
    process.exit(1);
  }
})();
