package com.niquewrld.casino.unityads

import android.content.Context
import android.telephony.TelephonyManager
import android.util.Log
import com.unity3d.ads.IUnityAdsInitializationListener
import com.unity3d.ads.IUnityAdsLoadListener
import com.unity3d.ads.IUnityAdsShowListener
import com.unity3d.ads.UnityAds
import com.unity3d.ads.UnityAdsShowOptions
import com.unity3d.ads.metadata.MetaData
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.Locale

/**
 * Godot Android Plugin for Unity Ads.
 *
 * Deliberately thin: it owns the SDK handshake and nothing else. Which placement
 * is rewarded and which is an interstitial is a Unity dashboard setting, not a
 * code path — both use the same load/show pair — so all policy (frequency caps,
 * live-vs-test gating, who gets the reward) stays in ad_manager_unity.gd where
 * it is readable and testable.
 *
 * Rewarded ads are distinguished only by the completion state reported to
 * ad_closed: "COMPLETED" means the player watched it through and has earned the
 * reward, "SKIPPED" means they backed out early.
 */
class GodotUnityAds(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "GodotUnityAds"
    }

    // Signals
    private val initializedSignal = SignalInfo("initialized")
    private val initFailedSignal = SignalInfo("init_failed", String::class.java)
    private val adLoadedSignal = SignalInfo("ad_loaded", String::class.java)
    private val adLoadFailedSignal = SignalInfo("ad_load_failed", String::class.java, String::class.java)
    private val adShowStartSignal = SignalInfo("ad_show_start", String::class.java)
    private val adShowFailedSignal = SignalInfo("ad_show_failed", String::class.java, String::class.java)

    // completion_state is "COMPLETED" or "SKIPPED" — the reward signal for a
    // rewarded placement. Passed as a String rather than a Boolean because the
    // Godot signal marshaller handles strings unambiguously across versions.
    private val adClosedSignal = SignalInfo("ad_closed", String::class.java, String::class.java)

    private var initialized = false

    override fun getPluginName(): String = "GodotUnityAds"

    override fun getPluginSignals(): Set<SignalInfo> {
        return setOf(
            initializedSignal,
            initFailedSignal,
            adLoadedSignal,
            adLoadFailedSignal,
            adShowStartSignal,
            adShowFailedSignal,
            adClosedSignal
        )
    }

    // ── Consent ───────────────────────────────────────────────────────────────
    //
    // Unity ships no consent dialog of its own; it only accepts an answer that was
    // gathered elsewhere. Set this BEFORE initialize() so the very first ad request
    // already carries the right personalization flag.
    //
    // Each value needs its own commit() before the next one is set — batching them
    // onto one MetaData object silently drops all but the last.

    /**
     * @param consent true if the player agreed to personalized ads.
     *
     * gdpr.consent covers the EEA/UK. privacy.consent covers the US state laws and
     * is the flag Unity reads outside the EEA. user.nonbehavioral is the explicit
     * "contextual ads only" instruction, set when consent was refused so a refusal
     * still yields non-personalized inventory rather than no inventory at all.
     */
    @UsedByGodot
    fun setConsent(consent: Boolean) {
        val ctx: Context = activity?.applicationContext ?: run {
            Log.w(TAG, "setConsent: no context available")
            return
        }

        MetaData(ctx).apply { set("gdpr.consent", consent); commit() }
        MetaData(ctx).apply { set("privacy.consent", consent); commit() }
        MetaData(ctx).apply { set("user.nonbehavioral", !consent); commit() }

        Log.d(TAG, "Consent set: $consent")
    }

    /**
     * Best-effort ISO-3166 country for deciding whether a consent prompt is
     * required at all. Network country first (where the handset actually is),
     * then the SIM's home country, then the device locale's region for tablets
     * and Wi-Fi-only devices.
     *
     * Returns "" when nothing is knowable, which callers must treat as "ask
     * anyway" rather than "no consent needed". None of these reads require a
     * runtime permission.
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
     * @param testMode when true Unity serves its own test creatives and bills
     *   nobody. Drive this from a release-build check, never by hand.
     */
    @UsedByGodot
    fun initialize(gameId: String, testMode: Boolean) {
        if (initialized) {
            emitSignal(initializedSignal.name)
            return
        }

        val act = activity ?: run {
            emitSignal(initFailedSignal.name, "Activity not available")
            return
        }

        // The Unity SDK expects its entry points on the main thread; Godot calls
        // in from its own thread, so every hop into the SDK is posted across.
        act.runOnUiThread {
            UnityAds.initialize(
                act.applicationContext,
                gameId,
                testMode,
                object : IUnityAdsInitializationListener {
                    override fun onInitializationComplete() {
                        initialized = true
                        Log.d(TAG, "Initialized (testMode=$testMode)")
                        emitSignal(initializedSignal.name)
                    }

                    override fun onInitializationFailed(
                        error: UnityAds.UnityAdsInitializationError?,
                        message: String?
                    ) {
                        Log.e(TAG, "Init failed: $error $message")
                        emitSignal(initFailedSignal.name, "$error: ${message ?: "unknown"}")
                    }
                }
            )
        }
    }

    @UsedByGodot
    fun isInitialized(): Boolean = initialized

    // ── Load / show ───────────────────────────────────────────────────────────

    @UsedByGodot
    fun loadAd(placementId: String) {
        val act = activity ?: return
        act.runOnUiThread {
            UnityAds.load(placementId, object : IUnityAdsLoadListener {
                override fun onUnityAdsAdLoaded(placementId: String?) {
                    emitSignal(adLoadedSignal.name, placementId ?: "")
                }

                override fun onUnityAdsFailedToLoad(
                    placementId: String?,
                    error: UnityAds.UnityAdsLoadError?,
                    message: String?
                ) {
                    emitSignal(
                        adLoadFailedSignal.name,
                        placementId ?: "",
                        "$error: ${message ?: "unknown"}"
                    )
                }
            })
        }
    }

    /**
     * Shows a previously loaded placement. Exactly one of ad_show_failed or
     * ad_closed always follows, so a caller can restore game state on either
     * without risking a state machine that hangs waiting for a signal that never
     * arrives.
     */
    @UsedByGodot
    fun showAd(placementId: String) {
        val act = activity ?: run {
            emitSignal(adShowFailedSignal.name, placementId, "Activity not available")
            return
        }

        act.runOnUiThread {
            UnityAds.show(act, placementId, UnityAdsShowOptions(), object : IUnityAdsShowListener {
                override fun onUnityAdsShowFailure(
                    placementId: String?,
                    error: UnityAds.UnityAdsShowError?,
                    message: String?
                ) {
                    emitSignal(
                        adShowFailedSignal.name,
                        placementId ?: "",
                        "$error: ${message ?: "unknown"}"
                    )
                }

                override fun onUnityAdsShowStart(placementId: String?) {
                    emitSignal(adShowStartSignal.name, placementId ?: "")
                }

                override fun onUnityAdsShowClick(placementId: String?) {}

                override fun onUnityAdsShowComplete(
                    placementId: String?,
                    state: UnityAds.UnityAdsShowCompletionState?
                ) {
                    val completed =
                        if (state == UnityAds.UnityAdsShowCompletionState.COMPLETED) "COMPLETED"
                        else "SKIPPED"
                    emitSignal(adClosedSignal.name, placementId ?: "", completed)
                }
            })
        }
    }
}
