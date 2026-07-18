# Leaderboard Rewards — Design & Implementation Plan

Two independent coin-reward systems layered on the existing leaderboards, with
**no backend** (client-computed, guarded only by Firestore rules — same trust
model as the rest of the economy).

- **All-time milestones** — paid *immediately* at game over, once per rank band
  per difficulty.
- **Daily standings** — paid on the *first login after the day closes*, for
  where you finished on yesterday's (or the most recent played day's) board.

---

## 1. All-time milestone rewards (immediate, once per band)

Per difficulty (3 boards: easy / moderate / hard), reward the player the first
time they reach a new, better rank band on the all-time board.

| Rank | Coins | Band index |
|------|-------|------------|
| 1        | 1000 | 1 |
| 2        | 750  | 2 |
| 3        | 500  | 3 |
| 4 – 10   | 350  | 4 |
| 11 – 24  | 250  | 5 |
| 25 – 50  | 150  | 6 |
| 51+      | 0    | 0 (none) |

**Rule:** award = `reward(band_of(new_rank))` **only if** that band is strictly
better (lower index) than the best band ever rewarded for this difficulty.
Never cumulative.

- `73 → 48`  : none → band 6 → **+150**
- `35 → 9`   : band 6 → band 4 → **+350**
- `45 → 32`  : band 6 → band 6 → **0** (same band)
- `70 → 6`   : none → band 4 → **+350** (only the landed band, not 150+250+350)

**Why gating on new personal-best is correct:** an all-time rank can only
*improve* when you beat your own stored score (everyone else only pushes you
down over time). So a band improvement always coincides with a new high — and
game-over already computes `my_rank` on the new-high path (`_submit_and_show_rank`).

**Storage** — one wallet field on `/users/{uid}`:

```
alltime_reward_bands: { easy: 4, moderate: 0, hard: 6 }   # best (lowest) band idx per diff
```

Idempotency is inherent: the band only ever moves toward 1, and we compare
before awarding. The coin delta and the band update go in the **same merge
write**, so a failed write never leaves "rewarded but unpaid".

---

## 2. Daily standing rewards (first login after the day closes)

Final daily standing, paid the next time you open the app after that day ended.

| Rank | Coins |
|------|-------|
| 1        | 500 |
| 2        | 300 |
| 3        | 150 |
| 4 – 10   | 100 |
| 11 – 25  | 50  |
| 26 – 50  | 25  |
| 51+      | 0   |

### The core problem this solves

The old daily rows are keyed by **`uid`**, so playing again *overwrites* your own
previous-day row — even infinite TTL couldn't preserve history. And a daily
rank is *relative* to everyone else's rows, so you cannot compute your final
placement from your row alone. Without a server to snapshot ranks at day-close,
**the day's rows must survive until the player returns to collect.**

### Fix: historical, date-partitioned rows

Key each daily row by **`{date}__{uid}`** and store `uid` as a field (exactly the
pattern `contest_members` already uses). Each day becomes its own immutable row a
later replay can't clobber. Retain **14 days** via TTL
(`expires_at = next_midnight + 14 days`), then let TTL prune.

```
daily_hard/2026-07-12__<uid>  -> { uid, name, score, date:"2026-07-12", expires_at }
daily_hard/2026-07-13__<uid>  -> { uid, name, score, date:"2026-07-13", expires_at }
```

The screen still queries `date == today`, so history never pollutes the live
board. Rank for any retained day = `count(date == D AND score > mine) + 1` via
the aggregation endpoint — reusing the existing `(date, score)` indexes. **No new
indexes.**

### Collection: "your one most-recent uncollected played day"

You **cannot stack** multiple days: to land on a day's board you must *play* that
day, which means *opening* the app that day, which runs collection and pays the
prior day. So there's always ≤1 uncollected day. The scan below is for **delayed
collection** (return a day or two later) and as a **safety net** for a dropped
write — not an accumulator.

On first login of the day (`grant_daily_rewards_if_due`, hooked into the existing
`register_login` heartbeat):

```
stamp last_daily_reward_date on /users/{uid}   # "" until first run
if empty (new / migrating user): set last = yesterday, save, return   # no retroactive pay
if last >= yesterday: return                    # already resolved through yesterday
start = max(last + 1, yesterday - 13)           # bounded to the 14-day window
for day in start .. yesterday:
    for diff in easy/moderate/hard:
        rank = my_daily_rank_for(diff, day)     # 0 = didn't play, -1 = query failed
        if rank < 0: return                     # abort WITHOUT stamping → retry next open
        total += reward(rank)
last_daily_reward_date = yesterday              # stamp
pay `total`, save coins + earned_coins + last_daily_reward_date in ONE merge write
emit daily_rank_reward_granted(total, results)  # home shows a summary popup
```

**Correctness properties**

- *Delayed return*: play Mon, skip Tue, open Wed → scan Mon..Tue → Monday's row
  found, Tuesday absent → pays Monday once. (The old "check only yesterday" would
  have missed it — the exact bug we're fixing.)
- *Exactly once*: `last_daily_reward_date` is stamped to yesterday and the coin
  delta rides the **same merge write**, so a failed save reloads server truth on
  next sign-in and re-pays cleanly (never double, never partial).
- *Query failure*: `my_daily_rank_for` distinguishes HTTP 404 (definitely no row
  → 0) from network error (→ -1). A -1 aborts the whole pass without stamping, so
  a transient failure never causes a wrong/skipped reward — it just retries.
- *Migration*: existing users have no `last_daily_reward_date` → we stamp
  yesterday and start fresh; there are no pre-existing date-partitioned rows, so
  there is no retroactive windfall.
- *>14 days away*: the last played board has been TTL-swept → forfeited. Standard
  "collect your daily reward" contract.

---

## 3. Trust model

Rank and payout are computed client-side (Firestore rules can't run
queries/aggregations), so amounts are trusted — identical to how every other
coin write in this app already works. The only "correct" hardening is a Cloud
Function, which is out of scope for this backend-less app. Ship client-side; add
a per-write coin-delta bound later if abuse shows up.

---

## 4. Files touched

| File | Change |
|------|--------|
| `leaderboard_manager.gd` | daily rows keyed `{date}__{uid}` + `uid` field; 14-day TTL; identity from `data.uid` (not doc id) in top/neighborhood; `my_daily_rank_for(diff, date)` with 404-vs-error distinction; delete-all + rename updated for date-partitioned rows; editor-sim parity |
| `coins_manager.gd` | `alltime_reward_bands`, `last_daily_reward_date` fields (load/save/reset); reward tables + band index; `maybe_reward_alltime()`; `grant_daily_rewards_if_due()`; `daily_rank_reward_granted` signal; day-index date helpers |
| `game_over.gd` | in `_submit_and_show_rank`, call `maybe_reward_alltime` after `my_rank`; surface the coins on the rank pill |
| `home_screen.gd` | after `register_login`, call `grant_daily_rewards_if_due`; connect `daily_rank_reward_granted` → show summary popup |
| `daily_rank_reward_popup.gd` | **new** self-built modal summarizing yesterday's placements + total (modeled on `daily_claim_popup.gd`) |
| `firestore.rules` | daily `match` → validate `data.uid == auth.uid` (create/update) and `resource.data.uid == auth.uid` (delete); `dailyRowOk()` requires `uid is string`; `/users` validators for `alltime_reward_bands` (map) and `last_daily_reward_date` (string) |

No new composite indexes. Storage grows to ≤14 days of tiny daily rows (TTL-capped).

### Rollout / deploy order (important)

- **Deploy `firestore.rules` together with the client update.** The new client
  writes daily rows as `{date}__{uid}`; under the *old* rules
  (`allow write: if isUser(docId)`) those writes would be denied.
- The rules are written to accept **both** the new shape and the **legacy**
  shape (doc id == uid, no `uid` field) so already-released app versions keep
  writing daily scores until their users update. Once old versions age out, the
  legacy branch (`dailyOwner`'s `docId == uid`, and the legacy delete clause) can
  be removed.
- TTL: no policy change — the existing `expires_at` TTL policy still applies; we
  just write a farther-out expiry (14 days).
- **Transient on deploy day only:** a player who has both a lingering legacy
  `{uid}` row and a new `{date}__{uid}` row for the same day may appear twice on
  the live board until the legacy row TTL-expires (~within a day). The reward
  flow is unaffected (it reads `{date}__{uid}` for a *closed* day).

## 5. Test checklist (editor sim + on-device)

- All-time: 73→48→32→9→6 sequence pays 150, 0, 350, 0 in order; per-difficulty independence.
- Daily: place #1 today, open tomorrow → +500 once; reopen same day → nothing.
- Daily delayed: play, skip a day, return within 14 days → still paid once.
- Daily forfeit: gap >14 days → nothing (rows swept).
- Live daily board still shows only today; top-N and neighborhood identify "me" correctly with the new keying.
- Account deletion removes all date-partitioned daily rows.
</content>
</invoke>
