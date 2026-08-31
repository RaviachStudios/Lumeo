package com.raviachstudios.lumeo.levelplay

import android.content.Context
import android.telephony.TelephonyManager
import android.util.Log
import com.unity3d.mediation.LevelPlay
import com.unity3d.mediation.LevelPlayAdError
import com.unity3d.mediation.LevelPlayAdInfo
import com.unity3d.mediation.LevelPlayConfiguration
import com.unity3d.mediation.LevelPlayInitError
import com.unity3d.mediation.LevelPlayInitListener
import com.unity3d.mediation.LevelPlayInitRequest
import com.unity3d.mediation.LevelPlayPrivacySettings
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAd
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAdListener
import com.unity3d.mediation.rewarded.LevelPlayReward
import com.unity3d.mediation.rewarded.LevelPlayRewardedAd
import com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.Locale

/**
 * Godot Android plugin for Unity LevelPlay (ex-ironSource) mediation.
 *
 * Deliberately thin, exactly like the Unity Ads plugin it replaces: it owns the
 * SDK handshake and the two ad objects, and nothing else. Every policy decision —
 * when an interstitial may run, who gets a reward, how a failed load is retried —
 * lives in ad_manager_levelplay.gd where it is readable and reviewable.
 *
 * Two things about the LevelPlay API shape drive the code below:
 *
 *  - The ad objects (LevelPlayInterstitialAd / LevelPlayRewardedAd) are long-lived
 *    per ad unit and may only be constructed AFTER onInitSuccess. So they are
 *    created in the init callback, not in initialize(), and every entry point
 *    tolerates being called before that happened.
 *  - There is no test-mode boolean. Unlike Unity Ads, you cannot flip a flag and
 *    get free test creatives; test devices are registered in the LevelPlay
 *    dashboard and verified through the Test Suite (see launchTestSuite).
 *
 * All SDK entry points are posted to the UI thread — Godot calls in from its own.
 */
class GodotLevelPlay(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "GodotLevelPlay"

        // The `kind` string carried by every ad signal, so one handler in GDScript
        // can tell the two formats apart.
        private const val KIND_INTERSTITIAL = "interstitial"
        private const val KIND_REWARDED = "rewarded"
    }

    // ── Signals ───────────────────────────────────────────────────────────────
    //
    // Everything after `initialized` carries `kind` first. Numbers are passed as
    // strings for the same reason the Unity plugin did it: the Godot signal
    // marshaller handles strings unambiguously across engine versions, and the
    // only numeric payload here (the dashboard's reward amount) is informational —
    // the game computes its own reward.

    private val initializedSignal = SignalInfo("initialized")
    private val initFailedSignal = SignalInfo("init_failed", String::class.java)
    private val adLoadedSignal = SignalInfo("ad_loaded", String::class.java)
    private val adLoadFailedSignal =
        SignalInfo("ad_load_failed", String::class.java, String::class.java)
    private val adDisplayedSignal = SignalInfo("ad_displayed", String::class.java)
    private val adDisplayFailedSignal =
        SignalInfo("ad_display_failed", String::class.java, String::class.java)
    private val adRewardedSignal =
        SignalInfo("ad_rewarded", String::class.java, String::class.java, String::class.java)
    private val adClickedSignal = SignalInfo("ad_clicked", String::class.java)
    private val adClosedSignal = SignalInfo("ad_closed", String::class.java)

    private var initialized = false

    private var interstitialAd: LevelPlayInterstitialAd? = null
    private var rewardedAd: LevelPlayRewardedAd? = null

    private var interstitialAdUnitId = ""
    private var rewardedAdUnitId = ""

    override fun getPluginName(): String = "GodotLevelPlay"

    override fun getPluginSignals(): Set<SignalInfo> {
        return setOf(
            initializedSignal,
            initFailedSignal,
            adLoadedSignal,
            adLoadFailedSignal,
            adDisplayedSignal,
            adDisplayFailedSignal,
            adRewardedSignal,
            adClickedSignal,
            adClosedSignal
        )
    }

    // ── Consent ───────────────────────────────────────────────────────────────
    //
    // LevelPlay ships no consent UI either — it only ACCEPTS an answer gathered
    // elsewhere (consent_manager.gd). Set this BEFORE init so the very first ad
    // request already carries the right personalization flag.

    /**
     * @param consent true if the player agreed to personalized ads.
     *
     * Two regulations, one answer. setGDPRConsent covers the EEA/UK, where the
     * boolean means what it says. setCCPA covers the US state privacy laws, where
     * the boolean is INVERTED: it asks "has the user opted OUT of the sale or
     * sharing of their data", so a refusal here is setCCPA(true). Getting that
     * backwards would sell the data of exactly the people who said no, silently.
     *
     * These replace the older LevelPlay.setConsent / setMetaData("do_not_sell")
     * pair, which is deprecated as of SDK 9.4-9.5 and slated for removal. Both are
     * safe to call before init, which is when we call them.
     */
    @UsedByGodot
    fun setConsent(consent: Boolean) {
        try {
            LevelPlayPrivacySettings.setGDPRConsent(consent)
            LevelPlayPrivacySettings.setCCPA(!consent)
            Log.d(TAG, "Consent set: $consent")
        } catch (e: Exception) {
            Log.w(TAG, "setConsent failed: ${e.message}")
        }
    }

    /**
     * Child-directed treatment. Lumeo is not a children's app, so this is never
     * set today; it exists so the Play Console's target-audience answer and the ad
     * stack can be made to agree without a plugin rebuild if that ever changes.
     */
    @UsedByGodot
    fun setChildDirected(isChild: Boolean) {
        try {
            LevelPlayPrivacySettings.setCOPPA(isChild)
        } catch (e: Exception) {
            Log.w(TAG, "setCOPPA failed: ${e.message}")
        }
    }

    /** Escape hatch for any other dashboard metadata key (COPPA, per-network flags). */
    @UsedByGodot
    fun setMetaData(key: String, value: String) {
        try {
            LevelPlay.setMetaData(key, value)
        } catch (e: Exception) {
            Log.w(TAG, "setMetaData($key) failed: ${e.message}")
        }
    }

    /**
     * Best-effort ISO-3166 country, used only to decide whether a consent prompt
     * is required at all. Network country first (where the handset actually is),
     * then the SIM's home country, then the locale's region for tablets and
     * Wi-Fi-only devices. "" means "unknown", which callers must read as "ask
     * anyway". None of these reads needs a runtime permission.
     */
    @UsedByGodot
    fun getCountryCode(): String {
        val ctx: Context = activity?.applicationContext ?: return ""
        try {
            val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (tm != null) {
                val network = tm.networkCountryIso
                if (!network.isNullOrEmpty()) return network.uppercase(Locale.ROOT)
                val sim = tm.simCountryIso
                if (!sim.isNullOrEmpty()) return sim.uppercase(Locale.ROOT)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Country lookup failed: ${e.message}")
        }
        return Locale.getDefault().country.uppercase(Locale.ROOT)
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /**
     * @param appKey LevelPlay dashboard → App Settings → App Key.
     * @param userId stable per-player id (Firebase uid here) so LevelPlay's
     *   reporting and any future server-side reward callbacks line up with our
     *   own accounts. Empty is allowed.
     * @param interstitialAdUnit / @param rewardedAdUnit dashboard ad unit IDs.
     * @param enableTestSuite when true, arms the Test Suite so launchTestSuite()
     *   can be opened from a debug build. It does NOT make live ads free — a
     *   device still has to be registered as a test device in the dashboard.
     */
    @UsedByGodot
    fun initialize(
        appKey: String,
        userId: String,
        interstitialAdUnit: String,
        rewardedAdUnit: String,
        enableTestSuite: Boolean
    ) {
        interstitialAdUnitId = interstitialAdUnit
        rewardedAdUnitId = rewardedAdUnit

        if (initialized) {
            emitSignal(initializedSignal.name)
            return
        }

        val act = activity ?: run {
            emitSignal(initFailedSignal.name, "Activity not available")
            return
        }

        act.runOnUiThread {
            try {
                if (enableTestSuite) {
                    // Must be set before init or the Test Suite entry point is absent.
                    LevelPlay.setMetaData("is_test_suite", "enable")
                }

                val builder = LevelPlayInitRequest.Builder(appKey)
                if (userId.isNotEmpty()) {
                    builder.withUserId(userId)
                }

                LevelPlay.init(act, builder.build(), object : LevelPlayInitListener {
                    override fun onInitSuccess(configuration: LevelPlayConfiguration) {
                        initialized = true
                        Log.d(TAG, "Initialized (sdk ${LevelPlay.getSdkVersion()})")
                        createAdObjects()
                        emitSignal(initializedSignal.name)
                    }

                    override fun onInitFailed(error: LevelPlayInitError) {
                        Log.e(TAG, "Init failed: ${error.errorMessage}")
                        emitSignal(initFailedSignal.name, describe(error))
                    }
                })
            } catch (e: Exception) {
                Log.e(TAG, "Init threw: ${e.message}")
                emitSignal(initFailedSignal.name, e.message ?: "unknown")
            }
        }
    }

    @UsedByGodot
    fun isInitialized(): Boolean = initialized

    /**
     * Builds the two reusable ad objects. Called from onInitSuccess only —
     * constructing them earlier is what LevelPlay reports as
     * ERROR_CODE_LOAD_BEFORE_INIT_SUCCESS_CALLBACK on the first load.
     */
    private fun createAdObjects() {
        if (interstitialAdUnitId.isNotEmpty() && interstitialAd == null) {
            interstitialAd = LevelPlayInterstitialAd(interstitialAdUnitId).apply {
                setListener(object : LevelPlayInterstitialAdListener {
                    override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
                        emitSignal(adLoadedSignal.name, KIND_INTERSTITIAL)
                    }

                    override fun onAdLoadFailed(error: LevelPlayAdError) {
                        emitSignal(adLoadFailedSignal.name, KIND_INTERSTITIAL, describe(error))
                    }

                    override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {
                        emitSignal(adDisplayedSignal.name, KIND_INTERSTITIAL)
                    }

                    override fun onAdDisplayFailed(
                        error: LevelPlayAdError,
                        adInfo: LevelPlayAdInfo
                    ) {
                        emitSignal(adDisplayFailedSignal.name, KIND_INTERSTITIAL, describe(error))
                    }

                    override fun onAdClicked(adInfo: LevelPlayAdInfo) {
                        emitSignal(adClickedSignal.name, KIND_INTERSTITIAL)
                    }

                    override fun onAdClosed(adInfo: LevelPlayAdInfo) {
                        emitSignal(adClosedSignal.name, KIND_INTERSTITIAL)
                    }

                    override fun onAdInfoChanged(adInfo: LevelPlayAdInfo) {}
                })
            }
        }

        if (rewardedAdUnitId.isNotEmpty() && rewardedAd == null) {
            rewardedAd = LevelPlayRewardedAd(rewardedAdUnitId).apply {
                setListener(object : LevelPlayRewardedAdListener {
                    override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
                        emitSignal(adLoadedSignal.name, KIND_REWARDED)
                    }

                    override fun onAdLoadFailed(error: LevelPlayAdError) {
                        emitSignal(adLoadFailedSignal.name, KIND_REWARDED, describe(error))
                    }

                    override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {
                        emitSignal(adDisplayedSignal.name, KIND_REWARDED)
                    }

                    // The ONLY place a reward is earned. It arrives before
                    // onAdClosed, so the manager latches it and pays out on close.
                    override fun onAdRewarded(reward: LevelPlayReward, adInfo: LevelPlayAdInfo) {
                        emitSignal(
                            adRewardedSignal.name,
                            KIND_REWARDED,
                            reward.name ?: "",
                            reward.amount.toString()
                        )
                    }

                    override fun onAdDisplayFailed(
                        error: LevelPlayAdError,
                        adInfo: LevelPlayAdInfo
                    ) {
                        emitSignal(adDisplayFailedSignal.name, KIND_REWARDED, describe(error))
                    }

                    override fun onAdClicked(adInfo: LevelPlayAdInfo) {
                        emitSignal(adClickedSignal.name, KIND_REWARDED)
                    }

                    override fun onAdClosed(adInfo: LevelPlayAdInfo) {
                        emitSignal(adClosedSignal.name, KIND_REWARDED)
                    }

                    override fun onAdInfoChanged(adInfo: LevelPlayAdInfo) {}
                })
            }
        }
    }

    // ── Load / show ───────────────────────────────────────────────────────────
    //
    // Each load answers with exactly one of ad_loaded / ad_load_failed, and each
    // show with exactly one of (ad_displayed → ad_closed) / ad_display_failed. A
    // show that never got that far because the object doesn't exist yet reports
    // ad_display_failed itself, so the GDScript side can never hang waiting on a
    // signal that isn't coming.

    @UsedByGodot
    fun loadInterstitial() {
        val ad = interstitialAd ?: run {
            emitSignal(adLoadFailedSignal.name, KIND_INTERSTITIAL, "not initialized")
            return
        }
        activity?.runOnUiThread { ad.loadAd() }
    }

    @UsedByGodot
    fun isInterstitialReady(): Boolean = interstitialAd?.isAdReady ?: false

    /** @param placement dashboard placement name, or "" for the ad unit default. */
    @UsedByGodot
    fun showInterstitial(placement: String) {
        val act = activity
        val ad = interstitialAd
        if (act == null || ad == null) {
            emitSignal(adDisplayFailedSignal.name, KIND_INTERSTITIAL, "not initialized")
            return
        }
        act.runOnUiThread {
            if (!ad.isAdReady) {
                emitSignal(adDisplayFailedSignal.name, KIND_INTERSTITIAL, "not ready")
                return@runOnUiThread
            }
            if (placement.isEmpty()) {
                ad.showAd(act)
            } else {
                ad.showAd(act, placement)
            }
        }
    }

    @UsedByGodot
    fun isInterstitialPlacementCapped(placement: String): Boolean {
        if (placement.isEmpty()) return false
        return try {
            LevelPlayInterstitialAd.isPlacementCapped(placement)
        } catch (e: Exception) {
            false
        }
    }

    @UsedByGodot
    fun loadRewarded() {
        val ad = rewardedAd ?: run {
            emitSignal(adLoadFailedSignal.name, KIND_REWARDED, "not initialized")
            return
        }
        activity?.runOnUiThread { ad.loadAd() }
    }

    @UsedByGodot
    fun isRewardedReady(): Boolean = rewardedAd?.isAdReady ?: false

    @UsedByGodot
    fun showRewarded(placement: String) {
        val act = activity
        val ad = rewardedAd
        if (act == null || ad == null) {
            emitSignal(adDisplayFailedSignal.name, KIND_REWARDED, "not initialized")
            return
        }
        act.runOnUiThread {
            if (!ad.isAdReady) {
                emitSignal(adDisplayFailedSignal.name, KIND_REWARDED, "not ready")
                return@runOnUiThread
            }
            if (placement.isEmpty()) {
                ad.showAd(act)
            } else {
                ad.showAd(act, placement)
            }
        }
    }

    @UsedByGodot
    fun isRewardedPlacementCapped(placement: String): Boolean {
        if (placement.isEmpty()) return false
        return try {
            LevelPlayRewardedAd.isPlacementCapped(placement)
        } catch (e: Exception) {
            false
        }
    }

    // ── Diagnostics ───────────────────────────────────────────────────────────
    //
    // The Test Suite is LevelPlay's answer to "is my integration actually wired
    // up" — it lists every configured network and lets you fire a test ad per ad
    // unit. Only reachable from a debug build (see ad_manager_levelplay.gd).

    @UsedByGodot
    fun launchTestSuite() {
        val act = activity ?: return
        act.runOnUiThread { LevelPlay.launchTestSuite(act) }
    }

    @UsedByGodot
    fun validateIntegration() {
        val act = activity ?: return
        act.runOnUiThread { LevelPlay.validateIntegration(act) }
    }

    @UsedByGodot
    fun getSdkVersion(): String = try {
        LevelPlay.getSdkVersion()
    } catch (e: Exception) {
        ""
    }

    private fun describe(error: LevelPlayAdError): String =
        "${error.errorCode}: ${error.errorMessage ?: "unknown"}"

    private fun describe(error: LevelPlayInitError): String =
        "${error.errorCode}: ${error.errorMessage ?: "unknown"}"
}
