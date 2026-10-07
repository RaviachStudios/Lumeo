# Class Games (Teacher Mode) — Implementation Plan

> **Status: implemented.** Code: `class_rules.gd`, `class_referee.gd`,
> `class_manager.gd` (autoload `ClassManager`), `class_screen.gd`, `class_art.gd`,
> class mode in `game.gd`, plus hooks in home, Arena, loading, `contest_manager.gd`,
> `firestore.rules` and `functions/index.js` (`sweepExpiredClasses`). Device testing:
> `CLASS_GAMES_TEST_PLAN.md` and `tools/class_sim/`.
>
> Where the build differs from the text below:
> - The "I'm in class X" pointer is a **local file** (`user://class_pointer.cfg`),
>   not `users.current_class`, so joining costs no extra write.
> - The teacher **doesn't listen** to its own class doc (it is the only writer).
> - Report shards are deleted by the **server sweep** with their class, not by the
>   teacher.
> - Timing: `SLACK` is 6 s; a student is "too late" past 4.5 s; round 1's banner
>   is 4 s (3-2-1 plus time for the game screen to build). Rounds are stamped as
>   `round_at_ms` in server milliseconds.

A teacher creates a class game, students join with the class PID, and everyone
plays the same hard-mode sequence round by round. A round ends when every student
still in has finished or failed. The game ends when **one student is left**, when
everyone left fails in the same round, or after round 15. There are at most 45
students. A podium is shown at the end.

This plan reuses what the Arena already does well and moves the pieces that would
cost reads and writes. It is based on `contest_manager.gd`, `game.gd`,
`firestore.rules` and `functions/index.js` as they stand today.

## Decisions (settled)

| Question | Decision |
|---|---|
| When does the game end? | As soon as **one student is left** (they win). Also when everyone left fails in the same round, or after round 15. |
| Must students sign in? | **Yes.** Same Google sign-in and name picker as Arena (`_require_account()`). No anonymous sign-in. |
| What do class games count toward? | **Coins only.** No leaderboard submit, no badges, no daily tasks. |
| Teacher's device drops mid-game | The game **pauses** ("Waiting for teacher…") and continues when the teacher's app comes back. No always-on Cloud Function referee. |

## The main design choice: the teacher's device runs the game

Today's Arena keeps a whole room in one document, and every player listens to it.
That's fine for a single run each. For class games it would be expensive: up to
45 students × 15 rounds ≈ 675 score writes, and each write would be sent to 46
listeners, so about **31,000 reads per game**.

The plan instead splits who writes what and who listens to what:

| Document | Who writes it | Who listens to it |
|---|---|---|
| `classes/{PID}`: the class's "clock" | **Teacher only**, about 20 writes per game | All students |
| `class_reports/{PID}_{0..4}`: 5 shards, each student's row lives in shard `hash(uid) % 5` | Each student, only their own row | **Teacher only** |

The teacher's device acts as the referee. It sees every student's report, decides
when a round is over, and writes "round r+1" once. Students never hear about each
other's writes.

**Why the teacher's device and not a Cloud Function?** A Firestore trigger adds
1–3 s of delay on every round (more on a cold start). Triggers also arrive in no
guaranteed order, which `syncContest` already had to work around. A single referee
device avoids both problems. The teacher's phone or tablet is on the classroom
Wi-Fi and is probably the screen being projected anyway. All game state lives in
Firestore, so if the teacher's app restarts, it picks the game back up by reading
1 + 5 documents.

**Why 5 shards?** If 45 students finish a round within a second or two, that's 45
writes to one document, which is above Firestore's guideline of about 1 write per
second per document. Five shards of about 9 students each avoids that. The Arena
lobby already listens to 5 shard documents, so the plugin handles it.

## Cost per game (45 students, worst case where 45 survive all 15 rounds)

| | Writes | Reads |
|---|---|---|
| Joins (read the class doc, write your row) | 45 | 45 |
| Round reports (one per surviving student per round) | ≤ 675 | ≤ 675 (teacher's listener) |
| Teacher clock writes (create, full, start, 15 rounds, final) | ~20 | ~20 × 45 = 900 |
| Coin commit (one per student, at the end of their game) | 45 | 0 |
| **Total** | **~785** | **~1,600** |

That's about **20× fewer reads** than the single-document approach, and well
under $0.01 per game. A real game costs much less, because students drop out
along the way and the game stops at one survivor. No Cloud Function runs while a
game is in progress.

## Data model

```
users/{uid}.role = "teacher"           // set by hand in the console
users/{uid}.current_class = PID        // resume pointer (teacher and students)
classes/{PID} {                        // PID = 6-digit code, same generator as Arena
  v,                                   // ClassRules version; a mismatched app can't join
  teacher_uid, teacher_name,
  status: lobby|playing|finished|cancelled,
  created_at, expires_unix, full: bool,
  seed,                                // one shared sequence, generated on each device
  roster: {uid: {n, d}},               // frozen at START: name + device token
  round, round_at,                     // round number + publish time in SERVER time
  out: {uid: round},                   // who is out and in which round (incl. timeouts)
  kicked: {uid: true},                 // removed by the teacher; can't rejoin
  alive,                               // for "12 still in" on spectator screens
  results: [{u, n, r, s, t}]           // full ranking, written once at the end
}
class_reports/{PID}_{k} {
  players: { uid: { n, d: device_token, j: joined_at,
                    st: lobby|in|out|left, r: rounds_done, s: score, t: total_ms,
                    f: failed_round } }
}
```

The `out` map is how a student learns that the teacher counted them out (for
example their report arrived after the deadline). It rides along with each round
write, so it costs no extra writes.

**Teacher flag:** it goes on `users/{uid}`, which `CoinsManager._load_user()`
already reads at startup, so it costs no extra reads. All three client writes to
`users` are merges (`coins_manager.gd:1498`, `badge_manager.gd:503`,
`daily_tasks_manager.gd:644`), so adding a rule that makes `role` read-only is
safe:

```
(resource == null && !('role' in request.resource.data))
|| (resource != null && request.resource.data.get('role', null) == resource.data.get('role', null))
```

The current `users` rule lets owners write any field it doesn't list, so without
this rule anyone could make themselves a teacher.

**Rules for the new collections:**

- **Creating a class:** requires `get(/users/$(auth.uid)).data.role == 'teacher'`.
  That costs one extra read, and only when a class is created.
- **Updating a class:** only `teacher_uid` can update it.
- **Report shards:** a student can only touch their own key, checked with
  `request.resource.data.players.diff(resource.data.players).affectedKeys().hasOnly([request.auth.uid])`.
  This is stronger protection than Arena rooms have. Each shard is capped at 15
  entries. The teacher may write and delete shards.
- **The 45-student limit:**
  - The teacher writes `full: true` once 45 students are in.
  - A joining student reads the class doc first and is turned away if it's full.
  - Anyone who slips in during a race isn't included in `roster` at START and
    sees "class is full".

## Shared server time

Device clocks don't agree, and the Android plugin can't write server timestamps.
So each device estimates its offset from server time once, from the HTTP `Date`
header of a REST read it already makes (the class doc read on create or join;
the existing `_http_get` path). This is accurate to about 1 s, which is enough.

- The teacher writes `round_at` in server time.
- A student uses `round_at` only to measure **how late** a round update reached
  them. All gameplay timers still run on the student's own device.
- If the offset can't be measured, the device falls back to offset 0 and skips
  the lateness check.

## Round timing

Put the shared formulas in a small `ClassRules.gd` so the teacher and students
compute exactly the same values:

- `limit(r)`: 10 s for rounds 1–5, 14 s for rounds 6–10, 18 s for rounds 11–15.
- `playback(r)`: how long the hard-mode sequence takes to show, using
  `GameState`'s hard values for `flash_time`, `flash_gap` and `speed_increase`.
- `banner(r)`: about 3 s for the 3-2-1 before round 1, about 1.5 s for the
  "Round r" banner after that.
- `SLACK = 5 s`: allowance for network delay on top of the round's length.
- `deadline(r) = round_at + banner(r) + playback(r) + limit(r) + SLACK`.

**What each student does in a round:**

1. The class doc arrives with a new round number.
2. The device ignores the update if `round` is not newer than the round it
   already knows (a stale or repeated push).
3. If the student is in `out` or `kicked`, they become a spectator and show why.
4. If the update is too late to play (lateness > `SLACK`), the student is out
   for this round. The screen says "Your connection was too slow — you're out in
   round r". The device writes `{st:"out", f: r}`.
5. Otherwise the device shows the banner, plays the sequence from the seed, and
   starts the local `limit(r)` timer.
6. If the student finishes, they score `points = ceil(100 × time_left / limit)`
   for that round (at most 1,500 over a game). The device writes one merge:
   `{st:"in", r, s: total, t: total_ms}`.
7. If they press wrong or the timer runs out, the device writes
   `{st:"out", f: r, s: total, t: total_ms}`. Coins are committed and the student
   becomes a spectator, listening for the final results.

**What the teacher's device does:**

1. It publishes round r with `round_at` = now in server time.
2. It advances as soon as every student in the roster who is still in has
   reported round r.
3. Otherwise it advances at `deadline(r)`. Students who haven't reported by then
   go into `out` for round r.
4. Reports for an older round, or from students not in the roster, are ignored.
5. Ending the game:
   - If **exactly one** student is left after round r, they win and the game
     ends.
   - If **nobody** is left (everyone remaining failed in round r), the game ends.
     Those students all completed r − 1 rounds and are ranked by score.
   - If round 15 is done, the game ends. Everyone left is ranked by score.
6. At the end it writes `results` and `status: "finished"` (one write that
   reaches every student) and then deletes the 5 shards.

**Ranking** sorts by rounds completed (most first), then score (highest first),
then total time (lowest first). So 10 rounds with 300 points beats 8 rounds with
410. Students still tied after all three share the same place.

## Edge cases

### Connection and app lifecycle — students

| Case | What happens |
|---|---|
| **Loses connection mid-round, comes back before the deadline** | The Firestore SDK queues the report and sends it on reconnect. It counts as normal. |
| **Loses connection mid-round, comes back after the deadline** | The teacher has already counted them out. The late report has an old `r` and is ignored. When the student's listener reconnects, it gets the latest class doc, sees itself in `out` and shows "You lost connection — you're out in round r". |
| **Offline while a round update is pushed** | On reconnect the listener delivers only the latest snapshot. The student may have missed rounds. If they're in `out`, they become a spectator; if the update is too late, step 4 above applies. They are never shown a round they can't fairly play. |
| **Closes or kills the app mid-round** | Nothing is reported, so the teacher counts them out at the deadline. Coins earned so far in this game are lost (same as a killed solo game). |
| **Reopens the app after closing it** | `users.current_class` sends them back into the class. They read the class doc once and see: the podium (finished), "You're out in round r" with the live spectator view (playing), the lobby (lobby), or "The class has ended" (cancelled, or the doc is gone). If they're out, they can't keep playing. |
| **App goes to the background mid-round** (home button, notification, call) | The round timer is based on real time. On resume, if `limit(r)` has passed, they're out by timeout and the device writes the report. If they come back within the limit, they keep playing. |
| **Presses back or Leave** | A confirmation dialog appears ("Leave class? You'll be out."). If they confirm: coins are committed and the device writes `st:"left"`. In the lobby this removes them from the teacher's list; during play they count as out. |
| **Closes the app while in the lobby** | Their row stays at `st:"lobby"`, so the teacher still sees their name. The teacher can remove them. Otherwise they're included at START and drop out at the round-1 deadline. No lobby heartbeat, which would cost writes. |
| **Coin commit fails (offline)** | `CoinsManager` keeps the balance locally and pushes it on its next normal save, the same as solo play. |

### Connection and app lifecycle — teacher

| Case | What happens |
|---|---|
| **Teacher's app goes to the background or loses connection mid-game** | No new round is published. A student's device waits until `deadline(r)` plus a few seconds, then shows "Waiting for teacher…". Students' own round reports are already in their shards. |
| **Teacher comes back** | The teacher re-attaches the listeners and reads the class doc + 5 shards (6 reads). It rebuilds the referee state from them, judges the current round (counting out anyone who didn't report by the deadline) and continues. Nobody who finished in time loses anything. Wait for `GameManager.await_gl_stable()` before any heavy drawing on resume. |
| **Teacher's app is killed and reopened** | `users.current_class` sends the teacher back to the live board, and play resumes as above. |
| **Teacher never comes back** | While waiting, each student device reads the class doc every 30 s (watchdog). The sweep deletes the class once `expires_unix` passes, which is about 30 minutes after the last round write. The plugin never delivers a delete to a listener, so it's the watchdog read that finds the doc gone. The device then shows "The class has ended" and commits coins. |
| **Teacher closes the app in the lobby** | The class expires 60 minutes after creation unless it starts. Students in the lobby are told by the same watchdog read, every 60 s while in the lobby. |
| **Teacher presses Cancel Class** | The teacher writes `status: "cancelled"` (a write, not a delete, so listeners hear it). Students see "Your teacher ended the class" and commit coins. |
| **Teacher presses End Game mid-play** | The current round ends right away and results are written from the reports on hand. Students who were mid-round get no points for it. |
| **Screen lock on the teacher's device** | The teacher's lobby and live board keep the screen on (`DisplayServer.screen_set_keep_on(true)`). |

### Joining

| Case | What happens |
|---|---|
| Student isn't signed in or has no name | JOIN YOUR CLASS goes through sign-in and the name picker first, then opens the PID popup. |
| Wrong PID | "No class with that code." (1 read) |
| Class already started, finished or cancelled | "This class game already started" / "This class game has ended." |
| Class full (45) | "This class is full." Also covered for last-second joins by the roster frozen at START. |
| Student was removed by the teacher | "Your teacher removed you from this class." They can't rejoin. |
| Student is in an Arena room or another class | Blocked: "Leave your current game first." Extends `ContestManager.active_room()` to cover classes too. |
| Same account on two devices | Each row carries a device token `d`. The roster saved at START keeps the token of the last device that joined. The other device sees "You're playing on another device" and becomes a spectator. Costs nothing extra. |
| Old app version (different `ClassRules` version `v`) | "Please update the app to join this class." This stops devices with different timing rules from playing in the same class. |
| Network error while joining | A toast with a retry. Nothing is written until the class doc read succeeds. |

### Starting and ending

| Case | What happens |
|---|---|
| Teacher presses START with fewer than 2 students | START stays disabled until there are at least 2 students. A game with one student would end the moment it starts. |
| Teacher removes a student mid-game | The teacher adds them to `kicked` and `out`, in the next class-doc write. The student becomes a spectator with "Removed by teacher". |
| One student left after a round | Game ends, they're 1st. |
| Everyone left fails in the same round | Game ends. Those students all completed the same number of rounds, so they're ranked by score, then time. |
| Round 15 completed by several students | Game ends. Ranked by score, then time. |
| Student opens the app after the class doc was deleted | The pointer read finds nothing, so the pointer is cleared and they land on the home screen. |

### Gameplay

| Case | What happens |
|---|---|
| The level-8 skin events (Volcano and Arcade banners, lake party) | Turned off in class mode. They freeze one student's screen for about 3 s and would break the deadline math. |
| Rewarded "continue" or replay | Hidden in class mode. No ad prompts at all during a class. |
| Hard-mode button count | Always 6. Skins change only how the buttons look, so the shared seed gives every student the same sequence. |
| Slow or low-FPS device | Timers use real time, not frames, so the round limit is the same for everyone. |

## Changes to `game.gd` (new `class_context`, next to `contest_context`)

- Force hard difficulty. The student's own skin and buttons apply as normal.
- Replace the per-press timer (`PRESS_LIMIT`) with one timer for the whole
  sequence, showing a visible countdown. It is based on real time, so time spent
  in the background counts.
- After a successful round, don't call `_next_round()`. Report the result, show
  "Waiting for classmates… next round in ≤ Ns" (computed locally, no reads), and
  wait for `ClassManager.round_started`.
- Turn off the level-8 freeze events, rewarded continue, and replay.
- The quit dialog becomes "Leave class?", and leaving counts as out.
- **Coins only:** coins are earned per round as in a normal hard game and are
  committed once, when the student is out, the class ends or they leave. Skip
  `LeaderboardManager.submit_score`, `BadgeManager.note_score`,
  `DailyTasks.note_score` and `GameState.submit_score`.

## UI (illustrated, game-like style)

- **Home, for teachers:** the big wheel button becomes **CREATE CLASS GAME** (for
  example a chalkboard or apple design, drawn in code). A smaller PLAY wheel sits
  beside it. If the teacher already has a live class, the button returns to it.
- **Arena hub:** a third card, **JOIN YOUR CLASS**. It opens a PID popup that
  reuses the private-join number entry. If the student is already in a class, the
  card returns to it.
- **Teacher lobby:**
  - The PID shown very large for the projector.
  - A grid of student names that updates live from the shards, plus a counter
    like "32 / 45".
  - Tap a name to remove that student.
  - START (enabled at 2+ students) and Cancel Class buttons.
  - The screen stays awake.
- **Student lobby:** "You're in [teacher]'s class, waiting for the teacher to
  start" with the flying Simon character.
- **Teacher's live board during play:** round number and timer, students still
  in vs out (updates as reports come in), and an End Game button.
- **Student spectator view (after going out):** why they're out, the round
  they reached, their score, and the round and number of students left (from the
  class doc they already receive).
- **"Waiting for teacher…" overlay** on student screens when the teacher is
  late, as described above.
- **Podium:** reuse `podium_stage.gd`, with the full ranked list underneath. Each
  student's device highlights their own row and shows the coins they earned.

## Cloud Functions (cleanup only)

- Extend `sweepExpiredRooms` to also delete expired `classes` and their
  `class_reports` shards.
- Expiry horizons, all pushed forward by teacher writes the game already makes
  (no separate keepalive writes):
  - Lobby: 60 minutes after creation.
  - Playing: 30 minutes after the latest round write.
  - Finished or cancelled: 10 minutes, so students who reopen the app can still
    see the podium.
- Deploying: rules are deployed by hand, and functions need
  `FUNCTIONS_DISCOVERY_TIMEOUT=180`.

## Build order

1. Rules, the `role` field and `ClassRules.gd` (limits, playback, deadline,
   ranking, version).
2. The `ClassManager` autoload: create, join, leave, kick, start, referee loop,
   report, listeners, watchdog, server-time offset, resume via
   `current_class`, and an **editor simulation with 40 bot students** (like
   `_sim_rooms`). The bots should cover: slow reporters, students who never
   report, late reports after the deadline, a teacher pause and resume, and
   every way a game ends.
3. Class mode in `game.gd`.
4. The screens (home teacher button, Arena join card and popup, teacher lobby,
   student lobby, live board, spectator view, waiting overlay, podium).
5. The cleanup function, then deploy.
6. Test on 2–3 real devices. Go through the edge-case tables above, especially
   airplane mode mid-round (back before and after the deadline), killing a
   student's app, backgrounding the teacher's app mid-round, and the teacher
   never returning.
