plugins {
    id("com.android.library") version "8.1.4"
    id("org.jetbrains.kotlin.android") version "2.1.0"
}

android {
    namespace = "com.raviachstudios.lumeo.levelplay"
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
    // Godot library — provided at runtime by the engine, same as the other plugins.
    compileOnly(fileTree(mapOf("dir" to "libs", "include" to listOf("godot-lib*.aar"))))

    // LevelPlay (ex-ironSource) mediation SDK. compileOnly, NOT implementation:
    // the real artifact is pulled in at export time by
    // addons/GodotLevelPlay/export_plugin.gd via _get_android_dependencies.
    // Bundling it here as well would put two copies of the SDK on the classpath
    // and fail the app build with duplicate classes.
    //
    // Keep this version in lockstep with export_plugin.gd — compiling against one
    // version and running against another is how you get a NoSuchMethodError at
    // the first ad request and nowhere near this file.
    compileOnly("com.unity3d.ads-mediation:mediation-sdk:9.6.0")
}
