# Unity Ads — manual steps

Code is done. These are the parts only you can do. Follow in order.

---

## 1. Unity dashboard — done

Game ID `800274606`, with `Rewarded_Android`, `Interstitial_Android` and
`Banner_Android`. Already in the code. Two notes:

- **Verify the formats** under Monetization → Ad Units: `Rewarded_Android` must be
  format **Rewarded**, `Interstitial_Android` must be **Interstitial**. A wrong
  format initializes fine and then never fills, with no error in the log.
- **`Banner_Android` is unused.** Simon has no banner surface. Leave it or delete
  it; an idle ad unit costs nothing.

The arena interstitial shares `Interstitial_Android` for now. To split arena
revenue out in reporting later: create an Interstitial-format ad unit named
`Arena_Interstitial_Android`, then set `ARENA_INTERSTITIAL_AD_UNIT` in
`ad_manager_unity.gd` to that string. One line, nothing else changes.

---

## 2. Build the Android plugin — done

Both AARs are built and installed:

```
addons\GodotUnityAds\bin\debug\GodotUnityAds-debug.aar     (11 KB)
addons\GodotUnityAds\bin\release\GodotUnityAds-release.aar (11 KB)
```

11 KB is correct — the Unity SDK is deliberately not bundled; Gradle pulls
`com.unity3d.ads:unity-ads:4.18.1` at export time via `export_plugin.gd`.

To rebuild after editing the Kotlin:

```bat
cd plugin_unityads
build_plugin.bat
```

The script now pins JDK 17 (21 and 25 are also installed and AGP 8.1 rejects both),
copies `godot-lib.aar` out of the project's Android build template, and writes
`local.properties` pointing at `C:\Users\USER\android_sdk`.

---

## 3. Open Godot and confirm

- **Project Settings → Plugins**: `GodotUnityAds` enabled, `AdMob` gone.
- **Project Settings → Autoload**: `ConsentManager` listed **above** `AdManager`,
  and `AdManager` points at `res://ad_manager_unity.gd`.

Both are already written into `project.godot` — you're only checking the editor
agrees.

---

## 4. Test on a device

Export a **debug** APK and install it. Debug builds run `testMode = true`, so
Unity serves its own test creatives and bills nobody.

Check:

- Rewarded ad plays; the reward lands only when watched to the end, not on skip.
- Interstitial appears at game over, and not twice inside 120 s.
- Arena interstitial appears after a contest. It shares the 120 s cooldown with the
  game-over one, so leave a gap before testing it or it will correctly not show.

Consent dialog: it only appears in the EEA/UK. To force it, temporarily make
`consent_manager.gd` `_country_code()` return `"DE"`. Run `ConsentManager.reset()`
to clear a stored answer and see it again.

Logs:

```bash
adb logcat -s GodotUnityAds:V UnityAds:V
```

---

## 5. Delete AdMob

Only after step 4 passes:

```
addons/admob/          (whole folder)
ad_manager.gd
ad_manager.gd.uid
```

It's already disabled in `project.godot`, so it no longer injects the banned
`APPLICATION_ID` into the manifest — but delete it so it can't come back.

---

## 6. Play Console

**App content → Data safety.** The advertising ID is now collected and shared
with **Unity Technologies**, not Google. Update the third-party list and the
purpose. Leave the "contains ads" declaration on.

---

## 7. Go live

Export a **signed release** build. `_live_ads()` becomes true, `testMode` becomes
false, and live inventory serves. There is no separate live/test ID to swap — one
boolean, decided by the build type.

First revenue takes ~24 h to appear in the Unity dashboard.

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `No placement configured for id` | Ad unit ID mismatch or not created on the dashboard |
| Initializes, never fills | Ad unit format wrong (Interstitial vs Rewarded) |
| Nothing at all, no log lines | Plugin AAR not built, or addon not enabled |
| Works in debug, not release | Release AAR missing from `bin/release/` |
| Reward granted on skip | Should be impossible — reward only fires on `COMPLETED` |

---

## Reference

- Ad units: <https://docs.unity.com/en-us/grow/dashboard/ad-units/create>
- Consent API: <https://docs.unity.com/en-us/grow/ads/privacy/gdpr/set-up-gdpr-consent>
