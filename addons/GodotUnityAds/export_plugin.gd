@tool
extends EditorPlugin

# Mirrors addons/GodotGooglePlayBilling/export_plugin.gd — same shape, so the two
# behave identically at export time.

var export_plugin: UnityAdsExportPlugin


func _enter_tree():
	export_plugin = UnityAdsExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree():
	remove_export_plugin(export_plugin)
	export_plugin = null


class UnityAdsExportPlugin extends EditorExportPlugin:
	var _plugin_name = "GodotUnityAds"

	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	func _get_android_libraries(platform, debug):
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		else:
			return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	# The Unity Ads SDK itself is resolved from Maven here rather than bundled into
	# the AAR, which is why plugin_unityads/build.gradle.kts declares it compileOnly.
	# Bump both together or the plugin compiles against one version and runs on another.
	func _get_android_dependencies(platform, debug):
		return PackedStringArray(["com.unity3d.ads:unity-ads:4.18.1"])

	func _get_name():
		return _plugin_name
