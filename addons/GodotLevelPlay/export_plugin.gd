@tool
extends EditorPlugin

# Mirrors addons/GodotUnityAds/export_plugin.gd — same shape, so the Android
# export treats it identically.

var export_plugin: LevelPlayExportPlugin


func _enter_tree():
	export_plugin = LevelPlayExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree():
	remove_export_plugin(export_plugin)
	export_plugin = null


class LevelPlayExportPlugin extends EditorExportPlugin:
	var _plugin_name = "GodotLevelPlay"

	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	func _get_android_libraries(platform, debug):
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		else:
			return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	# Resolved from Maven Central at export time rather than bundled into the AAR,
	# which is why plugin_levelplay/build.gradle.kts declares the SDK compileOnly.
	# Bump mediation-sdk in BOTH places together.
	#
	#  - mediation-sdk       the LevelPlay SDK itself (includes the ironSource
	#                        network and, since 8.9.0, Ad Quality).
	#  - unityads-adapter    lets LevelPlay mediate the Unity Ads demand this game
	#                        was already running, instead of throwing it away.
	#  - unity-ads           the Unity Ads SDK the adapter drives. It has to be
	#                        listed HERE: the adapter's POM declares no
	#                        dependencies at all, so nothing pulls the SDK in on
	#                        its own. Ship the adapter without it and LevelPlay
	#                        logs
	#                          AdapterVersionScanner: failed to get version for
	#                          UnityAds: NoClassDefFoundError com/unity3d/ads/MediationInfo
	#                        at init, then answers every load with 509 Mediation
	#                        No fill — the network is in the waterfall and cannot
	#                        be instantiated. Nothing else reports it.
	#                        Every com.unity3d.ads class adapter 5.12.0 references
	#                        exists in 4.18.1; bump the two together and re-check.
	#                        (This is also the dependency the retired GodotUnityAds
	#                        export plugin used to contribute. Only one of the two
	#                        plugins may be enabled — both would declare it twice.)
	#                        Add more adapters here as you enable networks on the
	#                        dashboard, each with its own SDK; an adapter with no
	#                        dashboard instance just sits idle.
	#  - facebook-adapter    META AUDIENCE NETWORK, as a mediated demand source in
	#    + audience-         the same auction as Unity Ads. Same two-artifact rule
	#      network-sdk       as above, for the same reason: the adapter's POM
	#                        declares NO dependencies, so the Meta SDK has to be
	#                        listed beside it or the adapter cannot be instantiated
	#                        and every Meta bid comes back as no-fill. The artifact
	#                        is still called "facebook-*"; Meta never renamed it.
	#
	#                        THE VERSIONS ARE PINNED BELOW THE LATEST ON PURPOSE.
	#                        audience-network-sdk 6.22.0 is current, and it drags in
	#                        androidx.browser:1.9.0, whose aar-metadata demands
	#                        minCompileSdk 36 AND Android Gradle Plugin >= 8.9.1.
	#                        Godot 4.7's build template (android/build/config.gradle)
	#                        pins androidGradlePlugin 8.6.1, so 6.22.0 fails the app
	#                        build outright — not at the ad request, at assemble.
	#                        6.21.0 has no androidx.browser dependency at all.
	#                        5.3.0 is the adapter built against 6.21.0 (its own
	#                        FacebookAdapter.getAdapterSDKVersion reports it), so
	#                        the pair is matched rather than merely compatible.
	#                        Before moving either: check the newer SDK's POM for a
	#                        browser bump, and re-check AGP in config.gradle.
	#  - play-services-*     required by the SDK to read the advertising / app-set
	#                        ID. Firebase already pulls most of this in; listing it
	#                        explicitly keeps the ad stack working if Firebase is
	#                        ever removed. These also OUTRANK the ancient
	#                        play-services-basement 11.0.4 that audience-network-sdk
	#                        asks for transitively — Gradle takes the highest, which
	#                        is 18.1.0 here, and that is the intended outcome.
	func _get_android_dependencies(platform, debug):
		return PackedStringArray([
			"com.unity3d.ads-mediation:mediation-sdk:9.6.0",
			"com.unity3d.ads-mediation:unityads-adapter:5.12.0",
			"com.unity3d.ads:unity-ads:4.18.1",
			"com.unity3d.ads-mediation:facebook-adapter:5.3.0",
			"com.facebook.android:audience-network-sdk:6.21.0",
			"com.google.android.gms:play-services-appset:16.0.0",
			"com.google.android.gms:play-services-ads-identifier:18.1.0",
			"com.google.android.gms:play-services-basement:18.1.0",
		])

	func _get_name():
		return _plugin_name
