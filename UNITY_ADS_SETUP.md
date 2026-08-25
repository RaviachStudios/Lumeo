# Unity Ads — manual steps

Code is done. These are the parts only you can do. Follow in order.

---

## 1. Unity dashboard — done

Game ID `800274606`, with `Rewarded_Android`, `Interstitial_Android` and
`Banner_Android`. Two notes:

- **`Rewarded_Android` is the only ad unit the game uses.** Verify its format under
  Monetization → Ad Units: it must be **Rewarded**. A wrong format initializes fine
  and then never fills, with no error in the log.
- **`Interstitial_Android` and `Banner_Android` are unused.** Leave them or delete
  them; idle ad units cost nothing.

**Interstitials were removed from the game.** They ran at solo game over, on
arrival at the arena results board, and on leaving a room, and Unity filled them
with long un-skippable video — not something to serve a player who just lost a
round and asked for nothing. The only ad left is the opt-in "watch an ad to
replay" reward. `ad_manager_unity.gd` no longer loads or shows any interstitial,
and there is no frequency cap in it any more because there is nothing to cap.

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

- **Project Settings → Plugins**: `GodotUnityAds` enabled.
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
- The "watch ad to replay" button only appears while an ad is actually loaded.
- **No ad appears anywhere else** — not at game over, not on the arena results
  board, not on leaving a room.

Consent dialog: it only appears in the EEA/UK. To force it, temporarily make
`consent_manager.gd` `_country_code()` return `"DE"`. Run `ConsentManager.reset()`
to clear a stored answer and see it again.

Logs:

```bash
adb logcat -s GodotUnityAds:V UnityAds:V
```

---

## 5. AdMob is gone

Done — nothing to do here. `addons/admob/`, `ad_manager.gd`, `ad_manager.gd.uid`
and the iOS `ios/plugins/` tree (which held nothing but the AdMob xcframeworks)
have all been deleted, so the plugin can't come back and can no longer inject the
banned `APPLICATION_ID` into the manifest.

If you ever see an `admob` folder reappear under `addons/` or in the Android
export staging area, it's stale — delete it.

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
| Initializes, never fills | `Rewarded_Android` format is not **Rewarded** |
| Nothing at all, no log lines | Plugin AAR not built, or addon not enabled |
| Works in debug, not release | Release AAR missing from `bin/release/` |
| Reward granted on skip | Should be impossible — reward only fires on `COMPLETED` |

---

## Reference

- Ad units: <https://docs.unity.com/en-us/grow/dashboard/ad-units/create>
- Consent API: <https://docs.unity.com/en-us/grow/ads/privacy/gdpr/set-up-gdpr-consent>
