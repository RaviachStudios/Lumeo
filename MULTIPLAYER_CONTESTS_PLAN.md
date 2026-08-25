# Multiplayer Contests — Implementation Plan

A plan to add **head-to-head contests** to Lumeo: a player creates a contest (choosing
a **type** and a **difficulty**), shares its **contest ID** with friends, they join,
the creator starts it, everyone plays **inside the contest**, and at the end a large
**podium + full standings table** is shown. Contests are backed by Firestore and are
cleaned up once finished and abandoned.

This document specifies the **data model**, **Firestore writes/reads & rules**, the
**UI**, the **contest lifecycle state machine**, and — most importantly — **all the
edge cases** and how we resolve them.

---

## 0. The one constraint that shapes everything: there is no server

The app is **client + Firestore only** (autoloads talk to Firestore via the plugin +
REST; there are **no Cloud Functions**, see `leaderboard_manager.gd`, `coins_manager.gd`).
So there is **no trusted clock and no trusted compute** to:

- decide a time-boxed contest is over at exactly the deadline,
- freeze scores and compute the podium,
- delete abandoned contest documents on a schedule.

Everything must be done **cooperatively by the clients**, with Firestore **rules** as
the only guard rail, plus **Firestore TTL** as a janitor for orphans. The trust model
is the same one the leaderboards already accept: **clients report their own scores**
(`scoreOk()` in `firestore.rules` only bounds the number, it doesn't verify play). For a
casual friends game this is acceptable; this plan does not attempt cheat-proofing beyond
what the leaderboards already do, and calls out where a malicious client could bend rules.

**Design consequence:** the contest document carries an explicit, absolute
`deadline_at` (a timestamp) written when the contest is started. Any client that opens
the contest and observes `now >= deadline_at` (or the "everyone played" condition)
performs **finalization** — a guarded, idempotent transition that computes standings
and flips the contest to `finished`. First writer wins; everyone else re-reads the
finished result.

---

## 1. Scope & rules of the feature (product spec, restated)

- A player can **create a contest** with a chosen **type** and **difficulty**
  (easy / moderate / hard).
- **Contest types (end condition):**
  1. **1 Game** — ends when every member has played their single game.
  2. **1 Hour** — ends 1 hour after start; highest score in the window wins.
  3. **1 Day** — ends 24 hours after start; highest score wins.
  4. **Daily** — ends at the next **00:00 UTC** (aligned to the calendar day, same day
     boundary as the existing daily leaderboard); highest score wins.
- On create, the contest is saved to Firebase with a **shareable contest ID**.
- The creator shares the ID; friends **join by ID**.
- The creator **starts** the contest.
- While a contest is **active**, users can **still join**, and the **creator can kick**
  members.
- **End of contest:** show the **podium large** + a **full standings table**; members
  can no longer play, only **exit**.
- **Limits (v1):** a user may **join at most 2** contests and **create at most 1** at a
  time. (Later: shop upgrades to raise both caps — designed for, not built now.)
- The user's Firestore profile stores **which contests they are currently in**, so we
  can list them, track them, and enforce the caps.
- Contest documents are **deleted** once the contest is over **and all members have
  exited**.
- **Playing rules:**
  - A contest game must be started **from the contest page**. A normal game from the
    main screen does **not** count toward any contest.
  - A contest game **still updates the player's global & daily high scores** (and thus
    their leaderboard rank) exactly like a normal game.

---

## 2. Assumptions & decisions (RESOLVED)

All six open questions have been answered (see §13 for the summary). The choices are
baked into the sections below.

1. **"Daily" semantics** = a single contest that ends at the next UTC midnight after
   start (**not** a self-recurring contest). Highest score counts. Same UTC day boundary
   as the existing daily leaderboard.
2. **Contest ID** = a 6-character uppercase code (Crockford base32, no ambiguous
   chars) used **as the Firestore document ID**, so join-by-ID is a direct doc read.
   Collisions handled by generate-then-claim (create fails if the doc exists).
3. **Participants live in a subcollection** `contests/{id}/members/{uid}`, **not** a map
   on the contest doc. This gives clean **per-user write ownership** in rules
   (`allow write: if isUser(uid)`), which a map cannot express safely. The contest doc
   holds only meta + a `member_count`.
4. **Late join for "1 Game"**: allowed while `active`. The completion condition is
   "**all current members have submitted their game**"; a late joiner adds one more
   pending game. The creator can also **Finalize now** to end it deterministically
   (kicks/finalizes stragglers). This honors "can still join while active" without a
   contest that never resolves.
5. **Time source**: device clock. `deadline_at` is written at start as
   `started_at + duration` using the device clock; `created_at`/`started_at` also use
   `FieldValue.server_timestamp()` where the plugin supports it for audit. Clock-skew
   edge is handled in §9.
6. **Caps enforced client-side** (with an optional soft rule check via `get()` on the
   user doc). True server enforcement is impossible without Functions; the profile list
   is the source of truth for the UI and caps.
7. **Max members per contest**: 50 (keeps standings reads cheap; friends contests are
   small). Configurable constant.

---

## 3. New files & where they slot in

| File | Type | Role |
| --- | --- | --- |
| `contest_manager.gd` | **new autoload** (`ContestManager`) | All Firestore contest I/O, lifecycle, caps, resolution, editor sim. Mirrors `LeaderboardManager`/`CoinsManager` structure. |
| `multiplayer_screen.gd` | new screen | Hub: "My Contests" list + "Create" + "Join by ID". |
| `contest_create_screen.gd` | new screen (or modal) | Pick type + difficulty, confirm, generate ID. |
| `contest_detail_screen.gd` | new screen | Lobby (pre-start), live (active), results (finished). Roster, share ID, start/kick/leave, **Play** button, podium. |
| `firestore.rules` | edit | Add `contests` + `contests/{id}/members` rules; add `active_contests`/`created_contests` fields to `/users/{uid}`. |
| `game_manager.gd` | edit | `show_multiplayer()`, `show_contest_detail(id)`, `show_contest_create()`. |
| `home_screen.gd` | edit | Add a **Multiplayer** nav card/button (guest-gated like Shop/Leaderboards). |
| `game_state.gd` | edit | Hold `contest_context` (id/type/difficulty) so the game + game-over know they're in a contest. |
| `game.gd` | edit | Minor: in contest mode, hide/relabel Quit ("Forfeit"), keep coin HUD. |
| `game_over.gd` | edit | If in contest context, submit the contest result and route back to `contest_detail`. |
| `project.godot` | edit | Register `ContestManager` autoload after `CoinsManager`. |

**Reuse:** the podium + spotlights + glass panels + orbiting-orb background + loading
overlay in `leaderboards_screen.gd` should be factored into a small shared helper (or
copied) for `contest_detail_screen.gd`'s results view, so the podium looks identical.

---

## 4. Firestore data model

### 4.1 Contest meta document — `contests/{CONTEST_ID}`

```jsonc
{
  "creator_uid": "abc123",
  "creator_name": "Dana",
  "type": "one_hour",          // one_game | one_hour | one_day | daily
  "difficulty": "moderate",    // easy | moderate | hard
  "status": "lobby",           // lobby | active | finished
  "member_count": 4,           // maintained on join/leave/kick; drives cap + delete
  "created_at": <timestamp>,   // server_timestamp on create
  "started_at": <timestamp>,   // set on start
  "deadline_at": <timestamp>,  // set on start; null for one_game (event-driven end)
  "finished_at": <timestamp>,  // set on finalize
  "standings": [               // written once, at finalize (frozen snapshot)
    {"uid":"...", "name":"Dana", "score": 31, "games": 2, "rank": 1},
    ...
  ],
  "expires_at": <timestamp>    // TTL janitor: created_at + 3 days (bumped on activity)
}
```

- `standings` is the **frozen** result. Once `status == finished`, the live member docs
  are no longer read for ranking — the podium reads `standings`.
- `expires_at` is a **Firestore TTL policy field** (same mechanism the daily
  leaderboard uses). It guarantees an abandoned/never-finished contest is eventually
  reaped even if no client ever runs the leave-cleanup.

### 4.2 Member document — `contests/{CONTEST_ID}/members/{uid}`

```jsonc
{
  "uid": "xyz789",
  "name": "Sam",
  "joined_at": <timestamp>,
  "best_score": 27,           // best across this member's contest games
  "games_played": 1,          // how many contest games submitted
  "last_played_at": <timestamp>,
  "state": "playing_done",    // joined | in_progress | playing_done  (see §7)
  "done": true                // convenience for the one_game "all played" check
}
```

`done` semantics per type:
- **one_game**: `done == games_played >= 1`.
- **timed types**: `done` is not used for completion; the deadline ends it. (We still
  record it if the player chooses to stop.)

### 4.3 User profile additions — `/users/{uid}` (existing wallet doc)

```jsonc
{
  // ...existing wallet fields...
  "active_contests": { "AB12CD": {"role":"member","type":"one_hour"},
                       "ZZ99QW": {"role":"creator","type":"daily"} },
  "created_contests": { "ZZ99QW": true }   // for the create-cap; subset of active_contests
}
```

- `active_contests` is a **map** (same shape convention as `owned_themes`/`owned_levels`).
- **Join cap** = `active_contests.size() < JOIN_LIMIT` (2).
- **Create cap** = `created_contests.size() < CREATE_LIMIT` (1).
- Later shop upgrades raise `JOIN_LIMIT`/`CREATE_LIMIT` by reading purchased entitlements
  (store as `contest_join_slots` / `contest_create_slots` ints on the wallet).

---

## 5. Firestore security rules (additions to `firestore.rules`)

```
// ---- Contests ----
function contestMeta(id) { return get(/databases/$(database)/documents/contests/$(id)).data; }

match /contests/{cid} {
  // Anyone signed in can read a contest they have the ID for (IDs are the share token).
  allow read: if request.auth != null;

  // Create: only as its own creator, must start in "lobby", must be the creator's row.
  allow create: if request.auth != null
    && request.resource.data.creator_uid == request.auth.uid
    && request.resource.data.status == 'lobby'
    && request.resource.data.type in ['one_game','one_hour','one_day','daily']
    && request.resource.data.difficulty in ['easy','moderate','hard']
    && request.resource.data.member_count is int;

  // Update: creator can change status/deadline/standings/member_count/expires_at;
  //         any member may bump member_count/expires_at (join/leave) — kept permissive
  //         because rules can't recompute standings. Finalization writes are trusted
  //         (same trust model as leaderboard scores).
  allow update: if request.auth != null
    && resource.data.creator_uid == request.auth.uid ? true
       : (request.auth.uid == request.resource.data.creator_uid == false); // members: see note

  // Delete: only when the contest is empty (member_count reaches 0) or by the creator.
  allow delete: if request.auth != null
    && (resource.data.member_count <= 0 || resource.data.creator_uid == request.auth.uid);

  match /members/{uid} {
    allow read: if request.auth != null;
    // Each user owns their own member row...
    allow write: if isUser(uid)
      && request.resource.data.score_fields_ok();   // pseudo — inline the bounds like scoreOk()
    // ...but the creator may DELETE any member row (kick).
    allow delete: if isUser(uid)
      || request.auth.uid == contestMeta(cid).creator_uid;
  }
}
```

> **Rules notes / caveats (must be finalized during build):**
> - Firestore rules **cannot iterate a map** or recompute standings, so the meta
>   `update` for `member_count`/`standings` is necessarily **trusted client input**.
>   Bound what you can (types, enums, `member_count` within `[0, MAX_MEMBERS]`, `status`
>   only advancing `lobby→active→finished`).
> - The "members bump member_count on join" write means non-creators can update the meta
>   doc; scope it to *only* allow changing `member_count`/`expires_at` by diffing
>   `request.resource.data` against `resource.data` for the other fields
>   (`request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`).
> - `contestMeta(cid)` uses `get()` — billed as a read and only available in rules, fine
>   for kick.
> - Port the `scoreOk()` bounds (`0..9999`) to the member `best_score`.
> - Add matching **composite indexes** if we ever `runQuery` members ordered by
>   `best_score` (we will, for standings — see §7.4): index `members` by
>   `best_score DESC`. Firestore returns the create link on first run (same workflow as
>   the leaderboard indexes).

---

## 6. ContestManager (autoload) — public API

Mirrors `LeaderboardManager`: `_is_editor` in-memory sim (`_sim_contests`,
`_sim_members`, `_sim_users`) so the **entire flow is testable in the editor** without a
device; live path uses the plugin for writes/owned reads and REST for public standings
reads.

```gdscript
# --- creation / membership ---
func create_contest(type: String, difficulty: String) -> Dictionary   # {ok, id, error}
func join_contest(contest_id: String) -> Dictionary                   # {ok, error}
func leave_contest(contest_id: String) -> void                        # exit + cleanup
func kick_member(contest_id: String, uid: String) -> void             # creator only
func start_contest(contest_id: String) -> Dictionary                  # creator only

# --- reads ---
func load_my_contests() -> Array                # from /users/{uid}.active_contests
func load_contest(contest_id: String) -> Dictionary   # meta + members (live) or standings
func load_standings(contest_id: String) -> Array      # ranked rows

# --- gameplay hand-off ---
func begin_contest_game(contest_id: String) -> void   # sets GameState.contest_context, difficulty, show_game()
func submit_contest_result(contest_id: String, score: int) -> void

# --- lifecycle / resolution (called opportunistically on every load) ---
func maybe_finalize(contest_id: String) -> Dictionary  # returns finished meta if it flipped

# --- caps ---
func can_join() -> bool
func can_create() -> bool
func join_limit() -> int      # base 2 + purchased slots (later)
func create_limit() -> int    # base 1 + purchased slots (later)

signal my_contests_changed
signal contest_updated(contest_id: String)
```

### 6.1 `create_contest`
1. Cap check: `can_create()` (client) → error popup if at limit.
2. Generate a 6-char ID; attempt `create` on `contests/{id}` (fails if exists → retry
   new ID up to N times).
3. Write meta (`status=lobby`, `member_count=1`, `created_at`, `expires_at`).
4. Write creator's `members/{uid}` row.
5. Patch `/users/{uid}`: add to `active_contests` (`role:creator`) and `created_contests`.
6. Return `{ok, id}`; navigate to `contest_detail`.

*(Steps 3–5 are separate writes, not atomic — see §9 "partial create".)*

### 6.2 `join_contest`
1. Cap check `can_join()`.
2. Read `contests/{id}` → not found / `finished` / `member_count >= MAX` → specific error.
3. Write `members/{uid}` row (`state=joined`).
4. Increment `member_count` (+bump `expires_at`).
5. Patch `/users/{uid}.active_contests[id] = {role:member,type}`.

### 6.3 `start_contest` (creator only)
1. Verify caller is creator and `status==lobby`.
2. Compute `deadline_at`:
   - `one_hour` → now + 3600s; `one_day` → now + 86400s; `daily` → next 00:00 UTC;
     `one_game` → null.
3. Write meta `status=active`, `started_at`, `deadline_at`.

### 6.4 `begin_contest_game` → play → `submit_contest_result`
- `begin_contest_game`: guard (`status==active`, not past deadline, player not already
  `done` for `one_game`), set `GameState.contest_context = {id,type,difficulty}`,
  `GameState.set_difficulty(difficulty)`, mark member `state=in_progress`, `show_game()`.
- On game over (`game_over.gd`), if `GameState.contest_context` is set:
  - Call the **same** `LeaderboardManager.submit_score` + `submit_score_daily` as a
    normal game (so global/daily boards + rank update — requirement met).
  - Call `submit_contest_result(id, rounds)`:
    - Update `members/{uid}`: `best_score=max(...)`, `games_played+=1`,
      `last_played_at`, `state=playing_done`, `done` per type.
    - Clear `GameState.contest_context`.
  - After finalize check, route to `contest_detail(id)` (not the normal game-over home
    buttons) — show the game-over celebration, then a **"Back to Contest"** CTA.

### 6.5 `maybe_finalize` (the resolution protocol)
Called at the top of every `load_contest`/`contest_detail` open and after every
`submit_contest_result`. Idempotent.

```
read meta (+ members if needed)
if status == finished: return meta            # already done
if status != active:   return meta            # lobby not endable
ended := false
match type:
  one_game: ended = every member's done == true (member_count == count(done))
  one_hour/one_day/daily: ended = now >= deadline_at AND no member is in_progress
if not ended: return meta
# --- finalize (guarded) ---
standings := members sorted by best_score DESC, then last_played_at ASC (tiebreak)
attempt meta update: {status: 'finished', finished_at: now, standings}
   guarded so it only applies if resource.status == 'active' (transaction / compare)
return finished meta
```

- **First-writer-wins**: use a Firestore transaction (or a compare-and-set: re-read,
  only write if still `active`). Losers just re-read the winner's `standings`.
- **`in_progress` grace**: a timed contest does **not** finalize while any member is
  `in_progress` (someone is mid-game at the deadline) — we wait for them to submit.
  Bounded by a **grace cap** (e.g. 5 min after deadline) so a crashed mid-game player
  can't wedge the contest forever; past the cap we finalize ignoring them.

### 6.6 `leave_contest` + deletion
1. Delete `members/{uid}`.
2. Patch `/users/{uid}`: remove from `active_contests` (and `created_contests`).
3. Decrement meta `member_count` (+bump `expires_at`).
4. If `member_count` hits 0 → **delete** `contests/{id}` (and, best-effort, any leftover
   member docs). If the delete races/fails, TTL (`expires_at`) reaps it later.
5. If the **creator** leaves an active/lobby contest → see §9 "creator leaves".

---

## 7. Contest lifecycle state machine

```
        create                start                 finalize
 (none) ──────► LOBBY ─────────────► ACTIVE ──────────────► FINISHED ──► (deleted when empty)
                  │  join/kick/leave    │  join/kick/leave/play   │  exit only
                  └── creator deletes ──┘                         └── exit → cleanup → delete
```

Per-member state (`members/{uid}.state`): `joined → in_progress → playing_done`
(timed contests can go back to `in_progress` for another attempt; `one_game` cannot).

### 7.1 End condition per type (summary table)

| Type | Ends when | Score that counts | Replays allowed | Mid-game at deadline |
| --- | --- | --- | --- | --- |
| one_game | all members `done` (or creator Finalizes) | the single game | no | n/a |
| one_hour | `now ≥ start+1h` | best of all games | yes | finish current game, grace ≤5m |
| one_day | `now ≥ start+24h` | best of all games | yes | finish current game, grace ≤5m |
| daily | `now ≥ next 00:00 UTC` | best of all games | yes | finish current game, grace ≤5m |

---

## 8. UI design

Visual language matches the existing screens (deep-space shader bg, orbiting orbs, glass
panels, gold accents; podium reused from `leaderboards_screen.gd`).

### 8.1 Home entry
Add a **Multiplayer** card/button on `home_screen.gd` alongside Shop / Leaderboard.
Guest-gated exactly like `_on_leaderboards` (needs sign-in **and** a display name;
reuse `_show_sign_in_required_popup`). A small **badge** shows count of active contests /
"your turn" (optional, nice-to-have).

### 8.2 Multiplayer hub — `multiplayer_screen.gd`
- Header: "MULTIPLAYER" with the trophy/underline treatment.
- **My Contests** list (from `load_my_contests`): each row shows type icon, difficulty
  chip, status pill (LOBBY / LIVE / ⏳time-left / FINISHED / **YOUR TURN**), member count,
  creator badge. Tapping → `contest_detail`.
- Two primary buttons:
  - **Create Contest** → `contest_create_screen` (disabled + tooltip if `!can_create()`).
  - **Join by ID** → inline field / small modal; validates + calls `join_contest`
    (disabled if `!can_join()`).
- Cap hint line: "Joined 1/2 · Created 1/1" (foreshadows shop upgrades).
- Back → home.

### 8.3 Create — `contest_create_screen.gd`
- **Type** selector: four cards (1 Game / 1 Hour / 1 Day / Daily) each with icon +
  one-line rule ("Everyone plays one game", "Highest score in 1 hour", ...).
- **Difficulty** selector: reuse the EASY/MODERATE/HARD pill styling from the
  leaderboard/difficulty screens. Respect owned-levels? (Contests can use any difficulty
  — but see §9 "difficulty ownership".)
- **Create** button → `create_contest`, then go to detail with a celebratory reveal of
  the **big shareable ID** + a **Copy** and **Share** (`OS.share`/intent) affordance.

### 8.4 Contest detail — `contest_detail_screen.gd` (three modes by `status`)

**LOBBY (pre-start):**
- Big **contest ID** with Copy/Share.
- Type + difficulty summary.
- **Roster** list (live from members subcollection) with join order; creator sees a
  small **kick (✕)** on each other row.
- Creator: **Start Contest** button (disabled until ≥2 members? — decision in §9).
- Everyone: **Leave** button.

**ACTIVE (live):**
- Header shows a **countdown** (timed types) or "Waiting for N players to finish"
  (one_game). The countdown is computed from `deadline_at` read **once** on open and
  then ticks down **client-side** — no polling while it runs (see §10).
- **Standings** list (rank, name, best score, games played, "playing…" indicator for
  `in_progress`). Loaded on open; refreshed **only on a manual Refresh button / pull**,
  or automatically **once** when the client-side countdown hits 0 (to fetch results).
  Reads/writes are treated as expensive — no background auto-poll.
- Prominent **PLAY** button (this is the *only* place a contest game can start):
  - one_game: hidden/disabled once you're `done`.
  - timed: always available until deadline; shows your best.
- Creator: **kick**, and **Finalize now** (one_game) / **End early**? (decision §9).
- Leave (with confirm — leaving forfeits).

**FINISHED (results):**
- **Large podium** (reuse the `leaderboards_screen.gd` podium: top-3 blocks, cups,
  spotlights) fed from frozen `standings`.
- **Full standings table** below (all ranks, name, score, games).
- No PLAY. Only **Exit** (calls `leave_contest`; last one out triggers deletion).
- "You placed #N" highlight for the current user.

### 8.5 Playing a contest game
Reuse `game.gd`. In contest context:
- Keep the coin HUD and normal gameplay untouched (contest games still earn coins
  + update leaderboards — requirement).
- Relabel **Quit → Forfeit game** with a confirm ("This counts as your game / your turn
  ends"); for `one_game`, forfeiting = a submitted score of your current progress (or 0
  if you quit before finishing — decision §9).
- On game over, the game-over screen shows the score celebration then **Back to
  Contest** instead of Play Again / Home.

---

## 9. Edge cases & how each is handled

**Membership / caps**
1. **Join cap reached (2)** — `join`/`create` buttons disabled + explanatory popup;
   `join_contest` re-checks and returns `error:"at_join_limit"` (defense in depth).
2. **Create cap reached (1)** — same treatment; `create_contest` returns
   `error:"at_create_limit"`.
3. **Joining a contest you're already in** — detected (member row exists / present in
   `active_contests`) → just navigate to it, don't double-count.
4. **Joining a full contest** (`member_count >= MAX_MEMBERS`) → `error:"full"`.
5. **Joining a finished/deleted contest** — `finished` → open results read-only;
   not-found → `error:"not_found"` ("Contest not found or already ended").
6. **Bad/typo contest ID** — validated (length/charset) before the read;
   `error:"not_found"` otherwise.
7. **Two people join at the same time near the cap/MAX** — `member_count` is a
   best-effort counter; a small overshoot is harmless (bounded by MAX in UI). Not
   treated as a correctness bug.

**Start / lobby**
8. **Non-creator tries to start** — button not shown; `start_contest` rejects (rule +
   client check on `creator_uid`).
9. **Start with only the creator present** — **allowed** (decided). A solo contest is
   valid and just finalizes with one entrant. Show a warning on Start ("No one else has
   joined yet — start anyway?").
10. **Creator kicks a member** — deletes `members/{uid}` (rule allows creator delete),
    decrements `member_count`, and (best-effort) removes the contest from the kicked
    user's `active_contests`. Since one user can't write another's `/users` doc, the
    kicked client **self-heals** on next `load_my_contests`: if a listed contest no
    longer has their member row, drop it from `active_contests`. (This reconciliation is
    also the general fix for stale user-doc entries.)
11. **Creator leaves an active/lobby contest** — **cancel/close for everyone** (decided).
    Lobby → **delete** the contest. Active → **finalize** with the current standings
    (so far-along members still get a podium). The creator's create-slot is freed.
    Members see it flip to `finished` (or "cancelled") on their next load. Confirm dialog
    warns the creator this ends it for everyone.

**Playing / scoring**
12. **Playing from the main screen** — never touches contests (`GameState.contest_context`
    is empty). Only `begin_contest_game` sets it. ✔ requirement.
13. **Contest game updates leaderboards** — game-over calls the same
    `LeaderboardManager.submit_score` + `submit_score_daily`. ✔ requirement.
14. **Score submit fails (network)** — retry (the manager's write path can retry like
    the REST helpers); if it ultimately fails, keep the member `state=in_progress` and
    show "couldn't record — retry" so the player isn't wrongly marked `done`.
15. **one_game: player quits/forfeits before finishing** — **submit the partial score**
    reached so far (levels-1) and mark them `done` (decided). Quitting the app entirely
    without submitting leaves them `in_progress`; the creator's **Finalize now** or the
    grace cap resolves it.
16. **one_game never resolves** (a member never plays) — creator **Finalize now** ends
    it (non-players ranked last with 0 / "DNP"); or they get kicked.
17. **Replays / watch-ad-to-replay inside a contest game** — allowed; it's part of the
    single game, same as normal play. The final level count is the game's score.

**Timed contests & the clock**
18. **Player mid-game at the deadline** — finalize waits while any member is
    `in_progress` (§6.5), up to a **grace cap** (~5 min) so a crash can't wedge it.
    Their in-flight game, if submitted within grace, counts.
19. **No one opens the contest after the deadline** — nothing finalizes (no server!).
    It stays `active` in Firestore but every client that opens it finalizes on load, and
    `load_my_contests` shows it as "Ended — tap to see results" by comparing
    `deadline_at` locally even before the meta flips. TTL eventually reaps it if fully
    abandoned.
20. **Device clock skew / manipulation** — `deadline_at` is absolute; a user with a fast
    clock might see it "ended" early or a slow clock late. Because finalize is
    first-writer-wins and idempotent, the honest majority converges. We prefer
    `server_timestamp` for `created_at`/`started_at` for audit, but comparisons use
    device time (accepted limitation, same trust class as client scores).
21. **Two clients finalize simultaneously** — transaction/compare-and-set → one wins,
    the other re-reads. Standings are deterministic (sort by score desc, tiebreak by
    `last_played_at`), so even a race produces the same result.
22. **daily contest started right before 00:00 UTC** — deadline is the *next* midnight,
    which could be seconds away. Acceptable (matches the "daily" definition). If you want
    a minimum window, add `deadline = max(next_midnight, now+15m)` — flag if desired.

**Deletion / cleanup**
23. **Last member exits a finished contest** — `member_count → 0`, client deletes the
    meta doc + member docs. ✔ requirement.
24. **Delete race (two last-leavers)** — both attempt delete; second is a harmless no-op
    / permission-tolerant. Leftovers are swept by TTL.
25. **Orphaned contest** (everyone uninstalled / cleared data) — TTL on `expires_at`
    reaps meta; member subcollection docs need explicit deletion (Firestore TTL doesn't
    cascade) — on any load that finds a `finished`+expired contest, the loader
    best-effort deletes stray member docs, and/or we accept small orphan cost. *Call
    out:* subcollection cleanup without Functions is imperfect; document it.
26. **Stale `active_contests` entry** (contest deleted, user doc still lists it) — on
    `load_my_contests`, any ID that fails to read (not_found) is pruned from
    `active_contests`/`created_contests`. Self-healing (also covers kicks, case 10).

**Auth / profile**
27. **Guest (no sign-in / no name)** — Multiplayer is gated like Leaderboards; needs
    sign-in + display name.
28. **Rename mid-contest** — `display_name_changed` should also patch the user's
    `members/{uid}.name` in their active contests (like `LeaderboardManager` propagates
    renames), so standings show the new name.
29. **Sign-out while in contests** — contests persist in Firestore; local caches clear.
    On next sign-in the list re-hydrates from `active_contests`.
30. **Difficulty ownership** — contest play **bypasses the owned-levels gate** (decided):
    a contest at moderate/hard is playable by anyone in it regardless of what they've
    purchased. It's a social feature; don't block friends. (`begin_contest_game` sets
    the difficulty directly and does not consult `CoinsManager.owned_levels`.)

**Consistency (no transactions across docs)**
31. **Partial create** (meta written, member/user-doc write fails) — on next load, a
    contest whose creator has no member row is treated as broken; the creator's client
    reconciles by completing the missing writes or deleting the half-made contest.
32. **Partial join** (member row written, `member_count`/user-doc not) — reconciled on
    load (recount from subcollection when cheap; fix user doc from membership reality).

---

## 10. Reads, writes & refresh strategy (minimize Firebase I/O — reads/writes are expensive)

**No realtime listeners and no background polling.** This is a hard requirement: every
read/write costs money and the Android plugin's read callbacks are unreliable anyway.

- **Countdown**: read `deadline_at` **once** when the detail screen opens, then run the
  countdown **entirely client-side** (a local timer against the device clock). No reads
  occur while it ticks.
- **When the countdown reaches 0**: do **one** read — call `maybe_finalize` / reload the
  contest to fetch the finished `standings` and switch the screen to results mode. (If a
  member is still `in_progress`, one short retry within the grace cap; §6.5.)
- **Standings while active**: refreshed **only on explicit user action** — a manual
  **Refresh** button / pull-to-refresh. No automatic background refresh.
- **My-contests list**: read on hub open only (one `get_document` on `/users/{uid}` +
  the per-contest summary reads); manual refresh otherwise. Cache in `ContestManager`
  so navigating hub↔detail doesn't re-read.
- **Write frequency**: writes happen only on discrete actions (create, join, start,
  submit one game result, kick, leave, finalize). No heartbeat/keepalive writes.
- **Standings read** = `runQuery` on `contests/{id}/members` ordered by `best_score DESC`
  (public read; needs the composite index in §5). For small rosters we can also just
  `list` the subcollection and sort client-side.
- **My contests read** = plugin `get_document` on `/users/{uid}` (owner-only, like
  `coins_manager._load_user`), then a `get` per listed contest for its status/summary
  (or a small `runQuery` by document IDs).
- **Writes** = plugin `set_document(..., merge=true)` + `await write_task_completed`,
  exactly like `coins_manager._save_partial` and `leaderboard_manager.submit_score`.
- **Editor sim** = in-memory dicts so create/join/start/play/finalize/leave/delete are
  fully exercisable in the editor (mirror `LeaderboardManager._is_editor` and
  `CoinsManager._sim_db`). This is essential for testing the lifecycle without a device.

---

## 11. Later: shop upgrades (design-ahead, not built now)

- Wallet entitlements: `contest_join_slots` (int, +N to base 2),
  `contest_create_slots` (int, +N to base 1). Sold in the shop like `owned_levels`.
- `ContestManager.join_limit()/create_limit()` read base + entitlements.
- Rules: extend the `/users/{uid}` validation with the two int fields (bounded).
- UI already shows "Joined x/y · Created a/b"; the caps just grow.

---

## 12. Implementation phases (suggested order)

1. **Data + rules + sim**: `contest_manager.gd` with the full editor-sim lifecycle;
   `firestore.rules` additions; user-doc fields. Unit-test create→join→start→play→
   finalize→leave→delete in the editor.
2. **Navigation + hub**: `game_manager` methods, home Multiplayer card,
   `multiplayer_screen.gd` (list + create + join).
3. **Create + detail (lobby)**: `contest_create_screen.gd`, `contest_detail_screen.gd`
   lobby mode, share ID, roster, kick, start.
4. **Play integration**: `GameState.contest_context`, `begin_contest_game`, `game.gd`
   contest tweaks, `game_over.gd` contest routing + dual submit (contest + leaderboards).
5. **Active + finalize**: live standings, countdown/poll, `maybe_finalize`, grace cap.
6. **Results**: podium reuse + full table + exit + deletion.
7. **Edge-case hardening**: reconciliation/self-heal (cases 10, 25, 26, 31, 32),
   TTL policy, rename propagation.
8. **Live-device pass**: verify plugin write/read auth context on Android (the sim can't
   catch auth-context bugs — same class of issue documented in `coins_manager._load_user`).

---

## 13. Resolved decisions

1. **"Daily"** = single contest ending at the next UTC midnight (one-shot, not recurring).
2. **Creator leaves active contest** → **cancel/close for everyone** (lobby: delete;
   active: finalize with current standings).
3. **Start with 1 member** → **allowed**, with a warning on Start.
4. **Difficulty ownership** → **not gated**; anyone in a contest can play its difficulty
   regardless of purchases.
5. **one_game forfeit** → **submit the partial score** reached and mark the player done.
6. **Refresh model** → **no realtime, no background polling** (Firebase I/O is expensive):
   countdown is read once then runs client-side; when it hits 0, do one read to fetch
   results; standings otherwise refresh only on **manual** user action.
```
