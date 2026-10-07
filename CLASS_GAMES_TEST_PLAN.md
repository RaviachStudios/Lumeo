# Class Games — Testing With One Phone

Your phone plays one side of the class. The simulator (`tools/class_sim/class_sim.js`)
plays everyone else against **production Firestore**, using the same rules and
referee logic as the app.

- **Phone as teacher:** bot students join your class and play.
- **Phone as student:** a bot teacher runs the class, with bot classmates.

## Rules v2 (2026-10-08): what changed for testing

Nobody is knocked out any more (see CLASS_GAMES_PLAN.md). Where the tables below say a
student is "out", read instead:

| Situation | v2 expectation |
|---|---|
| Wrong press / time runs out (B2, B3) | "Missed! 0 points this round", then the next round starts as normal |
| Round reaches the phone too late, or the app was killed mid-round (B7, B8, B16) | 0 points for that round, a short notice, back in from the next round |
| Silent student (A3) | Round 2 waits for them once; from round 3 the class no longer waits; they stay on the board with 0s |
| Late report (A4) | Not credited for that round; still in |
| Game end | After the teacher's 10 / 15 rounds, or after a round nobody completed |
| Teacher lobby | ROUNDS 10 / 15 picker next to Cancel Class |
| Podium / list | Ranked by points; rows show "points · completed/played rounds" |

New simulator options: `--rounds 10|15`, `--start-after S` (bots-only runs, no phone).

Verified without a phone on 2026-10-08:
- Godot headless: referee tests (missed rounds, banking, silent/late students, 10-round
  stop, nobody-completed stop, leave/kick/end/cancel) and both editor-sim flows
  (teacher 10-round game; student misses round 3 and plays on to round 10).
- `class_sim.js selftest`: 7 scenarios incl. 10 rounds, nobody completes round 1,
  47 joiners, teacher drop, end early.
- Rules on the Firestore emulator (`firebase emulators:exec`): 20 checks — teacher-only
  create, read-only role, 10/15 only, bank / end_reason shape, own-row-only reports,
  no joins after start, no deletes, and the empty-map merge behaviour.
- Production: a bots-only 10-round game (`teacher --rounds 10 --start-after 12`) ran to
  round 10 with only the quitter out; class deleted afterwards.
- Not yet verified on a device: the new screens (rounds picker, 0-points flow).

## 0. One-time setup

1. **Deploy the server side** (rules are deployed by hand; see the memory notes):
   ```bash
   firebase deploy --only firestore:rules
   FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --only functions:sweepExpiredRooms
   ```
2. **Check the simulator can reach Firestore.** It reuses your `firebase login`:
   ```bash
   node tools/class_sim/class_sim.js whoami          # "OK — connected to simon-6bc39"
   node tools/class_sim/class_sim.js selftest        # offline check of the bot/referee logic
   ```
   If `whoami` fails with a permission or "API not enabled" error, use a
   service-account key instead: Firebase console → Project settings → Service
   accounts → Generate key, then
   `export GOOGLE_APPLICATION_CREDENTIALS=/path/key.json`.
3. **Make your account a teacher:**
   ```bash
   node tools/class_sim/class_sim.js make-teacher raviachstudios@gmail.com
   ```
   Then force-close and reopen the app. Home should show **CREATE CLASS GAME**,
   with a smaller START beside it.
4. Build and install the app as usual.

Useful anytime:
- `inspect <PID>` shows the class doc and every report row.
- `cleanup <PID>` deletes a test class immediately.

To watch reads and writes, use the Firestore console's Usage tab. A full
20-bot game should cost a few hundred of each.

---

## Part A — Phone as TEACHER (bot students)

Create a class on the phone, read the 6-digit code, then run the bots from the
laptop.

| # | Scenario | Command | Check on the phone |
|---|---|---|---|
| A1 | Happy path | `students <PID> --count 12` | Names appear live in the lobby with "12 / 45". START is enabled. Press START: rounds advance on their own, chips turn green as bots finish, the clock bar runs. Game ends at 1 survivor or round 15; podium + full ranking. |
| A2 | Early round advance | `students <PID> --count 5 --fail 0` | Each round advances right after the last bot answers, not when the clock bar runs out. |
| A3 | Silent student (lost connection / app killed) | `students <PID> --count 8 --ghost 2` | Round 2 waits for the full deadline (bar runs out, "wrapping up…" for ~6 s), then the two ghosts show as out (R2). |
| A4 | Late report | `students <PID> --count 6 --late 1` | The late bot is out at R2; on the podium it shows 1 round and its round-2 points are not counted. |
| A5 | Student leaves mid-game | `students <PID> --count 6 --quit 1` | That bot shows out (R3). |
| A6 | Leaves the lobby | `students <PID> --count 6 --lobby-leave 2` | Two names appear, then disappear from the lobby; they're not in the game. |
| A7 | Full class | `students <PID> --count 47 --burst` | The counter reaches 45; once `full` is written, joining from another account says "This class is full". Start: only the first 45 play (inspect: roster = 45). |
| A8 | Remove a student | `students <PID> --count 6` | Tap a name in the lobby → it disappears. Mid-game: tap a chip → that student is out. Remove until 1 is left → game ends. |
| A9 | Too few to start | Create a class, add no bots, or 1 bot (`--count 1`) | START is disabled, with "At least 2 students are needed". |
| A10 | End Game | `students <PID> --count 6 --perfect 6` | Press End Game in round 3 or later → podium titled "(ended early)"; nobody is counted out for the cut round. |
| A11 | Cancel | `students <PID> --count 6`, then Cancel Class | The bot script prints "class cancelled" and exits. |
| A12 | **Teacher's app goes to the background** | `students <PID> --count 8 --perfect 4` | Mid-round, press Home for ~40 s, then come back. The game catches up at once: rounds the bots finished in time count, and the next round starts. Nobody who answered in time is out. |
| A13 | **Teacher's app killed** | same | Swipe the app away mid-game and reopen it. The loading screen goes straight back to the live board and the game continues. |
| A14 | Teacher's phone offline | same | Airplane mode for ~20 s mid-round, then back on. The board resumes and pending writes are sent. |
| A15 | Long game | `students <PID> --count 3 --perfect 3` | Plays all 15 rounds (limits 10 s → 14 s → 18 s). Ends after round 15; ranked by score. |
| A16 | Leaving the board | Back arrow during a game | Home shows **RETURN TO YOUR CLASS**; tap it → the live board, and the game kept running meanwhile. |
| A17 | One game at a time | During a class, open Arena → Create | "Finish your class game first." |

## Part B — Phone as STUDENT (bot teacher)

```bash
node tools/class_sim/class_sim.js teacher --students 8 --auto-start 15
```
It prints the class code. On the phone: **ARENA → JOIN YOUR CLASS → code**.
The bot teacher starts 15 s after your phone joins; leave out `--auto-start`
to start by pressing Enter instead.

| # | Scenario | Command / action | Check on the phone |
|---|---|---|---|
| B1 | Happy path | `teacher --students 8 --auto-start 15` | Lobby shows the teacher's name and code. Game opens by itself with ROUND 1 + 3-2-1. Your own skin and buttons, hard (6 buttons), clock on the right. After a correct round: "+N points!" then "Waiting for classmates… Ns". Next round starts on its own. |
| B2 | Fail a round | Press a wrong button | "You're out in round N!" → spectator view (rounds, points, coins, the live round). Stay on it until the podium appears; your row is highlighted. |
| B3 | Run out of time | Don't press | Clock turns red at 3 s; you're out on timeout. |
| B4 | Win | `teacher --students 2 --fail 0.6` | When you're the last one left: "YOU WIN!" → podium with you 1st. |
| B5 | **Teacher drops** | `teacher --students 6 --perfect 3 --auto-start 10 --pause-at 3 --pause-for 60` | Finish round 3 → "Waiting for classmates" counts down, then changes to **"Waiting for your teacher…"**. After 60 s the teacher returns and round 4 starts. You're not out. |
| B6 | **You lose connection, back in time** | Airplane mode right after the round starts, finish the sequence, airplane mode off within ~3 s | The report goes through and you stay in. |
| B7 | **You lose connection, back too late** | Airplane mode, finish, stay offline ~20 s | When you're back: "Time's up — you're out in round N" (the teacher counted you out). |
| B8 | **App killed mid-round** | Swipe the app away mid-round, reopen | Goes straight to the class: you're out for that round (spectator), then the podium when it ends. |
| B9 | App killed between rounds | Swipe away right after "+N points", reopen before the next round | Back in the class and the next round launches normally (your total score is kept). |
| B10 | App in the background mid-round | Home button ~5 s, come back | The clock kept running: still playing if time is left, out if not. |
| B11 | Leave | Quit button → "Leave class?" → Yes | Back home; the teacher log shows you out. |
| B12 | Removed by the teacher | `teacher --students 4 --perfect 4 --auto-start 10 --kick-phone-at 2` | "Your teacher removed you from the class." Rejoining the code → "removed" message. |
| B13 | Teacher cancels | `--cancel-at 2` (or `--cancel-at 0` in the lobby) | "Your teacher ended the class." |
| B14 | Teacher ends early | `--end-at 3` | "Your teacher ended the game." → podium "(ended early)". |
| B15 | Joining errors | Wrong code / a class that started / a finished one | "No class with that code", "already started", "has ended". |
| B16 | Too slow at the start of a round | Hard to force; optional | On a very slow connection: "Your connection was too slow — you're out". |
| B17 | Wandered off | In the lobby, go to the Shop | When the game starts, the app pulls you back into round 1. |
| B18 | Coins | Compare the coin balance before and after | Coins = the normal hard-mode earnings for the rounds you completed. No leaderboard entry, no badges, no daily-task progress. |
| B19 | Not signed in | Sign out → Arena → JOIN YOUR CLASS | "Sign in and pick a name to join your class." |

## Part C — Server cleanup

1. After a test, `inspect <PID>` still shows the class.
2. Wait about 10 min (finished or cancelled) or 30 min (abandoned mid-game).
3. The scheduled sweep runs every 15 min; afterwards `inspect` shows `null` and no
   shards.
4. You can also check this in the Firestore console under `classes` and
   `class_reports`.

## What is already verified automatically (no phone needed)

- **Godot, headless, editor simulation:**
  - Referee edge cases: early advance, deadline time-out, late report, everyone
    failing in the same round, one survivor, 15-round cap, the 45 cap, removing
    students, End Game, unsynced referee.
  - A full teacher game with bots through `ClassManager`.
  - A full student game against a simulated teacher.
- **`class_sim.js selftest`:** five complete games on an in-memory store,
  including 47 joiners, a teacher dropping mid-game, and End Game.

Not verified: real devices, real Firestore rules, and the look of the new screens.
That is what Parts A–C cover.

---

## Results — device run, 2026-10-07 (OnePlus CPH2645, debug-signed build)

Simulator driven over adb; the phone's own rounds were played by a scratch
auto-player that derives the sequence from the class seed and taps the board.

| Test | Result |
|---|---|
| A1 happy path, A2 early advance, A9 START disabled < 2 | Pass |
| A3 silent students, A4 late report, A5 quit mid-game, A6 lobby leaver | Pass |
| A7 47 join / 45 cap / `full` flag | Pass |
| A8 remove in lobby and mid-game | Pass |
| A10 End Game, A11 Cancel, A15 to round 15, A16 return to class, A17 Arena blocked | Pass |
| A13 teacher app killed mid-game | Pass — resumes on relaunch |
| A14 teacher offline 30 s | **Failed, fixed** — see bug 2; re-tested: game pauses with "Connection lost", nobody counted out |
| A12 teacher app backgrounded (Home) 30 s mid-game | Pass — game paused, resumed on return, nobody counted out, ran to round 15 |
| B1 happy path, B2 wrong press, B3 timeout, B4 win, B15 wrong code | Pass |
| B5 teacher drops | **Failed, fixed** — see bug 3; re-tested: "Waiting for your teacher…" shows |
| B6 offline briefly, B7 offline past deadline | Pass (bug 6 fix re-checked: spectator 1 round / 89 pts = results) |
| B8 killed mid-round | Pass (bug 5 fix re-checked: "The app was closed during round 3") |
| B9 killed between rounds, B10 backgrounded mid-input | Pass |
| B11 leave, B12 removed (+ rejoin refused), B13 cancelled, B14 ended early, B17 pulled back from Shop | Pass |
| B18 coins only | Pass (balance 0 → 42 over the run) |
| B19 not signed in | Pass — Arena (and so JOIN YOUR CLASS) asks to sign in first; signing back in keeps coins and the teacher role |
| C server cleanup | Pass — all test classes and shards swept |

Bugs found on device and fixed:
1. An empty `out` map in a merge write REPLACES the field in Firestore — earlier
   outs were wiped the first round nobody went out. Referee no longer sends empty maps.
2. A teacher who dropped offline judged rounds from stale listener data and counted the
   whole class out. Rounds are now judged only after re-reading the 5 shards from the
   server (5 reads/round); offline → paused.
3. A watchdog re-read of an unchanged doc reset "waiting for teacher" (and re-armed the
   read throttle, so waiting students read every 5 s instead of 30 s).
4. Listener pushes could be lost while the app was backgrounded on this phone — the app
   re-subscribes on resume.
5. Reopening after the app was killed mid-round said "connection too slow" — now
   "The app was closed during round N".
6. Spectator score included a late round's points the results don't credit.

Also confirmed: class games never touch the personal best / leaderboards (Hard best still 0 after ~15 class games).

Cosmetic, open: the class-code popup's dim backdrop doesn't visibly darken the Arena.
