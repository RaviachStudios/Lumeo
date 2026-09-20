# LevelPlay ads — manual steps

Replaces `UNITY_ADS_SETUP.md`. The code is done and the plugin is built. What is
left is the parts only you can do, in the dashboard and the Play Console.

The App Key and both ad unit IDs are in. What remains is dashboard demand,
app-ads.txt, and the Play Console / privacy disclosures.

---

## 1. Dashboard identifiers — **done**

All three are in `ad_manager_levelplay.gd`:

```gdscript
const APP_KEY := "27a21e7e5"
const INTERSTITIAL_AD_UNIT := "t80zvr7rlv90r4op"   # lumeo_inter
const REWARDED_AD_UNIT := "0g9ab47aerk4ud1a"       # lumeo_reward
```

`INTERSTITIAL_PLACEMENT` / `REWARDED_PLACEMENT` stay `""`. Those are *placement*
names, a named slot inside an ad unit — not the ad unit names `lumeo_inter` /
`lumeo_reward`. You have none, so each unit's default placement is used.

While you are there, confirm each unit's **format**: `lumeo_inter` must be
Interstitial and `lumeo_reward` must be Rewarded. A unit of the wrong format
initializes fine and then never fills, with no error saying so — the same trap
Unity Ads had.

### About the rewarded unit's reward

The dashboard reward on `lumeo_reward` (name `multiply_coins`, amount 1) is
deliberately **ignored** by the game. The payout is computed from the run's own
earnings — 4× whatever that run paid — which is not a number the dashboard can
know. The reward callback is used purely as "the player watched it through".

So leave the dashboard values as they are; nothing reads them. They only matter if
you ever turn on server-to-server reward callbacks, which we do not use.

---

## 2. Turn on some demand

> **What is actually enabled, as of 1.0.60:** one network per ad unit, and device
> logs show it is Unity Ads — ironSource never appears in the waterfall. Check
> **Setup → Networks** before trusting the rest of this section; it was written
> expecting ironSource to be the one that was on.

**ironSource alone is enough to ship.** It is a real network with real fill, it is
built into `mediation-sdk`, and it needs no adapter and no extra setup. Ads will
serve and pay with nothing else enabled, so this step does not block a release.

What it costs you is the auction. With one network there isn't one: ironSource
names its price and that is the price. Mediation earns more than a single network
because several bidders compete for the same impression, and the second network is
where most of that gain comes from — after about four the curve flattens.

**The cheapest next one is Unity Ads**, because you already have the account: game
ID `800274606`, from the setup this replaced. On the dashboard under
**Setup → Networks**, add Unity Ads, paste that game ID and the ad unit IDs from
the Unity dashboard, and enable it for both of Lumeo's ad units. This is the
network Lumeo actually runs on today, and both halves of it are in the export:

```gdscript
"com.unity3d.ads-mediation:unityads-adapter:5.12.0",
"com.unity3d.ads:unity-ads:4.18.1",
```

**Both lines, always.** A LevelPlay adapter's POM declares no dependencies, so the
network SDK it drives is never pulled in for you — check the POM on Maven Central
before you assume otherwise. An adapter without its SDK is worse than neither:
the network is in the waterfall, cannot be instantiated, and every load comes
back `509 Mediation No fill` with nothing in the log but one line at init,
`AdapterVersionScanner: failed to get version for <network>`. That shipped once
already, in 1.0.60.

Anything beyond that (AppLovin, Meta, Vungle, Mintegral…) needs three things: the
network configured on the LevelPlay dashboard, **and** its adapter added to
`_get_android_dependencies` in `addons/GodotLevelPlay/export_plugin.gd` as
`com.unity3d.ads-mediation:<network>-adapter:<version>`, **and** that network's own
SDK beside it, then a re-export. Miss the adapter and LevelPlay simply never calls
that network — no error, just no bids. An adapter with no dashboard configuration
sits idle, so a spare line costs only a little APK size.

---

## 2b. app-ads.txt — one line still missing

Buyers do not follow a link from the app. They read the **Website** field on the
Play Store listing, take that domain, and fetch `/app-ads.txt` at its **root**.

Your listing points at **lumeo-game.web.app**, so the file that matters is
`public/app-ads.txt` in this repo, served by Firebase Hosting.

### State of play

| | |
| --- | --- |
| `OWNERDOMAIN=lumeo-game.web.app` | added |
| Unity block (122 lines) | kept — still valid demand, now bidding through the auction |
| **ironSource line** | **missing — you have to add it** |

### The one thing to do

Get your Publisher ID from the LevelPlay platform: account avatar (bottom left) →
**Account → API tab → Publisher ID**. Then in `public/app-ads.txt`, replace the
commented TODO line with a real one:

```
ironsrc.com, <your publisher id>, DIRECT
```

Then publish:

```bash
firebase deploy --only hosting
curl https://lumeo-game.web.app/app-ads.txt | head
```

Crawlers re-scan every few days to a week, so do this before you look at eCPM and
conclude something is broken.

### Why this line is the important one

ironSource Ads **direct demand was sunset on 30 April 2026**. What "ironSource"
serves now is ironSource Exchange — programmatic demand. Programmatic buyers are
exactly the ones that check app-ads.txt and bid down, or refuse to bid, on
inventory it cannot vouch for.

With ironSource currently your only enabled network, this single missing line sits
between you and most of your fill. It is worth more right now than anything else
on this page.

### Loose end

`raviachstudios.github.io/app-ads.txt` also exists and contains one stale Google
AdMob `DIRECT` line for the disabled account. It is not the crawled domain, so it
changes nothing — but it authorises a dead account, and deleting it costs a
commit to the `raviachstudios.github.io` repo (a different repo from
`Raviach-policy`).

---

## 3. Godot: check the plugin swap took

Already written into `project.godot` — you are only confirming the editor agrees.

- **Project Settings → Plugins**: `GodotLevelPlay` **enabled**, `GodotUnityAds`
  **disabled**.
- **Project Settings → Autoload**: `ConsentManager` listed **above** `AdManager`,
  and `AdManager` points at `res://ad_manager_levelplay.gd`.

> **`GodotUnityAds` must stay disabled.** Both export plugins declare
> `com.unity3d.ads:unity-ads`, so with both enabled Gradle sees it twice. That is
> a build-time failure, not a runtime bug — you would find out during the export,
> but it costs you the export.

The old `ad_manager_unity.gd`, `plugin_unityads/` and `addons/GodotUnityAds/` are
left in the repo on purpose, as a working rollback. Nothing loads them.

---

## 4. Rebuild the plugin (only if you edit the Kotlin)

Both AARs are already built and installed:

```
addons\GodotLevelPlay\bin\debug\GodotLevelPlay-debug.aar     (14 KB)
addons\GodotLevelPlay\bin\release\GodotLevelPlay-release.aar (14 KB)
```

14 KB is correct — the LevelPlay SDK is deliberately not bundled; Gradle pulls
`com.unity3d.ads-mediation:mediation-sdk:9.6.0` at export time via
`export_plugin.gd`. To rebuild:

```bat
cd plugin_levelplay
build_plugin.bat
```

The script pins JDK 17 (21 and 25 are also installed and AGP 8.1 rejects both),
copies `godot-lib.aar` out of the project's Android build template, and writes
`local.properties` pointing at `C:\Users\USER\android_sdk`.

If you bump the SDK version, bump it in **both** `plugin_levelplay/build.gradle.kts`
and `addons/GodotLevelPlay/export_plugin.gd`. Compiling against one version and
running against another gives you a `NoSuchMethodError` at the first ad request,
nowhere near the file that caused it.

---

## 5. Testing — read this, it is not like Unity Ads

**LevelPlay has no test-mode boolean.** Unity Ads had one flag that made every ad
a free test creative. LevelPlay does not: ads are live from the first request.

So the defence is different in kind, and it is deliberate: **on a debug build this
game does not initialize the ad SDK at all.** No init, no requests, no
impressions, nothing anyone can be billed for. That is `_should_run_ads()` in
`ad_manager_levelplay.gd`.

To actually see ads on a device:

1. Register the device in the dashboard under **Test Devices** (it wants the
   advertising ID or the IDFA/GAID, which the dashboard's instructions show you
   how to read).
2. Set `FORCE_ADS_IN_DEBUG := true` in `ad_manager_levelplay.gd`.
3. Export a **debug** APK, install, play.
4. **Set it back to `false` before you commit.** Developer impressions on live
   inventory are what got the old AdMob account disabled.

The better tool is LevelPlay's **Test Suite**, which lists every network
configured for the app and fires a test ad per unit — the fastest way to tell "the
dashboard is wrong" from "the code is wrong". `AdManager.open_test_suite()` opens
it; it needs the SDK initialized, so it only does anything with
`FORCE_ADS_IN_DEBUG` on. Wire it to a hidden debug row when you need it.

Logs:

```bash
adb logcat -s GodotLevelPlay:V IronSource:V LevelPlay:V
```

---

## 6. What to check on the device

- **Rewarded, in-game**: the "Watch a video to replay" button appears only while
  an ad is loaded, and the replay lands only when the ad is watched through — not
  on a skip.
- **Rewarded, game over**: "Watch a video for 4× coins" appears under the
  coins-earned pill, and only when the run actually earned coins. After watching,
  the pill rewrites to 4× the amount and blooms once. After a skip, the button is
  gone and the coins are unchanged — that is intended.
- **Interstitial**: appears in the gap between the round ending and the game-over
  screen, on **every** game over (caps are off — see step 7). If it skips a game,
  that is no fill, not policy.
- Coins land in the wallet, once. Play a run, watch the 4×, background the app,
  come back: the balance should not have moved again.

---

## 7. The interstitial's frequency caps — currently OFF

Set to show at **every game over**, as chosen. All three constants at the top of
`ad_manager_levelplay.gd` are 0:

| Constant | Now | If you ever want to pace it |
| --- | --- | --- |
| `SKIP_FIRST_GAMES` | 0 | 3 — a new install sees none until its 4th game |
| `MIN_GAMES_BETWEEN` | 0 | 3 — at most one per three finished games |
| `MIN_SECONDS_BETWEEN` | 0 | 180 — and never twice inside three minutes |

The machinery is wired up and tested, just switched off, so pacing is a
three-number edit rather than a rewrite. Counters live in `user://ad_policy.cfg`
and survive a relaunch — a cap that resets every launch is not a cap.

**The one number to watch after this ships.** An interstitial on every game over
is the setting that most reliably teaches people to close the app at game over,
and a shorter session is worth less than the extra impressions gain. Nothing in
the code will now stop that. If games-per-session or day-1 retention drops in the
Play Console after release, this table is the first thing to move; `3 / 3 / 180`
is a reasonable conservative baseline to fall back to.

**You asked for an ad the player can dismiss immediately.** Worth being straight
about what is and isn't in your control here: the interstitial format is the
skippable one, and its close button is the format's own, drawn by whichever
network won the auction — you cannot force "X appears at 0 seconds" from the SDK.
Most networks show it after a few seconds; some rewarded-style creatives sold as
interstitials are slower. What you *can* control is on the dashboard, per network:
prefer static/playable interstitials over video where the network offers that
choice, and drop any network whose interstitials behave like unskippable video.
That is exactly why interstitials were pulled from this game once before.

The rewarded ad is the opposite and has no cap: the player asks for it by name and
is paid for it.

---

## 8. Remove-ads and the 4× offer

`CoinsManager.has_remove_ads` suppresses the interstitial completely — it is not
loaded and never shown.

It deliberately does **not** suppress either rewarded ad. Someone who bought
"remove ads" bought freedom from ads they did not ask for; taking away the button
they press themselves to quadruple their coins would make the purchase a
downgrade. If you disagree, the one place to change it is `show_rewarded` /
`_build_multiply_offer`.

---

## 9. Consent

`consent_manager.gd` still owns the GDPR/CCPA answer, and now feeds it to
`LevelPlayPrivacySettings.setGDPRConsent()` / `setCCPA()` before the SDK
initializes.

`DISCLOSURE_VERSION` was bumped to **2**, so every player is asked again on their
next launch. That is required, not optional: they consented to data going to Unity
Ads, and it now goes to Unity LevelPlay and every network in its auction. A wider
set of recipients than the one they agreed to is a new disclosure.

The dialog text in `consent_dialog.gd` was updated to say so.

---

## 10. Play Console

**App content → Data safety.** The advertising ID is now shared with **Unity
LevelPlay (Unity Technologies) and its mediated ad networks** — not with Unity Ads
alone. Update the third-party list to name every network you actually enable in
step 2, and keep the "contains ads" declaration on.

Your privacy policy (`privacy_policy.html`, and the published copy at
raviachstudios.github.io) needs the same edit.

---

## 11. Go live

Export a **signed release** build. `_should_run_ads()` becomes true, the SDK
initializes, and live inventory serves. There is no test/live ID pair to swap.

First revenue takes ~24 h to appear in the dashboard, and mediation eCPM takes
several days to settle as the auction learns.

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Nothing at all, no `GodotLevelPlay` log lines | Plugin AAR not built, or the addon is not enabled |
| `APP_KEY is empty` in the log | Step 1 not done |
| Initializes, never fills | Ad unit format wrong on the dashboard, or no network enabled/adapter missing |
| `509: Mediation No fill` on every load, forever | A configured network's adapter is in the build but its SDK is not — look for `AdapterVersionScanner: failed to get version for <network>` at init (step 2) |
| `ERROR_CODE_LOAD_BEFORE_INIT_SUCCESS_CALLBACK` | An ad was requested before init finished — should be impossible from this code; check for a second AdManager |
| Fills, but eCPM is very low | app-ads.txt missing/stale at the crawled domain (step 2b), or only one network enabled (step 2) |
| Duplicate class `com.unity3d.ads.*` at export | `GodotUnityAds` got re-enabled alongside the Unity adapter (see step 3) |
| No ads in a debug build | Working as designed — see step 5 |
| Rewarded pays on skip | Should be impossible: the reward is latched only by `onAdRewarded` |
| 4× button never appears | The run earned 0 coins, no rewarded ad was loaded, or the player is signed out |

---

## Reference

- Android SDK integration: <https://docs.unity.com/en-us/grow/levelplay/sdk/android/sdk-integration>
- Interstitial: <https://docs.unity.com/en-us/grow/levelplay/sdk/android/interstitial-integration>
- Rewarded: <https://docs.unity.com/en-us/grow/levelplay/sdk/android/rewarded-ads-integration>
- Privacy / regulation settings: <https://docs.unity.com/en-us/grow/levelplay/sdk/android/regulation-advanced-settings>
- SDK on Maven Central: <https://central.sonatype.com/artifact/com.unity3d.ads-mediation/mediation-sdk>
