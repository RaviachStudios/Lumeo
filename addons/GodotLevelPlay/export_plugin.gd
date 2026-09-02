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
	#  - play-services-*     required by the SDK to read the advertising / app-set
	#                        ID. Firebase already pulls most of this in; listing it
	#                        explicitly keeps the ad stack working if Firebase is
	#                        ever removed.
	func _get_android_dependencies(platform, debug):
		return PackedStringArray([
			"com.unity3d.ads-mediation:mediation-sdk:9.6.0",
			"com.unity3d.ads-mediation:unityads-adapter:5.12.0",
			"com.unity3d.ads:unity-ads:4.18.1",
			"com.google.android.gms:play-services-appset:16.0.0",
			"com.google.android.gms:play-services-ads-identifier:18.1.0",
			"com.google.android.gms:play-services-basement:18.1.0",
		])

	func _get_name():
		return _plugin_name
