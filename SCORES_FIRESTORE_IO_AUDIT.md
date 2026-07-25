# Scores / Leaderboard Firestore I/O Audit

Worst-case read & write counts for the **score-saving subsystem** (all-time boards,
daily boards, score histogram, and the daily/all-time reward writes on the user
doc). Scope is scores only — the Arena **contests/lobby** subsystem is separate and
not counted here.

## Assumptions ("booming game" worst case)

Every number below is the **worst case**, i.e. the most reads/writes a path can bill:

- The signed-in player is **outside the top-20 on every board** (this is what makes
  the "my row + neighborhood + rank" branch fire — a top-20 player skips all of it).
- The player just set a **new personal best on both the all-time and daily board**
  (so every write path fires; a non-improving score writes nothing).
- All boards are large, so every top-N query returns a full page.
- Constants (from `leaderboard_manager.gd` / `coins_manager.gd`):
  `GLOBAL_TOP_N = 20`, `NEIGHBOR_COUNT = 3`, `HIST_SHARDS = 10`, `DIFFS = 3`,
  daily `_SWEEP_LIMIT = 12`, `DAILY_RANK_WINDOW_DAYS = 14`.
- **P** = players who posted a score on a given day. Booming example: **P = 50,000**.

### Firestore billing rules applied

- `runQuery` (structured query): **1 read per document returned** (a `limit N` query
  bills ≤ N; an empty result still bills a 1-read minimum). It does **not** bill for
  documents scanned but not returned.
- `runAggregationQuery` (`count()`): **1 read per 1,000 index entries matched**,
  rounded up → `⌈matched / 1000⌉`.
- `batchGet`: 1 read per document returned (10 histogram shards = 10 reads, one HTTP call).
- `get` / single `_rest_get`: 1 read.
- Deletes are billed as **delete** operations (priced like writes), shown in the write table.

### Reusable per-board sub-costs (player outside top-20, with a row)

| Sub-cost | Composition | Reads |
|---|---|---|
| **G** — one all-time board load (`load_global` → `_load_board`) | 20 top + 1 my-row + 10 histogram-rank + 3 above + 3 below | **37** |
| **D** — one daily board load (`load_daily` → `_load_board`) | 20 top + 1 my-row + `⌈P/1000⌉` count-rank + 3 above + 3 below | **27 + ⌈P/1000⌉** → **77** @ P=50k |

The **20-row top list dominates every board** and is the same whether or not a
histogram exists — a histogram only replaces the *rank* term (the 10 for all-time,
the `⌈P/1000⌉` for daily).

---

## READS

| When in the flow | What is read | Use (context) | Worst-case reads (booming) |
|---|---|---|---|
| Sign-in / boot | `get_my_score` × 3 (`global_{diff}/{uid}`) | Hydrate local best per difficulty | **3** |
| Sign-in / boot | Warm all-time family: 3 × **G** | Preload leaderboards for instant screen-open | **111** |
| Sign-in / boot | Warm daily family: 3 × **D** | Same | **231** (3×77) |
| Sign-in / boot | Daily expiry sweep: 3 queries (`limit 12`) | GC expired daily rows | **36** (≈3 steady state) |
| First launch **of the day** | Daily reward: per diff → 1 row read + 1 `count()` agg, × 1 day | Compute yesterday's *placement* to pay coins | **3 × (1 + ⌈P/1000⌉) = 153** |
| First launch after **N-day absence** | Same, × up to `DAILY_RANK_WINDOW_DAYS` days | Back-pay missed placement rewards | up to **14 × 153 ≈ 2,142** |
| Game over — new high | `submit_score` compare-read (global row) | Check score beats stored all-time best | **1** |
| Game over — new high | `submit_score_daily` compare-read (daily row) | Check beats today's best | **1** |
| Game over — new high | `load_global` (1 × **G**) | Show rank pill + trigger all-time reward | **37** |
| Open leaderboards screen | Warm-cache hit (`take_warm`) | Paint board with no loader | **0** (up to 111 or 231 on a manual refresh of a family) |
| Open profile card | `cached_rank` hit; else `load_global` × up to 3 | Show all-time rank | **0** (up to **111** on cache miss) |

**Cold open on the first launch of a day (booming):**
`3 + 111 + 231 + 36 + 153 ≈ 534 reads`. A returning-after-2-weeks player can spike to
~2.5k from the reward back-pay scan alone.
**Every subsequent open the same day:** warm cache → the boot warm is still re-run on
each sign-in event, so ~381 reads. (Boards are always pre-warmed so a tab switch /
leaderboard open is instant — never a loading screen. Lazy-loading is intentionally
rejected.)
**Per new-high game over:** `1 + 1 + 37 ≈ 39 reads`.

---

## WRITES

| When in the flow | What is written | Use (context) | Worst-case writes (booming) |
|---|---|---|---|
| Game over — new **all-time** high | `set global_{diff}/{uid}` | Persist all-time best score | **1** |
| Game over — new all-time high | Histogram `:commit` increment (±1, 1 random shard) | Keep scale-invariant rank histogram in step | **1** |
| Game over — new **daily** high | `set daily_{diff}/{date}__{uid}` | Persist today's best (no histogram) | **1** |
| First launch of the day | User-doc merge (coins + `last_daily_reward_date`) | Pay daily placement reward + stamp "resolved through" | **1** |
| Game over — new all-time **band** | User-doc merge (coins + `alltime_reward_bands`) | Pay all-time milestone reward | **1** |
| Sign-in / boot (inside warm) | Daily sweep **deletes**: up to 12 × 3 | Remove expired daily rows | up to **36 deletes / pass** |
| Maintenance (rare, self-heal) | `rebuild_histograms`: `HIST_SHARDS × 3` | Recompute histogram after drift | **30** |

**Per new-high game over:** `1 (global row) + 1 (histogram) + 1 (daily row) = 3 writes`
(+1 if it also clears a new all-time reward band → 4).
**Steady-state daily sweep:** ~0 deletes most passes; up to 36 while draining a backlog.

---

## Where the cost actually concentrates (refactor levers)

1. **The 20-row top lists are 100% of the fixed read cost.** Six boards × 20 ≈ **342
   reads** just for the lists, every warm-up. A histogram does **nothing** for this.
   → **IMPLEMENTED.** The top-N lists are materialized into **one doc per family**
   (`board_top/global`, `board_top/daily`), each holding all three difficulties'
   top-20. A warm-up reads **2 docs instead of 342** (one per family, all tabs warmed
   in that read); a manual single-board refresh is **1 read instead of 20**. The
   per-player my-row / rank / neighborhood reads are unchanged (they only fire when a
   player is *outside* the top-20).

   The doc is written **server-side, not by clients** — Cloud Functions
   (`functions/index.js`) are the only writers, so there's no last-write-wins
   contention and the lists are **un-forgeable**: `firestore.rules` makes
   `board_top/*` client-read-only, and the Admin SDK bypasses rules. Missing/stale
   doc → the client falls back to its old live top-N query, so nothing breaks before
   the functions are deployed or right after the daily rollover.

   Maintenance is **event-triggered, gated on a real top-N change** (not a 5-min
   schedule): `onDocumentWritten` on each `global_*` / `daily_*` collection reads
   the family's `board_top` doc in a transaction, and **writes only when the score
   actually enters/reorders the top 20**. So the ~99% of submits that don't crack
   the top 20 cost one read and no write — no write-hotspot on the combined doc, and
   the list is fresh within seconds instead of up to 5 min. The transaction handles
   two entrants at once; the daily doc rolls over to the new day on the first write
   of the day. `rebuildLeaderboardsNow` (HTTPS) remains for seeding/healing.

   Lazy-loading is **not** an option: boards must stay pre-warmed so entering the
   leaderboard or switching a tab is instant, never a loading screen. This
   materialization keeps that instant feel while cutting the read cost.

2. **The daily `count()` rank is the only score read that scales with daily volume**
   (`⌈P/1000⌉`): ~1 read at <1k players/day, but ~50 reads/board at 50k/day. It used
   to fire again per-diff in the login reward grant — no longer (see lever 3). It now
   fires only for the *live neighborhood* of a player outside today's top-20. A
   **daily histogram** would cap this at 10 reads, but only pays off above ~10k
   players/day; consider it only if daily volume is genuinely that large.

3. **The placement reward was inherently read-heavy** (`153+` reads on the first open
   of each day, up to ~2,142 when back-paying an absence) because rank is relational
   and the client had no server to freeze it at midnight.
   → **IMPLEMENTED (server-side).** A scheduled Cloud Function (`closeDailyBoards`,
   00:05 UTC) reads the **top 50** of each of yesterday's daily boards (only the top
   50 earn coins), credits each winner's wallet directly, writes a date-keyed receipt
   into `pending_daily_rewards` on `/users/{uid}`, then deletes yesterday's rows. The
   client's per-open reward reads drop from `153+` (and the up-to-2,142 back-pay
   scan) to **0** — it just reads its own wallet doc (already loaded), shows the
   popup, and clears the receipt. Idempotent via the `last_daily_reward_date`
   watermark (a retry, or an old client honoring the same watermark, never double-pays).
   Placement rewards are now **authoritative + un-forgeable** and the daily-row
   cleanup moves from the client sweep to this job. Server cost is flat: ~150 reads +
   ≤150 user writes/day, independent of player count.
