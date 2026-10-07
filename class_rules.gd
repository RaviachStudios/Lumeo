extends RefCounted

# The rules of a Class Game, in one place, shared by EVERY party that has to agree on
# them: the teacher's referee (class_referee.gd), each student's game (game.gd class
# mode), the class screen, and the device-test simulator (tools/class_sim/class_sim.js,
# which mirrors these numbers by hand — change one, change both).
#
# Nothing here touches the network. The whole timing model rests on the teacher and
# every student computing the SAME deadline for a round from the same two inputs (the
# round number and the teacher's `round_at_ms` stamp), so that no device ever has to
# tell another one "time's up" — each works it out.
#
# Bump VERSION whenever a number below changes. A class carries the version it was
# created with, and a device on a different version is refused at the door (an older
# build would time rounds differently from the referee and be counted out unfairly).

# 2: nobody is knocked out any more — a missed round scores 0 and the student plays on;
#    the game ends after the teacher's chosen 10/15 rounds or a round nobody completed.
const VERSION := 2

const MAX_ROUNDS := 15                 # hard cap (rules + sequence length)
const ROUND_CHOICES := [10, 15]        # what the teacher can pick in the lobby
const DEFAULT_ROUNDS := 15
const MAX_STUDENTS := 45
const MIN_STUDENTS := 2           # a one-student game would end the moment it started

# Students' report rows are spread across SHARDS docs so a burst of finishes (45
# students all completing a round within a second) is ~9 writes per doc instead of
# 45 on one. SHARD_CAP mirrors the rules' per-shard size limit; it is comfortably
# above MAX_STUDENTS / SHARDS so a skewed hash can't lock anyone out.
const SHARDS := 5
const SHARD_CAP := 15

const PID_LEN := 6
const NAME_MAX := 20

# Per-round time limits for completing the WHOLE sequence: rounds 1-5, 6-10, 11-15.
const LIMITS := [10.0, 14.0, 18.0]

# The show before a round: round 1 gets a 3-2-1 (plus a beat for the game screen to
# finish building — it is opened by the very push that starts round 1), later rounds
# a short "Round N" banner.
const BANNER_FIRST := 4.0
const BANNER_NEXT := 1.5
# game.gd waits this long between "Watch carefully..." and the first flash.
const PRE_SEQUENCE := 0.6

# Network allowance added on top of a round's own length before the referee stops
# waiting for a student's report. Covers listener delivery to the student, their
# report's write, and the listener delivery back to the teacher.
const SLACK := 6.0
# A student who receives a round update this late (measured against the teacher's
# server-time stamp) cannot finish inside the referee's deadline even with a perfect
# run, so they are told so instead of being shown a round they cannot win.
# SLACK minus a margin for the report's own trip back.
const LATE_LIMIT := 4.5

# Hard-mode sequence speed. MUST match GameState.set_difficulty("hard") and the
# per-level ramp in game.gd _next_round / _class_on_round.
const HARD_FLASH := 0.42
const HARD_GAP := 0.13
const HARD_SPEED_INC := 0.038

# Expiry horizons (unix seconds added to "now"). The server sweep deletes a class
# once expires_unix passes; every one of these is refreshed by a write the game
# already makes, so there are no keepalive-only writes.
const LOBBY_TTL := 60 * 60
const LOBBY_REFRESH_BELOW := 10 * 60   # teacher re-stamps a lobby with < this left
const PLAY_TTL := 30 * 60
const DONE_TTL := 10 * 60

const MAX_POINTS := 100                # per round

static func limit(r: int) -> float:
	return LIMITS[clampi((r - 1) / 5, 0, LIMITS.size() - 1)]

static func banner(r: int) -> float:
	return BANNER_FIRST if r <= 1 else BANNER_NEXT

static func flash_time(r: int) -> float:
	return maxf(0.18, HARD_FLASH - (r - 1) * HARD_SPEED_INC)

static func flash_gap(r: int) -> float:
	return maxf(0.08, HARD_GAP - (r - 1) * HARD_SPEED_INC * 0.5)

# Seconds from the moment a round's banner starts until the sequence has finished
# playing and the player's input clock starts.
static func playback(r: int) -> float:
	return PRE_SEQUENCE + r * (flash_time(r) + flash_gap(r))

# The referee's deadline for round `r`, in server milliseconds.
static func deadline_ms(round_at_ms: int, r: int) -> int:
	return round_at_ms + int((banner(r) + playback(r) + limit(r) + SLACK) * 1000.0)

# When the round SHOULD be over for a student who played it on time (no slack) —
# what a waiting student counts down to.
static func expected_end_ms(round_at_ms: int, r: int) -> int:
	return round_at_ms + int((banner(r) + playback(r) + limit(r)) * 1000.0)

# Points for one completed round: the share of the time limit left over, out of 100.
# Always at least 1 — finishing at all is worth something.
static func points(time_left: float, lim: float) -> int:
	if lim <= 0.0:
		return 1
	return clampi(int(ceil(MAX_POINTS * clampf(time_left, 0.0, lim) / lim)), 1, MAX_POINTS)

# Which report shard a student's row lives in. Deliberately NOT String.hash(): the
# same account on two devices (and the JS simulator) must land on the same shard, so
# this is a plain, fully specified polynomial hash.
static func shard_of(uid: String) -> int:
	var h := 0
	for i in uid.length():
		h = (h * 31 + uid.unicode_at(i)) % 1000003
	return h % SHARDS

static func shard_id(pid: String, k: int) -> String:
	return "%s_%d" % [pid, k]

static func valid_pid(pid: String) -> bool:
	if pid.length() != PID_LEN:
		return false
	for c in pid:
		if "0123456789".find(c) < 0:
			return false
	return true

static func valid_rounds(n: int) -> int:
	return n if ROUND_CHOICES.has(n) else DEFAULT_ROUNDS

# Final ranking. `rows` = [{uid, n, s, c, t}] where s = total score (a missed round
# scores 0), c = rounds completed, t = total completion time in ms. Sorted by score
# (highest first), then rounds completed (most first), then time (lowest first).
# Exact ties share a place (1, 1, 3). Adds `p`.
static func rank(rows: Array) -> Array:
	var out := rows.duplicate(true)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["s"]) != int(b["s"]):
			return int(a["s"]) > int(b["s"])
		if int(a["c"]) != int(b["c"]):
			return int(a["c"]) > int(b["c"])
		if int(a["t"]) != int(b["t"]):
			return int(a["t"]) < int(b["t"])
		return String(a["n"]) < String(b["n"]))
	for i in out.size():
		var e: Dictionary = out[i]
		if i > 0:
			var prev: Dictionary = out[i - 1]
			if int(prev["c"]) == int(e["c"]) and int(prev["s"]) == int(e["s"]) \
					and int(prev["t"]) == int(e["t"]):
				e["p"] = int(prev["p"])
				continue
		e["p"] = i + 1
	return out

static func clean_name(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		s = "Student"
	if s.length() > NAME_MAX:
		s = s.substr(0, NAME_MAX)
	return s
