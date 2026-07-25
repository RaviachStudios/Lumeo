# Arena / Contests Firestore I/O Audit

Worst-case read & write counts for the **Arena (live rooms + contests)** subsystem —
room creation, join/leave, the public browse lobby, the race, and the results board.
Scope is Arena only; the score/leaderboard subsystem is separate (see
`SCORES_FIRESTORE_IO_AUDIT.md`). Everything here is **client-driven** — no Cloud
Function touches `contests/*` or `lobby/*`, so every read/write below is billed to a
player's client.

## Storage model (what's touched)

| Doc | Read by | Written by | Watched by |
|---|---|---|---|
| `contests/{CID}` — the whole room in one doc | REST `GET` (`_load_room`, `_room_exists`) | plugin `set`/`delete` (all room mutations) | a **document listener** per member on the detail screen |
| `lobby/s{0..4}` — 5-shard index of open public rooms | REST list of the collection (`_lobby_read_all`) | plugin `set` (claim / bump / close / compact) | **5 document listeners** per lobby viewer |
| `users/{uid}` — carries the `current_room` pointer | piggybacks CoinsManager's existing read (no extra read) | plugin `set` merge (`_set_current_room`) | — |

## Assumptions ("booming game" worst case)

Every number is the **worst case** a path can bill. Constants come from
`contest_manager.gd` / `contest_detail_screen.gd`:
`MAX_MEMBERS = 45`, `LOBBY_SHARDS = 5`, `LOBBY_SHARD_CAP = 20`,
`LOBBY_MAX = 100`, `START_WINDOW = 5 min`, `FINISH_GRACE = 3 min`,
`TTL_SECS = 20 min`, `KEEPALIVE_SECS = 5 min`, `SWEEP_LIMIT = 10`.

- **M** = active members in a room, all sitting on the detail screen (so all
  *listening*). Worst case **M = MAX_MEMBERS = 45**.
- **V** = players concurrently browsing the public lobby. Booming example **V = 1,000**.
- The public lobby is **full** (100 open rooms) and churning.
- A room runs a **full 45-player race** where everyone finishes.

### Firestore billing rules applied

- **Realtime listener** (`listen_to_document`): the initial attach delivers the current
  doc = **1 read**; thereafter **every change to that doc bills 1 read to *each*
  client currently listening**. This is the Arena's dominant cost — a single write to a
  shared doc fans out to N reads when N clients watch it.
- REST `GET` of one doc (`_rest_get`) = **1 read**.
- REST list of the 5-doc lobby collection = **5 reads** (1 per doc returned).
- `runQuery` (the expiry sweep, `limit 10`) = **1 read per doc returned** (≤10, min 1).
- `set_document` / `delete_document` = **1 write / 1 delete** each (deletes priced like writes).

> **The fan-out formula.** A write to a doc watched by N listeners costs `1 write +
> N reads`. So a room doc write with a full room = `1 + 45` reads. A race, where
> **each** of M players writes the room doc (begin + submit), costs on the order of
> **M² listener reads** (~2,025 at M=45). A lobby shard write with V viewers costs
> `1 + V` reads (~1,001 at V=1,000).

---

## READS

| When in the flow | What is read | Use (context) | Worst-case reads (booming) |
|---|---|---|---|
| Arena hub open (seated player) | `active_room()` → 1 REST `GET` of `contests/{cid}` (cached pointer rides CoinsManager's `/users` read — no extra read) | Validate the persisted room pointer; paint the "return to your room" card | **1** |
| Open Create modal → Create (**public**) | `_lobby_read_all` list (5) + `active_room` (1) + `_room_exists` (1/attempt) | Pick least-full shard, enforce one-room rule, dodge ID collision | **7** (+5 per rare ID-collision retry) |
| Create (**private**) | `active_room` (1) + `_room_exists` (1) | Same, no lobby read | **2** |
| Join by ID | `active_room` (1) + `_load_room` (1) | One-room guard + fetch the room to join | **2** |
| Open detail screen (first paint) | `load_room` 1 REST `GET` | Immediate paint before going live | **1** |
| Detail screen goes live (`watch_room`) | Document-listener initial snapshot | Attach the live room listener | **1 per member** (M=45 across a full room) |
| **Detail screen — every room change while open** | Listener delivers the changed `contests/{cid}` to **each** of M members | Live roster / start / score / finish push | **M per write to the doc** → a full race's write-storm ≈ **M² ≈ 2,025** |
| Submit result (game over) | `_load_room` 1 REST `GET` per finisher | Re-read to run the all-done check | **1 per finisher → M ≈ 45** per full room |
| Straggler finalize (`finalize_if_done` / `finalize_overdue`) | `_load_room` 1 REST `GET` per firing client | Re-check before force-finishing | **1 per firing client** (several may fire → up to M) |
| Open public lobby | 5 shard-listener snapshots (5) + sweep `runQuery` (≤10) | Paint list live + GC abandoned rooms | **≈15 per viewer open** |
| **Public lobby — every shard change while open** | Listener delivers the changed `lobby/s{N}` to **each** of V viewers | Rooms appear / change count / vanish live | **V per shard write** → **~1,000 per lobby event**; a churning full lobby pushes tens of thousands/min across V |
| Lobby expiry sweep (runs on lobby open) | `runQuery` `expires_unix < now`, `limit 10` | Find abandoned rooms to reap | **≤10** (min 1) |

**Cold Arena-hub open, seated player:** ~1 read.
**Open the public lobby (booming):** ~15 reads to that viewer, but the viewer then
becomes one of the V that every subsequent shard write bills against.
**A single full-room race:** ~45 REST reads (submit loads) **+ ~2,025 listener reads**
(the room-doc write-storm fanned across 45 members) — almost entirely self-inflicted by
the single-doc-per-room model.

---

## WRITES

| When in the flow | What is written | Use (context) | Worst-case writes (booming) |
|---|---|---|---|
| Create room (**public**) | `contests/{cid}` set + `lobby/s{N}` claim + `users/{uid}` merge | Persist room, list it, set pointer | **3 writes** (+ **V** lobby-listener reads for the claim) |
| Create room (**private**) | `contests/{cid}` set + `users/{uid}` merge | No lobby entry | **2 writes** |
| Join | `contests/{cid}` player-merge + `contests/{cid}` count-merge + `lobby/s{N}` bump + `users/{uid}` merge | Add player, republish count, set pointer | **4 writes** (+ **2M** room-listener reads + **V** lobby reads) |
| Leave (not last) | player-tombstone + count-merge + lobby bump + `users` clear | Leave the room | **4 writes** (+ **2M** + **V** reads) |
| Leave (last) / creator cancels a lobby | lobby close (`o=0`) + **delete** `contests/{cid}` + `users` clear | Tear the room down | **~3 writes/deletes** (delete fans to **M**; close fans to **V**) |
| **Start race** (creator) | `contests/{cid}` set (`status=playing`, `seed`) + `lobby/s{N}` close | Flip everyone to playing at once + delist | **2 writes** (+ **M** room-listener reads — the simultaneous auto-launch push — + **V** lobby reads) |
| **Begin game** (each player) | `contests/{cid}` player-merge (`state=playing`) | Mark self in-progress | **1 write/player → M writes/room**, each × M listeners = **M² ≈ 2,025 reads** |
| **Submit result** (each player) | `contests/{cid}` player-merge (`done`,`score`) [+ a finished-merge on the last] | Record score / finalize when all done | **1 write/player (+1 finalize) → M+1 writes/room**, each × M = **M² ≈ 2,025 reads** |
| **Keepalive heartbeat** | `contests/{cid}` expiry-merge, every 5 min per open screen | Keep a quiet-but-open room from being swept | **M writes / 5 min** per full room, each × M = **M² ≈ 2,025 listener reads / 5 min** |
| Straggler / Finish-now finalize | `contests/{cid}` set (`status=finished`) | Force-end a stalled/early race | **1 write** (+ **M** listener reads) |
| Kick member (creator) | player-tombstone + count-merge + lobby bump | Remove a player | **3 writes** (+ **M** + **V** reads) |
| Lobby sweep deletes | **delete** `contests/{cid}` × ≤10 | Reap abandoned rooms | **≤10 deletes/pass**, per lobby-opening client |
| Lobby compaction | `lobby/s{N}` non-merge rewrite × ≤5 | Reclaim dead index keys | **≤5 writes/pass** (only dirty shards) (+ **V** listener reads each) |

**Per full-room race:** ~45 begin-game writes + ~46 submit/finalize writes ≈ **91 room
writes**, and because each is a write to the one shared doc that 45 members watch, they
bill **~2,025 listener reads on top**.
**Idle full room (nobody doing anything):** the keepalive alone is **~45 writes +
~2,025 reads every 5 minutes** (~24k reads/hour) purely to stay alive.

---

## Where the cost actually concentrates

1. **Realtime-listener fan-out is THE Arena cost driver.** Unlike the scores subsystem
   (one-shot reads), Arena is built on live listeners, so *every write to a shared doc
   is multiplied by the number of clients watching it*. Two hot surfaces:
   - **The room doc** — watched by up to **M = 45** members. The race writes it ~91
     times, so ~**M² ≈ 2,025 reads** per race, plus the same shape every 5 min from
     keepalive. This is bounded (M ≤ 45) but quadratic in room size.
   - **The lobby index** — watched by **V** browsers. Every open / join / leave / close
     / count-bump across the (up to 100) rooms bills **1 read per viewer**, i.e. **V per
     event**. This is *unbounded in V*: the more people browsing, the more every single
     room event costs. At V=1,000 a busy lobby is the single largest line item.

2. **The single-doc-per-room model trades write-simplicity for read fan-out.** It's why
   concurrent joins/scores never clobber each other (deep-merge on one doc) — but it also
   means one player's score write wakes all 45 listeners. Sharding already spreads the
   *lobby* writes across 5 docs (Firestore's ~1 write/sec/doc ceiling); the room doc has
   no such spread, so a 45-way race is a genuine write-hotspot on one document.

3. **Keepalive is a standing idle tax.** A full, open, *idle* room still costs ~M²
   reads every `KEEPALIVE_SECS` (5 min). Levers: raise `KEEPALIVE_SECS`, or let only the
   host heartbeat (1 write/room instead of M) — the host's screen is enough to prove the
   room is still open.

4. **Cost-containment already in place (don't regress these):**
   - `unwatch_lobby` / `unwatch_room` drop listeners the instant a screen closes — an
     idle listener is a per-change read for every backgrounded client.
   - Lobby liveness is a pure **time predicate** (`now < o + START_WINDOW`), so closed /
     started / abandoned rooms leave the list with **no** re-query and no server event.
   - The 5-shard lobby index keeps any single shard ~2KB, so a full push to V viewers is
     cheap *per read* even though there are V of them.
   - Sweep + compaction are **bounded** (`SWEEP_LIMIT = 10`, ≤5 shard rewrites) and only
     run opportunistically when a player opens the lobby.

5. **Levers if Arena booms:** cap concurrent room size (M is the quadratic term); coalesce
   per-player score writes; have only the host heartbeat; and — the big one — server-side
   lobby pagination would cut the V-fan-out, but it needs Cloud Functions the Arena
   deliberately does without today.
