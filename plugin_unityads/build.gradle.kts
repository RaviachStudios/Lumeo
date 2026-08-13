plugins {
    id("com.android.library") version "8.1.4"
    id("org.jetbrains.kotlin.android") version "2.1.0"
}

android {
    namespace = "com.niquewrld.casino.unityads"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        targetSdk = 34

        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot library - provided at runtime, same as the GoogleSignIn plugin.
    compileOnly(fileTree(mapOf("dir" to "libs", "include" to listOf("godot-lib*.aar"))))

    // Unity Ads. compileOnly, NOT implementation: the real artifact is pulled in
    // at export time by addons/GodotUnityAds/export_plugin.gd via
    // _get_android_dependencies. Bundling it here too would put two copies of the
    // SDK on the classpath and fail the build with duplicate classes.
    compileOnly("com.unity3d.ads:unity-ads:4.18.1")
}
