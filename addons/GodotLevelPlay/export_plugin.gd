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
	#                        was already running, instead of throwing it away. The
	#                        adapter pulls the matching unity-ads SDK itself, so
	#                        the old direct `com.unity3d.ads:unity-ads` dependency
	#                        must NOT also be present (disable the GodotUnityAds
	#                        plugin — two copies is a duplicate-class build error).
	#                        Add more adapters here as you enable networks on the
	#                        dashboard; an adapter with no dashboard instance just
	#                        sits idle.
	#  - play-services-*     required by the SDK to read the advertising / app-set
	#                        ID. Firebase already pulls most of this in; listing it
	#                        explicitly keeps the ad stack working if Firebase is
	#                        ever removed.
	func _get_android_dependencies(platform, debug):
		return PackedStringArray([
			"com.unity3d.ads-mediation:mediation-sdk:9.6.0",
			"com.unity3d.ads-mediation:unityads-adapter:5.12.0",
			"com.google.android.gms:play-services-appset:16.0.0",
			"com.google.android.gms:play-services-ads-identifier:18.1.0",
			"com.google.android.gms:play-services-basement:18.1.0",
		])

	func _get_name():
		return _plugin_name
